package com.mebn.reader.reader

import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import com.mebn.reader.ReaderApp
import com.mebn.reader.formats.BookDocument
import com.mebn.reader.formats.TocEntry
import com.mebn.reader.model.Annotation
import com.mebn.reader.model.AnnotationKind
import com.mebn.reader.model.Book
import com.mebn.reader.model.Format
import com.mebn.reader.model.Locator
import com.mebn.reader.model.PageBackground
import com.mebn.reader.model.ReaderSettings
import com.mebn.reader.model.Scope
import com.mebn.reader.model.now
import com.mebn.reader.model.settingsDiff
import com.mebn.reader.reader.fixed.FixedEngine
import com.mebn.reader.reader.fixed.FixedSource
import com.mebn.reader.reader.reflow.ReflowEngine
import com.mebn.reader.sync.Actions
import com.mebn.reader.sync.BookFiles
import com.mebn.reader.sync.SyncEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.abs
import kotlin.math.roundToInt

/** Where another device read up to, and how to say so. */
data class ContinueOffer(val locator: Locator, val label: String)

/**
 * Where to open a book instead of its saved position, such as a highlight picked from the
 * library's notes. Taken once.
 */
object BookJump {
    private var pending: Pair<String, Locator>? = null

    fun set(bookId: String, locator: Locator) {
        pending = bookId to locator
    }

    fun take(bookId: String): Locator? {
        val jump = pending?.takeIf { it.first == bookId } ?: return null
        pending = null
        return jump.second
    }
}

sealed interface ReaderStatus {
    data object Loading : ReaderStatus
    data object Ready : ReaderStatus
    data class Failed(val message: String) : ReaderStatus
}

/** One open book: its document, where the reader is, and the reader's own panels. */
class ReaderModel(val bookId: String) : ReaderEngineDelegate {
    var status by mutableStateOf<ReaderStatus>(ReaderStatus.Loading); private set
    var document by mutableStateOf<BookDocument?>(null); private set
    var engine by mutableStateOf<ReaderEngine?>(null); private set
    var position by mutableStateOf<Position?>(null); private set
    var chrome by mutableStateOf(true)
    var selection by mutableStateOf<TextSelection?>(null); private set
    /** Where the selection is on screen, while its menu should show. */
    var selectionAnchor by mutableStateOf<Rect?>(null); private set
    /** The highlight whose color and note are being edited. */
    var editing by mutableStateOf<String?>(null)
    /** Where another device read up to, offered while it's ahead of this one. */
    var offer by mutableStateOf<ContinueOffer?>(null); private set
    /**
     * Where reading was before going to a highlight, note or bookmark, to get back to. Going
     * to another one keeps the first place; page turns and contents don't touch it.
     */
    var returnTo by mutableStateOf<Locator?>(null); private set
    var focusNote by mutableStateOf(false)
    var showContents by mutableStateOf(false)
    var showAppearance by mutableStateOf(false)
    /** Unsaved appearance changes for this book. */
    var draft by mutableStateOf<ReaderSettings?>(null); private set

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var lastSaved = "" to 0L
    /** Opened at a highlight or note: only a page turn or a jump makes it the reading position. */
    private var holdPosition = false
    private var saveJob: Job? = null
    private var draftJob: Job? = null
    private var chromeJob: Job? = null
    private var startLocator = Locator()

    private val library get() = SyncEngine.library

    val book: Book? get() = library.books[bookId]

    val isFixed: Boolean get() = document is BookDocument.Pdf || document is BookDocument.Comic

    val isPdf: Boolean get() = book?.format == Format.PDF

    val toc: List<TocEntry> get() = document?.toc ?: emptyList()

    val annotations: List<Annotation> get() = library.annotations(bookId)

    // Loading

    suspend fun load() {
        if (status == ReaderStatus.Ready) return
        val book = book ?: return
        val session = SyncEngine.session ?: return
        status = ReaderStatus.Loading
        try {
            val file = BookFiles.file(book, session)
            val doc = withContext(Dispatchers.IO) { BookDocument.open(file, book.format, book.fileName) }
            val saved = library.progress[bookId]
            lastSaved = (saved?.locator ?: "") to (saved?.modifiedAt ?: 0)
            val jump = BookJump.take(bookId)
            holdPosition = jump != null
            startLocator = jump ?: saved?.let { Locator.parse(it.locator) } ?: Locator()
            // Opened at a highlight or note, going back returns to where reading had got to.
            returnTo = if (jump != null) saved?.let { Locator.parse(it.locator) } else null
            document = doc
            engine = when (doc) {
                is BookDocument.Reflow -> ReflowEngine(doc.doc, bookId, this)
                is BookDocument.Pdf -> FixedEngine(FixedSource.Pdf(doc.doc), this)
                is BookDocument.Comic -> FixedEngine(FixedSource.Comic(doc.doc), this)
            }
            status = ReaderStatus.Ready
            showChromeBriefly()
        } catch (e: Exception) {
            status = ReaderStatus.Failed(e.message ?: "Something went wrong.")
        }
    }

