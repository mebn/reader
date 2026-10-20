import UIKit

extension NSAttributedString.Key {
    /// A link inside a book: "int:<path#anchor>" or "ext:<url>".
    static let bookLink = NSAttributedString.Key("reader.link")
}

/// How book text is set, from the reader settings and the page size.
struct TextStyle {
    var settings: ReaderSettings
    var text: UIColor
    var columnWidth: CGFloat
    var pageHeight: CGFloat
    var language: String?

    var fontSize: CGFloat { settings.fontSize }
}

/// A chapter laid out as attributed text, with a map between positions in it and the
/// character offsets the desktop app stores, which count every text node of the chapter.
final class ChapterText {
    let string: NSAttributedString
    /// For each UTF-16 unit of `string`, the DOM offset it came from. Units the layout
    /// added (paragraph breaks, bullets, images) carry the offset of the text after them.
    let domOffsets: [Int32]
    let synthetic: [Bool]
    /// Element ids and where they start in `string`.
    let anchors: [String: Int]
    /// Total DOM text length.
    let domLength: Int

    init(string: NSAttributedString, domOffsets: [Int32], synthetic: [Bool], anchors: [String: Int], domLength: Int) {
        self.string = string
        self.domOffsets = domOffsets
        self.synthetic = synthetic
        self.anchors = anchors
        self.domLength = domLength
    }

    /// Where a DOM offset falls in the laid out text.
    func displayIndex(forDom offset: Int) -> Int {
        var lo = 0, hi = domOffsets.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if Int(domOffsets[mid]) < offset { lo = mid + 1 } else { hi = mid }
        }
        while lo < synthetic.count && synthetic[lo] { lo += 1 }
        return min(lo, domOffsets.count)
    }

    func displayRange(domStart: Int, domEnd: Int) -> NSRange? {
        let start = displayIndex(forDom: domStart)
        let end = displayIndex(forDom: domEnd)
        return end > start ? NSRange(location: start, length: end - start) : nil
    }

    /// DOM offsets for a range of the laid out text.
    func domRange(_ range: NSRange) -> (start: Int, end: Int)? {
        var first = range.location
        var last = range.location + range.length - 1
        while first <= last && synthetic[first] { first += 1 }
        while last >= first && synthetic[last] { last -= 1 }
        guard first <= last else { return nil }
        return (Int(domOffsets[first]), Int(domOffsets[last]) + 1)
    }
}

/// Lays out a chapter's node tree the way the desktop app's book stylesheet does.
struct ChapterTextBuilder {
    let style: TextStyle
    let image: (String) -> UIImage?

    private static let blocks: Set<String> = [
        "p", "div", "section", "article", "aside", "header", "footer", "nav", "main", "figure", "figcaption", "blockquote",
        "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "dl", "dt", "dd", "table", "tr", "pre", "hr", "address", "center", "body", "caption",
    ]
    private static let headingScale: [String: CGFloat] = ["h1": 1.6, "h2": 1.35, "h3": 1.15, "h4": 1, "h5": 1, "h6": 1]

    private struct Inline {
        var italic = false
        var bold = false
        var mono = false
        var scale: CGFloat = 1
        var baseline: CGFloat = 0
        var link: String?
        var strike = false
        var underline = false
    }

    private struct Block {
        var heading: CGFloat?
        var paragraph = false
        var indent: CGFloat = 0
        var quote = false
        var pre = false
        var center = false
    }

    final class State {
        var units: [UInt16] = []
        var domOffsets: [Int32] = []
        var synthetic: [Bool] = []
        var runs: [(range: NSRange, attributes: [NSAttributedString.Key: Any])] = []
        var anchors: [String: Int] = [:]
        var dom = 0
        var pendingSpace: Int?
        var lineStart = true
        var hidden = 0
        var lists: [(ordered: Bool, count: Int)] = []
    }

    func build(_ root: Node) -> ChapterText {
        let state = State()
        walk(root, state, Inline(), Block())
        let string = NSMutableAttributedString(string: String(utf16CodeUnits: state.units, count: state.units.count))
        for run in state.runs { string.setAttributes(run.attributes, range: run.range) }
        return ChapterText(string: string, domOffsets: state.domOffsets, synthetic: state.synthetic, anchors: state.anchors, domLength: state.dom)
    }

