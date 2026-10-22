package com.mebn.reader.model

import android.graphics.Typeface
import com.mebn.reader.ReaderApp
import java.util.concurrent.ConcurrentHashMap

data class FontOption(
    val id: String,
    val label: String,
    /** The bundled font file without extension, or null for a font the system has. */
    val file: String?,
    /** Whether the font has a weight axis, so any weight can be drawn. */
    val variable: Boolean,
    /** The system family to fall back on, for fonts that aren't bundled. */
    val system: Typeface = Typeface.SERIF,
) {
    companion object {
        val all = listOf(
            FontOption("literata", "Literata", "Literata", true),
            FontOption("source-serif", "Source Serif", "SourceSerif4", true),
            FontOption("lora", "Lora", "Lora", true),
            FontOption("merriweather", "Merriweather", "Merriweather", true),
            FontOption("garamond", "EB Garamond", "EBGaramond", true),
            // Georgia isn't on Android; the system serif stands in.
            FontOption("georgia", "Georgia", null, false),
            FontOption("inter", "Inter", "Inter", true),
            FontOption("atkinson", "Atkinson", "AtkinsonHyperlegible", false),
            FontOption("system", "System", null, false, Typeface.DEFAULT),
        )

        fun find(id: String) = all.firstOrNull { it.id == id } ?: all[0]
    }
}

object BookFonts {
    private val cache = ConcurrentHashMap<String, Typeface>()

    /** A typeface for book text. `weight` is CSS-style (100–900); variable fonts get it exactly. */
    fun typeface(id: String, weight: Double, italic: Boolean = false, monospace: Boolean = false): Typeface =
        cache.getOrPut("$id|$weight|$italic|$monospace") { make(id, weight.toInt().coerceIn(100, 900), italic, monospace) }

    private fun make(id: String, weight: Int, italic: Boolean, monospace: Boolean): Typeface {
        if (monospace) return Typeface.create(Typeface.MONOSPACE, weight, italic)
        val option = FontOption.find(id)
        val file = option.file ?: return Typeface.create(option.system, weight, italic)
        val assets = ReaderApp.context.assets
        return runCatching {
            if (option.variable) {
                Typeface.Builder(assets, "fonts/$file${if (italic) "-Italic" else ""}.ttf")
                    .setFontVariationSettings("'wght' $weight")
                    .setWeight(weight)
                    .setItalic(italic)
                    .build()
            } else {
                val bold = weight >= 600
                val style = when {
                    bold && italic -> "BoldItalic"
                    bold -> "Bold"
                    italic -> "Italic"
                    else -> "Regular"
                }
                Typeface.Builder(assets, "fonts/$file-$style.ttf").build()
            }
        }.getOrNull() ?: Typeface.create(Typeface.SERIF, weight, italic)
    }
}
