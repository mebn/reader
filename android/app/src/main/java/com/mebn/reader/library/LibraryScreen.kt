package com.mebn.reader.library

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.CreateNewFolder
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import com.mebn.reader.model.Annotation
import com.mebn.reader.model.AnnotationKind
import com.mebn.reader.model.Book
import com.mebn.reader.model.Folder
import com.mebn.reader.model.LibraryTab
import com.mebn.reader.reader.AnnotationRow
import com.mebn.reader.sync.Actions
import com.mebn.reader.sync.NaturalOrder
import com.mebn.reader.sync.SyncEngine
import com.mebn.reader.ui.literata
import com.mebn.reader.ui.sectionTitle
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

/**
 * The library's tab and search, kept while a book is open so they're still there on return.
 * The tab is null until picked, so each launch starts on the default tab.
 */
object LibraryFilter {
    var tab by mutableStateOf<LibraryTab?>(null)
    var query by mutableStateOf("")
}

/** Opening books and folders, and the settings, from anywhere in the library. */
class LibraryNavigation(
    val openBook: (Book) -> Unit,
    val openAt: (Book, com.mebn.reader.model.Locator) -> Unit,
    val openFolder: (String) -> Unit,
)

/** "plain" is highlights without a note, for when notes are listed on their own. */
enum class AnnotationFilter(val title: String) {
    HIGHLIGHTS("Highlights"), PLAIN("Highlights"), NOTES("Notes"), BOOKMARKS("Bookmarks");

    fun matches(a: Annotation, query: String): Boolean {
        val kind = when (this) {
            HIGHLIGHTS -> a.kind == AnnotationKind.HIGHLIGHT
            PLAIN -> a.kind == AnnotationKind.HIGHLIGHT && !a.hasNote
            NOTES -> a.hasNote
            BOOKMARKS -> a.kind == AnnotationKind.BOOKMARK
        }
        return kind && (query.isEmpty() || listOf(a.text, a.note, a.label).any { it.lowercase().contains(query) })
    }
}

