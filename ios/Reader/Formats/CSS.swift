import UIKit

/// A book's CSS, parsed leniently into rules. Only what the text builder can draw is kept;
/// anything it doesn't understand (unknown at-rules, pseudo-elements, bad syntax) is skipped.
struct Stylesheet {
    struct Declaration {
        var property: String
        var value: String
        var important: Bool
    }

    struct Rule {
        var selector: CSSSelector
        var declarations: [Declaration]
        var order: Int
    }

    private(set) var rules: [Rule] = []
    /// Style sheets this one imports, as written.
    private(set) var imports: [String] = []

    init() {}

    init(_ css: String) {
        let s = Self.clean(css)
        parseRules(s, 0, s.count, depth: 0)
    }

    /// Several sheets as one, in order.
    init(_ sheets: [Stylesheet]) {
        for sheet in sheets {
            for var rule in sheet.rules {
                rule.order = rules.count
                rules.append(rule)
            }
        }
    }

    var isEmpty: Bool { rules.isEmpty }

    /// The properties this engine reads, after shorthands are expanded.
    static let supported: Set<String> = [
        "text-align", "text-indent", "font-style", "font-weight", "font-size", "font-variant", "text-transform",
        "display", "vertical-align", "text-decoration-line", "list-style-type",
        "margin-top", "margin-right", "margin-bottom", "margin-left",
        "padding-top", "padding-right", "padding-bottom", "padding-left",
    ]

    // MARK: - Parsing

    /// The source without comments or the HTML comment markers old books wrap styles in.
    private static func clean(_ css: String) -> [Character] {
        let s = Array(css)
        var out: [Character] = []
        out.reserveCapacity(s.count)
        var i = 0
        var quote: Character?
        while i < s.count {
            let c = s[i]
            if let q = quote {
                out.append(c)
                if c == "\\", i + 1 < s.count { out.append(s[i + 1]); i += 2; continue }
                if c == q || c == "\n" { quote = nil }
                i += 1
            } else if c == "\"" || c == "'" {
                quote = c
                out.append(c)
                i += 1
            } else if c == "/", i + 1 < s.count, s[i + 1] == "*" {
                var j = i + 2
                while j + 1 < s.count, !(s[j] == "*" && s[j + 1] == "/") { j += 1 }
                i = j + 2
                out.append(" ")
            } else if c == "<", i + 3 < s.count, s[i + 1] == "!", s[i + 2] == "-", s[i + 3] == "-" {
                i += 4
            } else if c == "-", i + 2 < s.count, s[i + 1] == "-", s[i + 2] == ">" {
                i += 3
            } else {
                out.append(c)
                i += 1
            }
        }
        return out
    }

