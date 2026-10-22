package com.mebn.reader.reader.reflow

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.text.Layout
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextPaint
import android.text.style.AlignmentSpan
import android.text.style.LeadingMarginSpan
import android.text.style.LineHeightSpan
import android.text.style.MetricAffectingSpan
import android.text.style.ReplacementSpan
import android.text.style.StrikethroughSpan
import androidx.core.graphics.ColorUtils
import com.mebn.reader.formats.BookImage
import com.mebn.reader.formats.Node
import com.mebn.reader.model.BookFonts
import com.mebn.reader.model.ReaderSettings
import com.mebn.reader.model.TextAlign
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** How book text is set, from the reader settings and the page size, in pixels. */
data class TextStyle(
    val settings: ReaderSettings,
    val text: Int,
    val columnWidth: Int,
    val pageHeight: Int,
    val language: String?,
    /** Pixels per point. */
    val density: Float,
) {
    val fontSize: Float get() = settings.fontSize.toFloat() * density
}

/** A paragraph as the book's stylesheet sets it, which may hold several lines broken by `<br>`. */
class Paragraph(val start: Int, val end: Int, val before: Int, val after: Int)

/**
 * A chapter set as styled text, with a map between positions in it and the character
 * offsets the desktop app stores, which count every text node of the chapter.
 */
class ChapterText(
    val text: Spanned,
    /** For each character of `text`, the DOM offset it came from. Characters the layout
     * added (paragraph breaks, bullets, images) carry the offset of the text after them. */
    private val domOffsets: IntArray,
    private val synthetic: BooleanArray,
    /** Element ids and where they start in `text`. */
    val anchors: Map<String, Int>,
    /** Total DOM text length. */
    val domLength: Int,
    val paragraphs: List<Paragraph>,
    /** Links by range, "int:<path#anchor>" or "ext:<url>". */
    val links: List<Triple<Int, Int, String>>,
) {
    val length get() = text.length

    /** Where a DOM offset falls in the laid out text. */
    fun displayIndex(dom: Int): Int {
        var lo = 0
        var hi = domOffsets.size
        while (lo < hi) {
            val mid = (lo + hi) / 2
            if (domOffsets[mid] < dom) lo = mid + 1 else hi = mid
        }
        while (lo < synthetic.size && synthetic[lo]) lo++
        return min(lo, domOffsets.size)
    }

    fun displayRange(domStart: Int, domEnd: Int): IntRange? {
        val start = displayIndex(domStart)
        val end = displayIndex(domEnd)
        return if (end > start) start until end else null
    }

    /** DOM offsets for a range of the laid out text. */
    fun domRange(start: Int, end: Int): Pair<Int, Int>? {
        var first = start
        var last = end - 1
        while (first <= last && synthetic[first]) first++
        while (last >= first && synthetic[last]) last--
        if (first > last) return null
        return domOffsets[first] to domOffsets[last] + 1
    }

    fun link(at: Int): String? = links.firstOrNull { at >= it.first && at < it.second }?.third
}

/** Lays out a chapter's node tree the way the desktop app's book stylesheet does. */
class ChapterTextBuilder(private val style: TextStyle, private val image: (String, Int) -> BookImage?) {
    private data class Inline(
        val italic: Boolean = false,
        val bold: Boolean = false,
        val mono: Boolean = false,
        val scale: Float = 1f,
        val baseline: Float = 0f,
        val link: String? = null,
        val strike: Boolean = false,
        val underline: Boolean = false,
    )

    private data class Block(
        val heading: Float? = null,
        val paragraph: Boolean = false,
        val indent: Float = 0f,
        val quote: Boolean = false,
        val pre: Boolean = false,
        val center: Boolean = false,
    )

    /** A stretch of text and how it's set; `special` is an image or a rule. */
    private class Run(val start: Int, val end: Int, val inline: Inline, val block: Block, val special: Any? = null, val spacing: Float = 0f)

    private class IntList {
        var data = IntArray(1024)
        var size = 0
        fun add(v: Int) {
            if (size == data.size) data = data.copyOf(size * 2)
            data[size++] = v
        }
        fun toArray() = data.copyOf(size)
    }

