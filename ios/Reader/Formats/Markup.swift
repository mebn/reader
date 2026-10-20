import Foundation

/// A small DOM for book markup (XHTML, FB2, XML metadata). Text nodes keep their raw
/// characters, so character offsets match what a browser's DOM counts.
final class Node {
    enum Kind {
        case element(String)
        case text(String)
    }

    let kind: Kind
    var attributes: [String: String]
    var children: [Node] = []
    weak var parent: Node?

    init(_ kind: Kind, attributes: [String: String] = [:]) {
        self.kind = kind
        self.attributes = attributes
    }

    static func element(_ name: String, _ attributes: [String: String] = [:], _ children: [Node] = []) -> Node {
        let node = Node(.element(name), attributes: attributes)
        children.forEach(node.append)
        return node
    }

    static func text(_ text: String) -> Node { Node(.text(text)) }

    /// Local name without a namespace prefix, lowercased; nil for text.
    var name: String? {
        if case let .element(name) = kind { return name }
        return nil
    }

    var isText: Bool { name == nil }

    func append(_ child: Node) {
        child.parent = self
        children.append(child)
    }

    subscript(attribute: String) -> String? {
        attributes[attribute] ?? attributes.first { $0.key.hasSuffix(":" + attribute) }?.value
    }

    /// All text inside, like textContent.
    var textContent: String {
        if case let .text(text) = kind { return text }
        return children.map(\.textContent).joined()
    }

    /// textContent with whitespace collapsed and trimmed.
    var trimmedText: String {
        textContent.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    /// The first element with this local name, depth first, including self.
    func first(_ name: String) -> Node? {
        if self.name == name { return self }
        for child in children {
            if let found = child.first(name) { return found }
        }
        return nil
    }

    func all(_ name: String) -> [Node] {
        var out: [Node] = []
        func walk(_ node: Node) {
            if node.name == name { out.append(node) }
            node.children.forEach(walk)
        }
        walk(self)
        return out
    }

    func childElements(_ name: String? = nil) -> [Node] {
        children.filter { !$0.isText && (name == nil || $0.name == name) }
    }

    /// Text of the first element with this name, trimmed.
    func text(of name: String) -> String {
        first(name)?.textContent.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Removes active content the way the desktop app's sanitizer does, so both count the
    /// same text.
    func sanitize() {
        children.removeAll { $0.name.map(Markup.removed.contains) ?? false }
        children.forEach { $0.sanitize() }
    }
}

enum Markup {
    static let removed: Set<String> = ["script", "style", "link", "meta", "iframe", "object", "embed", "form", "input", "button", "textarea", "select", "noscript", "audio", "video"]
    private static let void: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]
    private static let rawText: Set<String> = ["script", "style"]

    /// Parses XML or HTML leniently into a document node.
    static func parse(_ source: String) -> Node {
        let doc = Node.element("#document")
        var stack: [Node] = [doc]
        let s = Array(source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").utf16)
        var i = 0
        var textStart = 0

        func flushText(_ end: Int) {
            guard end > textStart else { return }
            let raw = String(utf16CodeUnits: Array(s[textStart..<end]), count: end - textStart)
            stack.last!.append(.text(decodeEntities(raw)))
        }

        func find(_ needle: String, from: Int) -> Int? {
            let n = Array(needle.utf16)
            var j = from
            while j + n.count <= s.count {
                if s[j] == n[0] && Array(s[j..<j + n.count]) == n { return j }
                j += 1
            }
            return nil
        }

        let lt: UInt16 = 60, gt: UInt16 = 62, slash: UInt16 = 47, bang: UInt16 = 33, question: UInt16 = 63
        while i < s.count {
            guard s[i] == lt, i + 1 < s.count else { i += 1; continue }
            let next = s[i + 1]
            let isTag = next == slash || next == bang || next == question || isNameStart(next)
            guard isTag else { i += 1; continue }
            flushText(i)

            if next == bang {
                if hasPrefix(s, i, "<!--") {
                    i = (find("-->", from: i + 4).map { $0 + 3 }) ?? s.count
                } else if hasPrefix(s, i, "<![CDATA[") {
                    let end = find("]]>", from: i + 9) ?? s.count
                    stack.last!.append(.text(String(utf16CodeUnits: Array(s[(i + 9)..<end]), count: end - i - 9)))
                    i = min(s.count, end + 3)
                } else {
                    i = skipTag(s, i)
                }
            } else if next == question {
                i = (find("?>", from: i + 2).map { $0 + 2 }) ?? s.count
            } else if next == slash {
                let end = skipTag(s, i)
                let name = localName(String(utf16CodeUnits: Array(s[(i + 2)..<max(i + 2, end - 1)]), count: max(0, end - 1 - i - 2)))
                if let index = stack.lastIndex(where: { $0.name == name }), index > 0 {
                    stack.removeSubrange(index...)
                }
                i = end
            } else {
                let end = skipTag(s, i)
                let inner = String(utf16CodeUnits: Array(s[(i + 1)..<max(i + 1, end - 1)]), count: max(0, end - 1 - i - 1))
                let selfClosing = inner.hasSuffix("/")
                let (name, attributes) = parseTag(selfClosing ? String(inner.dropLast()) : inner)
                let node = Node(.element(name), attributes: attributes)
                stack.last!.append(node)
                i = end
                if rawText.contains(name) && !selfClosing {
                    // Script and style content is never markup.
                    let close = find("</\(name)", from: i) ?? s.count
                    node.append(.text(String(utf16CodeUnits: Array(s[i..<close]), count: close - i)))
                    i = close < s.count ? skipTag(s, close) : s.count
                } else if !selfClosing && !void.contains(name) {
                    stack.append(node)
                }
            }
            textStart = i
        }
        flushText(s.count)
        return doc
    }

    private static func hasPrefix(_ s: [UInt16], _ at: Int, _ prefix: String) -> Bool {
        let p = Array(prefix.utf16)
        return at + p.count <= s.count && Array(s[at..<at + p.count]) == p
    }

    private static func isNameStart(_ c: UInt16) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c > 127
    }

    /// The index just past the tag starting at `start`, honoring quoted attribute values.
    private static func skipTag(_ s: [UInt16], _ start: Int) -> Int {
        var i = start + 1
        var quote: UInt16 = 0
        while i < s.count {
            let c = s[i]
            if quote != 0 {
                if c == quote { quote = 0 }
            } else if c == 34 || c == 39 {
                quote = c
            } else if c == 62 {
                return i + 1
            }
            i += 1
        }
        return s.count
    }

    private static func localName(_ raw: String) -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return name.split(separator: ":").last.map(String.init) ?? name
    }