    /// The index of the first of `stops` at nesting depth zero, or `end`.
    private static func scan(_ s: [Character], _ from: Int, _ end: Int, _ stops: Set<Character>) -> Int {
        var i = from
        var quote: Character?
        var parens = 0
        while i < end {
            let c = s[i]
            if let q = quote {
                if c == "\\" { i += 2; continue }
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "(" {
                parens += 1
            } else if c == ")" {
                parens = max(0, parens - 1)
            } else if parens == 0, stops.contains(c) {
                return i
            }
            i += 1
        }
        return end
    }

    /// The index of the brace closing the one at `open`, or `end`.
    private static func closing(_ s: [Character], _ open: Int, _ end: Int) -> Int {
        var depth = 0
        var i = open
        var quote: Character?
        while i < end {
            let c = s[i]
            if let q = quote {
                if c == "\\" { i += 2; continue }
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "{" {
                depth += 1
            } else if c == "}" {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }
        return end
    }

    private mutating func parseRules(_ s: [Character], _ start: Int, _ end: Int, depth: Int) {
        var i = start
        while i < end {
            if s[i].isWhitespace || s[i] == ";" || s[i] == "}" { i += 1; continue }
            if s[i] == "@" {
                let stop = Self.scan(s, i, end, [";", "{"])
                let prelude = String(s[(i + 1)..<stop])
                let name = String(prelude.prefix { $0.isLetter || $0 == "-" }).lowercased()
                let rest = String(prelude.dropFirst(name.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard stop < end, s[stop] == "{" else {
                    if name == "import", let href = Self.importHref(rest) { imports.append(href) }
                    i = stop + 1
                    continue
                }
                let close = Self.closing(s, stop, end)
                if depth < 4, (name == "media" && Self.mediaApplies(rest)) || name == "supports" {
                    parseRules(s, stop + 1, close, depth: depth + 1)
                }
                i = close + 1
                continue
            }
            let stop = Self.scan(s, i, end, ["{", "}"])
            guard stop < end, s[stop] == "{" else { i = stop + 1; continue }
            let close = Self.closing(s, stop, end)
            let selectors = String(s[i..<stop]).split(separator: ",").compactMap { CSSSelector(String($0)) }
            let declarations = Self.declarations(String(s[(stop + 1)..<min(close, end)]))
            if !declarations.isEmpty {
                for selector in selectors { rules.append(Rule(selector: selector, declarations: declarations, order: rules.count)) }
            }
            i = close + 1
        }
    }

    private static func importHref(_ rest: String) -> String? {
        var r = rest
        if r.lowercased().hasPrefix("url(") { r = String(r.dropFirst(4)) }
        r = r.trimmingCharacters(in: .whitespaces)
        guard let first = r.first else { return nil }
        if first == "\"" || first == "'" {
            let body = r.dropFirst()
            return body.firstIndex(of: first).map { String(body[..<$0]) }
        }
        let href = r.prefix { $0 != ")" && !$0.isWhitespace && $0 != ";" }
        return href.isEmpty ? nil : String(href)
    }

    /// Whether a media query could match a reading screen. Features like widths count as
    /// matching; media types other than screen and all (print, e-reader specific) don't.
    static func mediaApplies(_ query: String) -> Bool {
        let parts = query.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if parts.isEmpty || parts == [""] { return true }
        return parts.contains { part in
            var words = part.split(whereSeparator: \.isWhitespace).map(String.init)
            var negated = false
            if words.first == "only" { words.removeFirst() }
            if words.first == "not" { negated = true; words.removeFirst() }
            guard let type = words.first, !type.hasPrefix("(") else { return !negated }
            return (type == "screen" || type == "all") != negated
        }
    }

    /// Declarations from a rule body or a style attribute, with shorthands expanded.
    static func declarations(_ body: String) -> [Declaration] {
        let s = Array(body)
        var out: [Declaration] = []
        var i = 0
        while i < s.count {
            let stop = scan(s, i, s.count, [";", "{"])
            if stop < s.count, s[stop] == "{" {
                // Nested rules aren't supported; skip the block.
                i = closing(s, stop, s.count) + 1
                continue
            }
            let part = String(s[i..<stop])
            i = stop + 1
            guard let colon = part.firstIndex(of: ":") else { continue }
            let property = part[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var value = part[part.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            var important = false
            if let bang = value.range(of: #"!\s*important\s*$"#, options: [.regularExpression, .caseInsensitive]) {
                important = true
                value = value[..<bang.lowerBound].trimmingCharacters(in: .whitespaces)
            }
            guard !property.isEmpty, !value.isEmpty else { continue }
            for (p, v) in expand(property, value) where supported.contains(p) {
                out.append(Declaration(property: p, value: v, important: important))
            }
        }
        return out
    }

    private static func expand(_ property: String, _ value: String) -> [(String, String)] {
        switch property {
        case "margin", "padding":
            let v = value.split(whereSeparator: \.isWhitespace).map(String.init)
            guard (1...4).contains(v.count) else { return [] }
            let top = v[0], right = v.count > 1 ? v[1] : top, bottom = v.count > 2 ? v[2] : top, left = v.count > 3 ? v[3] : right
            return [("\(property)-top", top), ("\(property)-right", right), ("\(property)-bottom", bottom), ("\(property)-left", left)]
        case "font":
            return font(value)
        case "text-decoration":
            return [("text-decoration-line", value)]
        case "font-variant-caps":
            return [("font-variant", value)]
        case "list-style":
            return [("list-style-type", value.lowercased().split(whereSeparator: \.isWhitespace).contains("none") ? "none" : "disc")]
        default:
            return [(property, value)]
        }
    }

    /// The `font` shorthand: style, variant and weight, then a size (and line height,
    /// ignored), then families, ignored too.
    private static func font(_ value: String) -> [(String, String)] {
        var style = "normal", variant = "normal", weight = "normal"
        for token in value.lowercased().split(whereSeparator: \.isWhitespace).map(String.init) {
            switch token {
            case "normal": continue
            case "italic", "oblique": style = token
            case "small-caps": variant = token
            case "bold", "bolder", "lighter": weight = token
            default:
                if let n = Int(token), (1...1000).contains(n) { weight = token; continue }
                let size = String(token.split(separator: "/").first ?? "")
                guard CSSStyle.fontKeywords[size] != nil || size.first.map({ $0.isNumber || $0 == "." }) == true else { return [] }
                return [("font-style", style), ("font-variant", variant), ("font-weight", weight), ("font-size", size)]
            }
        }
        return []
    }
}

// MARK: - Selectors

/// One complex selector: compounds joined by combinators, matched right to left.
struct CSSSelector {
    struct Attribute {
        var name: String
        /// "=", "~=", "|=", "^=", "$=", "*=", or nil for presence.
        var op: String?
        var value: String
        var insensitive: Bool
    }

    enum Pseudo {
        case firstChild, lastChild, onlyChild, firstOfType, lastOfType, root, link, empty
        case not(Compound)
    }

    struct Compound {
        var tag: String?
        var id: String?
        var classes: [String] = []
        var attributes: [Attribute] = []
        var pseudos: [Pseudo] = []

        var specificity: Int {
            var s = (id == nil ? 0 : 10000) + (classes.count + attributes.count) * 100 + (tag == nil ? 0 : 1)
            for pseudo in pseudos {
                if case let .not(inner) = pseudo { s += inner.specificity } else { s += 100 }
            }
            return s
        }
    }

    enum Combinator {
        case descendant, child, adjacent, sibling
    }

    /// Left to right; `combinators[i]` joins compound i and i + 1.
    private(set) var compounds: [Compound] = []
    private(set) var combinators: [Combinator] = []
    /// Ids, then classes, attributes and pseudo-classes, then types, as one number.
    let specificity: Int

    /// Fails for anything unsupported, which then never matches.
    init?(_ text: String) {
        let s = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !s.isEmpty else { return nil }
        var i = 0
        var compounds: [Compound] = []
        var combinators: [Combinator] = []
        while true {
            guard let compound = Self.compound(s, &i) else { return nil }
            compounds.append(compound)
            var spaced = false
            while i < s.count, s[i].isWhitespace { i += 1; spaced = true }
            if i >= s.count { break }
            switch s[i] {
            case ">": combinators.append(.child); i += 1
            case "+": combinators.append(.adjacent); i += 1
            case "~": combinators.append(.sibling); i += 1
            default:
                guard spaced else { return nil }
                combinators.append(.descendant)
            }
            while i < s.count, s[i].isWhitespace { i += 1 }
            if i >= s.count { return nil }
        }
        self.compounds = compounds
        self.combinators = combinators
        specificity = compounds.reduce(0) { $0 + $1.specificity }
    }

    private static func isIdent(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "-" || c == "_" || c == "\\" || !c.isASCII
    }

    private static func ident(_ s: [Character], _ i: inout Int) -> String? {
        var out = ""
        while i < s.count, isIdent(s[i]) {
            if s[i] == "\\" {
                i += 1
                if i < s.count { out.append(s[i]); i += 1 }
                continue
            }
            out.append(s[i])
            i += 1
        }
        return out.isEmpty ? nil : out
    }

    private static func compound(_ s: [Character], _ i: inout Int) -> Compound? {
        var c = Compound()
        var any = false
        if i < s.count, s[i] == "*" {
            i += 1
            any = true
        } else if i < s.count, isIdent(s[i]), let name = ident(s, &i) {
            c.tag = name.lowercased()
            any = true
        }
        // A namespace prefix, as in svg|image or *|p.
        if any, i + 1 < s.count, s[i] == "|", s[i + 1] != "=" {
            i += 1
            if s[i] == "*" { i += 1; c.tag = nil } else if let name = ident(s, &i) { c.tag = name.lowercased() } else { return nil }
        }
        while i < s.count {
            switch s[i] {
            case ".":
                i += 1
                guard let name = ident(s, &i) else { return nil }
                c.classes.append(name)
            case "#":
                i += 1
                guard let name = ident(s, &i) else { return nil }
                c.id = name
            case "[":
                guard let close = s[i...].firstIndex(of: "]"), let attribute = attribute(Array(s[(i + 1)..<close])) else { return nil }
                c.attributes.append(attribute)
                i = close + 1
            case ":":
                i += 1
                // Pseudo-elements (::before, ::first-letter) aren't drawn.
                guard i < s.count, s[i] != ":", let name = ident(s, &i)?.lowercased() else { return nil }
                var argument: [Character]?
                if i < s.count, s[i] == "(" {
                    guard let close = s[i...].firstIndex(of: ")") else { return nil }
                    argument = Array(s[(i + 1)..<close])
                    i = close + 1
                }
                switch (name, argument) {
                case ("first-child", nil): c.pseudos.append(.firstChild)
                case ("last-child", nil): c.pseudos.append(.lastChild)
                case ("only-child", nil): c.pseudos.append(.onlyChild)
                case ("first-of-type", nil): c.pseudos.append(.firstOfType)
                case ("last-of-type", nil): c.pseudos.append(.lastOfType)
                case ("root", nil): c.pseudos.append(.root)
                case ("link", nil), ("any-link", nil): c.pseudos.append(.link)
                case ("empty", nil): c.pseudos.append(.empty)
                case let ("not", arg?):
                    let inner = Array(String(arg).trimmingCharacters(in: .whitespaces))
                    var j = 0
                    guard let parsed = compound(inner, &j), j == inner.count else { return nil }
                    c.pseudos.append(.not(parsed))
                default: return nil
                }
            default:
                return any ? c : nil
            }
            any = true
        }
        return any ? c : nil
    }

    private static func attribute(_ s: [Character]) -> Attribute? {
        var i = 0
        while i < s.count, s[i].isWhitespace { i += 1 }
        guard var name = ident(s, &i) else { return nil }
        if i + 1 < s.count, s[i] == "|", s[i + 1] != "=" {
            i += 1
            guard let local = ident(s, &i) else { return nil }
            name = local
        }
        while i < s.count, s[i].isWhitespace { i += 1 }
        guard i < s.count else { return Attribute(name: name.lowercased(), op: nil, value: "", insensitive: false) }
        var op: String
        if s[i] == "=" {
            op = "="
            i += 1
        } else if i + 1 < s.count, "~|^$*".contains(s[i]), s[i + 1] == "=" {
            op = String(s[i]) + "="
            i += 2
        } else {
            return nil
        }
        while i < s.count, s[i].isWhitespace { i += 1 }
        var value = ""
        if i < s.count, s[i] == "\"" || s[i] == "'" {
            let q = s[i]
            i += 1
            while i < s.count, s[i] != q { value.append(s[i]); i += 1 }
            guard i < s.count else { return nil }
            i += 1
        } else {
            guard let v = ident(s, &i) else { return nil }
            value = v
        }
        while i < s.count, s[i].isWhitespace { i += 1 }
        var insensitive = false
        if i < s.count, s[i] == "i" || s[i] == "I" { insensitive = true; i += 1 }
        while i < s.count, s[i].isWhitespace { i += 1 }
        guard i == s.count else { return nil }
        return Attribute(name: name.lowercased(), op: op, value: value, insensitive: insensitive)
    }

    // MARK: Matching

    /// The innermost compound, which the cascade indexes rules by.
    var key: Compound { compounds[compounds.count - 1] }

    func matches(_ node: Node) -> Bool { match(compounds.count - 1, node) }

    private func match(_ k: Int, _ node: Node) -> Bool {
        guard compounds[k].matches(node) else { return false }
        guard k > 0 else { return true }
        switch combinators[k - 1] {
        case .child:
            return CSSTree.parent(node).map { match(k - 1, $0) } ?? false
        case .descendant:
            var p = CSSTree.parent(node)
            while let a = p {
                if match(k - 1, a) { return true }
                p = CSSTree.parent(a)
            }
            return false
        case .adjacent:
            return CSSTree.previousSiblings(node).last.map { match(k - 1, $0) } ?? false
        case .sibling:
            return CSSTree.previousSiblings(node).contains { match(k - 1, $0) }
        }
    }
}

extension CSSSelector.Compound {
    func matches(_ node: Node) -> Bool {
        guard let name = node.name else { return false }
        if let tag, tag != name { return false }
        if let id, node.attributes["id"] != id { return false }
        if !classes.isEmpty {
            let own = (node.attributes["class"] ?? "").split(whereSeparator: \.isWhitespace)
            for c in classes where !own.contains(Substring(c)) { return false }
        }
        for a in attributes where !a.matches(node) { return false }
        for p in pseudos where !p.matches(node) { return false }
        return true
    }
}

extension CSSSelector.Attribute {
    func matches(_ node: Node) -> Bool {
        var actual = node[name]
        // Links lose their href when a chapter is loaded; it lives on as data-href.
        if actual == nil, name == "href", node.name == "a" { actual = node["data-href"] ?? node["data-external"] }
        guard var actual else { return false }
        guard let op else { return true }
        var value = self.value
        if insensitive { actual = actual.lowercased(); value = value.lowercased() }
        switch op {
        case "=": return actual == value
        case "~=": return actual.split(whereSeparator: \.isWhitespace).contains(Substring(value))
        case "|=": return actual == value || actual.hasPrefix(value + "-")
        case "^=": return !value.isEmpty && actual.hasPrefix(value)
        case "$=": return !value.isEmpty && actual.hasSuffix(value)
        case "*=": return !value.isEmpty && actual.contains(value)
        default: return false
        }
    }
}

extension CSSSelector.Pseudo {
    func matches(_ node: Node) -> Bool {
        switch self {
        case .firstChild: return CSSTree.previousSiblings(node).isEmpty
        case .lastChild: return CSSTree.nextSiblings(node).isEmpty
        case .onlyChild: return CSSTree.previousSiblings(node).isEmpty && CSSTree.nextSiblings(node).isEmpty
        case .firstOfType: return !CSSTree.previousSiblings(node).contains { $0.name == node.name }
        case .lastOfType: return !CSSTree.nextSiblings(node).contains { $0.name == node.name }
        case .root: return node.name == "html"
        case .link: return node.name == "a" && (node["data-href"] != nil || node["data-external"] != nil || node["href"] != nil)
        case .empty: return node.children.allSatisfy { if case let .text(t) = $0.kind { t.isEmpty } else { false } }
        case let .not(inner): return !inner.matches(node)
        }
    }
}

/// Tree walking for selectors. A chapter is just its body, so `html` (and `:root`) match a
/// stand-in parent of it.
enum CSSTree {
    static let html = Node.element("html")

    static func parent(_ node: Node) -> Node? {
        if let p = node.parent, p.name != "#document" { return p }
        return node.name == "body" ? html : nil
    }

    private static func siblings(_ node: Node) -> (before: ArraySlice<Node>, after: ArraySlice<Node>) {
        guard let p = node.parent, let i = p.children.firstIndex(where: { $0 === node }) else { return ([], []) }
        return (p.children[..<i], p.children[(i + 1)...])
    }

    static func previousSiblings(_ node: Node) -> [Node] { siblings(node).before.filter { !$0.isText } }
    static func nextSiblings(_ node: Node) -> [Node] { siblings(node).after.filter { !$0.isText } }
}

// MARK: - Cascade

/// Matches elements against the browser's default sheet and a book's, and sorts what
/// applies the way the cascade does: origin and importance, then specificity, then order.
struct CSSCascade {
    private struct Entry {
        var rule: Stylesheet.Rule
        var origin: Int
    }

    private var byId: [String: [Entry]] = [:]
    private var byClass: [String: [Entry]] = [:]
    private var byTag: [String: [Entry]] = [:]
    private var universal: [Entry] = []

    init(book: Stylesheet?) {
        for rule in CSSStyle.defaults.rules { add(Entry(rule: rule, origin: 0)) }
        for rule in book?.rules ?? [] { add(Entry(rule: rule, origin: 1)) }
    }

    private mutating func add(_ entry: Entry) {
        let key = entry.rule.selector.key
        if let id = key.id { byId[id, default: []].append(entry) }
        else if let c = key.classes.first { byClass[c, default: []].append(entry) }
        else if let tag = key.tag { byTag[tag, default: []].append(entry) }
        else { universal.append(entry) }
    }

    /// The winning value of each property set on an element, its style attribute included.
    func declarations(for node: Node) -> [String: String] {
        guard let name = node.name else { return [:] }
        var candidates = byTag[name] ?? []
        candidates += universal
        if let id = node.attributes["id"], let found = byId[id] { candidates += found }
        for c in Set((node.attributes["class"] ?? "").split(whereSeparator: \.isWhitespace).map(String.init)) {
            if let found = byClass[c] { candidates += found }
        }

        // Normal default < normal book < normal inline < important book < important inline.
        var matched: [(rank: Int, specificity: Int, order: Int, declaration: Stylesheet.Declaration)] = []
        for entry in candidates where entry.rule.selector.matches(node) {
            for d in entry.rule.declarations {
                let rank = entry.origin == 0 ? 0 : (d.important ? 3 : 1)
                matched.append((rank, entry.rule.selector.specificity, entry.rule.order, d))
            }
        }
        if let inline = node.attributes["style"] {
            for d in Stylesheet.declarations(inline) { matched.append((d.important ? 4 : 2, 0, 0, d)) }
        }
        // A stable sort keeps declaration order within a rule.
        let sorted = matched.enumerated().sorted { a, b in
            let x = a.element, y = b.element
            if x.rank != y.rank { return x.rank < y.rank }
            if x.specificity != y.specificity { return x.specificity < y.specificity }
            if x.order != y.order { return x.order < y.order }
            return a.offset < b.offset
        }
        var out: [String: String] = [:]
        for (_, m) in sorted { out[m.declaration.property] = m.declaration.value }
        return out
    }
}

// MARK: - Computed style

/// What the text builder needs to know about one element's CSS, resolved against its parent.
struct CSSStyle {
    enum Display { case none, block, inline }
    enum Transform { case none, uppercase, lowercase, capitalize }
    enum Vertical { case baseline, raised, lowered }

    /// What lengths resolve against.
    struct Context {
        /// The user's font size in points, which is 1em at the root.
        var fontSize: CGFloat
        /// The root element's font size, in ems of the user's, for rem.
        var rootSize: CGFloat = 1
        /// The column width, for percentages.
        var width: CGFloat
    }

    // Inherited.
    /// Font size in ems of the user's size.
    var size: CGFloat = 1
    var italic = false
    var weight: CGFloat
    var smallCaps = false
    var transform = Transform.none
    /// Nil is the start edge.
    var align: NSTextAlignment?
    /// Text indent in points.
    var indent: CGFloat = 0
    var listNone = false

    // Not inherited.
    var display: Display?
    var vertical = Vertical.baseline
    var underline = false
    var strike = false
    /// Margin plus padding on each side, in points.
    var top: CGFloat = 0
    var right: CGFloat = 0
    var bottom: CGFloat = 0
    var left: CGFloat = 0

    init(weight: CGFloat) {
        self.weight = weight
    }

    /// The style an element of this parent starts from.
    var inherited: CSSStyle {
        var s = self
        s.display = nil
        s.vertical = .baseline
        s.underline = false
        s.strike = false
        s.top = 0; s.right = 0; s.bottom = 0; s.left = 0
        return s
    }

    /// The style of an element with these declarations under `parent`.
    static func resolve(_ d: [String: String], parent: CSSStyle, context: Context) -> CSSStyle {
        var s = parent.inherited
        func value(_ property: String) -> String? {
            guard let v = d[property]?.lowercased().trimmingCharacters(in: .whitespaces), !v.isEmpty,
                  !["inherit", "initial", "unset", "revert", "revert-layer"].contains(v) else { return nil }
            return v
        }
        if let v = value("font-size"), let size = fontSize(v, parent: parent.size, context: context) { s.size = size }
        let em = s.size * context.fontSize
        func length(_ property: String) -> CGFloat? { value(property).flatMap { Self.length($0, em: em, context: context) } }

        if let v = value("font-style") { s.italic = v == "italic" || v.hasPrefix("oblique") }
        if let v = value("font-weight"), let w = weight(v, parent: parent.weight) { s.weight = w }
        if let v = value("font-variant") { s.smallCaps = v.contains("small-caps") }
        if let v = value("text-transform") {
            switch v {
            case "uppercase": s.transform = .uppercase
            case "lowercase": s.transform = .lowercase
            case "capitalize": s.transform = .capitalize
            case "none": s.transform = .none
            default: break
            }
        }
        if let v = value("text-align") {
            switch v {
            case "left": s.align = .left
            case "right", "end": s.align = .right
            case "center", "-webkit-center", "-moz-center": s.align = .center
            case "justify": s.align = .justified
            case "start": s.align = nil
            default: break
            }
        }
        if let v = length("text-indent") { s.indent = v }
        if let v = value("list-style-type") { s.listNone = v == "none" }
        if let v = value("display") {
            switch v {
            case "none": s.display = Display.none
            case "block", "list-item", "flex", "grid", "table", "table-row", "table-caption", "flow-root", "table-row-group":
                s.display = .block
            case "inline", "inline-block", "inline-flex", "inline-grid", "inline-table", "table-cell", "contents", "run-in":
                s.display = .inline
            default: break
            }
        }
        if let v = value("vertical-align") {
            switch v {
            case "super": s.vertical = .raised
            case "sub": s.vertical = .lowered
            default: break
            }
        }
        if let v = value("text-decoration-line") {
            s.underline = v.contains("underline")
            s.strike = v.contains("line-through")
        }
        s.top = (length("margin-top") ?? 0) + max(0, length("padding-top") ?? 0)
        s.bottom = (length("margin-bottom") ?? 0) + max(0, length("padding-bottom") ?? 0)
        s.left = (length("margin-left") ?? 0) + max(0, length("padding-left") ?? 0)
        s.right = (length("margin-right") ?? 0) + max(0, length("padding-right") ?? 0)
        return s
    }

    static let fontKeywords: [String: CGFloat] = [
        "xx-small": 0.6, "x-small": 0.75, "small": 0.889, "medium": 1, "large": 1.2, "x-large": 1.5, "xx-large": 2, "xxx-large": 3,
    ]

    /// A number and its unit, as in "1.5em" or "-10%".
    private static func dimension(_ v: String) -> (CGFloat, String)? {
        let numberEnd = v.firstIndex { !($0.isNumber || $0 == "." || $0 == "-" || $0 == "+") } ?? v.endIndex
        guard let n = Double(v[..<numberEnd]), n.isFinite else { return nil }
        return (CGFloat(n), String(v[numberEnd...]))
    }

    /// A font size in ems of the user's size. Pixels count against the browser default of
    /// 16, so the user's size stays the base.
    static func fontSize(_ v: String, parent: CGFloat, context: Context) -> CGFloat? {
        let size: CGFloat
        if let k = fontKeywords[v] { size = k }
        else if v == "smaller" { size = parent / 1.2 }
        else if v == "larger" { size = parent * 1.2 }
        else {
            guard let (n, unit) = dimension(v), n >= 0 else { return nil }
            switch unit {
            case "em": size = n * parent
            case "%": size = n / 100 * parent
            case "rem": size = n * context.rootSize
            case "px": size = n / 16
            case "pt": size = n / 12
            case "ex", "ch": size = n * 0.5 * parent
            case "": guard n == 0 else { return nil }; size = 0
            default: return nil
            }
        }
        return min(5, max(0.3, size))
    }

    /// A length in points, with `em` the element's font size in points.
    static func length(_ v: String, em: CGFloat, context: Context) -> CGFloat? {
        if v == "auto" { return 0 }
        guard let (n, unit) = dimension(v) else { return nil }
        let px = context.fontSize / 16
        let points: CGFloat
        switch unit {
        case "em": points = n * em
        case "rem": points = n * context.rootSize * context.fontSize
        case "%": points = n / 100 * context.width
        case "px": points = n * px
        case "pt": points = n * 4 / 3 * px
        case "pc": points = n * 16 * px
        case "in": points = n * 96 * px
        case "cm": points = n * 96 / 2.54 * px
        case "mm": points = n * 96 / 25.4 * px
        case "ex", "ch": points = n * 0.5 * em
        case "vw": points = n / 100 * context.width
        case "": guard n == 0 else { return nil }; points = 0
        default: return nil
        }
        return points.isFinite ? points : nil
    }

    static func weight(_ v: String, parent: CGFloat) -> CGFloat? {
        switch v {
        case "normal": return 400
        case "bold": return 700
        case "bolder": return parent < 350 ? 400 : (parent < 550 ? 700 : 900)
        case "lighter": return parent < 550 ? 100 : (parent < 750 ? 400 : 700)
        default:
            guard let n = Double(v), (1...1000).contains(n) else { return nil }
            return CGFloat(n)
        }
    }

    /// The browser's own look for book markup, which original styles start from.
    static let defaults = Stylesheet("""
    p, dl, ul, ol, pre, figure { margin: 1em 0 }
    blockquote { margin: 1em 40px }
    figure { margin: 1em 40px }
    ul, ol { padding-left: 40px }
    ul ul, ul ol, ol ul, ol ol { margin-top: 0; margin-bottom: 0 }
    dd { margin-left: 40px }
    h1 { font-size: 2em; margin: 0.67em 0; font-weight: bold }
    h2 { font-size: 1.5em; margin: 0.83em 0; font-weight: bold }
    h3 { font-size: 1.17em; margin: 1em 0; font-weight: bold }
    h4 { margin: 1.33em 0; font-weight: bold }
    h5 { font-size: 0.83em; margin: 1.67em 0; font-weight: bold }
    h6 { font-size: 0.67em; margin: 2.33em 0; font-weight: bold }
    b, strong, th { font-weight: bolder }
    i, em, cite, dfn, var, address { font-style: italic }
    small { font-size: smaller }
    big { font-size: larger }
    sup { vertical-align: super; font-size: smaller }
    sub { vertical-align: sub; font-size: smaller }
    u, ins { text-decoration: underline }
    s, strike, del { text-decoration: line-through }
    center, th, caption { text-align: center }
    a[data-href], a[data-external] { text-decoration: underline }
    """)
}
