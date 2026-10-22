package com.mebn.reader.formats

import java.io.File
import java.nio.charset.Charset

/** Plain text, split into chapters at headings or into evenly sized parts. */
class TxtDocument(file: File, fileName: String) : ReflowDocument() {
    private class Chapter(var title: String? = null, val paragraphs: MutableList<String> = mutableListOf())

    private val chapters = split(decode(file.readBytes()))
    override val metadata = BookMetadata(Paths.nameWithoutExtension(fileName), "")
    override val toc = chapters.withIndex().mapNotNull { (i, c) -> c.title?.let { TocEntry(i, it, 0, chapter = i) } }
    override val chapterCount get() = chapters.size

    private fun decode(data: ByteArray): String {
        val utf8 = String(data, Charsets.UTF_8)
        val broken = utf8.count { it == '\uFFFD' }
        return if (broken > utf8.length / 1000) String(data, Charset.forName("windows-1252")) else utf8
    }

    private fun split(text: String): List<Chapter> {
        val normalized = text.replace(Regex("\r\n?"), "\n")
        val blocks = if (Regex("\n\\s*\n").containsMatchIn(normalized)) normalized.split(Regex("\n\\s*\n+")) else normalized.split("\n")
        val paragraphs = blocks.map { it.replace(Regex("\\s*\n\\s*"), " ").trim() }.filter { it.isNotEmpty() }

        val chapters = mutableListOf<Chapter>()
        var current = Chapter()
        var size = 0
        for (p in paragraphs) {
            val isHeading = p.length < 80 && heading.containsMatchIn(p)
            if ((isHeading || size > MAX_CHAPTER_CHARS) && current.paragraphs.isNotEmpty()) {
                chapters += current
                current = Chapter()
                size = 0
            }
            if (isHeading) current.title = p else current.paragraphs += p
            size += p.length
        }
        if (current.paragraphs.isNotEmpty() || current.title != null) chapters += current
        return chapters.ifEmpty { listOf(Chapter()) }
    }

    override fun chapter(index: Int): Node {
        val chapter = chapters[index]
        val root = Node.element("body")
        chapter.title?.let { root.append(Node.element("h2", children = listOf(Node.text(it)))) }
        for (p in chapter.paragraphs) root.append(Node.element("p", children = listOf(Node.text(p))))
        return root
    }

    override fun resolveLink(href: String): LinkTarget? = null
    override fun imageData(src: String): ByteArray? = null
    override fun cover(): ByteArray? = null

    companion object {
        private val heading = Regex("^\\s*(chapter|kapitel|part|book|del)\\s+([0-9]+|[ivxlcdm]+)\\b.*$", RegexOption.IGNORE_CASE)
        private const val MAX_CHAPTER_CHARS = 40_000
    }
}