class AnnotationGroup(val book: Book, val list: List<Annotation>)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(folderId: String?, nav: LibraryNavigation, onBack: () -> Unit, onSettings: () -> Unit) {
    val library = SyncEngine.library
    val scope = rememberCoroutineScope()
    var naming by remember { mutableStateOf(false) }
    var addMenu by remember { mutableStateOf(false) }
    var searching by remember { mutableStateOf(LibraryFilter.query.isNotEmpty()) }
    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (uris.isNotEmpty()) scope.launch { Actions.importFiles(uris, folderId) }
    }

    // Inside a folder there are no tabs: just its books and subfolders.
    val tab = if (folderId != null) LibraryTab.BOOKS else LibraryFilter.tab ?: library.appSettings.defaultTab
    val folder = folderId?.let { library.folders[it] }
    val query = LibraryFilter.query.trim().lowercase()
    if (folderId != null) BackHandler(onBack = onBack)

    val scroll = TopAppBarDefaults.enterAlwaysScrollBehavior()
    Scaffold(
        Modifier.nestedScroll(scroll.nestedScrollConnection),
        topBar = {
            CenterAlignedTopAppBar(
                title = {
                    if (searching) {
                        TextField(
                            LibraryFilter.query, { LibraryFilter.query = it },
                            Modifier.fillMaxWidth().padding(end = 8.dp),
                            placeholder = { Text("Search") },
                            singleLine = true,
                            shape = CircleShape,
                            leadingIcon = { Icon(Icons.Filled.Search, null) },
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                            keyboardActions = KeyboardActions {},
                            colors = TextFieldDefaults.colors(focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent),
                        )
                    } else {
                        Text(folder?.name ?: "Library", maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                },
                navigationIcon = {
                    if (folderId != null) IconButton(onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
                },
                actions = {
                    if (searching) {
                        IconButton({
                            searching = false
                            LibraryFilter.query = ""
                        }) { Icon(Icons.Filled.Close, "Close search") }
                    } else {
                        IconButton({ searching = true }) { Icon(Icons.Filled.Search, "Search") }
                        Box {
                            IconButton({ addMenu = true }) { Icon(Icons.Filled.Add, "Add") }
                            DropdownMenu(addMenu, { addMenu = false }) {
                                DropdownMenuItem({ Text("Book") }, {
                                    addMenu = false
                                    importer.launch(Actions.importTypes)
                                }, leadingIcon = { Icon(Icons.AutoMirrored.Outlined.MenuBook, null) })
                                DropdownMenuItem({ Text("Folder") }, {
                                    addMenu = false
                                    naming = true
                                }, leadingIcon = { Icon(Icons.Outlined.CreateNewFolder, null) })
                            }
                        }
                        IconButton(onSettings) { Icon(Icons.Outlined.Settings, "Settings") }
                    }
                },
                scrollBehavior = scroll,
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background, scrolledContainerColor = MaterialTheme.colorScheme.surfaceContainer),
            )
        },
    ) { padding ->
        var refreshing by remember { mutableStateOf(false) }
        PullToRefreshBox(
            refreshing,
            {
                refreshing = true
                scope.launch {
                    SyncEngine.pull()
                    refreshing = false
                }
            },
            Modifier.padding(padding).fillMaxSize(),
        ) {
            LibraryContent(folderId, tab, query, nav)
        }
    }

    if (naming) NameDialog("New folder", "", "Create", { naming = false }) { Actions.createFolder(it, folderId) }
}

@Composable
private fun LibraryContent(folderId: String?, tab: LibraryTab, query: String, nav: LibraryNavigation) {
    val library = SyncEngine.library
    // Whether a book is in this folder or any folder inside it; everything at the top.
    val ids = folderId?.let { library.descendants(it) }
    val inScope: (Book) -> Boolean = { book -> ids == null || (book.folderId != null && book.folderId in ids) }

    // With a search: from the top of the library, every matching book and folder anywhere;
    // inside a folder, only that folder's own books and subfolders.
    var folders = library.childFolders(folderId)
    var books = library.books(folderId)
    if (query.isNotEmpty()) {
        val matches = { b: Book -> b.title.lowercase().contains(query) || b.author.lowercase().contains(query) }
        if (folderId != null) {
            folders = folders.filter { it.name.lowercase().contains(query) }
            books = books.filter(matches)
        } else {
            folders = library.folders.values.filter { it.name.lowercase().contains(query) }.sortedWith(compareBy(NaturalOrder) { it.name })
            books = library.books.values.filter(matches).sortedByDescending { it.addedAt }
        }
    }
    val showBooks = tab == LibraryTab.ALL || tab == LibraryTab.BOOKS
    val noBooks = folders.isEmpty() && books.isEmpty()
    // In All, each kind gets its own section, and a highlight with a note shows only under Notes.
    val kinds = when (tab) {
        LibraryTab.ALL -> listOf(AnnotationFilter.PLAIN, AnnotationFilter.NOTES, AnnotationFilter.BOOKMARKS)
        LibraryTab.HIGHLIGHTS -> listOf(AnnotationFilter.HIGHLIGHTS)
        LibraryTab.NOTES -> listOf(AnnotationFilter.NOTES)
        LibraryTab.BOOKMARKS -> listOf(AnnotationFilter.BOOKMARKS)
        LibraryTab.BOOKS -> emptyList()
    }
    val groups = kinds.map { it to annotationGroups(it, query, inScope) }
    val anyNotes = groups.any { it.second.isNotEmpty() }
    val last = if (showBooks && folderId == null && query.isEmpty()) lastRead(inScope) else null

    LazyVerticalGrid(
        GridCells.Adaptive(108.dp),
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 40.dp),
        horizontalArrangement = Arrangement.spacedBy(18.dp),
        verticalArrangement = Arrangement.spacedBy(26.dp),
    ) {
        if (folderId == null) item(span = { GridItemSpan(maxLineSpan) }) { TabChips(tab) }
        if (last != null) item(span = { GridItemSpan(maxLineSpan) }) { ContinueReadingCard(last.first, last.second, last.third, nav) }
        if (showBooks) {
            if (noBooks) {
                if (library.ready && !(tab == LibraryTab.ALL && anyNotes)) {
                    item(span = { GridItemSpan(maxLineSpan) }) { EmptyState(if (query.isEmpty()) "Add books with the + button" else "No books match") }
                }
            } else {
                if (tab == LibraryTab.ALL) item(span = { GridItemSpan(maxLineSpan) }) { SectionTitle("Books") }
                items(folders, key = { "folder:${it.id}" }) { FolderCard(it, nav) }
                items(books, key = { "book:${it.id}" }) { BookCard(it, nav) }
            }
        }
        for ((kind, list) in groups) {
            if (list.isEmpty()) continue
            if (tab == LibraryTab.ALL) item(span = { GridItemSpan(maxLineSpan) }) { SectionTitle(kind.title, Modifier.padding(top = 12.dp)) }
            items(list, key = { "${kind.name}:${it.book.id}" }, span = { GridItemSpan(maxLineSpan) }) { AnnotationGroupView(it, nav) }
        }
        if (tab != LibraryTab.ALL && tab != LibraryTab.BOOKS && !anyNotes && library.ready) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                EmptyState(
                    if (query.isEmpty()) "Your ${tab.label.lowercase()} from ${if (folderId != null) "books in this folder" else "your books"} show up here" else "Nothing matches",
                )
            }
        }
    }
}