    private static let attributePattern = try! NSRegularExpression(pattern: #"([^\s=/>"']+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?"#)

    private static func parseTag(_ inner: String) -> (String, [String: String]) {
        let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameEnd = trimmed.firstIndex(where: { $0.isWhitespace }) ?? trimmed.endIndex
        let name = localName(String(trimmed[..<nameEnd]))
        var attributes: [String: String] = [:]
        let rest = String(trimmed[nameEnd...])
        let ns = rest as NSString
        for match in attributePattern.matches(in: rest, range: NSRange(location: 0, length: ns.length)) {
            let key = ns.substring(with: match.range(at: 1)).lowercased()
            var value = ""
            for group in 2...4 where match.range(at: group).location != NSNotFound {
                value = ns.substring(with: match.range(at: group))
            }
            attributes[key] = decodeEntities(value)
        }
        return (name, attributes)
    }

    // MARK: - Entities

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        out.reserveCapacity(text.count)
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            guard c == "&", let semi = text[i...].prefix(34).firstIndex(of: ";") else {
                out.append(c)
                i = text.index(after: i)
                continue
            }
            let entity = text[text.index(after: i)..<semi]
            if let decoded = decode(entity) {
                out += decoded
                i = text.index(after: semi)
            } else {
                out.append(c)
                i = text.index(after: i)
            }
        }
        return out
    }

    private static func decode(_ entity: Substring) -> String? {
        if entity.hasPrefix("#") {
            let hex = entity.dropFirst().first.map { $0 == "x" || $0 == "X" } ?? false
            let digits = entity.dropFirst(hex ? 2 : 1)
            guard let value = UInt32(digits, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(value) else { return nil }
            return String(Character(scalar))
        }
        return entities[String(entity)].map { String(Character(Unicode.Scalar($0)!)) }
    }

    private static let entities: [String: UInt32] = [
        "amp": 38, "lt": 60, "gt": 62, "quot": 34, "apos": 39, "nbsp": 160, "shy": 173,
        "ensp": 8194, "emsp": 8195, "thinsp": 8201, "zwnj": 8204, "zwj": 8205, "lrm": 8206, "rlm": 8207,
        "ndash": 8211, "mdash": 8212, "lsquo": 8216, "rsquo": 8217, "sbquo": 8218, "ldquo": 8220, "rdquo": 8221,
        "bdquo": 8222, "dagger": 8224, "Dagger": 8225, "bull": 8226, "hellip": 8230, "permil": 8240, "prime": 8242,
        "Prime": 8243, "lsaquo": 8249, "rsaquo": 8250, "laquo": 171, "raquo": 187, "euro": 8364, "trade": 8482,
        "copy": 169, "reg": 174, "deg": 176, "plusmn": 177, "sup1": 185, "sup2": 178, "sup3": 179, "micro": 181,
        "para": 182, "middot": 183, "sect": 167, "cent": 162, "pound": 163, "yen": 165, "curren": 164, "brvbar": 166,
        "uml": 168, "ordf": 170, "ordm": 186, "not": 172, "macr": 175, "acute": 180, "cedil": 184, "frac14": 188,
        "frac12": 189, "frac34": 190, "iquest": 191, "iexcl": 161, "times": 215, "divide": 247, "minus": 8722,
        "larr": 8592, "rarr": 8594, "uarr": 8593, "darr": 8595, "harr": 8596, "infin": 8734, "ne": 8800, "le": 8804, "ge": 8805,
        "Agrave": 192, "Aacute": 193, "Acirc": 194, "Atilde": 195, "Auml": 196, "Aring": 197, "AElig": 198, "Ccedil": 199,
        "Egrave": 200, "Eacute": 201, "Ecirc": 202, "Euml": 203, "Igrave": 204, "Iacute": 205, "Icirc": 206, "Iuml": 207,
        "ETH": 208, "Ntilde": 209, "Ograve": 210, "Oacute": 211, "Ocirc": 212, "Otilde": 213, "Ouml": 214, "Oslash": 216,
        "Ugrave": 217, "Uacute": 218, "Ucirc": 219, "Uuml": 220, "Yacute": 221, "THORN": 222, "szlig": 223,
        "agrave": 224, "aacute": 225, "acirc": 226, "atilde": 227, "auml": 228, "aring": 229, "aelig": 230, "ccedil": 231,
        "egrave": 232, "eacute": 233, "ecirc": 234, "euml": 235, "igrave": 236, "iacute": 237, "icirc": 238, "iuml": 239,
        "eth": 240, "ntilde": 241, "ograve": 242, "oacute": 243, "ocirc": 244, "otilde": 245, "ouml": 246, "oslash": 248,
        "ugrave": 249, "uacute": 250, "ucirc": 251, "uuml": 252, "yacute": 253, "thorn": 254, "yuml": 255,
        "OElig": 338, "oelig": 339, "Scaron": 352, "scaron": 353, "Yuml": 376, "fnof": 402, "circ": 710, "tilde": 732,
        "Alpha": 913, "Beta": 914, "Gamma": 915, "Delta": 916, "Omega": 937, "alpha": 945, "beta": 946, "gamma": 947,
        "delta": 948, "epsilon": 949, "lambda": 955, "mu": 956, "pi": 960, "sigma": 963, "omega": 969,
    ]
}

/// Helpers shared by the parsers.
enum Paths {
    /// Resolves `href` against the directory of `from`, both archive-relative paths.
    static func resolve(_ from: String, _ href: String) -> (path: String, hash: String?) {
        let parts = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let path = parts.first.map(String.init) ?? ""
        let hash = parts.count > 1 ? String(parts[1]) : nil
        if path.isEmpty { return (from, hash) }
        var segments = from.split(separator: "/").map(String.init).dropLast()
        for segment in (path.removingPercentEncoding ?? path).split(separator: "/") {
            if segment == ".." { _ = segments.popLast() } else if segment != "." { segments.append(String(segment)) }
        }
        return (segments.joined(separator: "/"), hash)
    }

    static func isExternal(_ href: String) -> Bool {
        href.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*:", options: .regularExpression) != nil
    }

    static func nameWithoutExtension(_ fileName: String) -> String {
        (fileName as NSString).deletingPathExtension.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
    }
}
