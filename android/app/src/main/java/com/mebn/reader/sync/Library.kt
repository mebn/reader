package com.mebn.reader.sync

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.mebn.reader.model.Annotation
import com.mebn.reader.model.AppSettings
import com.mebn.reader.model.Book
import com.mebn.reader.model.Changes
import com.mebn.reader.model.Folder
import com.mebn.reader.model.Progress
import com.mebn.reader.model.ReaderSettings
import com.mebn.reader.model.Scope
import com.mebn.reader.model.Setting
import com.mebn.reader.model.SyncRecord
import com.mebn.reader.model.decodeReaderSettings
import com.mebn.reader.model.decodeSettings
import com.mebn.reader.model.settingsObject
import kotlinx.serialization.Serializable

/**
 * Everything synced for the signed-in account. Records merge by last-write-wins and
 * tombstones remove entries. Changed on the main thread only; Compose sees every change.
 */
class Library {
    var folders by mutableStateOf(mapOf<String, Folder>()); private set
    var books by mutableStateOf(mapOf<String, Book>()); private set
    var progress by mutableStateOf(mapOf<String, Progress>()); private set
    var annotations by mutableStateOf(mapOf<String, Annotation>()); private set
    var settings by mutableStateOf(mapOf<String, Setting>()); private set
    /** Server version of the last applied pull. */
    var version by mutableLongStateOf(0); private set
    var ready by mutableStateOf(false)

    /** Called on every change, so the snapshot is written after edits. */
    var onChange: (() -> Unit)? = null

    fun merge(records: List<SyncRecord>) {
        if (records.isEmpty()) return
        folders = merge(folders, records.filterIsInstance<Folder>())
        books = merge(books, records.filterIsInstance<Book>())
        progress = merge(progress, records.filterIsInstance<Progress>())
        annotations = merge(annotations, records.filterIsInstance<Annotation>())
        settings = merge(settings, records.filterIsInstance<Setting>())
        onChange?.invoke()
    }

    fun apply(changes: Changes) {
        folders = merge(folders, changes.folders.orEmpty())
        books = merge(books, changes.books.orEmpty())
        progress = merge(progress, changes.progress.orEmpty())
        annotations = merge(annotations, changes.annotations.orEmpty())
        settings = merge(settings, changes.settings.orEmpty())
        version = maxOf(version, changes.version)
        ready = true
        onChange?.invoke()
    }

    fun reset(snapshot: Snapshot? = null) {
        folders = snapshot?.folders.orEmpty()
        books = snapshot?.books.orEmpty()
        progress = snapshot?.progress.orEmpty()
        annotations = snapshot?.annotations.orEmpty()
        settings = snapshot?.settings.orEmpty()
        version = snapshot?.version ?: 0
        ready = snapshot != null
    }

    val snapshot: Snapshot get() = Snapshot(folders, books, progress, annotations, settings, version)

    private fun <T : SyncRecord> merge(table: Map<String, T>, records: List<T>): Map<String, T> {
        if (records.isEmpty()) return table
        val out = table.toMutableMap()
        var changed = false
        for (record in records) {
            val existing = out[record.id]
            if (existing != null && existing.modifiedAt > record.modifiedAt) continue
            if (record.isDeleted) {
                if (out.remove(record.id) != null) changed = true
            } else if (existing != record) {
                out[record.id] = record
                changed = true
            }
        }
        return if (changed) out else table
    }

    @Serializable
    data class Snapshot(
        val folders: Map<String, Folder>,
        val books: Map<String, Book>,
        val progress: Map<String, Progress>,
        val annotations: Map<String, Annotation>,
        val settings: Map<String, Setting>,
        val version: Long,
    )

    // Settings

    val appSettings: AppSettings
        get() = decodeSettings(settingsObject(settings[Scope.APP]?.data), AppSettings(), AppSettings.serializer())

    /** Reader defaults for every book. */
    val defaultReaderSettings: ReaderSettings
        get() = decodeReaderSettings(settingsObject(settings[Scope.READER]?.data), ReaderSettings.defaults)

    /** Effective settings for a book: defaults, then the book's own overrides. */
    fun readerSettings(bookId: String): Pair<ReaderSettings, Boolean> {
        val override = settingsObject(settings[Scope.book(bookId)]?.data).filterKeys { it in ReaderSettings.keys }
        return decodeReaderSettings(override, defaultReaderSettings) to override.isNotEmpty()
    }

    // Views of the library

    fun folderPath(folderId: String?): List<Folder> {
        val path = ArrayDeque<Folder>()
        var current = folderId?.let { folders[it] }
        while (current != null && path.size < 32) {
            path.addFirst(current)
            current = current.parentId?.let { folders[it] }
        }
        return path
    }

    fun childFolders(parent: String?): List<Folder> =
        folders.values.filter { it.parentId == parent }.sortedWith(compareBy(NaturalOrder) { it.name })

    fun books(folderId: String?): List<Book> =
        books.values.filter { it.folderId == folderId }.sortedByDescending { it.addedAt }

    /** A folder and every folder inside it. */
    fun descendants(folderId: String): Set<String> {
        val ids = mutableSetOf(folderId)
        var grew = true
        while (grew) {
            grew = false
            for (f in folders.values) {
                if (f.parentId != null && f.parentId in ids && f.id !in ids) {
                    ids += f.id
                    grew = true
                }
            }
        }
        return ids
    }

    /** Folders as an indented tree, skipping `exclude` and its descendants. */
    fun folderTree(exclude: String? = null): List<Pair<Folder, Int>> {
        val out = mutableListOf<Pair<Folder, Int>>()
        fun walk(parent: String?, depth: Int) {
            for (f in childFolders(parent)) {
                if (f.id == exclude) continue
                out += f to depth
                walk(f.id, depth + 1)
            }
        }
        walk(null, 0)
        return out
    }

    fun annotations(bookId: String): List<Annotation> = annotations.values.filter { it.bookId == bookId }
}

/** Orders names the way Finder does: "Part 2" before "Part 10", ignoring case. */
object NaturalOrder : Comparator<String> {
    private val chunk = Regex("\\d+|\\D+")

    override fun compare(a: String, b: String): Int {
        val x = chunk.findAll(a.lowercase()).map { it.value }.toList()
        val y = chunk.findAll(b.lowercase()).map { it.value }.toList()
        for (i in 0 until minOf(x.size, y.size)) {
            val p = x[i]
            val q = y[i]
            val c = if (p[0].isDigit() && q[0].isDigit()) {
                p.trimStart('0').length.compareTo(q.trimStart('0').length).takeIf { it != 0 } ?: p.trimStart('0').compareTo(q.trimStart('0'))
            } else p.compareTo(q)
            if (c != 0) return c
        }
        return x.size.compareTo(y.size)
    }
}
