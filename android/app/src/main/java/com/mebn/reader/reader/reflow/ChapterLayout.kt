package com.mebn.reader.reader.reflow

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.text.LineBreaker
import android.icu.text.BreakIterator
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import androidx.core.graphics.ColorUtils
import com.mebn.reader.model.Annotation
import com.mebn.reader.model.BookFonts
import com.mebn.reader.model.highlightColor
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

/** A page: a run of lines, and where it starts and ends in the layout, in pixels. */
class PageLines(val first: Int, val last: Int, val top: Int, val bottom: Int)

/** A highlight placed in the text. */
class Mark(val id: String, val start: Int, val end: Int, val color: Int, val note: Boolean)

/** A chapter flowed into one tall layout and cut into pages a line at a time. */
class ChapterLayout(val index: Int, val text: ChapterText, val style: TextStyle) {
    val layout: StaticLayout
    val pages: List<PageLines>
    private val locale = style.language?.let { Locale.forLanguageTag(it) } ?: Locale.getDefault()
    /** Space a line has above or below its glyphs, from its paragraph, to leave out at page edges. */
    private val spaceBefore: IntArray
    private val spaceAfter: IntArray
    @Volatile var marks: List<Mark> = emptyList()

    val pageCount get() = max(1, pages.size)

    init {
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG)
        paint.textSize = style.fontSize
        paint.typeface = BookFonts.typeface(style.settings.font, style.settings.weight)
        paint.color = style.text
        paint.textLocale = locale
        layout = StaticLayout.Builder.obtain(text.text, 0, text.length, paint, style.columnWidth)
            .setIncludePad(false)
            .setUseLineSpacingFromFallbacks(false)
            .setLineSpacing(0f, 1f)
            .setBreakStrategy(LineBreaker.BREAK_STRATEGY_HIGH_QUALITY)
            .setHyphenationFrequency(if (style.settings.hyphenate) Layout.HYPHENATION_FREQUENCY_NORMAL else Layout.HYPHENATION_FREQUENCY_NONE)
            .setJustificationMode(if (ChapterTextBuilder.justified(style.settings)) LineBreaker.JUSTIFICATION_MODE_INTER_WORD else LineBreaker.JUSTIFICATION_MODE_NONE)
            .build()

