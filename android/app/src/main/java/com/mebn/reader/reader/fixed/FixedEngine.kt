package com.mebn.reader.reader.fixed

import android.graphics.Bitmap
import android.graphics.Point
import android.graphics.RectF
import android.util.LruCache
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.systemBarsIgnoringVisibility
import androidx.compose.foundation.layout.union
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import com.mebn.reader.formats.ComicBook
import com.mebn.reader.formats.PdfBook
import com.mebn.reader.formats.TocEntry
import com.mebn.reader.model.Annotation
import com.mebn.reader.model.AnnotationKind
import com.mebn.reader.model.Locator
import com.mebn.reader.model.highlightColor
import com.mebn.reader.reader.Appearance
import com.mebn.reader.reader.PageGestures
import com.mebn.reader.reader.PageTurner
import com.mebn.reader.reader.PageTurnerView
import com.mebn.reader.reader.Position
import com.mebn.reader.reader.ReaderEngine
import com.mebn.reader.reader.ReaderEngineDelegate
import com.mebn.reader.reader.TextSelection
import com.mebn.reader.reader.normalizedSelection
import com.mebn.reader.reader.reflow.ReflowEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Pages that are already laid out: a PDF's, or a comic's images. */
sealed interface FixedSource {
    val pageCount: Int
    val toc: List<TocEntry>
    /** The page's width over its height. */
    fun aspect(index: Int): Float
    fun render(index: Int, width: Int): Bitmap?

    class Pdf(val doc: PdfBook) : FixedSource {
        override val pageCount get() = doc.pageCount
        override val toc = doc.toc.filter { it.depth == 0 && it.page != null }
        override fun aspect(index: Int) = doc.sizes[index].let { it.first.toFloat() / max(1, it.second) }
        override fun render(index: Int, width: Int): Bitmap? = runCatching { doc.render(index, width) }.getOrNull()
    }

    class Comic(val doc: ComicBook) : FixedSource {
        private val aspects = mutableMapOf<Int, Float>()
        override val pageCount get() = doc.pages.size
        override val toc = emptyList<TocEntry>()
        override fun aspect(index: Int) = synchronized(aspects) { aspects[index] } ?: (2f / 3)
        override fun render(index: Int, width: Int): Bitmap? = doc.image(index, width)?.also {
            synchronized(aspects) { aspects[index] = it.width.toFloat() / max(1, it.height) }
        }
    }
}

/** Selected PDF text: the page, the range in its text, and where it is in page points. */
private data class PdfSelection(val page: Int, val start: Int, val end: Int, val rects: List<RectF>, val text: String)