    private class BoolList {
        var data = BooleanArray(1024)
        var size = 0
        fun add(v: Boolean) {
            if (size == data.size) data = data.copyOf(size * 2)
            data[size++] = v
        }
        fun toArray() = data.copyOf(size)
    }

    private class State {
        val units = StringBuilder()
        val domOffsets = IntList()
        val synthetic = BoolList()
        val runs = mutableListOf<Run>()
        val anchors = mutableMapOf<String, Int>()
        /** Where `<br>` put line breaks, which don't end the paragraph. */
        val lineBreaks = mutableSetOf<Int>()
        var dom = 0
        var pendingSpace: Int? = null
        var lineStart = true
        var hidden = 0
        val lists = mutableListOf<Pair<Boolean, Int>>()

        fun add(c: Char, offset: Int, synth: Boolean) {
            units.append(c)
            domOffsets.add(offset)
            synthetic.add(synth)
        }
    }

    fun build(root: Node): ChapterText {
        val state = State()
        walk(root, state, Inline(), Block())
        return finish(state)
    }

    private fun walk(node: Node, state: State, parentInline: Inline, parentBlock: Block) {
        val name = node.name
        if (name == null) {
            appendText(node.text ?: "", state, parentInline, parentBlock)
            return
        }
        var inline = parentInline
        var block = parentBlock
        val isBlock = name in blocks
        val fs = style.fontSize

        when (name) {
            "svg" -> {
                // Only an svg's images show; its text still counts toward offsets.
                for (image in node.all("image")) appendImage(image["src"], state, inline, block)
                state.hidden++
                node.children.forEach { walk(it, state, inline, block) }
                state.hidden--
                return
            }
            "img", "image" -> {
                appendImage(node["src"], state, inline, block)
                return
            }
            "br" -> {
                if (state.hidden == 0) {
                    state.lineBreaks += state.units.length
                    appendSynthetic("\n", state, inline, block)
                }
                state.pendingSpace = null
                state.lineStart = true
                return
            }
            "hr" -> {
                breakParagraph(state, inline, block)
                appendRule(state, block)
                return
            }
            "em", "i", "cite", "dfn", "var" -> inline = inline.copy(italic = true)
            "strong", "b", "th" -> inline = inline.copy(bold = true)
            "code", "kbd", "samp", "tt" -> inline = inline.copy(mono = true, scale = inline.scale * 0.88f)
            "sup" -> inline = inline.copy(scale = inline.scale * 0.7f, baseline = inline.baseline + fs * 0.35f)
            "sub" -> inline = inline.copy(scale = inline.scale * 0.7f, baseline = inline.baseline - fs * 0.2f)
            "s", "strike", "del" -> inline = inline.copy(strike = true)
            "u", "ins" -> inline = inline.copy(underline = true)
            "small" -> inline = inline.copy(scale = inline.scale * 0.85f)
            "a" -> {
                val link = node["data-href"]?.let { "int:$it" } ?: node["data-external"]?.let { "ext:$it" }
                if (link != null) inline = inline.copy(link = link)
            }
            "h1", "h2", "h3", "h4", "h5", "h6" -> {
                block = block.copy(heading = headingScale[name])
                inline = inline.copy(bold = true)
            }
            "p" -> block = block.copy(paragraph = true)
            "blockquote" -> block = block.copy(indent = block.indent + fs, quote = true)
            "pre" -> {
                block = block.copy(pre = true)
                inline = inline.copy(mono = true, scale = inline.scale * 0.88f)
            }
            "center" -> block = block.copy(center = true)
            "ul", "ol" -> {
                block = block.copy(indent = block.indent + fs * 1.4f)
                state.lists += (name == "ol") to 0
            }
        }

        if (isBlock) breakParagraph(state, inline, block)
        node["id"]?.let { state.anchors[it] = state.units.length }

        if (name == "li" && state.lists.isNotEmpty()) {
            val (ordered, count) = state.lists.last()
            state.lists[state.lists.size - 1] = ordered to count + 1
            appendSynthetic(if (ordered) "${count + 1}. " else "• ", state, inline, block)
            state.lineStart = true
        }

        for (child in node.children) {
            walk(child, state, inline, block)
            if (child.name == "td" || child.name == "th") appendSynthetic("\t", state, inline, block)
        }

        if (name == "ul" || name == "ol") state.lists.removeAt(state.lists.size - 1)
        if (isBlock) breakParagraph(state, inline, block)
    }

