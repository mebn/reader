package com.mebn.reader.reader

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import com.mebn.reader.formats.TocEntry
import com.mebn.reader.model.Annotation
import com.mebn.reader.model.Locator
import com.mebn.reader.model.PageBackground
import com.mebn.reader.model.ReaderSettings

data class Position(
    /** 0-based chapter, or null when the book has no chapters. */
    val chapter: Int?,
    val chapterCount: Int,
    /** 1-based page; null while page numbers are still being computed. */
    val page: Int?,
    val pageCount: Int?,
    /** 1-based page within the current chapter, or null when the book has no chapters. */
    val chapterPage: Int?,
    val chapterPageCount: Int?,
    /** 0–1 through the whole book. */
    val percent: Double,
    val locator: Locator,
)

data class Appearance(val settings: ReaderSettings, val background: PageBackground)

data class TextSelection(val locator: Locator, val text: String)

/** What the reader screen asks of the view that shows the pages. */
interface ReaderEngine {
    val position: Position?
    fun setAppearance(appearance: Appearance)
    fun setAnnotations(annotations: List<Annotation>)
    fun goTo(locator: Locator)
    fun goTo(entry: TocEntry)
    fun turn(forward: Boolean)
    /** Whether a locator is on the page(s) showing. */
    fun isVisible(locator: Locator): Boolean
    /** The 1-based book page a locator falls on, or null while pages are still being counted. */
    fun pageOf(locator: Locator): Int?
    fun clearSelection()
    /** The text a locator covers, as a selection would give it; null when it can't be read. */
    fun text(locator: Locator): String?
    /** Whether the reader is at or past a contents entry. */
    fun hasReached(entry: TocEntry): Boolean
    fun dispose()

    @Composable
    fun Content(modifier: Modifier)
}

/** What the page views tell the reader screen. */
interface ReaderEngineDelegate {
    fun engineChanged(position: Position)
    /** A tap that hit nothing in particular, at this fraction of the width. */
    fun engineTapped(fraction: Float)
    fun engineTappedAnnotation(id: String)
    /** A finished selection, and where it is on screen to put its menu; nulls while it's cleared or being made. */
    fun engineSelected(selection: TextSelection?, anchor: Rect?)
    fun engineOpen(url: String)
}

/** Selected text the way it's stored: whitespace collapsed, no object placeholders. */
fun normalizedSelection(text: String): String =
    text.replace("\uFFFC", "").replace(Regex("\\s+"), " ").trim()
