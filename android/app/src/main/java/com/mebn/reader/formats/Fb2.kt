package com.mebn.reader.formats

import android.util.Base64
import java.io.File
import java.nio.charset.Charset

/** FictionBook, converted to the same HTML-like tree the desktop app builds. */
class Fb2Document(file: File, fileName: String) : ReflowDocument() {
    private val info: Node?
    private val chapters: List<Node>
    private val binaries = mutableMapOf<String, ByteArray>()
    private val anchors = mutableMapOf<String, Int>()
    override val metadata: BookMetadata
    override val toc: List<TocEntry>
    override val chapterCount get() = chapters.size

    init {
        val doc = Markup.parse(decode(file.readBytes()))
        info = doc.first("title-info")
        val author = info?.first("author")
        val title = info?.text("book-title") ?: ""

        for (bin in doc.all("binary")) {
            val base64 = bin.textContent.filterNot { it.isWhitespace() }
            runCatching { Base64.decode(base64, Base64.DEFAULT) }.getOrNull()?.let { binaries[bin["id"] ?: ""] = it }
        }

        val body = doc.all("body").firstOrNull { it["name"] != "notes" }
        val sections = body?.childElements("section").orEmpty()
        chapters = sections.ifEmpty { listOfNotNull(body) }

        for ((i, chapter) in chapters.withIndex()) {
            fun walk(node: Node) {
                node["id"]?.let { anchors[it] = i }
                node.children.forEach(::walk)
            }
            walk(chapter)
        }

        toc = chapters.mapIndexed { i, chapter ->
            val label = chapter.childElements("title").firstOrNull()?.trimmedText ?: ""
            TocEntry(i, label.ifEmpty { "${i + 1}" }, 0, chapter = i)
        }
        metadata = BookMetadata(
            title.ifEmpty { Paths.nameWithoutExtension(fileName) },
            listOf(author?.text("first-name") ?: "", author?.text("last-name") ?: "").filter { it.isNotEmpty() }.joinToString(" "),
            info?.text("lang")?.ifEmpty { null },
        )
    }

    private fun decode(data: ByteArray): String {
        val head = String(data, 0, minOf(200, data.size), Charsets.UTF_8).lowercase()
        if ("windows-1251" in head) return String(data, Charset.forName("windows-1251"))
        val utf8 = Charsets.UTF_8.newDecoder()
        return runCatching { utf8.decode(java.nio.ByteBuffer.wrap(data)).toString() }.getOrElse { String(data, Charset.forName("windows-1252")) }
    }

    override fun chapter(index: Int): Node {
        val root = Node.element("body")
        chapters[index].children.forEach { child -> convert(child).forEach(root::append) }
        return root
    }

    private fun convert(node: Node): List<Node> {
        val name = node.name ?: return listOf(Node.text(node.textContent))
        return when (name) {
            "image" -> listOf(Node.element("img", mapOf("src" to (node["href"] ?: "").replace("#", ""))))
            "empty-line" -> listOf(Node.element("br"))
            "a" -> {
                val href = node["href"] ?: ""
                val key = if (href.startsWith("#")) "data-href" else "data-external"
                listOf(Node.element("a", mapOf(key to href.removePrefix("#")), node.children.flatMap(::convert)))
            }
            else -> {
                val children = node.children.flatMap(::convert)
                val tag = tags[name] ?: return children
                listOf(Node.element(tag, node["id"]?.let { mapOf("id" to it) } ?: emptyMap(), children))
            }
        }
    }

    override fun resolveLink(href: String): LinkTarget? = anchors[href]?.let { LinkTarget.Chapter(it, href) }

    override fun imageData(src: String): ByteArray? = binaries[src]

    override fun cover(): ByteArray? {
        val id = (info?.first("coverpage")?.first("image")?.get("href") ?: "").replace("#", "")
        return binaries[id]
    }

    companion object {
        /** FictionBook element → HTML tag. Unlisted elements become their children. */
        private val tags = mapOf(
            "p" to "p", "title" to "h2", "subtitle" to "h3", "emphasis" to "em", "strong" to "strong", "strikethrough" to "s",
            "sup" to "sup", "sub" to "sub", "code" to "code", "epigraph" to "blockquote", "cite" to "blockquote", "poem" to "div",
            "stanza" to "p", "v" to "div", "text-author" to "p", "section" to "section", "table" to "table", "tr" to "tr", "td" to "td", "th" to "th",
        )
    }
}