    // Text

    private fun appendText(text: String, state: State, inline: Inline, block: Block) {
        val base = state.dom
        state.dom += text.length
        if (state.hidden != 0) return

        val start = state.units.length
        for (k in text.indices) {
            val u = text[k]
            val offset = base + k
            if (block.pre) {
                state.add(u, offset, false)
                continue
            }
            if (u == ' ' || u == '\t' || u == '\n' || u == '\u000C') {
                if (state.pendingSpace == null) state.pendingSpace = offset
                continue
            }
            val space = state.pendingSpace
            if (space != null && !state.lineStart) state.add(' ', space, false)
            state.pendingSpace = null
            state.lineStart = false
            state.add(u, offset, false)
        }
        if (state.units.length > start) state.runs += Run(start, state.units.length, inline, block)
    }

    private fun appendSynthetic(text: String, state: State, inline: Inline, block: Block, special: Any? = null, spacing: Float = 0f) {
        if (state.hidden != 0) return
        // A space waiting before this would land after it, out of order; it isn't needed.
        state.pendingSpace = null
        val start = state.units.length
        for (c in text) state.add(c, state.dom, true)
        state.runs += Run(start, state.units.length, inline, block, special, spacing)
    }

    /** Ends the current paragraph, if any text was written since the last break. */
    private fun breakParagraph(state: State, inline: Inline, block: Block) {
        state.pendingSpace = null
        state.lineStart = true
        val last = state.units.lastOrNull() ?: return
        if (last == '\n') return
        // The break belongs to the paragraph it ends, so it takes that paragraph's style.
        val previous = state.runs.lastOrNull()
        if (previous != null && previous.special == null) appendSynthetic("\n", state, previous.inline, previous.block)
        else appendSynthetic("\n", state, inline, block)
    }

    // Images

    private class ImageSpec(val image: BookImage, val width: Int, val height: Int, val inline: Boolean)

    private object Rule

    private fun appendImage(src: String?, state: State, inline: Inline, block: Block) {
        if (state.hidden != 0 || src == null) return
        val fs = style.fontSize
        val maxHeight = max(40f * style.density, style.pageHeight - fs * 2 - 8 * style.density)
        val loaded = image(src, style.columnWidth) ?: return
        // Book images are sized in CSS pixels, which are points here.
        val naturalW = loaded.width * style.density
        val naturalH = loaded.height * style.density
        if (naturalW <= 0 || naturalH <= 0) return

        if (naturalH <= fs * 1.6f) {
            // Small images (ornaments, dropped capitals) sit in the line.
            val space = state.pendingSpace
            if (space != null && !state.lineStart) {
                state.add(' ', space, false)
                state.runs += Run(state.units.length - 1, state.units.length, inline, block)
            }
            appendSynthetic("\uFFFC", state, inline, block, ImageSpec(loaded, naturalW.roundToInt(), naturalH.roundToInt(), true))
            state.lineStart = false
            return
        }

        val scale = min(1f, min(style.columnWidth / naturalW, maxHeight / naturalH))
        breakParagraph(state, inline, block)
        val spec = ImageSpec(loaded, floor(naturalW * scale).toInt(), floor(naturalH * scale).toInt(), false)
        appendSynthetic("\uFFFC\n", state, inline, block, spec, fs * 0.8f)
        state.lineStart = true
    }

    private fun appendRule(state: State, block: Block) {
        appendSynthetic("\uFFFC\n", state, Inline(), block, Rule, style.fontSize * 1.5f)
        state.lineStart = true
    }

    // Styling

