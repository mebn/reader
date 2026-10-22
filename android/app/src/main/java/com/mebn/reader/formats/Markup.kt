package com.mebn.reader.formats

/**
 * A small DOM for book markup (XHTML, FB2, XML metadata). Text nodes keep their raw
 * characters, so character offsets match what a browser's DOM counts.
 */
class Node private constructor(
    /** Local name without a namespace prefix, lowercased; null for text. */
    val name: String?,
    val text: String?,
    val attributes: MutableMap<String, String>,
) {
    val children = mutableListOf<Node>()
    var parent: Node? = null
        private set

    val isText get() = name == null

    fun append(child: Node) {
        child.parent = this
        children += child
    }

    operator fun get(attribute: String): String? =
        attributes[attribute] ?: attributes.entries.firstOrNull { it.key.endsWith(":$attribute") }?.value

    /** All text inside, like textContent. */
    val textContent: String
        get() = text ?: buildString { appendText(this) }

    private fun appendText(out: StringBuilder) {
        if (text != null) out.append(text) else children.forEach { it.appendText(out) }
    }

    /** textContent with whitespace collapsed and trimmed. */
    val trimmedText: String get() = textContent.replace(Regex("\\s+"), " ").trim()

    /** The first element with this local name, depth first, including this one. */
    fun first(name: String): Node? {
        if (this.name == name) return this
        for (child in children) child.first(name)?.let { return it }
        return null
    }

    fun all(name: String): List<Node> {
        val out = mutableListOf<Node>()
        fun walk(node: Node) {
            if (node.name == name) out += node
            node.children.forEach(::walk)
        }
        walk(this)
        return out
    }

    fun childElements(name: String? = null): List<Node> = children.filter { !it.isText && (name == null || it.name == name) }

    /** Text of the first element with this name, trimmed. */
    fun text(of: String): String = first(of)?.textContent?.trim() ?: ""

    /** Removes active content the way the desktop app's sanitizer does, so both count the same text. */
    fun sanitize() {
        children.removeAll { it.name != null && it.name in Markup.removed }
        children.forEach { it.sanitize() }
    }

    companion object {
        fun element(name: String, attributes: Map<String, String> = emptyMap(), children: List<Node> = emptyList()): Node =
            Node(name, null, attributes.toMutableMap()).also { node -> children.forEach(node::append) }

        fun text(text: String) = Node(null, text, mutableMapOf())
    }
}

object Markup {
    val removed = setOf(
        "script", "style", "link", "meta", "iframe", "object", "embed", "form", "input", "button", "textarea", "select",
        "noscript", "audio", "video",
    )
    private val void = setOf("area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr")
    private val rawText = setOf("script", "style")

    /** Parses XML or HTML leniently into a document node. */
    fun parse(source: String): Node {
        val doc = Node.element("#document")
        val stack = mutableListOf(doc)
        val s = source.replace("\r\n", "\n").replace('\r', '\n')
        val n = s.length
        var i = 0
        var textStart = 0

        fun flushText(end: Int) {
            if (end > textStart) stack.last().append(Node.text(decodeEntities(s.substring(textStart, end))))
        }

        while (i < n) {
            if (s[i] != '<' || i + 1 >= n) {
                i++
                continue
            }
            val next = s[i + 1]
            if (!(next == '/' || next == '!' || next == '?' || isNameStart(next))) {
                i++
                continue
            }
            flushText(i)

            when {
                next == '!' -> when {
                    s.startsWith("<!--", i) -> i = s.indexOf("-->", i + 4).let { if (it < 0) n else it + 3 }
                    s.startsWith("<![CDATA[", i) -> {
                        val end = s.indexOf("]]>", i + 9).let { if (it < 0) n else it }
                        stack.last().append(Node.text(s.substring(i + 9, end)))
                        i = minOf(n, end + 3)
                    }
                    else -> i = skipTag(s, i)
                }
                next == '?' -> i = s.indexOf("?>", i + 2).let { if (it < 0) n else it + 2 }
                next == '/' -> {
                    val end = skipTag(s, i)
                    val name = localName(s.substring(i + 2, maxOf(i + 2, end - 1)))
                    val index = stack.indexOfLast { it.name == name }
                    if (index > 0) while (stack.size > index) stack.removeAt(stack.size - 1)
                    i = end
                }
                else -> {
                    val end = skipTag(s, i)
                    val inner = s.substring(i + 1, maxOf(i + 1, end - 1))
                    val selfClosing = inner.endsWith("/")
                    val (name, attributes) = parseTag(if (selfClosing) inner.dropLast(1) else inner)
                    val node = Node.element(name, attributes)
                    stack.last().append(node)
                    i = end
                    if (name in rawText && !selfClosing) {
                        // Script and style content is never markup.
                        val close = s.indexOf("</$name", i).let { if (it < 0) n else it }
                        node.append(Node.text(s.substring(i, close)))
                        i = if (close < n) skipTag(s, close) else n
                    } else if (!selfClosing && name !in void) {
                        stack += node
                    }
                }
            }
            textStart = i
        }
        flushText(n)
        return doc
    }