    private func walk(_ node: Node, _ state: State, _ inline: Inline, _ block: Block) {
        guard let name = node.name else {
            if case let .text(text) = node.kind { appendText(text, state, inline, block) }
            return
        }

        var inline = inline
        var block = block
        let isBlock = Self.blocks.contains(name)

        switch name {
        case "svg":
            // Only an svg's images show; its text still counts toward offsets.
            for image in node.all("image") { appendImage(image["src"], state, inline, block) }
            state.hidden += 1
            node.children.forEach { walk($0, state, inline, block) }
            state.hidden -= 1
            return
        case "img", "image":
            appendImage(node["src"], state, inline, block)
            return
        case "br":
            appendSynthetic("\u{2028}", state, inline, block)
            state.pendingSpace = nil
            state.lineStart = true
            return
        case "hr":
            breakParagraph(state, inline, block)
            appendRule(state, block)
            return
        case "em", "i", "cite", "dfn", "var": inline.italic = true
        case "strong", "b", "th": inline.bold = true
        case "code", "kbd", "samp", "tt": inline.mono = true; inline.scale *= 0.88
        case "sup": inline.scale *= 0.7; inline.baseline += style.fontSize * 0.35
        case "sub": inline.scale *= 0.7; inline.baseline -= style.fontSize * 0.2
        case "s", "strike", "del": inline.strike = true
        case "u", "ins": inline.underline = true
        case "small": inline.scale *= 0.85
        case "a":
            if let href = node["data-href"] { inline.link = "int:\(href)" } else if let url = node["data-external"] { inline.link = "ext:\(url)" }
        case "h1", "h2", "h3", "h4", "h5", "h6":
            block.heading = Self.headingScale[name]
            inline.bold = true
        case "p": block.paragraph = true
        case "blockquote": block.indent += style.fontSize; block.quote = true
        case "pre": block.pre = true; inline.mono = true; inline.scale *= 0.88
        case "center": block.center = true
        case "ul", "ol":
            block.indent += style.fontSize * 1.4
            state.lists.append((name == "ol", 0))
        default: break
        }

        if isBlock { breakParagraph(state, inline, block) }
        if let id = node["id"] { state.anchors[id] = state.units.count }

        if name == "li", let list = state.lists.last {
            state.lists[state.lists.count - 1].count += 1
            appendSynthetic(list.ordered ? "\(list.count + 1). " : "• ", state, inline, block)
            state.lineStart = true
        }

        for child in node.children {
            walk(child, state, inline, block)
            if child.name == "td" || child.name == "th" { appendSynthetic("\t", state, inline, block) }
        }

        if name == "ul" || name == "ol" { state.lists.removeLast() }
        if isBlock { breakParagraph(state, inline, block) }
    }

    // MARK: - Text

    private func appendText(_ text: String, _ state: State, _ inline: Inline, _ block: Block) {
        let units = Array(text.utf16)
        defer { state.dom += units.count }
        guard state.hidden == 0 else { return }

        let attributes = self.attributes(inline, block)
        let start = state.units.count
        for (k, u) in units.enumerated() {
            let offset = Int32(state.dom + k)
            if block.pre {
                state.units.append(u)
                state.domOffsets.append(offset)
                state.synthetic.append(false)
                continue
            }
            if u == 0x20 || u == 0x09 || u == 0x0A || u == 0x0C {
                if state.pendingSpace == nil { state.pendingSpace = state.dom + k }
                continue
            }
            if let space = state.pendingSpace, !state.lineStart {
                state.units.append(0x20)
                state.domOffsets.append(Int32(space))
                state.synthetic.append(false)
            }
            state.pendingSpace = nil
            state.lineStart = false
            state.units.append(u)
            state.domOffsets.append(offset)
            state.synthetic.append(false)
        }
        if state.units.count > start {
            state.runs.append((NSRange(location: start, length: state.units.count - start), attributes))
        }
    }

    private func appendSynthetic(_ text: String, _ state: State, _ inline: Inline, _ block: Block, attributes: [NSAttributedString.Key: Any]? = nil) {
        guard state.hidden == 0 else { return }
        // A space waiting before this would land after it, out of order; it isn't needed.
        state.pendingSpace = nil
        let units = Array(text.utf16)
        let start = state.units.count
        state.units += units
        state.domOffsets += Array(repeating: Int32(state.dom), count: units.count)
        state.synthetic += Array(repeating: true, count: units.count)
        state.runs.append((NSRange(location: start, length: units.count), attributes ?? self.attributes(inline, block)))
    }

    /// Ends the current paragraph, if any text was written since the last break.
    private func breakParagraph(_ state: State, _ inline: Inline, _ block: Block) {
        state.pendingSpace = nil
        state.lineStart = true
        guard let last = state.units.last, last != 0x0A else { return }
        // The break belongs to the paragraph it ends, so it takes that paragraph's style.
        let attributes = state.runs.last?.attributes ?? self.attributes(inline, block)
        appendSynthetic("\n", state, inline, block, attributes: attributes)
    }

    // MARK: - Images

