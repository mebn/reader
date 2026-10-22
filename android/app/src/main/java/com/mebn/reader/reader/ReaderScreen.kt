package com.mebn.reader.reader

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsIgnoringVisibility
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.FormatListBulleted
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.mebn.reader.model.Book
import com.mebn.reader.model.ReaderSettings
import com.mebn.reader.model.ThemeMode
import com.mebn.reader.model.highlightColors
import com.mebn.reader.sync.SyncEngine
import com.mebn.reader.ui.ReaderTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date
import kotlin.math.roundToInt

/** Whether the app is dark, from its theme setting. */
@Composable
fun appIsDark(): Boolean = when (SyncEngine.library.appSettings.theme) {
    ThemeMode.DARK -> true
    ThemeMode.LIGHT -> false
    ThemeMode.SYSTEM -> androidx.compose.foundation.isSystemInDarkTheme()
}

/**
 * An open book: the pages, a toolbar that comes and goes, the running header and footer,
 * and the panels for contents, appearance and notes.
 */
@Composable
fun ReaderScreen(bookId: String, onClose: () -> Unit) {
    val model = remember(bookId) { ReaderModel(bookId) }
    DisposableEffect(model) { onDispose { model.close() } }
    LaunchedEffect(model) { model.load() }
    BackHandler(onBack = onClose)

    val book = model.book
    if (book == null) {
        Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background), contentAlignment = Alignment.Center) {
            if (SyncEngine.library.ready) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("This book is no longer in your library.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    TextButton(onClose) { Text("Close") }
                }
            }
        }
        return
    }

    val appDark = appIsDark()
    val background = model.background(appDark)
    // The reader takes the page's light or dark, so its panels match the page.
    ReaderTheme(dark = background.dark) {
        ReaderContent(model, book, background.dark, appDark, onClose)
    }
}

