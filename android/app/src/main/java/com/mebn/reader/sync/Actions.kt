package com.mebn.reader.sync

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.graphics.scale
import com.mebn.reader.ReaderApp
import com.mebn.reader.app.Toasts
import com.mebn.reader.formats.BookDocument
import com.mebn.reader.model.Annotation
import com.mebn.reader.model.AnnotationKind
import com.mebn.reader.model.AppSettings
import com.mebn.reader.model.Book
import com.mebn.reader.model.Folder
import com.mebn.reader.model.Format
import com.mebn.reader.model.Locator
import com.mebn.reader.model.Progress
import com.mebn.reader.model.Scope
import com.mebn.reader.model.Setting
import com.mebn.reader.model.json
import com.mebn.reader.model.now
import com.mebn.reader.model.settingsMap
import com.mebn.reader.model.settingsObject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import okhttp3.Request
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import kotlin.math.roundToInt

/** Changes to the library, applied locally and synced. Call on the main thread. */
object Actions {
    private val library get() = SyncEngine.library

    private fun newId() = UUID.randomUUID().toString().lowercase()

    // Folders

    fun createFolder(name: String, parentId: String?): Folder =
        SyncEngine.put(Folder(id = newId(), name = name, parentId = parentId))

    fun rename(folder: Folder, name: String) {
        SyncEngine.put(folder.copy(name = name))
    }

    fun move(folder: Folder, parentId: String?) {
        if (folder.id == parentId || (parentId != null && parentId in library.descendants(folder.id))) return
        SyncEngine.put(folder.copy(parentId = parentId))
    }

    fun delete(folder: Folder) = SyncEngine.deleteFolder(folder.id)

    // Books

    fun rename(book: Book, title: String) {
        SyncEngine.put(book.copy(title = title))
    }

    fun move(book: Book, folderId: String?) {
        SyncEngine.put(book.copy(folderId = folderId))
    }

    fun delete(book: Book) {
        SyncEngine.put(book.copy(deleted = true))
        BookFiles.remove(book.id)
    }

    // Reading

    fun saveProgress(bookId: String, locator: Locator, percent: Double) {
        val existing = library.progress[bookId]
        SyncEngine.put(Progress(id = bookId, modifiedAt = existing?.modifiedAt ?: 0, locator = locator.toJson(), percent = percent))
    }

    fun addAnnotation(
        bookId: String,
        kind: AnnotationKind,
        locator: Locator,
        text: String,
        note: String = "",
        color: String = "",
        label: String = "",
    ): Annotation = SyncEngine.put(
        Annotation(id = newId(), bookId = bookId, kind = kind, locator = locator.toJson(), text = text, note = note, color = color, label = label),
    )

    fun update(annotation: Annotation, note: String? = null, color: String? = null, locator: Locator? = null, text: String? = null) {
        SyncEngine.put(
            annotation.copy(
                note = note ?: annotation.note,
                color = color ?: annotation.color,
                locator = locator?.toJson() ?: annotation.locator,
                text = text ?: annotation.text,
            ),
        )
    }

    fun remove(annotation: Annotation) {
        SyncEngine.put(annotation.copy(deleted = true))
    }

    // Settings

    /** Saves a settings scope; null removes it. */
    fun saveSettings(scope: String, values: Map<String, JsonElement>?) {
        val existing = library.settings[scope]
        val data = values?.let { json.encodeToString(JsonObject.serializer(), JsonObject(it.toSortedMap())) } ?: ""
        SyncEngine.put(Setting(id = scope, modifiedAt = existing?.modifiedAt ?: 0, deleted = values == null, data = data))
    }

    fun <T> saveSettings(scope: String, settings: T, serializer: KSerializer<T>) = saveSettings(scope, settingsMap(settings, serializer))

    fun setApp(change: (AppSettings) -> AppSettings) {
        val app = change(library.appSettings)
        // Keys this app doesn't know stay as they were.
        val values = settingsObject(library.settings[Scope.APP]?.data)
        values.putAll(settingsMap(app, AppSettings.serializer()))
        saveSettings(Scope.APP, values)
    }

    // Import

