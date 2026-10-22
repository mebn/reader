package com.mebn.reader.reader.reflow

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.util.Log
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.core.graphics.ColorUtils
import com.mebn.reader.formats.LinkTarget
import com.mebn.reader.formats.Node
import com.mebn.reader.formats.ReflowDocument
import com.mebn.reader.formats.TocEntry
import com.mebn.reader.model.Annotation
import com.mebn.reader.model.AnnotationKind
import com.mebn.reader.model.Locator
import com.mebn.reader.reader.Appearance
import com.mebn.reader.reader.PageGestures
import com.mebn.reader.reader.PageTurner
import com.mebn.reader.reader.PageTurnerView
import com.mebn.reader.reader.Position
import com.mebn.reader.reader.ReaderEngine
import com.mebn.reader.reader.ReaderEngineDelegate
import com.mebn.reader.reader.TextSelection
import com.mebn.reader.reader.normalizedSelection
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Page counts per layout, shared across books opened in this session. */
private val pageCountCache = mutableMapOf<String, List<Int>>()

private data class Geometry(
    val width: Int,
    val height: Int,
    val column: Int,
    val gap: Int,
    val pageHeight: Int,
    /** Pages visible at once. */
    val span: Int,
    /** Where the first page's text starts. */
    val originX: Int,
    val originY: Int,
)

data class PageKey(val chapter: Int, val page: Int)

/** Text selected on one page: which column of a spread, and the range in the chapter's text. */
private data class Selection(val key: PageKey, val column: Int, val start: Int, val end: Int)

/**
 * Shows reflowable books (EPUB, FB2, TXT) as pages to turn. Each chapter is laid out as one
 * tall text layout cut into pages; the whole book is counted in the background so pages
 * have numbers.
 */
