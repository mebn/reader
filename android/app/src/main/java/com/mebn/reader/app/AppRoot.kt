package com.mebn.reader.app

import android.app.Activity
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Error
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.core.view.WindowCompat
import androidx.compose.ui.unit.dp
import com.mebn.reader.library.LibraryNavigation
import com.mebn.reader.library.LibraryScreen
import com.mebn.reader.login.LoginScreen
import com.mebn.reader.reader.BookJump
import com.mebn.reader.reader.ReaderScreen
import com.mebn.reader.reader.appIsDark
import com.mebn.reader.settings.SettingsScreen
import com.mebn.reader.ui.ReaderTheme

/** Signs in first, then the library with its folders, an open book and the settings over it. */
@Composable
fun AppRoot() {
    val signedIn = AppModel.signedIn
    val dark = if (signedIn) appIsDark() else androidx.compose.foundation.isSystemInDarkTheme()
    // The status bar's icons follow the app's theme, which can differ from the system's.
    val view = LocalView.current
    LaunchedEffect(dark) {
        (view.context as? Activity)?.window?.let { window ->
            WindowCompat.getInsetsController(window, view).apply {
                isAppearanceLightStatusBars = !dark
                isAppearanceLightNavigationBars = !dark
            }
        }
    }
    ReaderTheme(dark = dark) {
        Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
            if (signedIn) Library() else LoginScreen()
            ToastView()
        }
    }
}

@Composable
private fun Library() {
    var folders by rememberSaveable { mutableStateOf(listOf<String>()) }
    var book by rememberSaveable { mutableStateOf<String?>(null) }
    var settings by rememberSaveable { mutableStateOf(false) }
    val nav = LibraryNavigation(
        openBook = { book = it.id },
        openAt = { b, locator ->
            BookJump.set(b.id, locator)
            book = b.id
        },
        openFolder = { folders = folders + it },
    )

    AnimatedContent(
        folders,
        transitionSpec = {
            val forward = targetState.size > initialState.size
            (slideInHorizontally { if (forward) it / 4 else -it / 4 } + fadeIn(tween(220))) togetherWith
                (slideOutHorizontally { if (forward) -it / 4 else it / 4 } + fadeOut(tween(180)))
        },
        label = "folders",
    ) { stack ->
        LibraryScreen(stack.lastOrNull(), nav, onBack = { folders = folders.dropLast(1) }, onSettings = { settings = true })
    }

    AnimatedVisibility(settings, enter = slideInVertically { it / 6 } + fadeIn(), exit = slideOutVertically { it / 6 } + fadeOut()) {
        SettingsScreen { settings = false }
    }

    AnimatedVisibility(book != null, enter = scaleIn(initialScale = 0.92f) + fadeIn(), exit = scaleOut(targetScale = 0.92f) + fadeOut()) {
        // Keeps showing the book while it animates away.
        var last by rememberSaveable { mutableStateOf(book) }
        book?.let { last = it }
        last?.let { id -> ReaderScreen(id) { book = null } }
    }
}

/** Short notices over the app, like the desktop's toasts. */
@Composable
private fun ToastView() {
    val toast = Toasts.current
    AnimatedVisibility(
        toast != null,
        Modifier.fillMaxWidth().statusBarsPadding().padding(top = 8.dp),
        enter = slideInVertically { -it } + fadeIn(),
        exit = slideOutVertically { -it } + fadeOut(),
    ) {
        var shown by rememberSaveable { mutableStateOf(toast) }
        toast?.let { shown = it }
        val t = shown ?: return@AnimatedVisibility
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
            Surface(
                onClick = { if (!t.progress && t.action == null) Toasts.dismiss() },
                modifier = Modifier.padding(horizontal = 16.dp).widthIn(max = 420.dp).fillMaxWidth(),
                shape = RoundedCornerShape(24.dp),
                color = MaterialTheme.colorScheme.surfaceContainerHighest,
                shadowElevation = 8.dp,
            ) {
                Row(Modifier.padding(horizontal = 18.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (t.progress) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                    else if (t.isError) Icon(Icons.Filled.Error, null, tint = MaterialTheme.colorScheme.error)
                    Column(Modifier.weight(1f).padding(start = if (t.progress || t.isError) 12.dp else 0.dp)) {
                        Text(t.title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                        t.detail?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    }
                    t.action?.let { FilledTonalButton({ Toasts.runAction() }) { Text(it) } }
                }
            }
        }
    }
}