    /** Sets up a new engine once the screen has given it a look. */
    fun start(engine: ReaderEngine, appearance: Appearance) {
        engine.setAppearance(appearance)
        engine.setAnnotations(annotations)
        engine.goTo(startLocator)
    }

    /** Saves what's pending and lets go of the book. */
    fun close() {
        if (saveJob?.isActive == true) {
            saveJob?.cancel()
            position?.let { Actions.saveProgress(bookId, it.locator, it.percent) }
        }
        if (draftJob?.isActive == true) {
            draftJob?.cancel()
            draft?.let(::saveForBook)
        }
        scope.cancel()
        engine?.dispose()
        document?.close()
    }

    // Appearance

    val savedSettings: Pair<ReaderSettings, Boolean> get() = library.readerSettings(bookId)

    val settings: ReaderSettings get() = draft ?: savedSettings.first

    fun background(dark: Boolean): PageBackground = settings.background(dark)

    /** Changes this book's settings now and saves them shortly after, so dragging a slider saves once. */
    fun change(edit: (ReaderSettings) -> ReaderSettings) {
        val next = edit(settings)
        draft = next
        draftJob?.cancel()
        draftJob = scope.launch {
            delay(400)
            saveForBook(next)
            draft = null
        }
    }

    /** Only what differs from the defaults, so the book keeps following the rest. */
    private fun saveForBook(settings: ReaderSettings) {
        val diff = settingsDiff(settings, library.defaultReaderSettings, ReaderSettings.serializer())
        Actions.saveSettings(Scope.book(bookId), diff.ifEmpty { null })
    }

    fun makeDefault() {
        draftJob?.cancel()
        Actions.saveSettings(Scope.READER, settings, ReaderSettings.serializer())
        Actions.saveSettings(Scope.book(bookId), null)
        draft = null
    }

    fun useDefaults() {
        draftJob?.cancel()
        Actions.saveSettings(Scope.book(bookId), null)
        draft = null
    }

    val hasOverride: Boolean get() = savedSettings.second || draft != null

    fun setFontSize(size: Double) = change { it.copy(fontSize = size.coerceIn(12.0, 34.0)) }

    // Chrome

    fun toggleChrome() {
        chromeJob?.cancel()
        chrome = !chrome
    }

    private fun hideChrome() {
        chromeJob?.cancel()
        chrome = false
    }

    /** Shows the toolbar when a book opens, then gets out of the way. */
    private fun showChromeBriefly() {
        chrome = true
        chromeJob?.cancel()
        chromeJob = scope.launch {
            delay(2500)
            if (!showContents && !showAppearance) hideChrome()
        }
    }

    // Navigation

    fun turn(forward: Boolean) {
        holdPosition = false
        engine?.turn(forward)
    }

    fun go(locator: Locator) {
        holdPosition = false
        engine?.goTo(locator)
    }

    fun go(entry: TocEntry) {
        holdPosition = false
        engine?.goTo(entry)
    }

    /** Goes to a highlight, note or bookmark, remembering where reading was. */
    fun goToAnnotation(locator: Locator) {
        if (returnTo == null) returnTo = position?.locator
        go(locator)
    }

    fun goBack() {
        val target = returnTo ?: return
        returnTo = null
        go(target)
    }

    /** The way back, named by its page while pages are numbered. */
    val returnLabel: String?
        get() {
            val target = returnTo ?: return null
            return engine?.pageOf(target)?.let { "Back to page $it" } ?: "Back"
        }

    /** The chapter being read, by the contents' last entry at or before this position. */
    val chapterTitle: String? get() = currentEntry?.label

    /** The contents entry for where the reader is: the last one at or before this position. */
    val currentEntry: TocEntry?
        get() {
            if (position == null) return null
            val engine = engine ?: return null
            return toc.lastOrNull { engine.hasReached(it) }
        }

    // Bookmarks and highlights

    /** A bookmark on the page(s) showing. */
    val bookmark: Annotation?
        get() {
            if (position == null) return null
            val engine = engine ?: return null
            return annotations.firstOrNull { it.kind == AnnotationKind.BOOKMARK && engine.isVisible(it.position) }
        }

    fun toggleBookmark() {
        bookmark?.let {
            Actions.remove(it)
            return
        }
        val position = position ?: return
        val book = book ?: return
        Actions.addAnnotation(
            bookId, AnnotationKind.BOOKMARK, position.locator,
            text = position.page?.let { "Page $it" } ?: "${(position.percent * 100).roundToInt()}%",
            label = chapterTitle ?: book.title,
        )
    }