/**
 * Shows PDFs and comics a page (or two) at a time, turned like the books. PDF highlights are
 * stored as character offsets into a page's text and drawn over the page.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class FixedEngine(
    private val source: FixedSource,
    private val delegate: ReaderEngineDelegate,
) : ReaderEngine, PageGestures {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val renderer = Dispatchers.IO.limitedParallelism(1)
    private val turner = PageTurner()
    private val pdf = (source as? FixedSource.Pdf)?.doc

    private var look by mutableStateOf<Appearance?>(null)
    private var page by mutableIntStateOf(0)
    private var area by mutableStateOf(Rect.Zero)
    private var span by mutableIntStateOf(1)
    private var pendingLocator: Locator? = null
    private val bitmaps = mutableStateMapOf<Int, ImageBitmap>()
    private val cache = LruCache<Int, Bitmap>(8)
    private val loading = mutableMapOf<Int, Job>()
    private var renderWidth = 0
    private var marks by mutableStateOf(mapOf<Int, List<Pair<String, Pair<Int, List<RectF>>>>>())
    private var annotations = listOf<Annotation>()
    private var selection by mutableStateOf<PdfSelection?>(null)
    private var selectFrom: Point? = null
    private var view: View? = null
    private var density = 1f

    init {
        turner.canTurn = { forward -> if (forward) page + span < source.pageCount else page > 0 }
        turner.commit = { forward -> show(if (forward) page + span else page - span) }
    }

    // ReaderEngine

    override val position: Position
        get() {
            val toc = source.toc
            val count = source.pageCount
            val chapter = if (toc.isEmpty()) null else max(0, toc.indexOfLast { it.page!! <= page })
            val lastVisible = min(count, page + span)
            val chapterStart = chapter?.let { toc[it].page!! } ?: 0
            val chapterEnd = chapter?.let { if (it + 1 < toc.size) toc[it + 1].page!! else count } ?: count
            return Position(
                chapter, toc.size, page + 1, count,
                chapter?.let { max(1, page - chapterStart + 1) }, chapter?.let { max(1, chapterEnd - chapterStart) },
                lastVisible.toDouble() / max(1, count), Locator(page = page),
            )
        }

    override fun setAppearance(appearance: Appearance) {
        look = appearance
    }

    override fun setAnnotations(annotations: List<Annotation>) {
        this.annotations = annotations.filter { it.kind == AnnotationKind.HIGHLIGHT && it.position.page != null }
        refreshMarks()
    }

    override fun goTo(locator: Locator) {
        if (area == Rect.Zero) {
            pendingLocator = locator
            return
        }
        show(locator.page ?: 0)
    }

    override fun goTo(entry: TocEntry) {
        entry.page?.let { goTo(Locator(page = it)) }
    }

    override fun turn(forward: Boolean) {
        clearSelection()
        turner.turn(forward)
    }

    override fun isVisible(locator: Locator): Boolean {
        val target = locator.page ?: -1
        return target >= page && target < page + span
    }

    override fun pageOf(locator: Locator): Int = (locator.page ?: 0) + 1

    override fun hasReached(entry: TocEntry): Boolean = (entry.page ?: Int.MAX_VALUE) <= page

    override fun clearSelection() {
        if (selection == null) return
        selection = null
        delegate.engineSelected(null, null)
    }

    override fun text(locator: Locator): String? {
        val doc = pdf ?: return null
        val index = locator.page ?: return null
        val start = locator.start ?: return null
        val end = locator.end ?: return null
        val text = doc.text(index)
        if (start > end || end > text.length) return null
        return normalizedSelection(text.substring(start, end))
    }

    override fun dispose() = scope.cancel()

    // Pages

    private fun align(index: Int): Int {
        val clamped = index.coerceIn(0, max(0, source.pageCount - 1))
        return if (span == 2) clamped - clamped % 2 else clamped
    }

    private fun show(index: Int) {
        clearSelection()
        page = align(index)
        for (key in bitmaps.keys.toList()) if (key < page - span * 2 || key >= page + span * 3) bitmaps.remove(key)
        // The pages on either side are drawn ahead, so turning to them is instant.
        for (i in page - span until page + span * 2) request(i)
        refreshMarks()
        delegate.engineChanged(position)
    }

    private fun request(index: Int) {
        if (index !in 0 until source.pageCount || bitmaps.containsKey(index) || loading[index]?.isActive == true) return
        val width = renderWidth
        if (width <= 0) return
        cache.get(index)?.takeIf { it.width >= width }?.let {
            bitmaps[index] = it.asImageBitmap()
            return
        }
        loading[index] = scope.launch {
            val bitmap = withContext(renderer) { source.render(index, width) } ?: return@launch
            if (width != renderWidth) return@launch
            cache.put(index, bitmap)
            bitmaps[index] = bitmap.asImageBitmap()
        }
    }

    private fun applyArea(next: Rect, nextSpan: Int) {
        if (next == area && nextSpan == span) return
        val first = area == Rect.Zero
        val here = page
        area = next
        span = nextSpan
        val width = (next.width / nextSpan).roundToInt()
        if (width != renderWidth) {
            renderWidth = width
            bitmaps.clear()
            cache.evictAll()
            loading.values.forEach { it.cancel() }
            loading.clear()
        }
        val pending = pendingLocator
        pendingLocator = null
        show(if (first && pending != null) pending.page ?: 0 else here)
    }

    /** Where a page sits on screen: fitted into its half of a spread, or the whole area. */
    private fun frame(index: Int, column: Int): Rect {
        val cell = Rect(area.left + column * area.width / span, area.top, area.left + (column + 1) * area.width / span, area.bottom)
        val aspect = source.aspect(index)
        var w = cell.width
        var h = w / aspect
        if (h > cell.height) {
            h = cell.height
            w = h * aspect
        }
        // Facing pages meet at the spine.
        val x = when {
            span == 1 -> cell.left + (cell.width - w) / 2
            column == 0 -> cell.right - w
            else -> cell.left
        }
        val y = cell.top + (cell.height - h) / 2
        return Rect(x, y, x + w, y + h)
    }

    // Drawing

    @OptIn(ExperimentalLayoutApi::class)
    @Composable
    override fun Content(modifier: Modifier) {
        val pixels = LocalDensity.current
        val direction = LocalLayoutDirection.current
        val insets = WindowInsets.systemBarsIgnoringVisibility.union(WindowInsets.displayCutout)
        view = LocalView.current
        density = pixels.density
        BoxWithConstraints(modifier.fillMaxSize()) {
            val d = pixels.density
            val pad = if (pdf != null) 0f else 12 * d
            val top = insets.getTop(pixels) + (if (pdf != null) 8 else 28) * d
            val bottom = insets.getBottom(pixels) + (if (pdf != null) 8 else 28) * d
            val next = Rect(insets.getLeft(pixels, direction) + pad, top, constraints.maxWidth - insets.getRight(pixels, direction) - pad, constraints.maxHeight - bottom)
            val wantSpan = if ((look?.settings?.pages ?: 1) == 2 && constraints.maxWidth / d > 760) 2 else 1
            LaunchedEffect(next, wantSpan) { applyArea(next, wantSpan) }

            val background = look?.background
            // Dark PDF pages are inverted with their hues kept, as the desktop app does.
            val invert = pdf != null && background?.dark == true
            val pageColor = Color(background?.color ?: 0)
            PageTurnerView(turner, this@FixedEngine, background = pageColor) { offset ->
                val first = when (offset) {
                    0 -> page
                    1 -> page + span
                    else -> page - span
                }
                Canvas(Modifier.fillMaxSize()) {
                    for (column in 0 until span) {
                        val index = first + column
                        if (index !in 0 until source.pageCount) continue
                        val image = bitmaps[index] ?: continue
                        val f = frame(index, column)
                        drawImage(
                            image,
                            dstOffset = IntOffset(f.left.roundToInt(), f.top.roundToInt()),
                            dstSize = IntSize(f.width.roundToInt(), f.height.roundToInt()),
                            colorFilter = if (invert) invertFilter else null,
                        )
                        val scale = f.width / max(1, pdf?.sizes?.get(index)?.first ?: 1)
                        for ((_, mark) in marks[index].orEmpty()) {
                            val (color, rects) = mark
                            for (r in rects) {
                                drawRect(Color(color).copy(alpha = 0.4f), Offset(f.left + r.left * scale, f.top + r.top * scale), Size(r.width() * scale, r.height() * scale))
                            }
                        }
                        val sel = selection?.takeIf { it.page == index && offset == 0 }
                        for (r in sel?.rects.orEmpty()) {
                            drawRect(Color(ReflowEngine.ACCENT).copy(alpha = 0.28f), Offset(f.left + r.left * scale, f.top + r.top * scale), Size(r.width() * scale, r.height() * scale))
                        }
                    }
                }
            }
        }
    }

    // Highlights

    private fun refreshMarks() {
        val doc = pdf ?: return
        val visible = (page - span until page + span * 2).filter { it in 0 until source.pageCount }
        val list = annotations.filter { it.position.page in visible }
        scope.launch {
            val out = withContext(renderer) {
                list.mapNotNull { a ->
                    val index = a.position.page!!
                    val range = resolve(doc, a, index) ?: return@mapNotNull null
                    index to (a.id to (highlightColor(a.color) to doc.bounds(index, range.first, range.last + 1)))
                }
            }
            marks = out.groupBy({ it.first }, { it.second })
        }
    }

    /**
     * The range of a highlight on its page. Offsets from another device's PDF text may differ
     * slightly, so the stored text is looked for when they don't match.
     */
    private fun resolve(doc: PdfBook, a: Annotation, index: Int): IntRange? {
        val text = doc.text(index)
        val start = a.position.start ?: return null
        val end = a.position.end ?: return null
        val wanted = normalizedSelection(a.text)
        if (end <= text.length && start < end && normalizedSelection(text.substring(start, end)) == wanted) return start until end
        if (wanted.isEmpty()) return null
        val pattern = wanted.split(' ').joinToString("\\s+") { Regex.escape(it) }
        return Regex(pattern).findAll(text).minByOrNull { abs(it.range.first - start) }?.range
    }

    // Gestures

    /** The page under a point, and the point in its own points. */
    private fun pageAt(point: Offset): Pair<Int, Point>? {
        val doc = pdf ?: return null
        for (column in 0 until span) {
            val index = page + column
            if (index >= source.pageCount) break
            val f = frame(index, column)
            if (!f.contains(point)) continue
            val scale = doc.sizes[index].first / f.width
            return index to Point(((point.x - f.left) * scale).roundToInt(), ((point.y - f.top) * scale).roundToInt())
        }
        return null
    }

    override fun onTap(point: Offset) {
        val hit = pageAt(point)
        if (hit != null) {
            val (index, p) = hit
            marks[index]?.lastOrNull { (_, mark) -> mark.second.any { it.contains(p.x.toFloat(), p.y.toFloat()) } }?.let {
                delegate.engineTappedAnnotation(it.first)
                return
            }
        }
        if (selection != null) {
            clearSelection()
            return
        }
        delegate.engineTapped(point.x / max(1f, turner.width))
    }

    override fun beginSelection(point: Offset): Boolean {
        val doc = pdf ?: return false
        val (index, p) = pageAt(point) ?: return false
        selectFrom = p
        val word = selectWord(doc, index, p) ?: return false
        selection = word
        view?.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
        delegate.engineSelected(null, null)
        return true
    }

    /** The word under a point. */
    private fun selectWord(doc: PdfBook, index: Int, p: Point): PdfSelection? {
        val hit = doc.select(index, p, p) ?: return null
        val range = doc.locate(index, hit) ?: return null
        return selection(doc, index, range.first, range.last + 1)
    }

    /** Selected text from `start` to `end`, widened to whole words. */
    private fun selection(doc: PdfBook, index: Int, from: Int, to: Int): PdfSelection? {
        val text = doc.text(index)
        var start = from
        var end = to
        while (start > 0 && text[start - 1].isLetterOrDigit()) start--
        while (end < text.length && text[end].isLetterOrDigit()) end++
        if (start >= end || end > text.length) return null
        return PdfSelection(index, start, end, doc.bounds(index, start, end), text.substring(start, end))
    }

    override fun extendSelection(point: Offset) {
        val doc = pdf ?: return
        val sel = selection ?: return
        val (index, p) = pageAt(point) ?: return
        if (index != sel.page) return
        val from = selectFrom ?: return
        val hit = doc.select(index, from, p) ?: return
        val range = doc.locate(index, hit) ?: return
        val next = selection(doc, index, range.first, range.last + 1) ?: return
        if (next.start != sel.start || next.end != sel.end) {
            selection = next
            view?.performHapticFeedback(HapticFeedbackConstants.TEXT_HANDLE_MOVE)
        }
    }

    override fun endSelection() {
        val sel = selection ?: return
        val doc = pdf ?: return
        val text = normalizedSelection(sel.text)
        if (text.isEmpty()) return
        val column = sel.page - page
        val f = frame(sel.page, column)
        val scale = f.width / doc.sizes[sel.page].first
        val bounds = sel.rects.fold(RectF(sel.rects.firstOrNull() ?: RectF())) { acc, r -> acc.apply { union(r) } }
        val anchor = Rect(f.left + bounds.left * scale, f.top + bounds.top * scale, f.left + bounds.right * scale, f.top + bounds.bottom * scale)
        delegate.engineSelected(TextSelection(Locator(page = sel.page, start = sel.start, end = sel.end), text), anchor)
    }

    override fun onDragStart() = clearSelection()

    companion object {
        /** Inverts colors, then turns hues back around, so dark pages keep their colors. */
        private val invertFilter: ColorFilter = run {
            val h = floatArrayOf(-0.574f, 1.43f, 0.144f, 0.426f, 0.43f, 0.144f, 0.426f, 1.43f, -0.856f)
            val lift = 255f + 10f
            ColorFilter.colorMatrix(
                ColorMatrix(
                    floatArrayOf(
                        -h[0], -h[1], -h[2], 0f, lift,
                        -h[3], -h[4], -h[5], 0f, lift,
                        -h[6], -h[7], -h[8], 0f, lift,
                        0f, 0f, 0f, 1f, 0f,
                    ),
                ),
            )
        }
    }
}
