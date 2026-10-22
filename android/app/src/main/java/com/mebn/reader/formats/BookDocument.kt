package com.mebn.reader.formats

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Point
import android.graphics.RectF
import android.graphics.pdf.PdfRenderer
import android.graphics.pdf.models.selection.PageSelection
import android.graphics.pdf.models.selection.SelectionBoundary
import android.os.ParcelFileDescriptor
import android.util.LruCache
import com.mebn.reader.ReaderApp
import com.mebn.reader.model.Format
import com.mebn.reader.sync.NaturalOrder
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.io.MemoryUsageSetting
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.interactive.documentnavigation.outline.PDOutlineNode
import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.File
import java.util.zip.ZipFile
import kotlin.math.max
import kotlin.math.roundToInt

data class BookMetadata(
    val title: String,
    val author: String,
    /** BCP 47 language tag, used for hyphenation. */
    val language: String? = null,
)

data class TocEntry(
    val id: Int,
    val label: String,
    val depth: Int,
    val chapter: Int? = null,
    val anchor: String? = null,
    val page: Int? = null,
)

sealed interface LinkTarget {
    data class Chapter(val index: Int, val anchor: String?) : LinkTarget
    data class External(val url: String) : LinkTarget
}

class BookError(message: String) : Exception(message)

/** An image from a book, decoded no larger than needed, with its size in CSS pixels. */
class BookImage(val bitmap: Bitmap, val width: Int, val height: Int)

/** Text that flows into pages: EPUB, FB2, TXT. Safe to read from any thread. */
abstract class ReflowDocument : Closeable {
    abstract val metadata: BookMetadata
    abstract val toc: List<TocEntry>
    abstract val chapterCount: Int

    /**
     * A sanitized copy of a chapter's body. Images carry a `src` that [image] loads; links
     * carry `data-href` (inside the book) or `data-external`.
     */
    abstract fun chapter(index: Int): Node
    abstract fun resolveLink(href: String): LinkTarget?
    abstract fun cover(): ByteArray?
    protected abstract fun imageData(src: String): ByteArray?

    private val images = LruCache<String, BookImage>(48)
    private val missing = mutableSetOf<String>()

    /** An image, decoded at least `maxWidth` pixels wide when it's that large. */
    fun image(src: String, maxWidth: Int): BookImage? {
        val key = "$src|$maxWidth"
        images[key]?.let { return it }
        synchronized(missing) { if (src in missing) return null }
        val data = imageData(src)
        val image = data?.let { decodeImage(it, maxWidth) }
        if (image == null) synchronized(missing) { missing += src } else images.put(key, image)
        return image
    }

    override fun close() {}
}

