package com.mebn.reader.reader

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.mebn.reader.model.Annotation
import com.mebn.reader.model.AnnotationKind
import com.mebn.reader.model.ThemeMode
import com.mebn.reader.model.highlightColor
import com.mebn.reader.settings.FooterSettingsSection
import com.mebn.reader.settings.HeaderSettingsSection
import com.mebn.reader.settings.LayoutSettingsSection
import com.mebn.reader.settings.PageSettingsSection
import com.mebn.reader.settings.PagesPicker
import com.mebn.reader.settings.Segments
import com.mebn.reader.settings.TextSettingsSection
import com.mebn.reader.sync.Actions
import com.mebn.reader.sync.SyncEngine
import com.mebn.reader.ui.literata
import com.mebn.reader.ui.sectionTitle

private enum class ContentsTab(val label: String) { CONTENTS("Contents"), NOTES("Notes"), BOOKMARKS("Bookmarks") }

/** Contents, highlights and bookmarks of the open book. Picking one jumps there. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ContentsSheet(model: ReaderModel, onDismiss: () -> Unit) {
    val state = rememberModalBottomSheetState()
    var tab by rememberSaveable { mutableStateOf(ContentsTab.CONTENTS) }
    ModalBottomSheet(onDismiss, sheetState = state) {
        Column(Modifier.fillMaxHeight(0.85f)) {
            Segments(ContentsTab.entries.map { it to it.label }, tab, Modifier.fillMaxWidth().padding(horizontal = 20.dp)) { tab = it }
            Box(Modifier.weight(1f).padding(top = 12.dp)) {
                when (tab) {
                    ContentsTab.CONTENTS -> Contents(model, onDismiss)
                    ContentsTab.NOTES -> AnnotationList(model, model.annotations.filter { it.kind == AnnotationKind.HIGHLIGHT }, onDismiss)
                    ContentsTab.BOOKMARKS -> AnnotationList(model, model.annotations.filter { it.kind == AnnotationKind.BOOKMARK }, onDismiss)
                }
            }
        }
    }
}

@Composable
private fun Contents(model: ReaderModel, onDismiss: () -> Unit) {
    val toc = model.toc
    if (toc.isEmpty()) return Empty()
    val current = model.currentEntry
    // The chapter being read is centered rather than the list starting at the top.
    val list = rememberLazyListState(initialFirstVisibleItemIndex = maxOf(0, toc.indexOf(current) - 4))
    LazyColumn(state = list) {
        items(toc, key = { it.id }) { entry ->
            val here = entry == current
            Text(
                entry.label,
                Modifier
                    .fillMaxWidth()
                    .background(if (here) MaterialTheme.colorScheme.primary.copy(alpha = 0.10f) else Color.Transparent)
                    .clickable {
                        model.go(entry)
                        onDismiss()
                    }
                    .padding(start = 20.dp + (entry.depth * 16).dp, end = 20.dp, top = 13.dp, bottom = 13.dp),
                fontWeight = if (here) FontWeight.SemiBold else FontWeight.Normal,
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AnnotationList(model: ReaderModel, annotations: List<Annotation>, onDismiss: () -> Unit) {
    if (annotations.isEmpty()) return Empty()
    LazyColumn {
        items(annotations.sortedBy { it.position.sortKey }, key = { it.id }) { a ->
            val swipe = rememberSwipeToDismissBoxState()
            LaunchedEffect(swipe.currentValue) {
                if (swipe.currentValue == SwipeToDismissBoxValue.EndToStart) Actions.remove(a)
            }
            SwipeToDismissBox(
                swipe,
                enableDismissFromStartToEnd = false,
                backgroundContent = {
                    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.error).padding(horizontal = 24.dp), contentAlignment = Alignment.CenterEnd) {
                        Icon(Icons.Outlined.Delete, "Remove", tint = MaterialTheme.colorScheme.onError)
                    }
                },
            ) {
                AnnotationRow(
                    a,
                    Modifier
                        .background(MaterialTheme.colorScheme.surfaceContainerLow)
                        .clickable {
                            model.goToAnnotation(a.position)
                            onDismiss()
                        }
                        .padding(horizontal = 20.dp, vertical = 12.dp),
                )
            }
            HorizontalDivider(Modifier.padding(start = 20.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
        }
    }
}

@Composable
private fun Empty() {
    Box(Modifier.fillMaxWidth().padding(vertical = 64.dp), contentAlignment = Alignment.Center) {
        Text("Nothing yet", color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** A highlight (with its note) or a bookmark, as listed in the reader and the library. */