class ReflowEngine(
    private val doc: ReflowDocument,
    private val bookId: String,
    private val delegate: ReaderEngineDelegate,
) : ReaderEngine, PageGestures {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val turner = PageTurner()

    private var look by mutableStateOf<Appearance?>(null)
    private var frame by mutableStateOf<Geometry?>(null)
    private var density = 1f
    private val layouts = mutableStateMapOf<Int, ChapterLayout>()
    private val building = mutableMapOf<Int, Deferred<ChapterLayout>>()
    /** Bumped on every relayout, so work for an older one is dropped. */
    private var generation = 0
    /** Bumped on every jump, so only the last one lands. */
    private var jump = 0
    private var current by mutableStateOf(PageKey(0, 0))
    private var bookPages by mutableStateOf<List<Int>?>(null)
    private var paginateJob: Job? = null
    /** Where to go once the first layout is done. */
    private var pendingLocator: Locator? = null
    /** Where the reader is or is headed, kept while a layout is being redone. */
    private var landing: Locator? = null
    private var annotations = listOf<Annotation>()
    private var marksVersion by mutableIntStateOf(0)
    private var selection by mutableStateOf<Selection?>(null)
    /** The word a long press started on, which a drag grows from. */
    private var anchorWord: IntRange? = null
    private var view: View? = null

    init {
        turner.canTurn = { forward -> neighbor(current, forward) != null }
        turner.commit = { forward -> neighbor(current, forward)?.let(::settle) }
    }

    // ReaderEngine

    override val position: Position?
        get() {
            val layout = layouts[current.chapter] ?: return null
            val g = frame ?: return null
            val page = current.page
            val chapterPages = layout.pageCount
            val fraction = page.toDouble() / chapterPages
            // The first character on the page pins the position exactly on any device; the
            // fraction is for readers that don't know it.
            val range = layout.characterRange(page)
            val first = layout.text.domRange(range.first, range.last + 1)?.first
            val locator = Locator(chapter = current.chapter, fraction = fraction, start = first)
            val pages = bookPages
            val total = pages?.sum()
            val bookPage = pages?.let { it.take(current.chapter).sum() + page + 1 }
            val percent = if (total != null && bookPage != null && total > 0) {
                min(1.0, (bookPage + g.span - 1).toDouble() / total)
            } else {
                (current.chapter + fraction) / max(1, doc.chapterCount)
            }
            return Position(current.chapter, doc.chapterCount, bookPage, total, page + 1, chapterPages, percent, locator)
        }

    override fun setAppearance(appearance: Appearance) {
        if (appearance == look) return
        look = appearance
        if (frame != null) relayout()
    }

    override fun setAnnotations(annotations: List<Annotation>) {
        this.annotations = annotations.filter { it.kind == AnnotationKind.HIGHLIGHT }
        for (layout in layouts.values) layout.setHighlights(highlights(layout.index))
        marksVersion++
    }

    override fun goTo(locator: Locator) {
        if (frame == null || look == null) {
            pendingLocator = locator
            return
        }
        val target = (locator.chapter ?: 0).coerceIn(0, max(0, doc.chapterCount - 1))
        landing = locator
        navigate(target) { layout ->
            val page = locator.start?.let { layout.pageOfDom(it) } ?: floor((locator.fraction ?: 0.0) * layout.pageCount + 1e-6).toInt()
            align(page, layout)
        }
    }

    override fun goTo(entry: TocEntry) {
        entry.chapter?.let { goToAnchor(it, entry.anchor) }
    }

    override fun turn(forward: Boolean) {
        clearSelection()
        turner.turn(forward)
    }

    override fun isVisible(locator: Locator): Boolean {
        val span = frame?.span ?: 1
        if (locator.chapter != current.chapter) return false
        val layout = layouts[current.chapter] ?: return false
        val target = locator.start?.let { layout.pageOfDom(it) } ?: floor((locator.fraction ?: 0.0) * layout.pageCount + 1e-6).toInt()
        return target >= current.page && target < current.page + span
    }

    override fun pageOf(locator: Locator): Int? {
        val pages = bookPages ?: return null
        val target = (locator.chapter ?: 0).coerceIn(0, max(0, pages.size - 1))
        val before = pages.take(target).sum()
        val layout = layouts[current.chapter]
        val start = locator.start
        val inChapter = if (target == current.chapter && start != null && layout != null) {
            layout.pageOfDom(start)
        } else {
            floor((locator.fraction ?: 0.0) * pages[target] + 1e-6).toInt()
        }
        return before + inChapter.coerceIn(0, max(0, pages[target] - 1)) + 1
    }

    override fun text(locator: Locator): String? {
        val layout = layouts[locator.chapter ?: return null] ?: return null
        val range = layout.text.displayRange(locator.start ?: return null, locator.end ?: return null) ?: return null
        return normalizedSelection(layout.text.text.subSequence(range.first, range.last + 1).toString())
    }

    override fun clearSelection() {
        if (selection == null) return
        selection = null
        anchorWord = null
        delegate.engineSelected(null, null)
    }

    /** Entries inside the current chapter count by their anchor's page, since one file often holds several chapters. */
    override fun hasReached(entry: TocEntry): Boolean {
        val target = entry.chapter ?: return false
        if (target != current.chapter) return target < current.chapter
        val layout = layouts[current.chapter] ?: return true
        val index = entry.anchor?.let { layout.text.anchors[it] } ?: return true
        return layout.page(index) < current.page + (frame?.span ?: 1)
    }

    override fun dispose() = scope.cancel()

    // Layout

    private fun computeGeometry(width: Int, height: Int, safeTop: Int, safeBottom: Int, safeLeft: Int, safeRight: Int): Geometry? {
        val settings = look?.settings ?: return null
        if (width <= 0 || height <= 0) return null
        val d = density
        val top = max(52 * d, safeTop + 34 * d)
        val bottom = max(52 * d, safeBottom + 34 * d)
        val w = (width - safeLeft - safeRight).toFloat()
        val h = max(120 * d, height - top - bottom)
        // The margin is a share of the width, as on the desktop, but scaled down on narrow
        // screens where a fifth of the width each side would leave a sliver of text.
        val scale = min(1f, max(0.35f, w / d / 900))
        val margin = max(16 * d, (w * settings.sideMargin.toFloat() / 100 * scale).roundToInt().toFloat())
        val span = if (settings.pages == 2 && w / d > 760) 2 else 1
        val gap = if (span == 2) (w * 0.05f).coerceIn(40 * d, 96 * d).roundToInt() else 0
        val column = floor(if (span == 2) (w - margin * 2 - gap) / 2 else w - margin * 2).toInt()
        return Geometry(width, height, column, gap, floor(h).toInt(), span, (safeLeft + margin).roundToInt(), top.roundToInt())
    }

    private fun applyFrame(next: Geometry?) {
        if (next == null || next == frame) return
        frame = next
        relayout()
    }

    /** Lays everything out again, keeping the reading position. */
    private fun relayout() {
        // Keeps the same text at the top of the page, not the same share of the chapter.
        val here = position?.locator ?: landing
        generation++
        building.values.forEach { it.cancel() }
        building.clear()
        layouts.clear()
        paginateJob?.cancel()
        selection = null
        bookPages = pageCountCache[cacheKey]

        val pending = pendingLocator
        pendingLocator = null
        goTo(pending ?: here ?: Locator(chapter = current.chapter, fraction = 0.0))
        if (bookPages == null) paginate()
    }

    private val style: TextStyle
        get() {
            val g = frame!!
            val a = look!!
            return TextStyle(a.settings, a.background.text, g.column, g.pageHeight, doc.metadata.language, density)
        }

    private fun load(index: Int): Deferred<ChapterLayout> {
        building[index]?.let { return it }
        val gen = generation
        val style = style
        val job = scope.async {
            val layout = withContext(Dispatchers.Default) { ChapterLayout(index, buildText(index, style), style) }
            if (gen == generation) {
                layout.setHighlights(highlights(index))
                layouts[index] = layout
            }
            layout
        }
        building[index] = job
        return job
    }

    private fun buildText(index: Int, style: TextStyle): ChapterText {
        val root = runCatching { doc.chapter(index) }.getOrElse { Node.element("body") }
        return ChapterTextBuilder(style) { src, width -> doc.image(src, width) }.build(root)
    }

    /** Goes to a page of a chapter once it's laid out. */
    private fun navigate(chapter: Int, page: (ChapterLayout) -> Int) {
        val token = ++jump
        val gen = generation
        scope.launch {
            val layout = runCatching { load(chapter).await() }
                .onFailure { if (it !is CancellationException) Log.w("reflow", "couldn't lay out chapter $chapter", it) }
                .getOrNull() ?: return@launch
            if (token != jump || gen != generation) return@launch
            clearSelection()
            settle(PageKey(chapter, page(layout)))
        }
    }

    private fun highlights(chapter: Int) = annotations.filter { it.position.chapter == chapter }

    private fun align(page: Int, layout: ChapterLayout): Int {
        val span = frame?.span ?: 1
        val clamped = page.coerceIn(0, layout.pageCount - 1)
        return clamped - clamped % span
    }

    private val cacheKey: String
        get() = "$bookId|${look?.settings?.layoutKey(frame?.column ?: 0, frame?.pageHeight ?: 0) ?: ""}|${frame?.span}|$density"

    /** Counts every chapter's pages in the background to number pages across the book. */
    private fun paginate() {
        val key = cacheKey
        val style = style
        val count = doc.chapterCount
        paginateJob = scope.launch {
            // Wait for resizing to settle before starting.
            delay(300)
            val counts = mutableListOf<Int>()
            for (i in 0 until count) {
                counts += withContext(Dispatchers.Default) { ChapterLayout(i, buildText(i, style), style).pageCount }
            }
            pageCountCache[key] = counts
            if (key == cacheKey) {
                bookPages = counts
                emit()
            }
        }
    }

    // Pages

    /** The page before or after, when it's known; `prefetch` lays out a chapter that isn't yet. */
    private fun neighbor(key: PageKey, forward: Boolean, prefetch: Boolean = true): PageKey? {
        val span = frame?.span ?: 1
        if (forward) {
            val layout = layouts[key.chapter] ?: return null
            if (key.page + span < layout.pageCount) return PageKey(key.chapter, key.page + span)
            if (key.chapter + 1 >= doc.chapterCount) return null
            if (prefetch && layouts[key.chapter + 1] == null) load(key.chapter + 1)
            return PageKey(key.chapter + 1, 0)
        }
        if (key.page > 0) return PageKey(key.chapter, max(0, key.page - span))
        if (key.chapter == 0) return null
        val previous = layouts[key.chapter - 1] ?: run { if (prefetch) load(key.chapter - 1); return null }
        return PageKey(key.chapter - 1, align(previous.pageCount - 1, previous))
    }

    /** Makes a page the current one, and drops chapters that are far away. */
    private fun settle(key: PageKey) {
        clearSelection()
        current = key
        for (index in layouts.keys.toList()) if (abs(index - key.chapter) > 1) layouts.remove(index)
        for (index in building.keys.toList()) if (abs(index - key.chapter) > 1) building.remove(index)?.cancel()
        // The chapters on either side are laid out ahead, so turning into them is instant.
        if (key.chapter + 1 < doc.chapterCount) load(key.chapter + 1)
        if (key.chapter > 0) load(key.chapter - 1)
        emit()
    }

    private fun emit() {
        position?.let {
            landing = it.locator
            delegate.engineChanged(it)
        }
    }

    private fun goToAnchor(chapter: Int, anchor: String?) {
        navigate(chapter) { layout ->
            anchor?.let { layout.text.anchors[it] }?.let { align(layout.page(it), layout) } ?: 0
        }
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
            val g = computeGeometry(
                constraints.maxWidth, constraints.maxHeight,
                insets.getTop(pixels), insets.getBottom(pixels), insets.getLeft(pixels, direction), insets.getRight(pixels, direction),
            )
            LaunchedEffect(g, look) { applyFrame(g) }
            val background = Color(look?.background?.color ?: 0)
            PageTurnerView(turner, this@ReflowEngine, background = background) { offset ->
                val key = when (offset) {
                    0 -> current
                    else -> neighbor(current, offset > 0, prefetch = false)
                }
                Canvas(Modifier.fillMaxSize()) {
                    marksVersion
                    drawIntoCanvas { if (key != null) drawSpread(it.nativeCanvas, key, offset == 0) }
                }
            }
        }
    }

    private val handlePaint = Paint(Paint.ANTI_ALIAS_FLAG)

    private fun drawSpread(canvas: Canvas, key: PageKey, isCurrent: Boolean) {
        val g = frame ?: return
        val layout = layouts[key.chapter] ?: return
        val sel = selection?.takeIf { isCurrent && it.key == key }
        for (column in 0 until g.span) {
            val page = key.page + column
            if (page >= layout.pages.size) break
            canvas.save()
            canvas.translate((g.originX + column * (g.column + g.gap)).toFloat(), g.originY.toFloat())
            val range = sel?.takeIf { it.column == column }?.let { it.start until it.end }
            layout.draw(canvas, page, range, ColorUtils.setAlphaComponent(ACCENT, 72))
            if (range != null) drawHandles(canvas, layout, page, range)
            canvas.restore()
        }
    }

    private fun drawHandles(canvas: Canvas, layout: ChapterLayout, page: Int, range: IntRange) {
        handlePaint.color = ACCENT
        val r = HANDLE_RADIUS * density
        for (atEnd in listOf(false, true)) {
            val (x, top, bottom) = layout.caret(page, if (atEnd) range.last + 1 else range.first, atEnd) ?: continue
            canvas.drawRect(x - density, top, x + density, bottom, handlePaint)
            // A teardrop below the line, its point at the selection's edge.
            val cx = if (atEnd) x + r * 0.7f else x - r * 0.7f
            canvas.drawCircle(cx, bottom + r, r, handlePaint)
            canvas.drawRect(if (atEnd) x else x - r * 0.7f, bottom, if (atEnd) x + r * 0.7f else x, bottom + r, handlePaint)
        }
    }

    // Gestures

    /** Which page of the spread a point is on, and where on it. */
    private fun locate(point: Offset): Triple<Int, Float, Float>? {
        val g = frame ?: return null
        val x = point.x - g.originX
        val column = if (g.span == 2 && x > g.column + g.gap / 2f) 1 else 0
        return Triple(column, x - column * (g.column + g.gap), point.y - g.originY)
    }

    override fun onTap(point: Offset) {
        // A tap with text selected only clears the selection.
        if (selection != null) {
            clearSelection()
            return
        }
        val layout = layouts[current.chapter]
        val located = locate(point)
        if (layout != null && located != null) {
            val (column, x, y) = located
            val index = layout.characterAt(current.page + column, x, y, onText = true)
            if (index != null) {
                layout.marks.lastOrNull { index >= it.start && index < it.end }?.let {
                    delegate.engineTappedAnnotation(it.id)
                    return
                }
                layout.text.link(index)?.let {
                    follow(it)
                    return
                }
            }
        }
        delegate.engineTapped(point.x / max(1f, turner.width))
    }

    override fun beginSelection(point: Offset): Boolean {
        val layout = layouts[current.chapter] ?: return false
        val (column, x, y) = locate(point) ?: return false
        val page = current.page + column
        if (page >= layout.pages.size) return false
        val index = layout.characterAt(page, x, y, onText = true) ?: return false
        val word = layout.word(index)
        // Holding between words selects nothing, rather than a lone space.
        if (layout.text.text.subSequence(word.first, word.last + 1).isBlank()) return false
        anchorWord = word
        selection = Selection(current, column, word.first, word.last + 1)
        view?.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
        delegate.engineSelected(null, null)
        return true
    }

    override fun extendSelection(point: Offset) {
        val sel = selection ?: return
        val anchor = anchorWord ?: return
        val layout = layouts[sel.key.chapter] ?: return
        val (_, x, y) = locate(point) ?: return
        val g = frame ?: return
        val px = x.coerceIn(0f, g.column.toFloat())
        val index = layout.characterAt(sel.key.page + sel.column, px, y, onText = false) ?: return
        val word = layout.word(index)
        var start = min(anchor.first, word.first)
        var end = max(anchor.last, word.last) + 1
        // Dragging into the space between paragraphs doesn't take the break.
        val text = layout.text.text
        while (end > start + 1 && text[end - 1].isWhitespace()) end--
        while (start < end - 1 && text[start].isWhitespace()) start++
        val next = sel.copy(start = start, end = end)
        if (next != sel) {
            selection = next
            view?.performHapticFeedback(HapticFeedbackConstants.TEXT_HANDLE_MOVE)
        }
    }

    override fun endSelection() = report()

    override fun handleAt(point: Offset): Int? {
        val sel = selection ?: return null
        val layout = layouts[sel.key.chapter] ?: return null
        val g = frame ?: return null
        val page = sel.key.page + sel.column
        val r = HANDLE_RADIUS * density
        val left = g.originX + sel.column * (g.column + g.gap)
        for ((i, atEnd) in listOf(false, true).withIndex()) {
            val (x, _, bottom) = layout.caret(page, if (atEnd) sel.end else sel.start, atEnd) ?: continue
            val cx = left + x + if (atEnd) r * 0.7f else -r * 0.7f
            val cy = g.originY + bottom + r
            if ((point - Offset(cx, cy)).getDistance() < r * 2.4f) return i
        }
        return null
    }

    override fun dragHandle(handle: Int, point: Offset) {
        val sel = selection ?: return
        val layout = layouts[sel.key.chapter] ?: return
        val g = frame ?: return
        val left = g.originX + sel.column * (g.column + g.gap)
        // Aim at the line above the knob, not the knob itself.
        val x = point.x - left
        val y = point.y - g.originY - HANDLE_RADIUS * density * 2 - layout.style.fontSize * 0.6f
        val at = layout.boundary(sel.key.page + sel.column, x, y)
        val next = if (handle == 0) sel.copy(start = min(at, sel.end - 1)) else sel.copy(end = max(at, sel.start + 1))
        if (next != sel) {
            selection = next
            view?.performHapticFeedback(HapticFeedbackConstants.TEXT_HANDLE_MOVE)
            delegate.engineSelected(null, null)
        }
    }

    override fun endHandle() = report()

    override fun onDragStart() = clearSelection()

    /** Tells the reader screen what's selected and where, to show its menu. */
    private fun report() {
        val sel = selection ?: return
        val layout = layouts[sel.key.chapter] ?: return
        val g = frame ?: return
        val dom = layout.text.domRange(sel.start, sel.end) ?: return
        val text = normalizedSelection(layout.text.text.subSequence(sel.start, sel.end).toString())
        if (text.isEmpty()) return
        val page = sel.key.page + sel.column
        val top = layout.pages[page].top
        val left = g.originX + sel.column * (g.column + g.gap)
        val rects = layout.rects(page, sel.start, sel.end)
        val bounds = rects.fold(RectF(rects.firstOrNull() ?: RectF())) { acc, r -> acc.apply { union(r) } }
        val anchor = Rect(left + bounds.left, g.originY + bounds.top - top, left + bounds.right, g.originY + bounds.bottom - top)
        delegate.engineSelected(TextSelection(Locator(chapter = sel.key.chapter, start = dom.first, end = dom.second), text), anchor)
    }

    private fun follow(link: String) {
        if (link.startsWith("ext:")) {
            delegate.engineOpen(link.removePrefix("ext:"))
        } else if (link.startsWith("int:")) {
            val target = doc.resolveLink(link.removePrefix("int:"))
            if (target is LinkTarget.Chapter) goToAnchor(target.index, target.anchor)
        }
    }

    companion object {
        /** The selection color, as the app's accent. */
        const val ACCENT = 0xff3d7bf7.toInt()
        private const val HANDLE_RADIUS = 10f
    }
}