    val importTypes = arrayOf(
        "application/epub+zip", "application/pdf", "text/plain", "application/x-fictionbook+xml", "application/x-fictionbook",
        "application/vnd.comicbook+zip", "application/x-cbz", "application/zip", "application/octet-stream", "text/xml", "application/xml",
    )
    private const val COVER_WIDTH = 600

    /** Parses, uploads and adds books. Unsupported files are skipped with a notice. */
    suspend fun importFiles(uris: List<Uri>, folderId: String?) {
        val session = SyncEngine.session ?: return
        val named = uris.map { it to displayName(it) }
        val supported = named.filter { Format.of(it.second) != null }
        val skipped = uris.size - supported.size
        if (skipped > 0) Toasts.show("$skipped file${if (skipped > 1) "s" else ""} skipped", "Supported: EPUB, PDF, FB2, CBZ, TXT")
        if (supported.isEmpty()) return

        Toasts.show(if (supported.size > 1) "Adding ${supported.size} books" else "Adding ${supported[0].second}", progress = true)
        var added = 0
        for ((uri, fileName) in supported) {
            val local = File(ReaderApp.context.cacheDir, "${UUID.randomUUID()}-$fileName")
            try {
                val format = Format.of(fileName)!!
                // Parsed off the main thread; large books take a moment.
                val (metadata, cover) = withContext(Dispatchers.IO) {
                    ReaderApp.context.contentResolver.openInputStream(uri)!!.use { input -> local.outputStream().use { input.copyTo(it) } }
                    val doc = BookDocument.open(local, format, fileName)
                    try {
                        doc.metadata to doc.cover()?.let(::shrink)
                    } finally {
                        doc.close()
                    }
                }
                val time = now()
                val book = Book(
                    id = newId(), modifiedAt = time, folderId = folderId, title = metadata.title.ifEmpty { fileName }, author = metadata.author,
                    format = format, fileName = fileName, size = local.length(), hash = "", hasCover = cover != null, addedAt = time,
                )
                val saved = Api.uploadBook(session, book, local, cover)
                BookFiles.store(local, saved)
                SyncEngine.received(saved)
                added++
            } catch (e: Exception) {
                Toasts.show("Couldn't add $fileName", e.message, error = true)
            } finally {
                local.delete()
            }
        }
        if (added > 0) Toasts.show(if (added > 1) "Added $added books" else "Book added")
    }

    private fun displayName(uri: Uri): String {
        ReaderApp.context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0)?.let { name -> return name }
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "book"
    }

    private fun shrink(data: ByteArray): ByteArray {
        val image = BitmapFactory.decodeByteArray(data, 0, data.size) ?: return data
        if (image.width <= COVER_WIDTH) return data
        val resized = image.scale(COVER_WIDTH, (image.height.toFloat() / image.width * COVER_WIDTH).roundToInt())
        return ByteArrayOutputStream().also { resized.compress(Bitmap.CompressFormat.JPEG, 86, it) }.toByteArray()
    }
}

/** Book files, downloaded once and kept on the device. */
object BookFiles {
    private val directory: File get() = File(ReaderApp.context.cacheDir, "books").apply { mkdirs() }

    fun file(book: Book) = File(directory, "${book.id}.${book.format.extension}")

    fun store(file: File, book: Book) {
        runCatching { file.copyTo(file(book), overwrite = true) }
    }

    fun remove(id: String) {
        for (format in Format.entries) File(directory, "$id.${format.extension}").delete()
    }

    /** The book's file on this device, downloading it if needed. */
    suspend fun file(book: Book, session: Session): File {
        val target = file(book)
        if (target.exists()) return target
        val request = Request.Builder().url(Api.bookFileUrl(session, book.id)).header("Authorization", "Bearer ${session.token}").build()
        val response = try {
            Api.client.newCall(request).await()
        } catch (e: java.io.IOException) {
            throw ApiError("Can't reach the server", 0)
        }
        response.use {
            if (it.code != 200) throw ApiError(if (it.code == 404) "The file is missing on the server." else "Couldn't download the book.", it.code)
            withContext(Dispatchers.IO) {
                val temp = File(directory, "${book.id}.download")
                temp.outputStream().use { out -> it.body.byteStream().copyTo(out) }
                temp.renameTo(target)
            }
        }
        return target
    }
}