/** The unfinished book read most recently, if any. */
private fun lastRead(inScope: (Book) -> Boolean): Triple<Book, Double, Long>? {
    val library = SyncEngine.library
    return library.progress.values
        .mapNotNull { p -> library.books[p.id]?.takeIf { p.percent > 0 && p.percent < 0.995 && inScope(it) }?.let { Triple(it, p.percent, p.modifiedAt) } }
        .maxByOrNull { it.third }
}

/** Highlights, notes and bookmarks grouped by book, most recently touched first. */
private fun annotationGroups(kind: AnnotationFilter, query: String, inScope: (Book) -> Boolean): List<AnnotationGroup> {
    val library = SyncEngine.library
    return library.annotations.values
        .filter { a -> library.books[a.bookId]?.let(inScope) == true && kind.matches(a, query) }
        .groupBy { it.bookId }
        .map { (id, list) -> AnnotationGroup(library.books[id]!!, list.sortedBy { it.position.sortKey }) }
        .sortedByDescending { group -> group.list.maxOf { it.modifiedAt } }
}

@Composable
private fun TabChips(selected: LibraryTab) {
    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 4.dp)) {
        items(LibraryTab.entries) { tab ->
            FilterChip(
                selected = tab == selected,
                onClick = { LibraryFilter.tab = tab },
                label = { Text(tab.label, fontWeight = if (tab == selected) FontWeight.SemiBold else FontWeight.Normal) },
                shape = CircleShape,
                colors = FilterChipDefaults.filterChipColors(selectedContainerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.14f)),
                border = null,
            )
        }
    }
}