    private fun isNameStart(c: Char) = c in 'A'..'Z' || c in 'a'..'z' || c == '_' || c.code > 127

    /** The index just past the tag starting at `start`, honoring quoted attribute values. */
    private fun skipTag(s: String, start: Int): Int {
        var i = start + 1
        var quote = 0.toChar()
        while (i < s.length) {
            val c = s[i]
            if (quote != 0.toChar()) {
                if (c == quote) quote = 0.toChar()
            } else if (c == '"' || c == '\'') {
                quote = c
            } else if (c == '>') {
                return i + 1
            }
            i++
        }
        return s.length
    }

    private fun localName(raw: String): String {
        val name = raw.trim().lowercase()
        return name.substringAfterLast(':')
    }

    private val attributePattern = Regex("""([^\s=/>"']+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?""")

    private fun parseTag(inner: String): Pair<String, Map<String, String>> {
        val trimmed = inner.trim()
        val nameEnd = trimmed.indexOfFirst { it.isWhitespace() }.let { if (it < 0) trimmed.length else it }
        val name = localName(trimmed.substring(0, nameEnd))
        val attributes = mutableMapOf<String, String>()
        for (match in attributePattern.findAll(trimmed.substring(nameEnd))) {
            val key = match.groupValues[1].lowercase()
            val value = (2..4).mapNotNull { match.groups[it]?.value }.lastOrNull() ?: ""
            attributes[key] = decodeEntities(value)
        }
        return name to attributes
    }

    // Entities

    fun decodeEntities(text: String): String {
        if ('&' !in text) return text
        val out = StringBuilder(text.length)
        var i = 0
        while (i < text.length) {
            val c = text[i]
            val semi = if (c == '&') text.indexOf(';', i).takeIf { it in (i + 1)..(i + 33) } else null
            val decoded = semi?.let { decode(text.substring(i + 1, it)) }
            if (decoded != null) {
                out.append(decoded)
                i = semi + 1
            } else {
                out.append(c)
                i++
            }
        }
        return out.toString()
    }

    private fun decode(entity: String): String? {
        if (entity.startsWith("#")) {
            val hex = entity.getOrNull(1)?.let { it == 'x' || it == 'X' } ?: false
            val value = entity.drop(if (hex) 2 else 1).toIntOrNull(if (hex) 16 else 10) ?: return null
            return if (Character.isValidCodePoint(value)) String(Character.toChars(value)) else null
        }
        return entities[entity]?.let { String(Character.toChars(it)) }
    }

