package com.mebn.reader.settings

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.Typeface
import androidx.compose.ui.text.style.TextAlign as UiTextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.mebn.reader.formats.Node
import com.mebn.reader.model.BookFonts
import com.mebn.reader.model.FontOption
import com.mebn.reader.model.PageBackground
import com.mebn.reader.model.ReaderSettings
import com.mebn.reader.model.TextAlign
import com.mebn.reader.reader.reflow.ChapterLayout
import com.mebn.reader.reader.reflow.ChapterTextBuilder
import com.mebn.reader.reader.reflow.TextStyle
import java.util.Locale
import kotlin.math.roundToInt

/** A labeled row in a settings form. */
@Composable
fun FormRow(label: String, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Row(modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        content()
    }
}

@Composable
fun SwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable { onChange(!checked) }.padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        Switch(checked, onChange)
    }
}

/** Two or three choices side by side. */
@Composable
fun <T> Segments(options: List<Pair<T, String>>, selected: T, modifier: Modifier = Modifier, onSelect: (T) -> Unit) {
    SingleChoiceSegmentedButtonRow(modifier) {
        options.forEachIndexed { i, (value, label) ->
            SegmentedButton(
                selected = value == selected,
                onClick = { onSelect(value) },
                shape = SegmentedButtonDefaults.itemShape(i, options.size),
                icon = {},
            ) { Text(label, maxLines = 1) }
        }
    }
}

/** Page color for light and dark. `dark` picks which one is being edited. */
@Composable
fun PageSettingsSection(settings: ReaderSettings, dark: Boolean, onDark: (Boolean) -> Unit, onChange: (ReaderSettings) -> Unit) {
    Segments(listOf(false to "Light", true to "Dark"), dark, Modifier.fillMaxWidth()) { onDark(it) }
    FormRow("Background", Modifier.padding(top = 8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (bg in PageBackground.all.filter { it.dark == dark }) {
                val selected = (if (dark) settings.darkBackground else settings.lightBackground) == bg.id
                Box(
                    Modifier
                        .size(36.dp)
                        .border(2.dp, if (selected) MaterialTheme.colorScheme.onSurface else Color.Transparent, CircleShape)
                        .padding(4.dp)
                        .clip(CircleShape)
                        .background(Color(bg.color))
                        .border(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.15f), CircleShape)
                        .clickable { onChange(if (dark) settings.copy(darkBackground = bg.id) else settings.copy(lightBackground = bg.id)) }
                        .semantics {
                            contentDescription = bg.id.replaceFirstChar { it.uppercase() }
                            this.selected = selected
                        },
                )
            }
        }
    }
}

@Composable
fun TextSettingsSection(settings: ReaderSettings, onChange: (ReaderSettings) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(vertical = 4.dp)) {
        for (row in FontOption.all.chunked(3)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (font in row) {
                    val selected = settings.font == font.id
                    val family = remember(font.id) { FontFamily(Typeface(BookFonts.typeface(font.id, 400.0))) }
                    Column(
                        Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(12.dp))
                            .background(if (selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.12f) else Color.Transparent)
                            .border(
                                BorderStroke(if (selected) 1.5.dp else 1.dp, if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f)),
                                RoundedCornerShape(12.dp),
                            )
                            .clickable { onChange(settings.copy(font = font.id)) }
                            .padding(horizontal = 10.dp, vertical = 8.dp),
                    ) {
                        Text("Aa", fontFamily = family, fontSize = 20.sp)
                        Text(font.label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
                repeat(3 - row.size) { Box(Modifier.weight(1f)) }
            }
        }
    }
    SliderRow("Size", settings.fontSize, 12.0..34.0, 1.0, { "${it.roundToInt()}" }) { onChange(settings.copy(fontSize = it)) }
    SliderRow("Line height", settings.lineHeight, 1.1..2.4, 0.05, { String.format(Locale.US, "%.2f", it) }) { onChange(settings.copy(lineHeight = it)) }
    SliderRow("Weight", settings.weight, 300.0..700.0, 50.0, { "${it.roundToInt()}" }) { onChange(settings.copy(weight = it)) }
    SliderRow("Spacing", settings.tracking, -0.03..0.12, 0.005, { String.format(Locale.US, "%.1f", it * 100) }) { onChange(settings.copy(tracking = it)) }
}