/** Decodes an image, sampled down to no less than `maxWidth` wide. */
fun decodeImage(data: ByteArray, maxWidth: Int): BookImage? {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
    var sample = 1
    while (bounds.outWidth / (sample * 2) >= maxWidth && bounds.outHeight / (sample * 2) >= 64) sample *= 2
    val bitmap = BitmapFactory.decodeByteArray(data, 0, data.size, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
    return BookImage(bitmap, bounds.outWidth, bounds.outHeight)
}

sealed class BookDocument : Closeable {
    class Reflow(val doc: ReflowDocument) : BookDocument()
    class Pdf(val doc: PdfBook) : BookDocument()
    class Comic(val doc: ComicBook) : BookDocument()

    val metadata: BookMetadata
        get() = when (this) {
            is Reflow -> doc.metadata
            is Pdf -> doc.metadata
            is Comic -> doc.metadata
        }

    val toc: List<TocEntry>
        get() = when (this) {
            is Reflow -> doc.toc
            is Pdf -> doc.toc
            is Comic -> emptyList()
        }

    /** A cover image, if the book has one. */
    fun cover(): ByteArray? = when (this) {
        is Reflow -> doc.cover()
        is Pdf -> doc.cover()
        is Comic -> doc.cover()
    }

    override fun close() = when (this) {
        is Reflow -> doc.close()
        is Pdf -> doc.close()
        is Comic -> doc.close()
    }

    companion object {
        fun open(file: File, format: Format, fileName: String): BookDocument = when (format) {
            Format.EPUB -> Reflow(EpubDocument(file))
            Format.FB2 -> Reflow(Fb2Document(file, fileName))
            Format.TXT -> Reflow(TxtDocument(file, fileName))
            Format.PDF -> Pdf(PdfBook(file, fileName))
            Format.CBZ -> Comic(ComicBook(file, fileName))
        }
    }
}

/** Opens a ZIP archive, reading names that aren't UTF-8 as Latin-1. */
fun openZip(file: File): ZipFile = try {
    ZipFile(file).also { zip -> zip.entries().toList() }
} catch (_: IllegalArgumentException) {
    ZipFile(file, Charsets.ISO_8859_1)
}

fun ZipFile.data(path: String): ByteArray = getEntry(path)?.let { entry -> getInputStream(entry).use { it.readBytes() } }
    ?: throw BookError("missing $path")

fun ZipFile.text(path: String): String = String(data(path), Charsets.UTF_8)

// PDF

/**
 * A PDF, drawn with PdfRenderer. Metadata and the outline come from PdfBox, which reads
 * what PdfRenderer can't. Calls are serialized, as PdfRenderer allows one page at a time.
 */
class PdfBook(file: File, fileName: String) : Closeable {
    private val descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    private val renderer = try {
        PdfRenderer(descriptor)
    } catch (e: Exception) {
        descriptor.close()
        throw BookError("not a PDF")
    }
    val pageCount = renderer.pageCount
    /** Page sizes in points. */
    val sizes: List<Pair<Int, Int>> = (0 until pageCount).map { i -> page(i) { it.width to it.height } }
    val metadata: BookMetadata
    val toc: List<TocEntry>
    private val texts = LruCache<Int, String>(32)

    init {
        var title = ""
        var author = ""
        val entries = mutableListOf<TocEntry>()
        runCatching {
            PDFBoxResourceLoader.init(ReaderApp.context)
            PDDocument.load(file, MemoryUsageSetting.setupTempFileOnly()).use { doc ->
                title = usableTitle(doc.documentInformation?.title)
                author = doc.documentInformation?.author?.trim().orEmpty()
                fun walk(node: PDOutlineNode, depth: Int) {
                    for (item in node.children()) {
                        val page = runCatching { item.findDestinationPage(doc)?.let { doc.pages.indexOf(it) } }.getOrNull()
                        if (page != null && page >= 0) entries += TocEntry(entries.size, item.title?.trim().orEmpty(), depth, page = page)
                        walk(item, depth + 1)
                    }
                }
                doc.documentCatalog.documentOutline?.let { walk(it, 0) }
            }
        }
        metadata = BookMetadata(title.ifEmpty { Paths.nameWithoutExtension(fileName) }, author)
        toc = entries
    }

    private fun <T> page(index: Int, use: (PdfRenderer.Page) -> T): T = synchronized(renderer) {
        renderer.openPage(index).use(use)
    }

    /** A page drawn `width` pixels wide on white. */
    fun render(index: Int, width: Int): Bitmap {
        val (w, h) = sizes[index]
        val height = max(1, (width.toFloat() * h / w).roundToInt())
        val bitmap = Bitmap.createBitmap(max(1, width), height, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(Color.WHITE)
        page(index) { it.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY) }
        return bitmap
    }

    /** The page's text, as selections count it. */
    fun text(index: Int): String = texts[index] ?: page(index) { page -> page.textContents.joinToString("") { it.text } }.also { texts.put(index, it) }

    /** Text between two points, in page points. */
    fun select(index: Int, from: Point, to: Point): PageSelection? =
        runCatching { page(index) { it.selectContent(SelectionBoundary(from), SelectionBoundary(to)) } }.getOrNull()

    /**
     * The range of the page's text a selection made by points covers. Those don't say where
     * they are in the text, so it's found by its words, nearest to where it was made.
     */
    fun locate(index: Int, selection: PageSelection): IntRange? {
        val words = selection.selectedTextContents.joinToString(" ") { it.text }.split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (words.isEmpty()) return null
        val pattern = Regex(words.joinToString("\\s*") { Regex.escape(it) })
        val near = selection.selectedTextContents.firstOrNull()?.bounds?.firstOrNull() ?: return null
        return pattern.findAll(text(index)).map { it.range }.take(64).minByOrNull { range ->
            val r = bounds(index, range.first, range.last + 1).firstOrNull() ?: return@minByOrNull Float.MAX_VALUE
            kotlin.math.abs(r.left - near.left) + kotlin.math.abs(r.top - near.top)
        }
    }

    /** Where a range of the page's text is, in page points, a rect per line. */
    fun bounds(index: Int, start: Int, end: Int): List<RectF> =
        runCatching {
            page(index) { it.selectContent(SelectionBoundary(start), SelectionBoundary(end)) }
                ?.selectedTextContents?.flatMap { it.bounds }.orEmpty()
        }.getOrDefault(emptyList())

    fun cover(): ByteArray? = runCatching {
        val bitmap = render(0, 480)
        ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.JPEG, 85, it) }.toByteArray()
    }.getOrNull()

    override fun close() {
        synchronized(renderer) { renderer.close() }
        descriptor.close()
    }

    /** PDF titles are often left as the source file name or a tool's default. */
    private fun usableTitle(title: String?): String {
        val t = title?.trim().orEmpty()
        if (Regex("\\.[a-z0-9]{2,5}$", RegexOption.IGNORE_CASE).containsMatchIn(t)) return ""
        if (Regex("^(untitled|microsoft word)", RegexOption.IGNORE_CASE).containsMatchIn(t)) return ""
        return t
    }
}

// Comics

class ComicBook(file: File, fileName: String) : Closeable {
    private val zip = openZip(file)
    val pages: List<String> = zip.entries().toList().map { it.name }
        .filter { Regex("\\.(jpe?g|png|gif|webp|avif|bmp)$", RegexOption.IGNORE_CASE).containsMatchIn(it) && !it.startsWith("__MACOSX") }
        .sortedWith(NaturalOrder)
    val metadata = BookMetadata(Paths.nameWithoutExtension(fileName), "")

    fun image(index: Int, maxWidth: Int): Bitmap? =
        pages.getOrNull(index)?.let { path -> runCatching { synchronized(zip) { zip.data(path) } }.getOrNull() }?.let { decodeImage(it, maxWidth)?.bitmap }

    fun cover(): ByteArray? = pages.firstOrNull()?.let { runCatching { zip.data(it) }.getOrNull() }

    override fun close() = zip.close()
}
