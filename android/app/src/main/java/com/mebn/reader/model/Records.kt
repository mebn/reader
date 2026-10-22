package com.mebn.reader.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.time.OffsetDateTime

/** Reads what the server sends and writes what it expects: nulls are sent, so a null folder moves a book to the root. */
val json = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
    coerceInputValues = true
}

@Serializable
enum class Format {
    @SerialName("epub") EPUB,
    @SerialName("pdf") PDF,
    @SerialName("fb2") FB2,
    @SerialName("cbz") CBZ,
    @SerialName("txt") TXT;

    val extension: String get() = name.lowercase()

    companion object {
        fun of(fileName: String): Format? =
            entries.firstOrNull { it.extension == fileName.substringAfterLast('.', "").lowercase() }
    }
}

/** A signed-in app on the account, as the server lists it. */
@Serializable
data class Device(
    val id: String,
    val name: String = "",
    val platform: String = "",
    val createdAt: String = "",
    val lastSeenAt: String = "",
    val current: Boolean = false,
    /** Connected for live updates right now. */
    val online: Boolean = false,
) {
    val lastSeenMillis: Long
        get() = runCatching { OffsetDateTime.parse(lastSeenAt).toInstant().toEpochMilli() }.getOrDefault(0)
}

enum class Collection(val path: String) {
    FOLDERS("folders"), BOOKS("books"), PROGRESS("progress"), ANNOTATIONS("annotations"), SETTINGS("settings"),
}

/** Every synced record carries a client `modifiedAt` (ms) and a server-assigned `version`. */
sealed interface SyncRecord {
    val id: String
    val modifiedAt: Long
    val version: Long?
    val deleted: Boolean?
    val isDeleted: Boolean get() = deleted ?: false
    val collection: Collection

    fun stamped(modifiedAt: Long): SyncRecord
    fun encode(): String
}

@Serializable
data class Folder(
    override val id: String,
    override val modifiedAt: Long = 0,
    override val version: Long? = null,
    override val deleted: Boolean? = false,
    val name: String = "",
    val parentId: String? = null,
) : SyncRecord {
    override val collection get() = Collection.FOLDERS
    override fun stamped(modifiedAt: Long) = copy(modifiedAt = modifiedAt)
    override fun encode() = json.encodeToString(serializer(), this)
}

@Serializable
data class Book(
    override val id: String,
    override val modifiedAt: Long = 0,
    override val version: Long? = null,
    override val deleted: Boolean? = false,
    val folderId: String? = null,
    val title: String = "",
    val author: String = "",
    val format: Format = Format.EPUB,
    val fileName: String = "",
    val size: Long = 0,
    val hash: String = "",
    val hasCover: Boolean = false,
    val addedAt: Long = 0,
) : SyncRecord {
    override val collection get() = Collection.BOOKS
    override fun stamped(modifiedAt: Long) = copy(modifiedAt = modifiedAt)
    override fun encode() = json.encodeToString(serializer(), this)
}

/** Progress uses the book ID as its ID. `locator` is a serialized [Locator]. */
@Serializable
data class Progress(
    override val id: String,
    override val modifiedAt: Long = 0,
    override val version: Long? = null,
    override val deleted: Boolean? = null,
    val locator: String = "",
    val percent: Double = 0.0,
) : SyncRecord {
    override val collection get() = Collection.PROGRESS
    override fun stamped(modifiedAt: Long) = copy(modifiedAt = modifiedAt)
    override fun encode() = json.encodeToString(serializer(), this)
}

@Serializable
enum class AnnotationKind {
    @SerialName("highlight") HIGHLIGHT,
    @SerialName("bookmark") BOOKMARK,
}

@Serializable
data class Annotation(
    override val id: String,
    override val modifiedAt: Long = 0,
    override val version: Long? = null,
    override val deleted: Boolean? = null,
    val bookId: String = "",
    val kind: AnnotationKind = AnnotationKind.HIGHLIGHT,
    val locator: String = "",
    val text: String = "",
    val note: String = "",
    val color: String = "",
    val label: String = "",
) : SyncRecord {
    override val collection get() = Collection.ANNOTATIONS
    override fun stamped(modifiedAt: Long) = copy(modifiedAt = modifiedAt)
    override fun encode() = json.encodeToString(serializer(), this)

    val position: Locator get() = Locator.parse(locator)
    val hasNote: Boolean get() = note.isNotBlank()
}

/** Settings use their scope as ID: "app", "reader" or "reader:<bookId>". */
@Serializable
data class Setting(
    override val id: String,
    override val modifiedAt: Long = 0,
    override val version: Long? = null,
    override val deleted: Boolean? = null,
    val data: String = "",
) : SyncRecord {
    override val collection get() = Collection.SETTINGS
    override fun stamped(modifiedAt: Long) = copy(modifiedAt = modifiedAt)
    override fun encode() = json.encodeToString(serializer(), this)
}

fun Collection.decode(text: String): SyncRecord = when (this) {
    Collection.FOLDERS -> json.decodeFromString(Folder.serializer(), text)
    Collection.BOOKS -> json.decodeFromString(Book.serializer(), text)
    Collection.PROGRESS -> json.decodeFromString(Progress.serializer(), text)
    Collection.ANNOTATIONS -> json.decodeFromString(Annotation.serializer(), text)
    Collection.SETTINGS -> json.decodeFromString(Setting.serializer(), text)
}

@Serializable
data class Changes(
    val version: Long = 0,
    val folders: List<Folder>? = null,
    val books: List<Book>? = null,
    val progress: List<Progress>? = null,
    val annotations: List<Annotation>? = null,
    val settings: List<Setting>? = null,
)

@Serializable
data class User(val id: String = "", val email: String = "")

/**
 * A position in a book. Reflowable books use chapter + fraction so positions survive font
 * and window changes; fixed layouts use the page. Text ranges add character offsets,
 * counted the way the desktop app's DOM counts them.
 */
@Serializable
data class Locator(
    val chapter: Int? = null,
    val fraction: Double? = null,
    val page: Int? = null,
    val start: Int? = null,
    val end: Int? = null,
) {
    fun toJson(): String = locatorJson.encodeToString(serializer(), this)

    /** Orders annotations by where they are in the book. */
    val sortKey: Double
        get() = (chapter ?: page ?: 0) * 1e7 + (start?.toDouble() ?: ((fraction ?: 0.0) * 1e6))

    companion object {
        private val locatorJson = Json { ignoreUnknownKeys = true; explicitNulls = false }

        fun parse(text: String): Locator =
            runCatching { locatorJson.decodeFromString(serializer(), text) }.getOrDefault(Locator())
    }
}

fun now(): Long = System.currentTimeMillis()