@Composable
fun LayoutSettingsSection(settings: ReaderSettings, onChange: (ReaderSettings) -> Unit) {
    SliderRow("Margins", settings.sideMargin, 0.0..40.0, 1.0, { if (it == 0.0) "None" else "${it.roundToInt()}%" }) { onChange(settings.copy(sideMargin = it)) }
    SliderRow("Paragraphs", settings.paragraphSpacing, 0.0..2.0, 0.1, { String.format(Locale.US, "%.1f", it) }) { onChange(settings.copy(paragraphSpacing = it)) }
    FormRow("Align") {
        Segments(listOf(TextAlign.LEFT to "Left", TextAlign.JUSTIFY to "Justify"), settings.align, Modifier.width(200.dp)) { onChange(settings.copy(align = it)) }
    }
    PagesPicker(settings, onChange)
    SwitchRow("Hyphenation", settings.hyphenate) { onChange(settings.copy(hyphenate = it)) }
}

/** One page at a time, or two facing pages on a wide screen. */
@Composable
fun PagesPicker(settings: ReaderSettings, onChange: (ReaderSettings) -> Unit) {
    FormRow("Pages") {
        Segments(listOf(1 to "One", 2 to "Two"), settings.pages, Modifier.width(200.dp)) { onChange(settings.copy(pages = it)) }
    }
}

@Composable
fun HeaderSettingsSection(settings: ReaderSettings, onChange: (ReaderSettings) -> Unit) {
    SwitchRow("Book title", settings.headerTitle) { onChange(settings.copy(headerTitle = it)) }
    SwitchRow("Author", settings.headerAuthor) { onChange(settings.copy(headerAuthor = it)) }
    SwitchRow("Chapter title", settings.headerChapter) { onChange(settings.copy(headerChapter = it)) }
    SwitchRow("Clock", settings.headerClock) { onChange(settings.copy(headerClock = it)) }
}

@Composable
fun FooterSettingsSection(settings: ReaderSettings, onChange: (ReaderSettings) -> Unit) {
    SwitchRow("Chapter title", settings.footerChapter) { onChange(settings.copy(footerChapter = it)) }
    SwitchRow("Page in chapter", settings.footerChapterPages) { onChange(settings.copy(footerChapterPages = it)) }
    SwitchRow("Page in book", settings.footerBookPages) { onChange(settings.copy(footerBookPages = it)) }
    SwitchRow("Percent read", settings.footerPercent) { onChange(settings.copy(footerPercent = it)) }
}

@Composable
fun SliderRow(label: String, value: Double, range: ClosedFloatingPointRange<Double>, step: Double, format: (Double) -> String, onChange: (Double) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(label, Modifier.width(96.dp), style = MaterialTheme.typography.bodyLarge)
        Slider(
            value = value.toFloat(),
            onValueChange = { onChange(((it / step).roundToInt() * step).coerceIn(range.start, range.endInclusive)) },
            valueRange = range.start.toFloat()..range.endInclusive.toFloat(),
            modifier = Modifier.weight(1f),
        )
        Text(
            format(value),
            Modifier.width(42.dp),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = UiTextAlign.End,
        )
    }
}

private val sample = Node.element(
    "body",
    children = listOf(
        Node.element("h3", children = listOf(Node.text("One"))),
        Node.element("p", children = listOf(Node.text("It was a bright cold day in April, and the clocks were striking thirteen. The hallway smelt of boiled cabbage and old rag mats."))),
        Node.element("p", children = listOf(Node.text("At one end of it a coloured poster, too large for indoor display, had been tacked to the wall."))),
    ),
)

/** A small page that shows how the settings will read. */
@Composable
fun SettingsPreview(settings: ReaderSettings, dark: Boolean, modifier: Modifier = Modifier) {
    val bg = settings.background(dark)
    val density = LocalDensity.current.density
    BoxWithConstraints(modifier.clip(RoundedCornerShape(16.dp)).background(Color(bg.color))) {
        val width = constraints.maxWidth
        val height = (width * 4f / 3).roundToInt()
        val margin = (width * settings.sideMargin / 100 * 0.6).roundToInt()
        val pad = (20 * density).roundToInt()
        val layout = remember(settings, dark, width) {
            val style = TextStyle(settings.copy(fontSize = settings.fontSize * 0.8), bg.text, width - margin * 2, height * 4, "en", density)
            ChapterLayout(0, ChapterTextBuilder(style) { _, _ -> null }.build(sample), style)
        }
        Canvas(Modifier.fillMaxWidth().height(with(LocalDensity.current) { height.toDp() })) {
            drawIntoCanvas {
                it.nativeCanvas.save()
                it.nativeCanvas.clipRect(0f, 0f, size.width, size.height - pad)
                it.nativeCanvas.translate(margin.toFloat(), pad.toFloat())
                layout.draw(it.nativeCanvas, 0, null, 0)
                it.nativeCanvas.restore()
            }
        }
    }
}