    private func appendImage(_ src: String?, _ state: State, _ inline: Inline, _ block: Block) {
        guard state.hidden == 0, let src, let image = image(src) else { return }
        let natural = image.size
        guard natural.width > 0, natural.height > 0 else { return }

        let attachment = NSTextAttachment()
        attachment.image = image
        if natural.height <= style.fontSize * 1.6 {
            // Small images (ornaments, dropped capitals) sit in the line.
            attachment.bounds = CGRect(x: 0, y: -style.fontSize * 0.2, width: natural.width, height: natural.height)
            if let space = state.pendingSpace, !state.lineStart {
                state.units.append(0x20)
                state.domOffsets.append(Int32(space))
                state.synthetic.append(false)
                state.runs.append((NSRange(location: state.units.count - 1, length: 1), attributes(inline, block)))
            }
            appendSynthetic("\u{FFFC}", state, inline, block, attributes: attributes(inline, block).merging([.attachment: attachment]) { $1 })
            state.lineStart = false
            return
        }

        let maxHeight = max(40, style.pageHeight - style.fontSize * 2 - 8)
        let scale = min(1, style.columnWidth / natural.width, maxHeight / natural.height)
        attachment.bounds = CGRect(x: 0, y: 0, width: floor(natural.width * scale), height: floor(natural.height * scale))
        breakParagraph(state, inline, block)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacingBefore = style.fontSize * 0.8
        paragraph.paragraphSpacing = style.fontSize * 0.8
        appendSynthetic("\u{FFFC}", state, inline, block, attributes: [.attachment: attachment, .paragraphStyle: paragraph])
        appendSynthetic("\n", state, inline, block, attributes: [.paragraphStyle: paragraph])
        state.lineStart = true
    }

    private func appendRule(_ state: State, _ block: Block) {
        let width = style.columnWidth * 0.6
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: 1))
        let line = renderer.image { _ in
            style.text.withAlphaComponent(0.18).setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: width, height: 1))
        }
        let attachment = NSTextAttachment()
        attachment.image = line
        attachment.bounds = CGRect(x: 0, y: 0, width: width, height: 1)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacingBefore = style.fontSize * 1.5
        paragraph.paragraphSpacing = style.fontSize * 1.5
        appendSynthetic("\u{FFFC}\n", state, Inline(), block, attributes: [.attachment: attachment, .paragraphStyle: paragraph])
        state.lineStart = true
    }

    // MARK: - Attributes

    private func attributes(_ inline: Inline, _ block: Block) -> [NSAttributedString.Key: Any] {
        let s = style.settings
        let size = style.fontSize * (block.heading ?? 1) * inline.scale
        let weight = block.heading != nil ? max(600, s.weight) : (inline.bold ? max(700, s.weight) : s.weight)
        let font = BookFonts.font(s.font, size: size, weight: weight, italic: inline.italic, monospace: inline.mono)

        let paragraph = NSMutableParagraphStyle()
        let leading = block.heading != nil ? 1.25 : s.lineHeight
        let lineHeight = (style.fontSize * (block.heading ?? 1)) * leading
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.headIndent = block.indent
        paragraph.firstLineHeadIndent = block.indent
        paragraph.lineBreakStrategy = .pushOut
        if let heading = block.heading {
            paragraph.alignment = .natural
            paragraph.paragraphSpacingBefore = style.fontSize * heading * 1.4
            paragraph.paragraphSpacing = style.fontSize * heading * 0.7
        } else {
            paragraph.alignment = block.center ? .center : (s.align == .justify ? .justified : .natural)
            paragraph.hyphenationFactor = s.hyphenate && !block.pre ? 1 : 0
            paragraph.paragraphSpacing = block.paragraph ? s.paragraphSpacing * style.fontSize : 0
        }
        if block.quote { paragraph.paragraphSpacing = max(paragraph.paragraphSpacing, style.fontSize) }

        var color = style.text
        if block.quote { color = color.withAlphaComponent(0.9) }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
            // Centers the glyphs in the fixed line height, as CSS does.
            .baselineOffset: (lineHeight - font.lineHeight) / 2 + inline.baseline,
        ]
        // Any kern attribute, even zero, makes justification spread letters instead of words.
        if s.tracking != 0 { attributes[.kern] = s.tracking * size }
        if let language = style.language, !language.isEmpty { attributes[.languageIdentifier] = language }
        if let link = inline.link {
            attributes[.bookLink] = link
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attributes[.underlineColor] = style.text.withAlphaComponent(0.35)
        } else if inline.underline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if inline.strike { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return attributes
    }
}

extension NSAttributedString.Key {
    static let languageIdentifier = NSAttributedString.Key(kCTLanguageAttributeName as String)
}