    /** Highlights the selection and opens it to pick a color or write a note, unless a color was already picked. */
    fun highlight(selection: TextSelection, color: String? = null, withNote: Boolean = false) {
        val created = mergeIntoHighlights(selection, color)
            ?: Actions.addAnnotation(bookId, AnnotationKind.HIGHLIGHT, selection.locator, selection.text, color = color ?: "yellow")
        engine?.clearSelection()
        this.selection = null
        selectionAnchor = null
        if (withNote || color == null) {
            focusNote = withNote
            editing = created.id
        }
    }

    /**
     * A selection that overlaps highlights already there grows the newest of them to cover it
     * all, keeping every note, instead of piling another highlight on top. Null when nothing overlaps.
     */
    private fun mergeIntoHighlights(selection: TextSelection, color: String?): Annotation? {
        val new = selection.locator
        val start = new.start ?: return null
        val end = new.end ?: return null
        val overlapping = annotations
            .filter { a ->
                val l = a.position
                val s = l.start
                val e = l.end
                a.kind == AnnotationKind.HIGHLIGHT && a.deleted != true && l.chapter == new.chapter && l.page == new.page &&
                    s != null && e != null && s < end && start < e
            }
            .sortedByDescending { it.modifiedAt }
        val keep = overlapping.firstOrNull() ?: return null
        val merged = new.copy(
            start = overlapping.mapNotNull { it.position.start }.fold(start, ::minOf),
            end = overlapping.mapNotNull { it.position.end }.fold(end, ::maxOf),
        )
        val note = overlapping.map { it.note.trim() }.filter { it.isNotEmpty() }.joinToString("\n\n")
        Actions.update(keep, note = note, color = color, locator = merged, text = engine?.text(merged) ?: selection.text)
        overlapping.drop(1).forEach(Actions::remove)
        return keep
    }

    fun dismissSelection() {
        engine?.clearSelection()
        selection = null
        selectionAnchor = null
    }

    // Progress

    /** Saves the reading position shortly after it settles. */
    private fun scheduleSave() {
        val position = position ?: return
        if (status != ReaderStatus.Ready || holdPosition) return
        val locator = position.locator.toJson()
        if (locator == lastSaved.first) return
        saveJob?.cancel()
        saveJob = scope.launch {
            delay(800)
            Actions.saveProgress(bookId, position.locator, position.percent)
            lastSaved = locator to now()
        }
    }

    /** Offers to jump when another device reads further while this one is open. */
    fun remoteProgressChanged() {
        val remote = library.progress[bookId] ?: return
        val engine = engine ?: return
        if (remote.modifiedAt <= lastSaved.second + 1000 || remote.locator == lastSaved.first) return
        val locator = Locator.parse(remote.locator)
        if (engine.isVisible(locator)) return
        lastSaved = remote.locator to remote.modifiedAt
        val page = engine.pageOf(locator)
        offer = ContinueOffer(locator, page?.let { "Continue on page $it?" } ?: "Continue at ${(remote.percent * 100).roundToInt()}%?")
    }

    fun acceptOffer() {
        val target = offer ?: return
        offer = null
        go(target.locator)
    }

    // ReaderEngineDelegate

    override fun engineChanged(position: Position) {
        // Swiping away from where a jump landed makes reading resume from here.
        val previous = this.position
        if (holdPosition && previous != null && (
                previous.locator.chapter != position.locator.chapter || previous.locator.page != position.locator.page ||
                    abs((previous.locator.fraction ?: 0.0) - (position.locator.fraction ?: 0.0)) > 1e-6
                )
        ) {
            holdPosition = false
        }
        this.position = position
        // Once the offered page is showing, by any route, there's nothing left to offer.
        offer?.let { if (engine?.isVisible(it.locator) == true) offer = null }
        scheduleSave()
    }

    override fun engineTapped(fraction: Float) {
        if (showContents || showAppearance || editing != null) return
        when {
            fraction < 0.3f -> {
                hideChrome()
                turn(false)
            }
            fraction > 0.7f -> {
                hideChrome()
                turn(true)
            }
            else -> toggleChrome()
        }
    }

    override fun engineTappedAnnotation(id: String) {
        focusNote = false
        editing = id
    }

    /** A finished selection and where it is; nothing while one is cleared or still being made. */
    override fun engineSelected(selection: TextSelection?, anchor: Rect?) {
        this.selection = selection
        selectionAnchor = anchor
    }

    override fun engineOpen(url: String) {
        runCatching {
            ReaderApp.context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
}