    private val entities = mapOf(
        "amp" to 38, "lt" to 60, "gt" to 62, "quot" to 34, "apos" to 39, "nbsp" to 160, "shy" to 173,
        "ensp" to 8194, "emsp" to 8195, "thinsp" to 8201, "zwnj" to 8204, "zwj" to 8205, "lrm" to 8206, "rlm" to 8207,
        "ndash" to 8211, "mdash" to 8212, "lsquo" to 8216, "rsquo" to 8217, "sbquo" to 8218, "ldquo" to 8220, "rdquo" to 8221,
        "bdquo" to 8222, "dagger" to 8224, "Dagger" to 8225, "bull" to 8226, "hellip" to 8230, "permil" to 8240, "prime" to 8242,
        "Prime" to 8243, "lsaquo" to 8249, "rsaquo" to 8250, "laquo" to 171, "raquo" to 187, "euro" to 8364, "trade" to 8482,
        "copy" to 169, "reg" to 174, "deg" to 176, "plusmn" to 177, "sup1" to 185, "sup2" to 178, "sup3" to 179, "micro" to 181,
        "para" to 182, "middot" to 183, "sect" to 167, "cent" to 162, "pound" to 163, "yen" to 165, "curren" to 164, "brvbar" to 166,
        "uml" to 168, "ordf" to 170, "ordm" to 186, "not" to 172, "macr" to 175, "acute" to 180, "cedil" to 184, "frac14" to 188,
        "frac12" to 189, "frac34" to 190, "iquest" to 191, "iexcl" to 161, "times" to 215, "divide" to 247, "minus" to 8722,
        "larr" to 8592, "rarr" to 8594, "uarr" to 8593, "darr" to 8595, "harr" to 8596, "infin" to 8734, "ne" to 8800, "le" to 8804, "ge" to 8805,
        "Agrave" to 192, "Aacute" to 193, "Acirc" to 194, "Atilde" to 195, "Auml" to 196, "Aring" to 197, "AElig" to 198, "Ccedil" to 199,
        "Egrave" to 200, "Eacute" to 201, "Ecirc" to 202, "Euml" to 203, "Igrave" to 204, "Iacute" to 205, "Icirc" to 206, "Iuml" to 207,
        "ETH" to 208, "Ntilde" to 209, "Ograve" to 210, "Oacute" to 211, "Ocirc" to 212, "Otilde" to 213, "Ouml" to 214, "Oslash" to 216,
        "Ugrave" to 217, "Uacute" to 218, "Ucirc" to 219, "Uuml" to 220, "Yacute" to 221, "THORN" to 222, "szlig" to 223,
        "agrave" to 224, "aacute" to 225, "acirc" to 226, "atilde" to 227, "auml" to 228, "aring" to 229, "aelig" to 230, "ccedil" to 231,
        "egrave" to 232, "eacute" to 233, "ecirc" to 234, "euml" to 235, "igrave" to 236, "iacute" to 237, "icirc" to 238, "iuml" to 239,
        "eth" to 240, "ntilde" to 241, "ograve" to 242, "oacute" to 243, "ocirc" to 244, "otilde" to 245, "ouml" to 246, "oslash" to 248,
        "ugrave" to 249, "uacute" to 250, "ucirc" to 251, "uuml" to 252, "yacute" to 253, "thorn" to 254, "yuml" to 255,
        "OElig" to 338, "oelig" to 339, "Scaron" to 352, "scaron" to 353, "Yuml" to 376, "fnof" to 402, "circ" to 710, "tilde" to 732,
        "Alpha" to 913, "Beta" to 914, "Gamma" to 915, "Delta" to 916, "Omega" to 937, "alpha" to 945, "beta" to 946, "gamma" to 947,
        "delta" to 948, "epsilon" to 949, "lambda" to 955, "mu" to 956, "pi" to 960, "sigma" to 963, "omega" to 969,
    )
}

/** Helpers shared by the parsers. */
object Paths {
    /** Resolves `href` against the directory of `from`, both archive-relative paths. */
    fun resolve(from: String, href: String): Pair<String, String?> {
        val hashAt = href.indexOf('#')
        val path = if (hashAt < 0) href else href.substring(0, hashAt)
        val hash = if (hashAt < 0) null else href.substring(hashAt + 1)
        if (path.isEmpty()) return from to hash
        val segments = from.split('/').filter { it.isNotEmpty() }.dropLast(1).toMutableList()
        val decoded = runCatching { java.net.URLDecoder.decode(path.replace("+", "%2B"), "UTF-8") }.getOrDefault(path)
        for (segment in decoded.split('/').filter { it.isNotEmpty() }) {
            when (segment) {
                ".." -> segments.removeLastOrNull()
                "." -> {}
                else -> segments += segment
            }
        }
        return segments.joinToString("/") to hash
    }

    fun isExternal(href: String) = Regex("^[a-zA-Z][a-zA-Z0-9+.-]*:").containsMatchIn(href)

    fun nameWithoutExtension(fileName: String) = fileName.substringBeforeLast('.').replace('_', ' ').trim()
}