@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(text.uppercase(), modifier, style = sectionTitle, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun EmptyState(text: String) {
    Box(Modifier.fillMaxWidth().heightIn(min = 320.dp), contentAlignment = Alignment.Center) {
        Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
    }
}

// Cards

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun BookCard(book: Book, nav: LibraryNavigation) {
    var menu by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf(false) }
    var moving by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    var details by remember { mutableStateOf(false) }
    val percent = SyncEngine.library.progress[book.id]?.percent ?: 0.0
    Box {
        Column(Modifier.clip(RoundedCornerShape(8.dp)).combinedClickable(onLongClick = { menu = true }) { nav.openBook(book) }) {
            BookCover(book, Modifier.fillMaxWidth().shadow(4.dp, RoundedCornerShape(6.dp)))
            Text(book.title, Modifier.padding(top = 10.dp), style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("${(percent * 100).roundToInt()}%", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        DropdownMenu(menu, { menu = false }) {
            DropdownMenuItem({ Text("Open") }, { menu = false; nav.openBook(book) })
            DropdownMenuItem({ Text("Details") }, { menu = false; details = true })
            HorizontalDivider()
            DropdownMenuItem({ Text("Rename") }, { menu = false; renaming = true })
            DropdownMenuItem({ Text("Move to…") }, { menu = false; moving = true })
            HorizontalDivider()
            DropdownMenuItem({ Text("Delete", color = MaterialTheme.colorScheme.error) }, { menu = false; deleting = true })
        }
    }
    if (renaming) NameDialog("Rename book", book.title, "Save", { renaming = false }) { Actions.rename(book, it) }
    if (moving) MoveDialog(book.folderId, null, { moving = false }) { Actions.move(book, it) }
    if (details) AlertDialog({ details = false }, confirmButton = { TextButton({ details = false }) { Text("Done") } }, text = { BookDetails(book) })
    if (deleting) {
        AlertDialog(
            { deleting = false },
            title = { Text("Delete “${book.title}”?") },
            text = { Text("It will be removed from all your devices, with its notes and highlights.") },
            confirmButton = { TextButton({ deleting = false; Actions.delete(book) }) { Text("Delete", color = MaterialTheme.colorScheme.error) } },
            dismissButton = { TextButton({ deleting = false }) { Text("Cancel") } },
        )
    }
}

/** Up to three covers fanned out like a small stack. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun FolderCard(folder: Folder, nav: LibraryNavigation) {
    var menu by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf(false) }
    var moving by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    val books = SyncEngine.library.books(folder.id)
    val stack = books.take(3).reversed()
    val fan = listOf(-7f to -0.14f, 6f to 0.14f, 0f to 0f)
    Box {
        Column(Modifier.clip(RoundedCornerShape(8.dp)).combinedClickable(onLongClick = { menu = true }) { nav.openFolder(folder.id) }) {
            androidx.compose.foundation.layout.BoxWithConstraints(
                Modifier.fillMaxWidth().aspectRatio(2f / 3f).clip(RoundedCornerShape(10.dp)).background(MaterialTheme.colorScheme.surfaceContainerHigh),
                contentAlignment = Alignment.Center,
            ) {
                val width = maxWidth * 0.52f
                stack.forEachIndexed { i, book ->
                    val (angle, x) = fan[fan.size - stack.size + i]
                    BookCover(book, Modifier.width(width).offset(x = width * x).rotate(angle).shadow(3.dp, RoundedCornerShape(4.dp)), corner = 4.dp)
                }
                if (stack.isEmpty()) Icon(Icons.Outlined.Folder, null, Modifier.size(36.dp), tint = MaterialTheme.colorScheme.outline)
            }
            Text(folder.name, Modifier.padding(top = 10.dp), style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("${books.size}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        DropdownMenu(menu, { menu = false }) {
            DropdownMenuItem({ Text("Rename") }, { menu = false; renaming = true })
            DropdownMenuItem({ Text("Move to…") }, { menu = false; moving = true })
            HorizontalDivider()
            DropdownMenuItem({ Text("Delete", color = MaterialTheme.colorScheme.error) }, { menu = false; deleting = true })
        }
    }
    if (renaming) NameDialog("Rename folder", folder.name, "Save", { renaming = false }) { Actions.rename(folder, it) }
    if (moving) MoveDialog(folder.parentId, folder.id, { moving = false }) { Actions.move(folder, it) }
    if (deleting) {
        AlertDialog(
            { deleting = false },
            title = { Text("Delete “${folder.name}”?") },
            text = { Text("Books inside are kept and moved up one level.") },
            confirmButton = { TextButton({ deleting = false; Actions.delete(folder) }) { Text("Delete", color = MaterialTheme.colorScheme.error) } },
            dismissButton = { TextButton({ deleting = false }) { Text("Cancel") } },
        )
    }
}

/** A wide card for picking up where you left off, on a soft wash of the book's own cover. */
@Composable
private fun ContinueReadingCard(book: Book, percent: Double, at: Long, nav: LibraryNavigation) {
    Surface(
        { nav.openBook(book) },
        Modifier.fillMaxWidth().padding(top = 4.dp),
        shape = RoundedCornerShape(28.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
        shadowElevation = 2.dp,
    ) {
        Box {
            coverUrl(book)?.let {
                AsyncImage(it, null, Modifier.matchParentSize().blur(40.dp), contentScale = ContentScale.Crop, alpha = 0.45f)
            }
            Row(Modifier.padding(22.dp), horizontalArrangement = Arrangement.spacedBy(22.dp), verticalAlignment = Alignment.CenterVertically) {
                BookCover(book, Modifier.width(92.dp).shadow(10.dp, RoundedCornerShape(6.dp)))
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("CONTINUE READING", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.6.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(book.title, fontFamily = literata(500), fontSize = 22.sp, lineHeight = 28.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    if (book.author.isNotEmpty()) Text(book.author, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                    Row(Modifier.padding(top = 8.dp).widthIn(max = 320.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        LinearProgressIndicator(
                            { percent.toFloat() }, Modifier.weight(1f).height(4.dp).clip(CircleShape),
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f), trackColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f),
                            drawStopIndicator = {},
                        )
                        Text("${(percent * 100).roundToInt()}%", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Text("Last read ${formatWhen(at)}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

/** Everything known about a book. */
@Composable
private fun BookDetails(book: Book) {
    val library = SyncEngine.library
    val progress = library.progress[book.id]
    val mine = library.annotations(book.id)
    val counts = listOf(
        mine.count { it.kind == AnnotationKind.HIGHLIGHT } to "highlight",
        mine.count { it.kind == AnnotationKind.HIGHLIGHT && it.hasNote } to "note",
        mine.count { it.kind == AnnotationKind.BOOKMARK } to "bookmark",
    ).filter { it.first > 0 }.map { "${it.first} ${it.second}${if (it.first == 1) "" else "s"}" }
    val percent = ((progress?.percent ?: 0.0) * 100).roundToInt()
    Row(horizontalArrangement = Arrangement.spacedBy(18.dp), modifier = Modifier.verticalScroll(rememberScrollState())) {
        BookCover(book, Modifier.width(96.dp))
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Column {
                Text(book.title, style = MaterialTheme.typography.titleMedium)
                if (book.author.isNotEmpty()) Text(book.author, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(
                (if (percent == 0) "Not started" else if (percent >= 100) "Finished" else "$percent% read") +
                    (if (progress != null && percent > 0) " · ${formatWhen(progress.modifiedAt)}" else ""),
                style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            val rows = buildList {
                if (counts.isNotEmpty()) add("Notes" to counts.joinToString(" · "))
                book.folderId?.let { library.folders[it] }?.let { add("Folder" to it.name) }
                add("Format" to "${book.format.extension.uppercase()} · ${formatSize(book.size)}")
                add("Added" to DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(book.addedAt)))
            }
            for ((label, value) in rows) {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(label, Modifier.width(52.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(value, style = MaterialTheme.typography.labelMedium)
                }
            }
        }
    }
}

private fun formatSize(bytes: Long) =
    if (bytes < 1024 * 1024) "${maxOf(1, (bytes / 1024.0).roundToInt())} KB" else String.format(Locale.US, "%.1f MB", bytes / 1024.0 / 1024.0)

/** "today", "yesterday", "3 days ago", then a date. */
fun formatWhen(at: Long): String {
    fun day(t: Long) = Calendar.getInstance().apply {
        timeInMillis = t
        set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
    }.timeInMillis
    val days = ((day(System.currentTimeMillis()) - day(at)) / 86_400_000L).toInt()
    return when {
        days <= 0 -> "today"
        days == 1 -> "yesterday"
        days < 7 -> "$days days ago"
        else -> DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(at))
    }
}

// Annotations

/** Highlights, notes and bookmarks of one book; picking one opens the book there. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun AnnotationGroupView(group: AnnotationGroup, nav: LibraryNavigation) {
    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()
    Column(Modifier.widthIn(max = 720.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.padding(bottom = 4.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            BookCover(group.book, Modifier.width(34.dp), corner = 3.dp)
            Column {
                Text(group.book.title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(
                    (if (group.book.author.isEmpty()) "" else "${group.book.author} · ") + "${group.list.size} ${if (group.list.size == 1) "item" else "items"}",
                    style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1,
                )
            }
        }
        for (a in group.list) {
            var menu by remember { mutableStateOf(false) }
            Box {
                AnnotationRow(
                    a,
                    Modifier
                        .clip(RoundedCornerShape(16.dp))
                        .background(MaterialTheme.colorScheme.surfaceContainer)
                        .combinedClickable(onLongClick = { menu = true }) { nav.openAt(group.book, a.position) }
                        .padding(horizontal = 14.dp, vertical = 12.dp),
                )
                DropdownMenu(menu, { menu = false }) {
                    DropdownMenuItem({ Text("Open") }, { menu = false; nav.openAt(group.book, a.position) })
                    DropdownMenuItem({ Text("Copy") }, {
                        menu = false
                        val text = if (a.kind == AnnotationKind.BOOKMARK) a.label else a.text
                        scope.launch { clipboard.setClipEntry(ClipEntry(android.content.ClipData.newPlainText("Note", text))) }
                    })
                    DropdownMenuItem({ Text("Remove", color = MaterialTheme.colorScheme.error) }, { menu = false; Actions.remove(a) })
                }
            }
        }
    }
}

// Dialogs

/** Asks for a name, as for a new folder or a rename. */
@Composable
fun NameDialog(title: String, initial: String, action: String, onDismiss: () -> Unit, onSubmit: (String) -> Unit) {
    var name by remember { mutableStateOf(initial) }
    val submit = {
        val trimmed = name.trim()
        if (trimmed.isNotEmpty()) onSubmit(trimmed)
        onDismiss()
    }
    AlertDialog(
        onDismiss,
        title = { Text(title) },
        text = {
            OutlinedTextField(
                name, { name = it }, singleLine = true, placeholder = { Text("Name") },
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done), keyboardActions = KeyboardActions { submit() },
            )
        },
        confirmButton = { TextButton(submit) { Text(action) } },
        dismissButton = { TextButton(onDismiss) { Text("Cancel") } },
    )
}

/** Every folder as a place to move something to. */
@Composable
private fun MoveDialog(current: String?, exclude: String?, onDismiss: () -> Unit, onMove: (String?) -> Unit) {
    val tree = SyncEngine.library.folderTree(exclude)
    AlertDialog(
        onDismiss,
        title = { Text("Move to") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                MoveRow("Library", 0, current == null) { onMove(null); onDismiss() }
                for ((folder, depth) in tree) MoveRow(folder.name, depth + 1, folder.id == current) { onMove(folder.id); onDismiss() }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun MoveRow(name: String, depth: Int, disabled: Boolean, onClick: () -> Unit) {
    TextButton(onClick, Modifier.fillMaxWidth().padding(start = (depth * 16).dp), enabled = !disabled) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(if (depth == 0) Icons.AutoMirrored.Outlined.MenuBook else Icons.Outlined.Folder, null, Modifier.size(18.dp))
            Text(name, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}
