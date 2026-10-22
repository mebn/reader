package com.mebn.reader.settings

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Computer
import androidx.compose.material.icons.outlined.DarkMode
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.LightMode
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.PhoneAndroid
import androidx.compose.material.icons.outlined.PhoneIphone
import androidx.compose.material.icons.outlined.Contrast
import androidx.compose.material.icons.outlined.TabletMac
import androidx.compose.material.icons.outlined.Laptop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.mebn.reader.app.AppModel
import com.mebn.reader.app.Toasts
import com.mebn.reader.library.LibraryFilter
import com.mebn.reader.library.formatWhen
import com.mebn.reader.model.Device
import com.mebn.reader.model.LibraryTab
import com.mebn.reader.model.ReaderSettings
import com.mebn.reader.model.Scope
import com.mebn.reader.model.ThemeMode
import com.mebn.reader.reader.appIsDark
import com.mebn.reader.sync.Actions
import com.mebn.reader.sync.Api
import com.mebn.reader.sync.SyncEngine
import com.mebn.reader.ui.sectionTitle
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private enum class Page(val title: String) { ROOT("Settings"), APPEARANCE("Appearance"), READING("Reading"), ACCOUNT("Account") }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(onClose: () -> Unit) {
    var page by rememberSaveable { mutableStateOf(Page.ROOT) }
    val back = { if (page == Page.ROOT) onClose() else page = Page.ROOT }
    BackHandler(onBack = back)
    Scaffold(
        topBar = {
            TopAppBar(
                { Text(page.title) },
                navigationIcon = { IconButton(back) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.TopCenter) {
            Column(Modifier.widthIn(max = 640.dp).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 40.dp)) {
                when (page) {
                    Page.ROOT -> {
                        NavRow(Icons.Outlined.Palette, "Appearance") { page = Page.APPEARANCE }
                        NavRow(Icons.AutoMirrored.Outlined.MenuBook, "Reading") { page = Page.READING }
                        NavRow(Icons.Outlined.AccountCircle, "Account") { page = Page.ACCOUNT }
                    }
                    Page.APPEARANCE -> AppearanceSettings()
                    Page.READING -> ReadingSettings()
                    Page.ACCOUNT -> AccountSettings()
                }
            }
        }
    }
}

@Composable
private fun NavRow(icon: ImageVector, label: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).clickable(onClick = onClick).padding(horizontal = 8.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Icon(icon, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(label, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun Section(title: String?, footer: String? = null, content: @Composable () -> Unit) {
    Column(Modifier.padding(top = 20.dp)) {
        if (title != null) Text(title.uppercase(), Modifier.padding(start = 4.dp, bottom = 8.dp), style = sectionTitle, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Surface(shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surfaceContainer) {
            Column(Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) { content() }
        }
        if (footer != null) Text(footer, Modifier.padding(start = 4.dp, top = 8.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Light, dark or following the system, for the whole app. Applies as soon as it's picked. */
@Composable
private fun AppearanceSettings() {
    val app = SyncEngine.library.appSettings
    Section("Theme", "Books use the page colors you choose for light and dark under Reading.") {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.padding(vertical = 4.dp)) {
            for (mode in ThemeMode.entries) {
                val selected = app.theme == mode
                Column(
                    Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(14.dp))
                        .background(if (selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.12f) else Color.Transparent)
                        .border(1.5.dp, if (selected) MaterialTheme.colorScheme.primary else Color.Transparent, RoundedCornerShape(14.dp))
                        .clickable { Actions.setApp { it.copy(theme = mode) } }
                        .padding(8.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    ThemeSwatch(mode)
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            when (mode) {
                                ThemeMode.SYSTEM -> Icons.Outlined.Contrast
                                ThemeMode.LIGHT -> Icons.Outlined.LightMode
                                ThemeMode.DARK -> Icons.Outlined.DarkMode
                            },
                            null, Modifier.size(14.dp),
                        )
                        Text(mode.label, style = MaterialTheme.typography.labelMedium)
                    }
                }
            }
        }
    }
    Section("Library") {
        var open by remember { mutableStateOf(false) }
        FormRow("Start on") {
            Box {
                TextButton({ open = true }) { Text(app.defaultTab.label) }
                DropdownMenu(open, { open = false }) {
                    for (tab in LibraryTab.entries) {
                        DropdownMenuItem({ Text(tab.label) }, {
                            open = false
                            Actions.setApp { it.copy(defaultTab = tab) }
                            // Show it on the way back to the library, not only after a restart.
                            LibraryFilter.tab = tab
                        })
                    }
                }
            }
        }
    }
}

/** A miniature window in the theme's colors; System is split down the middle. */
@Composable
private fun ThemeSwatch(mode: ThemeMode) {
    Row(Modifier.fillMaxWidth().aspectRatio(4f / 3f).clip(RoundedCornerShape(8.dp)).border(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.1f), RoundedCornerShape(8.dp))) {
        if (mode != ThemeMode.DARK) SwatchHalf(0xfffbfaf7, 0xffebe8e2, 0xffd9d5ce)
        if (mode != ThemeMode.LIGHT) SwatchHalf(0xff1c1c1e, 0xff2a2a2d, 0xff3a3a3e)
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.SwatchHalf(bg: Long, bar: Long, line: Long) {
    Column(Modifier.weight(1f).fillMaxSize().background(Color(bg)).padding(6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(Modifier.fillMaxWidth().height(5.dp).clip(RoundedCornerShape(2.dp)).background(Color(bar)))
        for (w in listOf(0.9f, 0.7f, 0.8f)) Box(Modifier.fillMaxWidth(w).height(3.dp).clip(RoundedCornerShape(2.dp)).background(Color(line)))
    }
}

/** Reader defaults for every book. */
@Composable
private fun ReadingSettings() {
    val library = SyncEngine.library
    var draft by remember { mutableStateOf(library.defaultReaderSettings) }
    var dark by remember { mutableStateOf(false) }
    val systemDark = appIsDark()
    LaunchedEffect(Unit) { dark = systemDark }
    val scope = rememberCoroutineScope()
    var saving by remember { mutableStateOf<Job?>(null) }
    // Picks up changes synced from other devices.
    val synced = library.settings[Scope.READER]?.modifiedAt
    LaunchedEffect(synced) { if (saving?.isActive != true) draft = library.defaultReaderSettings }
    val change: (ReaderSettings) -> Unit = { next ->
        draft = next
        // Saves shortly after the last change so dragging sliders doesn't flood sync.
        saving?.cancel()
        saving = scope.launch {
            delay(400)
            Actions.saveSettings(Scope.READER, next, ReaderSettings.serializer())
        }
    }

    Box(Modifier.fillMaxWidth().padding(top = 12.dp), contentAlignment = Alignment.Center) {
        SettingsPreview(draft, dark, Modifier.width(300.dp))
    }
    Section("Page") { PageSettingsSection(draft, dark, { dark = it }, change) }
    Section("Text") { TextSettingsSection(draft, change) }
    Section("Layout") { LayoutSettingsSection(draft, change) }
    Section("Header") { HeaderSettingsSection(draft, change) }
    Section("Footer") { FooterSettingsSection(draft, change) }
}

/** Who is signed in, and the devices on the account. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun AccountSettings() {
    val session = SyncEngine.session
    var devices by remember { mutableStateOf<List<Device>?>(null) }
    var error by remember { mutableStateOf("") }
    var removing by remember { mutableStateOf<Device?>(null) }
    val scope = rememberCoroutineScope()
    suspend fun load() {
        val s = session ?: return
        try {
            devices = Api.devices(s)
            error = ""
        } catch (e: Exception) {
            error = e.message ?: "Couldn't load devices"
        }
    }
    LaunchedEffect(Unit) {
        while (true) {
            load()
            delay(30_000)
        }
    }

    Section(null, "Your library, reading positions, highlights and settings stay in sync on every device you sign in on.") {
        FormRow("Signed in as") { Text(session?.email ?: "", color = MaterialTheme.colorScheme.onSurfaceVariant) }
        OutlinedButton({ AppModel.signOut() }, Modifier.padding(vertical = 6.dp)) { Text("Sign out", color = MaterialTheme.colorScheme.error) }
    }
    Section("Devices") {
        val list = devices
        if (list == null) {
            Text(error.ifEmpty { "Loading…" }, Modifier.padding(vertical = 8.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else {
            for (device in list) {
                var menu by remember { mutableStateOf(false) }
                Box {
                    DeviceRow(device, Modifier.combinedClickable(onLongClick = { if (!device.current) menu = true }) { if (!device.current) menu = true })
                    DropdownMenu(menu, { menu = false }) {
                        DropdownMenuItem({ Text("Sign out", color = MaterialTheme.colorScheme.error) }, { menu = false; removing = device })
                    }
                }
            }
        }
    }

    removing?.let { device ->
        AlertDialog(
            { removing = null },
            title = { Text("Sign out ${device.name}?") },
            text = { Text("It will stop syncing until someone signs in on it again.") },
            confirmButton = {
                TextButton({
                    removing = null
                    val s = session ?: return@TextButton
                    devices = devices?.filter { it.id != device.id }
                    scope.launch {
                        try {
                            Api.removeDevice(s, device.id)
                        } catch (e: Exception) {
                            Toasts.show("Couldn't sign out ${device.name}", e.message, error = true)
                        }
                        load()
                    }
                }) { Text("Sign out", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton({ removing = null }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun DeviceRow(device: Device, modifier: Modifier) {
    val icon = when (device.platform) {
        "macOS" -> Icons.Outlined.Laptop
        "Windows", "Linux" -> Icons.Outlined.Computer
        "Web" -> Icons.Outlined.Language
        "iPadOS" -> Icons.Outlined.TabletMac
        "iOS" -> Icons.Outlined.PhoneIphone
        "Android" -> Icons.Outlined.PhoneAndroid
        else -> Icons.Outlined.Computer
    }
    Row(modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Box {
            Box(Modifier.size(36.dp).clip(RoundedCornerShape(9.dp)).background(MaterialTheme.colorScheme.surfaceContainerHighest), contentAlignment = Alignment.Center) {
                Icon(icon, null, Modifier.size(20.dp))
            }
            if (device.online) {
                Box(Modifier.align(Alignment.BottomEnd).offset(3.dp, 3.dp).size(12.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainer).padding(2.dp).clip(CircleShape).background(Color(0xff34c759)))
            }
        }
        Column(Modifier.weight(1f)) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(device.name, maxLines = 1)
                if (device.current) {
                    Text(
                        "This device",
                        Modifier.clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainerHighest).padding(horizontal = 6.dp, vertical = 1.dp),
                        style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Medium,
                    )
                }
            }
            Text(
                (if (device.platform.isEmpty()) "" else "${device.platform} · ") + if (device.current || device.online) "Active now" else "Last active ${formatWhen(device.lastSeenMillis)}",
                style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1,
            )
        }
    }
}
