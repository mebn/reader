package com.mebn.reader.model

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject

@Serializable
enum class ThemeMode(val label: String) {
    @SerialName("system") SYSTEM("System"),
    @SerialName("light") LIGHT("Light"),
    @SerialName("dark") DARK("Dark"),
}

@Serializable
enum class LibraryTab(val label: String) {
    @SerialName("all") ALL("All"),
    @SerialName("books") BOOKS("Books"),
    @SerialName("highlights") HIGHLIGHTS("Highlights"),
    @SerialName("notes") NOTES("Notes"),
    @SerialName("bookmarks") BOOKMARKS("Bookmarks"),
}

@Serializable
enum class TextAlign {
    @SerialName("left") LEFT,
    @SerialName("justify") JUSTIFY,
}

/** How the reader moves from one page to the next. */
@Serializable
enum class PageTurn(val label: String) {
    @SerialName("instant") INSTANT("Instant"),
    @SerialName("fade") FADE("Fade"),
    @SerialName("slide") SLIDE("Slide"),
}

/**
 * Settings for how books look. Stored as JSON in the "reader" scope (defaults) and in
 * "reader:<bookId>" (only what a book changes), the same shape the desktop app uses.
 * Sizes are in points, which are density-independent pixels here.
 */
@Serializable
data class ReaderSettings(
    /** Background ids for the page while the app is light and while it is dark. */
    val lightBackground: String = "paper",
    val darkBackground: String = "night",
    val font: String = "literata",
    val fontSize: Double = 19.0,
    val lineHeight: Double = 1.6,
    val weight: Double = 400.0,
    val tracking: Double = 0.0,
    val paragraphSpacing: Double = 0.6,
    /** Space beside the text on each side, as a percentage of the width; 0 is none. */
    val sideMargin: Double = 20.0,
    val align: TextAlign = TextAlign.JUSTIFY,
    val hyphenate: Boolean = true,
    val pages: Int = 1,
    val pageTurn: PageTurn = PageTurn.SLIDE,
    /** What the header shows. */
    val headerTitle: Boolean = true,
    val headerAuthor: Boolean = false,
    val headerChapter: Boolean = false,
    val headerClock: Boolean = false,
    /** What the line under the text shows. */
    val footerChapter: Boolean = false,
    val footerChapterPages: Boolean = true,
    val footerBookPages: Boolean = true,
    val footerPercent: Boolean = false,
) {
    /** Settings that change the text layout, used to cache page counts. */
    fun layoutKey(width: Int, height: Int): String =
        listOf(font, fontSize, lineHeight, weight, tracking, paragraphSpacing, sideMargin, align, hyphenate, pages, width, height)
            .joinToString("|")

    fun background(dark: Boolean): PageBackground =
        PageBackground.find(if (dark) darkBackground else lightBackground) ?: PageBackground.find(if (dark) "night" else "paper")!!

    companion object {
        val defaults = ReaderSettings()

        /** Every key this type reads, so foreign keys in a book's override are ignored. */
        val keys: Set<String> = json.encodeToJsonElement(serializer(), defaults).jsonObject.keys
    }
}

@Serializable
data class AppSettings(
    /** Light or dark for the whole app, the reader included. */
    val theme: ThemeMode = ThemeMode.SYSTEM,
    val openInNewWindow: Boolean = false,
    /** The library tab shown when the app starts. */
    val defaultTab: LibraryTab = LibraryTab.ALL,
)

object Scope {
    const val APP = "app"
    const val READER = "reader"
    fun book(id: String) = "reader:$id"
}

data class PageBackground(val id: String, val color: Int, val text: Int, val dark: Boolean) {
    companion object {
        val all = listOf(
            PageBackground("paper", 0xfffbfaf7.toInt(), 0xff26231f.toInt(), false),
            PageBackground("white", 0xffffffff.toInt(), 0xff151515.toInt(), false),
            PageBackground("cream", 0xfff5eedf.toInt(), 0xff2e2820.toInt(), false),
            PageBackground("sepia", 0xffebdcc0.toInt(), 0xff3a2e20.toInt(), false),
            PageBackground("sage", 0xffe1e8dc.toInt(), 0xff1f2a20.toInt(), false),
            PageBackground("slate", 0xff2a2d33.toInt(), 0xffd6d7d9.toInt(), true),
            PageBackground("night", 0xff18181a.toInt(), 0xffcfccc6.toInt(), true),
            PageBackground("black", 0xff000000.toInt(), 0xffb3b1ad.toInt(), true),
        )

        fun find(id: String) = all.firstOrNull { it.id == id }
    }
}

val highlightColors = listOf(
    "yellow" to 0xfff5c84c.toInt(),
    "green" to 0xff7fcf8a.toInt(),
    "blue" to 0xff6fb3f0.toInt(),
    "pink" to 0xfff08fb8.toInt(),
)

fun highlightColor(name: String): Int = highlightColors.firstOrNull { it.first == name }?.second ?: highlightColors[0].second

// Parsing

/**
 * Older saved settings: one background for both modes, and a header that showed one thing
 * ("title", "chapter" or "none") rather than a set of switches.
 */
private fun migrate(o: MutableMap<String, JsonElement>) {
    val header = (o["header"] as? JsonPrimitive)?.contentOrNull
    if (header != null && o["headerTitle"] == null) {
        o["headerTitle"] = JsonPrimitive(header == "title")
        o["headerChapter"] = JsonPrimitive(header == "chapter")
    }
    val old = (o["background"] as? JsonPrimitive)?.contentOrNull?.let(PageBackground::find)
    if (old != null && o["lightBackground"] == null && o["darkBackground"] == null) {
        o[if (old.dark) "darkBackground" else "lightBackground"] = JsonPrimitive(old.id)
    }
}

/** The keys a settings record sets, after migrating older shapes. */
fun settingsObject(data: String?): MutableMap<String, JsonElement> {
    if (data.isNullOrEmpty()) return mutableMapOf()
    val parsed = runCatching { json.parseToJsonElement(data) as? JsonObject }.getOrNull() ?: return mutableMapOf()
    return parsed.toMutableMap().also(::migrate)
}

/** Decodes settings over a base, keeping the base for anything not set or not readable. */
fun <T> decodeSettings(o: Map<String, JsonElement>, base: T, serializer: KSerializer<T>): T {
    val merged = json.encodeToJsonElement(serializer, base).jsonObject.toMutableMap()
    var result = base
    for ((k, v) in o) {
        if (k !in merged) continue
        val previous = merged[k]
        merged[k] = v
        val decoded = runCatching { json.decodeFromJsonElement(serializer, JsonObject(merged)) }.getOrNull()
        if (decoded != null) result = decoded else merged[k] = previous!!
    }
    return result
}

fun decodeReaderSettings(o: Map<String, JsonElement>, base: ReaderSettings): ReaderSettings =
    decodeSettings(o, base, ReaderSettings.serializer()).let { if (it.pages == 2) it else it.copy(pages = 1) }

/** The keys where `settings` differs from `base`, as a JSON object. */
fun <T> settingsDiff(settings: T, base: T, serializer: KSerializer<T>): Map<String, JsonElement> {
    val a = json.encodeToJsonElement(serializer, settings).jsonObject
    val b = json.encodeToJsonElement(serializer, base).jsonObject
    return a.filter { (k, v) -> b[k] != v }
}

fun <T> settingsMap(settings: T, serializer: KSerializer<T>): Map<String, JsonElement> =
    json.encodeToJsonElement(serializer, settings).jsonObject