    private fun finish(state: State): ChapterText {
        val text = SpannableStringBuilder(state.units)
        val s = style.settings
        val links = mutableListOf<Triple<Int, Int, String>>()

        for (run in state.runs) {
            val inline = run.inline
            val block = run.block
            when (val special = run.special) {
                is ImageSpec -> {
                    val picture = Picture(special.image.bitmap, special.width, special.height, special.inline)
                    text.setSpan(ImageSpan(picture, style.fontSize), run.start, run.start + 1, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    continue
                }
                Rule -> {
                    text.setSpan(RuleSpan((style.columnWidth * 0.6f).toInt(), ColorUtils.setAlphaComponent(style.text, 46), style.density), run.start, run.start + 1, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    continue
                }
            }
            val size = style.fontSize * (block.heading ?: 1f) * inline.scale
            val weight = if (block.heading != null) max(600.0, s.weight) else if (inline.bold) max(700.0, s.weight) else s.weight
            val typeface = BookFonts.typeface(s.font, weight, inline.italic, inline.mono)
            var color = style.text
            if (block.quote) color = ColorUtils.setAlphaComponent(color, (255 * 0.9f).toInt())
            text.setSpan(
                FontSpan(typeface, size, inline.baseline, s.tracking.toFloat(), color, inline.link != null || inline.underline, inline.link != null),
                run.start, run.end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
            )
            if (inline.strike) text.setSpan(StrikethroughSpan(), run.start, run.end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            inline.link?.let { links += Triple(run.start, run.end, it) }
        }

        // Paragraph styles go on whole lines, from the first run of each paragraph.
        val paragraphs = mutableListOf<Paragraph>()
        var start = 0
        var runIndex = 0
        while (start < text.length) {
            var end = start
            // A paragraph runs to a newline that isn't a <br>.
            while (end < text.length) {
                if (text[end] == '\n' && end !in state.lineBreaks) break
                end++
            }
            end = min(end + 1, text.length)
            while (runIndex < state.runs.size && state.runs[runIndex].end <= start) runIndex++
            val run = state.runs.getOrNull(runIndex)
            if (run != null) paragraphs += styleParagraph(text, start, end, run)
            start = end
        }
        return ChapterText(text, state.domOffsets.toArray(), state.synthetic.toArray(), state.anchors, state.dom, paragraphs, links)
    }

    private fun styleParagraph(text: SpannableStringBuilder, start: Int, end: Int, run: Run): Paragraph {
        val s = style.settings
        val fs = style.fontSize
        val block = run.block
        var before = 0f
        var after = 0f
        var center = block.center
        var lineHeight: Float? = null
        when {
            run.special is ImageSpec && !run.special.inline || run.special === Rule -> {
                center = true
                before = run.spacing
                after = run.spacing
            }
            block.heading != null -> {
                lineHeight = fs * block.heading * 1.25f
                before = fs * block.heading * 1.4f
                after = fs * block.heading * 0.7f
            }
            else -> {
                lineHeight = fs * s.lineHeight.toFloat()
                after = if (block.paragraph) s.paragraphSpacing.toFloat() * fs else 0f
            }
        }
        if (block.quote) after = max(after, fs)
        val flags = Spanned.SPAN_PARAGRAPH
        if (center) text.setSpan(AlignmentSpan.Standard(Layout.Alignment.ALIGN_CENTER), start, end, flags)
        if (block.indent > 0) text.setSpan(LeadingMarginSpan.Standard(block.indent.roundToInt()), start, end, flags)
        text.setSpan(ParagraphSpan(lineHeight?.roundToInt(), before.roundToInt(), after.roundToInt()), start, end, flags)
        return Paragraph(start, end, before.roundToInt(), after.roundToInt())
    }

    companion object {
        private val blocks = setOf(
            "p", "div", "section", "article", "aside", "header", "footer", "nav", "main", "figure", "figcaption", "blockquote",
            "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "dl", "dt", "dd", "table", "tr", "pre", "hr", "address", "center", "body", "caption",
        )
        private val headingScale = mapOf("h1" to 1.6f, "h2" to 1.35f, "h3" to 1.15f, "h4" to 1f, "h5" to 1f, "h6" to 1f)

        /** Whether the text is set justified, which applies to the whole layout. */
        fun justified(settings: ReaderSettings) = settings.align == TextAlign.JUSTIFY
    }
}

/** Typeface, size, color and offsets for a run of text. */
class FontSpan(
    private val typeface: Typeface,
    private val size: Float,
    private val baseline: Float,
    /** Extra space between letters, in ems. */
    private val tracking: Float,
    private val color: Int,
    private val underline: Boolean,
    private val link: Boolean,
) : MetricAffectingSpan() {
    override fun updateMeasureState(paint: TextPaint) = apply(paint)

    override fun updateDrawState(paint: TextPaint) {
        apply(paint)
        paint.color = color
        // Links are underlined by the page, in a fainter color.
        paint.isUnderlineText = underline && !link
    }

    private fun apply(paint: TextPaint) {
        paint.typeface = typeface
        paint.textSize = size
        paint.letterSpacing = tracking
        paint.baselineShift -= baseline.roundToInt()
        paint.isFakeBoldText = false
    }
}

/**
 * A paragraph's fixed line height, with the glyphs centered in each line as CSS does,
 * and the space before and after it. Lines taller than the height keep their own.
 */
class ParagraphSpan(private val lineHeight: Int?, val before: Int, val after: Int) : LineHeightSpan {
    override fun chooseHeight(text: CharSequence, start: Int, end: Int, spanstartv: Int, lineHeight: Int, fm: Paint.FontMetricsInt) {
        val spanned = text as Spanned
        val height = this.lineHeight
        if (height != null) {
            val content = fm.descent - fm.ascent
            if (content < height) {
                val extra = height - content
                fm.ascent -= extra / 2
                fm.descent += extra - extra / 2
            }
        }
        fm.top = fm.ascent
        fm.bottom = fm.descent
        if (start == spanned.getSpanStart(this)) {
            fm.ascent -= before
            fm.top -= before
        }
        if (end == spanned.getSpanEnd(this)) {
            fm.descent += after
            fm.bottom += after
        }
    }
}

/** An image in the text: a block of its own, or a small one sitting on the line. */
private class ImageSpan(private val image: Picture, private val fontSize: Float) : ReplacementSpan() {
    override fun getSize(paint: Paint, text: CharSequence, start: Int, end: Int, fm: Paint.FontMetricsInt?): Int {
        val (_, width, height, inline) = image
        if (fm != null) {
            if (inline) {
                val below = (fontSize * 0.2f).roundToInt()
                fm.ascent = -(height - below)
                fm.descent = below
            } else {
                fm.ascent = -height
                fm.descent = 0
            }
            fm.top = fm.ascent
            fm.bottom = fm.descent
        }
        return width
    }

    override fun draw(canvas: Canvas, text: CharSequence, start: Int, end: Int, x: Float, top: Int, y: Int, bottom: Int, paint: Paint) {
        val (bitmap, width, height, inline) = image
        val bottomY = if (inline) y + fontSize * 0.2f else y.toFloat()
        canvas.drawBitmap(bitmap, null, RectF(x, bottomY - height, x + width, bottomY), Paint(Paint.FILTER_BITMAP_FLAG))
    }
}

/** What an image span draws. */
private data class Picture(val bitmap: Bitmap, val width: Int, val height: Int, val inline: Boolean)

/** A thin centered line, for `<hr>`. */
private class RuleSpan(private val width: Int, private val color: Int, private val density: Float) : ReplacementSpan() {
    override fun getSize(paint: Paint, text: CharSequence, start: Int, end: Int, fm: Paint.FontMetricsInt?): Int {
        if (fm != null) {
            fm.ascent = -density.roundToInt().coerceAtLeast(1)
            fm.descent = 0
            fm.top = fm.ascent
            fm.bottom = 0
        }
        return width
    }

    override fun draw(canvas: Canvas, text: CharSequence, start: Int, end: Int, x: Float, top: Int, y: Int, bottom: Int, paint: Paint) {
        canvas.drawRect(x, y - density, x + width, y.toFloat(), Paint().also { it.color = color })
    }
}