        val lines = layout.lineCount
        spaceBefore = IntArray(lines)
        spaceAfter = IntArray(lines)
        var p = 0
        for (line in 0 until lines) {
            val start = layout.getLineStart(line)
            val end = layout.getLineEnd(line)
            while (p < text.paragraphs.size && text.paragraphs[p].end <= start) p++
            val paragraph = text.paragraphs.getOrNull(p) ?: continue
            if (start == paragraph.start) spaceBefore[line] = paragraph.before
            if (end == paragraph.end) spaceAfter[line] = paragraph.after
        }
        pages = paginate()
    }

    private fun paginate(): List<PageLines> {
        val out = mutableListOf<PageLines>()
        val lines = layout.lineCount
        var line = 0
        while (line < lines) {
            val first = line
            val top = layout.getLineTop(first) + spaceBefore[first]
            var last = first
            while (last + 1 < lines && layout.getLineBottom(last + 1) - spaceAfter[last + 1] - top <= style.pageHeight) last++
            out += PageLines(first, last, top, layout.getLineBottom(last) - spaceAfter[last])
            line = last + 1
        }
        return out
    }

    /** The characters on a page. */
    fun characterRange(page: Int): IntRange {
        val p = pages.getOrNull(page) ?: return text.length until text.length
        return layout.getLineStart(p.first) until layout.getLineEnd(p.last)
    }

    /** The page a character is on. */
    fun page(character: Int): Int {
        if (pages.isEmpty() || text.length == 0) return 0
        val line = layout.getLineForOffset(min(character, text.length - 1))
        var lo = 0
        var hi = pages.size - 1
        while (lo < hi) {
            val mid = (lo + hi + 1) / 2
            if (pages[mid].first <= line) lo = mid else hi = mid - 1
        }
        return lo
    }

    fun pageOfDom(offset: Int) = page(text.displayIndex(offset))

    fun setHighlights(highlights: List<Annotation>) {
        marks = highlights.mapNotNull { a ->
            val loc = a.position
            val range = text.displayRange(loc.start ?: return@mapNotNull null, loc.end ?: return@mapNotNull null) ?: return@mapNotNull null
            Mark(a.id, range.first, range.last + 1, highlightColor(a.color), a.hasNote)
        }
    }

    // Geometry

    /** The visible end of a line, without its trailing spaces and break. */
    private fun visibleEnd(line: Int): Int {
        var end = layout.getLineEnd(line)
        val start = layout.getLineStart(line)
        while (end > start && text.text[end - 1].isWhitespace()) end--
        return end
    }

    /** Where a character boundary is on its line, as drawn, justification included. */
    private fun edge(line: Int, offset: Int): Float =
        if (offset >= layout.getLineEnd(line) && offset > layout.getLineStart(line)) layout.getLineRight(line) else layout.getPrimaryHorizontal(offset)

    /** Left and right of a span of one line's characters. */
    private fun span(line: Int, start: Int, end: Int): Pair<Float, Float>? {
        val a = max(start, layout.getLineStart(line))
        val b = min(end, visibleEnd(line))
        if (a >= b) return null
        val left = edge(line, a)
        val right = edge(line, b)
        return if (left < right) left to right else null
    }

    /** A line's box without its paragraph spacing. */
    private fun lineBox(line: Int) = (layout.getLineTop(line) + spaceBefore[line]) to (layout.getLineBottom(line) - spaceAfter[line])

    /** Rects a range covers on a page, one per line, in layout coordinates. */
    fun rects(page: Int, start: Int, end: Int): List<RectF> {
        val p = pages.getOrNull(page) ?: return emptyList()
        val out = mutableListOf<RectF>()
        for (line in p.first..p.last) {
            if (layout.getLineEnd(line) <= start || layout.getLineStart(line) >= end) continue
            val (left, right) = span(line, start, end) ?: continue
            val (top, bottom) = lineBox(line)
            out += RectF(left, top.toFloat(), right, bottom.toFloat())
        }
        return out
    }

    // Drawing

    private val markPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    /** Draws a page with its top-left at the canvas origin. */
    fun draw(canvas: Canvas, page: Int, selection: IntRange?, selectionColor: Int) {
        val p = pages.getOrNull(page) ?: return
        val range = characterRange(page)
        canvas.save()
        canvas.translate(0f, -p.top.toFloat())
        canvas.clipRect(-style.fontSize, p.top.toFloat(), style.columnWidth + style.fontSize, p.bottom + style.density * 2)

        val metricsPaint = Paint()
        metricsPaint.textSize = style.fontSize
        metricsPaint.typeface = BookFonts.typeface(style.settings.font, style.settings.weight)
        val metrics = metricsPaint.fontMetrics
        val glyphHeight = (metrics.descent - metrics.ascent) * 1.08f
        for (mark in marks) {
            if (mark.end <= range.first || mark.start > range.last) continue
            markPaint.color = ColorUtils.setAlphaComponent(mark.color, 107)
            val rects = rects(page, mark.start, mark.end)
            for (r in rects) {
                // The line box is taller than the type, which sits centered in it; the mark hugs the letters.
                val line = layout.getLineForVertical(r.centerY().toInt())
                val baseline = layout.getLineBaseline(line)
                val mid = baseline + (metrics.ascent + metrics.descent) / 2
                val height = min(glyphHeight, r.height() - 2)
                canvas.drawRoundRect(r.left - 1, mid - height / 2, r.right + 1, mid + height / 2, 3 * style.density, 3 * style.density, markPaint)
            }
            if (mark.note && mark.end - 1 in range) rects.lastOrNull()?.let { r ->
                val line = layout.getLineForVertical(r.centerY().toInt())
                val size = 5 * style.density
                val y = layout.getLineBaseline(line) + metrics.ascent * 0.9f
                markPaint.color = mark.color
                canvas.drawOval(r.right + 1.5f * style.density, y, r.right + 1.5f * style.density + size, y + size, markPaint)
            }
        }

        if (selection != null) {
            markPaint.color = selectionColor
            for (r in rects(page, selection.first, selection.last + 1)) canvas.drawRect(r, markPaint)
        }

        layout.draw(canvas)

        // Links, underlined faintly.
        markPaint.color = ColorUtils.setAlphaComponent(style.text, 90)
        for ((start, end, _) in text.links) {
            if (end <= range.first || start > range.last) continue
            for (r in rects(page, start, end)) {
                val line = layout.getLineForVertical(r.centerY().toInt())
                val y = layout.getLineBaseline(line) + metrics.descent * 0.45f
                canvas.drawRect(r.left, y, r.right, y + max(1f, style.density * 0.8f), markPaint)
            }
        }
        canvas.restore()
    }

    // Hit testing

    /** The character under a point on a page (page coordinates), or nearest to it unless `onText`. */
    fun characterAt(page: Int, x: Float, y: Float, onText: Boolean): Int? {
        val p = pages.getOrNull(page) ?: return null
        val ly = y + p.top
        if (onText && (ly < p.top || ly > p.bottom)) return null
        val line = layout.getLineForVertical(ly.toInt()).coerceIn(p.first, p.last)
        val caret = layout.getOffsetForHorizontal(line, x)
        val slop = 6 * style.density
        for (index in listOf(caret, caret - 1)) {
            if (index < layout.getLineStart(line) || index >= layout.getLineEnd(line) || index >= text.length) continue
            val left = edge(line, index)
            val right = edge(line, index + 1)
            if (!onText || x in min(left, right) - slop..max(left, right) + slop) {
                if (onText) {
                    val (top, bottom) = lineBox(line)
                    if (ly < top - slop || ly > bottom + slop) return null
                }
                return index
            }
        }
        return if (onText) null else min(caret, text.length - 1).takeIf { it >= 0 }
    }

    /** The gap between characters nearest a point, for dragging a selection handle. */
    fun boundary(page: Int, x: Float, y: Float): Int {
        val p = pages.getOrNull(page) ?: return 0
        val line = layout.getLineForVertical((y + p.top).toInt()).coerceIn(p.first, p.last)
        val range = characterRange(page)
        return layout.getOffsetForHorizontal(line, x).coerceIn(range.first, range.last + 1)
    }

    /** The word around a character, or the character itself when it isn't part of one. */
    fun word(at: Int): IntRange {
        val words = BreakIterator.getWordInstance(locale)
        val paragraph = text.paragraphs.firstOrNull { at >= it.start && at < it.end }
        val from = paragraph?.start ?: 0
        val to = paragraph?.end ?: text.length
        words.setText(text.text.subSequence(from, to).toString())
        val local = at - from
        val end = words.following(local).takeIf { it != BreakIterator.DONE } ?: (to - from)
        // The status of a boundary describes the text before it.
        val status = words.ruleStatus
        val start = words.previous().takeIf { it != BreakIterator.DONE } ?: 0
        if (start <= local && local < end && status != BreakIterator.WORD_NONE) return (from + start) until (from + end)
        return at..at
    }

    /** Where a selection's ends are on a page, for its handles: (x, line top, line bottom), in page coordinates. */
    fun caret(page: Int, offset: Int, atEnd: Boolean): Triple<Float, Float, Float>? {
        val p = pages.getOrNull(page) ?: return null
        val rects = rects(page, if (atEnd) offset - 1 else offset, if (atEnd) offset else offset + 1)
        val r = rects.firstOrNull() ?: return null
        return Triple(if (atEnd) r.right else r.left, r.top - p.top, r.bottom - p.top)
    }
}