@Composable
fun AnnotationRow(annotation: Annotation, modifier: Modifier = Modifier) {
    if (annotation.kind == AnnotationKind.BOOKMARK) {
        Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(Icons.Filled.Bookmark, null, Modifier.size(16.dp).padding(top = 2.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Column {
                Text(annotation.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (annotation.text.isNotEmpty()) {
                    Text(annotation.text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2)
                }
            }
        }
    } else {
        Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Quote(annotation, 4)
            if (annotation.hasNote) {
                Text(
                    annotation.note, Modifier.padding(start = 13.dp), style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 4, overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

/** Highlighted text beside a bar of its color. */
@Composable
private fun Quote(annotation: Annotation, lines: Int, color: Color = MaterialTheme.colorScheme.onSurface) {
    Row(Modifier.height(androidx.compose.foundation.layout.IntrinsicSize.Min)) {
        Box(Modifier.width(3.dp).fillMaxHeight().clip(RoundedCornerShape(2.dp)).background(Color(highlightColor(annotation.color))))
        Text(
            annotation.text, Modifier.padding(start = 10.dp), fontFamily = literata(400), fontSize = 15.sp, lineHeight = 22.sp,
            color = color, maxLines = lines, overflow = TextOverflow.Ellipsis,
        )
    }
}

private enum class AppearanceTab(val label: String) { TEXT("Text"), PAGE("Page"), LAYOUT("Layout") }

/**
 * Appearance of the open book, in tabs. Changes apply to this book and show on the page
 * right away; they can be promoted to every book or dropped.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppearanceSheet(model: ReaderModel, appDark: Boolean, onDismiss: () -> Unit) {
    // Fixed pages, as in a PDF, have no text to set.
    val tabs = if (model.isFixed) listOf(AppearanceTab.PAGE, AppearanceTab.LAYOUT) else AppearanceTab.entries
    var tab by rememberSaveable { mutableStateOf(tabs.first()) }
    val settings = model.settings
    val change: (com.mebn.reader.model.ReaderSettings) -> Unit = { next -> model.change { next } }
    // The pages show through behind the sheet, so it doesn't dim them.
    ModalBottomSheet(onDismiss, scrimColor = Color.Transparent) {
        Column(Modifier.padding(horizontal = 20.dp)) {
            Segments(tabs.map { it to it.label }, tab, Modifier.fillMaxWidth()) { tab = it }
            Column(Modifier.heightIn(max = 420.dp).verticalScroll(rememberScrollState()).padding(vertical = 16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                when (tab) {
                    AppearanceTab.TEXT -> TextSettingsSection(settings, change)
                    // Switching the page between light and dark switches the whole app.
                    AppearanceTab.PAGE -> PageSettingsSection(settings, appDark, { dark -> Actions.setApp { it.copy(theme = if (dark) ThemeMode.DARK else ThemeMode.LIGHT) } }, change)
                    AppearanceTab.LAYOUT -> {
                        if (model.isFixed) PagesPicker(settings, change) else LayoutSettingsSection(settings, change)
                        Text("HEADER", style = sectionTitle, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 16.dp, bottom = 4.dp))
                        HeaderSettingsSection(settings, change)
                        Text("FOOTER", style = sectionTitle, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 16.dp, bottom = 4.dp))
                        FooterSettingsSection(settings, change)
                    }
                }
            }
            Text(
                if (model.hasOverride) "This book has settings of its own." else "Changes apply to this book.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(Modifier.fillMaxWidth().padding(vertical = 16.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                OutlinedButton({ model.useDefaults() }, enabled = model.hasOverride) { Text("Use defaults") }
                Button({ model.makeDefault() }, enabled = model.hasOverride) { Text("Use for all books") }
            }
        }
    }
}

/** A highlight's color and note. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AnnotationEditor(annotation: Annotation, focusNote: Boolean, onDismiss: () -> Unit) {
    var note by remember(annotation.id) { mutableStateOf(annotation.note) }
    val focus = remember { FocusRequester() }
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    DisposableEffect(annotation.id) {
        onDispose {
            val latest = SyncEngine.library.annotations[annotation.id]
            if (latest != null && note != latest.note) Actions.update(latest, note = note)
        }
    }
    LaunchedEffect(focusNote) { if (focusNote) runCatching { focus.requestFocus() } }
    ModalBottomSheet(onDismiss, sheetState = state) {
        Column(Modifier.padding(horizontal = 20.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton({
                    Actions.remove(annotation)
                    onDismiss()
                }) {
                    Icon(Icons.Outlined.Delete, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.error)
                    Text("Remove", Modifier.padding(start = 6.dp), color = MaterialTheme.colorScheme.error)
                }
                Box(Modifier.weight(1f))
                TextButton(onDismiss) { Text("Done", fontWeight = FontWeight.SemiBold) }
            }
            Quote(SyncEngine.library.annotations[annotation.id] ?: annotation, 3, MaterialTheme.colorScheme.onSurfaceVariant)
            ColorDots(selected = (SyncEngine.library.annotations[annotation.id] ?: annotation).color) { color ->
                SyncEngine.library.annotations[annotation.id]?.let { Actions.update(it, color = color) }
            }
            TextField(
                note, { note = it },
                Modifier.fillMaxWidth().heightIn(min = 96.dp).focusRequester(focus),
                placeholder = { Text("Note") },
                shape = RoundedCornerShape(14.dp),
                colors = TextFieldDefaults.colors(focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent),
                minLines = 3,
                maxLines = 8,
            )
        }
    }
}
