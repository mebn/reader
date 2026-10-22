package com.mebn.reader.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.mebn.reader.model.BookFonts

/** Warm paper and ink, like the desktop and iOS apps. */
private val light = lightColorScheme(
    primary = Color(0xff4a453d),
    onPrimary = Color.White,
    primaryContainer = Color(0xffebe7e0),
    onPrimaryContainer = Color(0xff26231f),
    secondary = Color(0xff6f6a62),
    secondaryContainer = Color(0xffebe7e0),
    onSecondaryContainer = Color(0xff26231f),
    background = Color(0xfffbfaf7),
    onBackground = Color(0xff26231f),
    surface = Color(0xfffbfaf7),
    onSurface = Color(0xff26231f),
    surfaceVariant = Color(0xffefece6),
    onSurfaceVariant = Color(0xff6f6a62),
    surfaceContainerLowest = Color(0xffffffff),
    surfaceContainerLow = Color(0xfff6f4ef),
    surfaceContainer = Color(0xfff3f1ec),
    surfaceContainerHigh = Color(0xffeeebe5),
    surfaceContainerHighest = Color(0xffe8e5de),
    outline = Color(0xffc9c4bb),
    outlineVariant = Color(0xffe2ded6),
)

private val dark = darkColorScheme(
    primary = Color(0xffe8e3db),
    onPrimary = Color(0xff1b1917),
    primaryContainer = Color(0xff35312c),
    onPrimaryContainer = Color(0xfff1ece4),
    secondary = Color(0xffaaa49b),
    secondaryContainer = Color(0xff35312c),
    onSecondaryContainer = Color(0xfff1ece4),
    background = Color(0xff171513),
    onBackground = Color(0xfff1ece4),
    surface = Color(0xff171513),
    onSurface = Color(0xfff1ece4),
    surfaceVariant = Color(0xff2a2723),
    onSurfaceVariant = Color(0xffaaa49b),
    surfaceContainerLowest = Color(0xff110f0e),
    surfaceContainerLow = Color(0xff1e1c19),
    surfaceContainer = Color(0xff23201d),
    surfaceContainerHigh = Color(0xff2a2723),
    surfaceContainerHighest = Color(0xff33302b),
    outline = Color(0xff5c5750),
    outlineVariant = Color(0xff3a3632),
)

/** Literata, as in books and the other apps' headings. */
fun literata(weight: Int): FontFamily = FontFamily(androidx.compose.ui.text.font.Typeface(BookFonts.typeface("literata", weight.toDouble())))

@Composable
fun ReaderTheme(dark: Boolean, content: @Composable () -> Unit) {
    val base = Typography()
    MaterialTheme(
        colorScheme = if (dark) com.mebn.reader.ui.dark else light,
        typography = base.copy(
            headlineLarge = base.headlineLarge.copy(fontFamily = literata(500), fontWeight = FontWeight.Medium),
            headlineMedium = base.headlineMedium.copy(fontFamily = literata(500), fontWeight = FontWeight.Medium),
            titleLarge = base.titleLarge.copy(fontFamily = literata(500), fontWeight = FontWeight.Medium),
        ),
        content = content,
    )
}

/** Small capitals over a section, as in the other apps. */
val sectionTitle = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.7.sp)