@Composable
private fun ReaderContent(model: ReaderModel, book: Book, dark: Boolean, appDark: Boolean, onClose: () -> Unit) {
    val background = model.background(appDark)
    val pageColor = Color(background.color)
    val textColor = Color(background.text)
    val engine = model.engine
    val appearance = Appearance(model.settings, background)

    LaunchedEffect(engine) { engine?.let { model.start(it, appearance) } }
    LaunchedEffect(engine, appearance) { engine?.setAppearance(appearance) }
    val annotations = model.annotations
    LaunchedEffect(engine, annotations) { engine?.setAnnotations(annotations) }
    val remote = SyncEngine.library.progress[model.bookId]?.modifiedAt
    LaunchedEffect(remote) { model.remoteProgressChanged() }

    SystemBars(visible = model.chrome, dark = dark, appDark = appDark)
    val focus = remember { FocusRequester() }
    LaunchedEffect(engine) { runCatching { focus.requestFocus() } }

    Box(
        Modifier
            .fillMaxSize()
            .background(pageColor)
            .focusRequester(focus)
            .focusable()
            .onKeyEvent { event -> event.type == KeyEventType.KeyDown && shortcut(model, event.key, event.isCtrlPressed, event.isShiftPressed, onClose) },
    ) {
        if (engine != null) {
            val shown by animateFloatAsState(if (model.position == null) 0f else 1f, label = "pages")
            engine.Content(Modifier.fillMaxSize().alpha(shown))
        }

        val header = header(model, book, model.settings)
        RunningHeader(header, visible = !model.chrome && model.status == ReaderStatus.Ready, color = textColor)
        RunningFooter(model, textColor)
        CornerButtons(model, textColor)

        AnimatedVisibility(
            visible = model.chrome || model.status != ReaderStatus.Ready,
            enter = fadeIn() + slideInVertically { -it / 2 },
            exit = fadeOut() + slideOutVertically { -it / 2 },
        ) {
            ReaderToolbar(model, header, onClose)
        }

        model.selectionAnchor?.let { anchor ->
            val selection = model.selection
            if (selection != null) SelectionMenu(model, selection, anchor)
        }

        when (val status = model.status) {
            ReaderStatus.Loading -> CircularProgressIndicator(Modifier.align(Alignment.Center), color = textColor.copy(alpha = 0.6f))
            is ReaderStatus.Failed -> Column(
                Modifier.align(Alignment.Center).padding(32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text("Couldn't open this book. ${status.message}", color = textColor.copy(alpha = 0.7f))
                FilledTonalButton(onClose, Modifier.padding(top = 16.dp)) { Text("Close") }
            }
            ReaderStatus.Ready -> {}
        }
    }

    if (model.showContents) ContentsSheet(model) { model.showContents = false }
    if (model.showAppearance) AppearanceSheet(model, appDark) { model.showAppearance = false }
    model.editing?.let { id ->
        SyncEngine.library.annotations[id]?.let { annotation ->
            AnnotationEditor(annotation, model.focusNote) { model.editing = null }
        }
    }
}

/** Hides the status and navigation bars along with the toolbar, and colors their icons for the page. */
@Composable
private fun SystemBars(visible: Boolean, dark: Boolean, appDark: Boolean) {
    val view = LocalView.current
    val window = (view.context as? Activity)?.window ?: return
    DisposableEffect(visible, dark, appDark) {
        val controller = WindowCompat.getInsetsController(window, view)
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        if (visible) controller.show(WindowInsetsCompat.Type.systemBars()) else controller.hide(WindowInsetsCompat.Type.systemBars())
        controller.isAppearanceLightStatusBars = !dark
        controller.isAppearanceLightNavigationBars = !dark
        onDispose {
            controller.show(WindowInsetsCompat.Type.systemBars())
            // Back to the app's own light or dark.
            controller.isAppearanceLightStatusBars = !appDark
            controller.isAppearanceLightNavigationBars = !appDark
        }
    }
}

/** Keyboard shortcuts while reading, for a hardware keyboard. */
private fun shortcut(model: ReaderModel, key: Key, ctrl: Boolean, shift: Boolean, onClose: () -> Unit): Boolean {
    when {
        key == Key.DirectionRight || key == Key.PageDown || (key == Key.Spacebar && !shift) -> model.turn(true)
        key == Key.DirectionLeft || key == Key.PageUp || (key == Key.Spacebar && shift) -> model.turn(false)
        key == Key.D && ctrl -> model.toggleBookmark()
        key == Key.B && !ctrl -> model.toggleBookmark()
        key == Key.C && !ctrl -> model.showContents = !model.showContents
        key == Key.A && !ctrl -> model.showAppearance = !model.showAppearance
        key == Key.Equals && ctrl -> model.setFontSize(model.settings.fontSize + 1)
        key == Key.Minus && ctrl -> model.setFontSize(model.settings.fontSize - 1)
        key == Key.Zero && ctrl -> model.setFontSize(ReaderSettings.defaults.fontSize)
        key == Key.H && !ctrl -> model.selection?.let { model.highlight(it) } ?: return false
        key == Key.N && !ctrl -> model.selection?.let { model.highlight(it, withNote = true) } ?: return false
        key == Key.Escape -> onClose()
        else -> return false
    }
    return true
}

/** What the header shows: the book, author and chapter, and the time. */
private data class HeaderLine(val parts: List<String>, val clock: Boolean)

private fun header(model: ReaderModel, book: Book, s: ReaderSettings): HeaderLine? {
    val parts = listOfNotNull(if (s.headerTitle) book.title else null, if (s.headerAuthor) book.author else null, if (s.headerChapter) model.chapterTitle else null)
        .filter { it.isNotEmpty() }
    if (parts.isEmpty() && !s.headerClock) return null
    return HeaderLine(parts, s.headerClock)
}

@Composable
private fun HeaderText(header: HeaderLine, color: Color, size: Int, modifier: Modifier = Modifier) {
    val time by produceState("", header.clock) {
        while (header.clock) {
            value = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date())
            delay(60_000 - System.currentTimeMillis() % 60_000)
        }
    }
    Text(
        (header.parts + listOfNotNull(time.takeIf { header.clock && it.isNotEmpty() })).joinToString("  ·  "),
        modifier,
        color = color,
        fontSize = size.sp,
        fontWeight = FontWeight.Medium,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
    )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RunningHeader(header: HeaderLine?, visible: Boolean, color: Color) {
    header ?: return
    val alpha by animateFloatAsState(if (visible) 0.45f else 0f, label = "header")
    Box(Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.systemBarsIgnoringVisibility).padding(top = 14.dp, start = 48.dp, end = 48.dp).alpha(alpha), contentAlignment = Alignment.TopCenter) {
        HeaderText(header, color, 11)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RunningFooter(model: ReaderModel, color: Color) {
    val p = model.position ?: return
    val s = model.settings
    val parts = buildList {
        if (s.footerChapter) model.chapterTitle?.let { add(it) }
        if (s.footerChapterPages && p.chapterPage != null && p.chapterPageCount != null) add("${p.chapterPage} / ${p.chapterPageCount} in chapter")
        if (s.footerBookPages) add(if (p.page != null && p.pageCount != null) "${p.page} / ${p.pageCount}" else "…")
        if (s.footerPercent) add("${(p.percent * 100).roundToInt()}%")
    }
    if (parts.isEmpty()) return
    Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.systemBarsIgnoringVisibility).padding(bottom = 8.dp, start = 48.dp, end = 48.dp), contentAlignment = Alignment.BottomCenter) {
        Text(parts.joinToString("  ·  "), color = color.copy(alpha = 0.45f), fontSize = 11.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/**
 * Quiet buttons above the footer: back to where reading was before going to a highlight,
 * note or bookmark on the left, and the offer to continue where another device got to on the right.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CornerButtons(model: ReaderModel, color: Color) {
    Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.systemBarsIgnoringVisibility).padding(bottom = 22.dp, start = 8.dp, end = 8.dp)) {
        AnimatedVisibility(model.returnLabel != null, Modifier.align(Alignment.BottomStart), enter = fadeIn(), exit = fadeOut()) {
            TextButton({ model.goBack() }) {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, null, tint = color.copy(alpha = 0.6f), modifier = Modifier.size(18.dp))
                Text(model.returnLabel ?: "Back", color = color.copy(alpha = 0.6f), fontSize = 12.sp, fontWeight = FontWeight.Medium)
            }
        }
        AnimatedVisibility(model.offer != null, Modifier.align(Alignment.BottomEnd), enter = fadeIn(), exit = fadeOut()) {
            TextButton({ model.acceptOffer() }, Modifier.semantics { contentDescription = "You read further on another device. ${model.offer?.label ?: ""}" }) {
                Text(model.offer?.label ?: "", color = color.copy(alpha = 0.6f), fontSize = 12.sp, fontWeight = FontWeight.Medium)
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ReaderToolbar(model: ReaderModel, header: HeaderLine?, onClose: () -> Unit) {
    val glass = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.94f)
    Box(Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.systemBarsIgnoringVisibility).padding(horizontal = 16.dp, vertical = 4.dp)) {
        Surface(onClose, Modifier.size(48.dp).align(Alignment.CenterStart), shape = CircleShape, color = glass, shadowElevation = 3.dp) {
            Box(contentAlignment = Alignment.Center) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Close book") }
        }
        if (header != null && model.status == ReaderStatus.Ready) {
            // Beside the back button, clear of the buttons on the right.
            HeaderText(header, MaterialTheme.colorScheme.onSurfaceVariant, 13, Modifier.align(Alignment.CenterStart).padding(start = 64.dp, end = 172.dp))
        }
        Surface(Modifier.align(Alignment.CenterEnd), shape = CircleShape, color = glass, shadowElevation = 3.dp) {
            Row(Modifier.padding(horizontal = 4.dp)) {
                IconButton({ model.showContents = true }) { Icon(Icons.AutoMirrored.Filled.FormatListBulleted, "Contents and notes") }
                val marked = model.bookmark != null
                IconButton({ model.toggleBookmark() }, enabled = model.position != null) {
                    Icon(if (marked) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder, if (marked) "Remove bookmark" else "Bookmark this page")
                }
                IconButton({ model.showAppearance = true }) { Icon(Icons.Filled.TextFields, "Appearance") }
            }
        }
    }
}

/** Highlight colors, a note, copy and search, over the selected text. */
@Composable
private fun SelectionMenu(model: ReaderModel, selection: TextSelection, anchor: androidx.compose.ui.geometry.Rect) {
    val clipboard = LocalClipboard.current
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val gap = with(LocalDensity.current) { 14.dp.roundToPx() }
    val provider = remember(anchor) {
        object : PopupPositionProvider {
            override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize, layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset {
                val x = (anchor.center.x - popupContentSize.width / 2f).roundToInt().coerceIn(0, maxOf(0, windowSize.width - popupContentSize.width))
                val above = anchor.top.roundToInt() - popupContentSize.height - gap
                val y = if (above > gap * 4) above else anchor.bottom.roundToInt() + gap * 2
                return IntOffset(x, y)
            }
        }
    }
    Popup(popupPositionProvider = provider) {
        Surface(shape = RoundedCornerShape(24.dp), color = MaterialTheme.colorScheme.surfaceContainerHighest, shadowElevation = 8.dp, tonalElevation = 2.dp) {
            Row(Modifier.height(48.dp).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                ColorDots(size = 22) { model.highlight(selection, color = it) }
                VerticalDivider(Modifier.height(24.dp).padding(horizontal = 6.dp))
                MenuText("Note") { model.highlight(selection, withNote = true) }
                MenuText("Copy") {
                    scope.launch { clipboard.setClipEntry(ClipEntry(ClipData.newPlainText("Selection", selection.text))) }
                    model.dismissSelection()
                }
                MenuText("Search") {
                    model.engineOpen("https://www.google.com/search?q=${Uri.encode(selection.text)}")
                    model.dismissSelection()
                }
            }
        }
    }
}

@Composable
private fun MenuText(label: String, onClick: () -> Unit) {
    Text(
        label,
        Modifier.clip(RoundedCornerShape(12.dp)).clickable(onClick = onClick).padding(horizontal = 10.dp, vertical = 8.dp),
        style = MaterialTheme.typography.labelLarge,
    )
}

/** The highlight colors as dots to pick from. */
@Composable
fun ColorDots(selected: String? = null, size: Int = 28, onPick: (String) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        for ((name, color) in highlightColors) {
            Box(
                Modifier
                    .size((size + 8).dp)
                    .clip(CircleShape)
                    .clickable { onPick(name) }
                    .semantics { contentDescription = name.replaceFirstChar { it.uppercase() } },
                contentAlignment = Alignment.Center,
            ) {
                if (selected == name) Box(Modifier.size((size + 6).dp).clip(CircleShape).background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)))
                if (selected == name) Box(Modifier.size((size + 2).dp).clip(CircleShape).background(MaterialTheme.colorScheme.surface))
                Box(Modifier.size(size.dp).clip(CircleShape).background(Color(color)))
            }
        }
    }
}
