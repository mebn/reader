package com.mebn.reader.formats

import java.io.File

class EpubDocument(file: File) : ReflowDocument() {
    private data class Item(val id: String, val path: String, val type: String, val properties: List<String>)

    private val zip = openZip(file)
    private val opf: Node
    private val manifest: Map<String, Item>
    private val spine: List<Item>
    private val chapterIndex: Map<String, Int>
    override val metadata: BookMetadata
    override val toc: List<TocEntry>
    override val chapterCount get() = spine.size

    init {
        val container = Markup.parse(runCatching { zip.text("META-INF/container.xml") }.getOrElse { zip.close(); throw BookError("not an EPUB") })
        val opfPath = container.first("rootfile")?.get("full-path") ?: run { zip.close(); throw BookError("not an EPUB") }
        opf = Markup.parse(zip.text(opfPath))

        val order = mutableListOf<Item>()
        val items = mutableMapOf<String, Item>()
        for (el in opf.all("item")) {
            val href = el["href"] ?: continue
            val id = el["id"] ?: href
            val item = Item(id, Paths.resolve(opfPath, href).first, el["media-type"] ?: "", (el["properties"] ?: "").split(' ').filter { it.isNotEmpty() })
            items[id] = item
            order += item
        }
        manifest = items
        spine = (opf.first("spine")?.all("itemref") ?: emptyList()).mapNotNull { items[it["idref"] ?: ""] }
        chapterIndex = spine.withIndex().associate { (i, item) -> item.path to i }

        metadata = BookMetadata(opf.text("title"), opf.text("creator"), opf.text("language").ifEmpty { null })
        toc = readToc(order)
    }

    /** A chapter's markup as stored in the book. */
    fun chapterSource(index: Int): String = zip.text(spine[index].path)

    override fun chapter(index: Int): Node {
        val path = spine[index].path
        val doc = Markup.parse(synchronized(zip) { chapterSource(index) })
        val body = doc.first("body") ?: doc.first("html") ?: doc
        body.sanitize()

        fun rewrite(node: Node) {
            when (node.name) {
                "img", "image" -> {
                    val src = node["src"] ?: node["href"]
                    if (src != null && !Paths.isExternal(src)) node.attributes["src"] = Paths.resolve(path, src).first
                }
                "a" -> node.attributes.remove("href")?.let { href ->
                    if (Paths.isExternal(href)) {
                        node.attributes["data-external"] = href
                    } else {
                        val (target, hash) = Paths.resolve(path, href)
                        node.attributes["data-href"] = if (hash != null) "$target#$hash" else target
                    }
                }
            }
            node.children.forEach(::rewrite)
        }
        rewrite(body)
        return body
    }

    override fun resolveLink(href: String): LinkTarget? {
        val parts = href.split('#', limit = 2)
        val chapter = chapterIndex[parts[0]] ?: return null
        return LinkTarget.Chapter(chapter, parts.getOrNull(1))
    }

    override fun imageData(src: String): ByteArray? = runCatching { synchronized(zip) { zip.data(src) } }.getOrNull()

    override fun cover(): ByteArray? {
        val items = manifest.values
        val coverId = opf.all("meta").firstOrNull { it["name"] == "cover" }?.get("content")
        val item = items.firstOrNull { "cover-image" in it.properties }
            ?: coverId?.let { manifest[it] }
            ?: items.firstOrNull { it.type.startsWith("image/") && (it.id + it.path).contains("cover", ignoreCase = true) }
        return item?.let { imageData(it.path) }
    }

    override fun close() = zip.close()

    private fun readToc(manifest: List<Item>): List<TocEntry> {
        val entries = mutableListOf<TocEntry>()
        fun add(label: String, base: String, href: String, depth: Int) {
            val (path, hash) = Paths.resolve(base, href)
            val chapter = chapterIndex[path]
            if (label.isNotEmpty() && chapter != null) entries += TocEntry(entries.size, label, depth, chapter, hash)
        }

        val nav = manifest.firstOrNull { "nav" in it.properties }
        val navText = nav?.let { runCatching { zip.text(it.path) }.getOrNull() }
        if (nav != null && navText != null) {
            val navs = Markup.parse(navText).all("nav")
            val tocNav = navs.firstOrNull { (it["epub:type"] ?: it["type"] ?: "").contains("toc") } ?: navs.firstOrNull()
            fun walk(ol: Node?, depth: Int) {
                for (li in ol?.childElements("li").orEmpty()) {
                    val a = li.childElements().firstOrNull { it.name == "a" || it.name == "span" }
                    val href = a?.get("href")
                    if (a != null && href != null) add(a.trimmedText, nav.path, href, depth)
                    walk(li.childElements("ol").firstOrNull(), depth + 1)
                }
            }
            walk(tocNav?.childElements("ol")?.firstOrNull(), 0)
            if (entries.isNotEmpty()) return entries
        }

        val ncxId = opf.first("spine")?.get("toc")
        val ncx = manifest.firstOrNull { it.id == ncxId } ?: manifest.firstOrNull { it.type == "application/x-dtbncx+xml" }
        val ncxText = ncx?.let { runCatching { zip.text(it.path) }.getOrNull() }
        if (ncx != null && ncxText != null) {
            fun walk(parent: Node, depth: Int) {
                for (point in parent.childElements("navpoint")) {
                    val label = point.first("navlabel")?.text("text") ?: ""
                    point.first("content")?.get("src")?.let { add(label, ncx.path, it, depth) }
                    walk(point, depth + 1)
                }
            }
            Markup.parse(ncxText).first("navmap")?.let { walk(it, 0) }
        }
        return entries
    }
}
