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

/// Lays out a chapter's node tree the way the desktop app's book stylesheet does, or with
/// original styles, in the book's own CSS over the browser's defaults.
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
        // Original styles only.
        /// Font size in ems of the user's size.
        var size: CGFloat = 1
        var weight: CGFloat?
        var smallCaps = false
        var transform = CSSStyle.Transform.none
    }

    private struct Block {
        var heading: CGFloat?
        var paragraph = false
        var indent: CGFloat = 0
        var quote = false
        var pre = false
        var center = false
        // Original styles only.
        /// The element's computed style, which its children inherit.
        var css: CSSStyle?
        var tailIndent: CGFloat = 0
        var textIndent: CGFloat = 0
        var align: NSTextAlignment?
        /// The block's font size in ems of the user's size, which sets its line height.
        var size: CGFloat = 1
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
        // Original styles only.
        var cascade: CSSCascade?
        var context = CSSStyle.Context(fontSize: 0, width: 0)
        var root: Node?
        /// Vertical margin waiting for the next paragraph, collapsed as CSS does.
        var margin: CGFloat = 0
        /// The current paragraph's space before it.
        var spaceBefore: CGFloat = 0
    }

    func build(_ root: Node) -> ChapterText {
        let state = State()
        var block = Block()
        if style.settings.originalStyles {
            let cascade = CSSCascade(book: root.stylesheet)
            state.cascade = cascade
            state.root = root
            state.context = CSSStyle.Context(fontSize: style.fontSize, width: style.columnWidth)
            // The root element's font size is what rem counts in.
            let html = CSSStyle.resolve(cascade.declarations(for: CSSTree.html), parent: CSSStyle(weight: style.settings.weight), context: state.context)
            state.context.rootSize = html.size
            block.css = html
        }
        walk(root, state, Inline(), block)
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
        var isBlock = Self.blocks.contains(name)

        if let cascade = state.cascade, let parent = block.css {
            var css = CSSStyle.resolve(cascade.declarations(for: node), parent: parent, context: state.context)
            // The book's CSS may not move or hide the text column itself, as on desktop.
            if node === state.root { css.display = nil; css.top = 0; css.right = 0; css.bottom = 0; css.left = 0 }
            if css.display == CSSStyle.Display.none {
                // Hidden text still counts toward offsets.
                if let id = node["id"] { state.anchors[id] = state.units.count }
                let list = name == "ul" || name == "ol"
                if list { state.lists.append((name == "ol", 0)) }
                state.hidden += 1
                node.children.forEach { walk($0, state, inline, block) }
                state.hidden -= 1
                if list { state.lists.removeLast() }
                return
            }
            if let display = css.display { isBlock = display == .block }
            inline.italic = css.italic
            inline.weight = css.weight
            inline.size = css.size
            inline.smallCaps = css.smallCaps
            inline.transform = css.transform
            if css.underline { inline.underline = true }
            if css.strike { inline.strike = true }
            switch css.vertical {
            case .raised: inline.baseline += style.fontSize * parent.size * 0.35
            case .lowered: inline.baseline -= style.fontSize * parent.size * 0.2
            case .baseline: break
            }
            if isBlock {
                block.indent += css.left
                block.tailIndent += css.right
                block.textIndent = css.indent
                block.align = css.align
                block.size = css.size
            }
            block.css = css
        }
        let original = block.css != nil

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
        default: break
        }

        switch name {
        case "a":
            if let href = node["data-href"] { inline.link = "int:\(href)" } else if let url = node["data-external"] { inline.link = "ext:\(url)" }
        case "code", "kbd", "samp", "tt": inline.mono = true; inline.scale *= 0.88
        case "pre": block.pre = true; inline.mono = true; inline.scale *= 0.88
        case "ul", "ol":
            if !original { block.indent += style.fontSize * 1.4 }
            state.lists.append((name == "ol", 0))
        default: break
        }

        if !original {
            readerLook(name, &inline, &block)
        }

        if isBlock { breakParagraph(state, inline, block) }
        if original, isBlock { state.margin = max(state.margin, block.css?.top ?? 0) }
        if let id = node["id"] { state.anchors[id] = state.units.count }

        if name == "li", let list = state.lists.last {
            state.lists[state.lists.count - 1].count += 1
            if !(block.css?.listNone ?? false) {
                appendSynthetic(list.ordered ? "\(list.count + 1). " : "• ", state, inline, block)
                state.lineStart = true
            }
        }

        for child in node.children {
            walk(child, state, inline, block)
            if child.name == "td" || child.name == "th" { appendSynthetic("\t", state, inline, block) }
        }

        if name == "ul" || name == "ol" { state.lists.removeLast() }
        if isBlock { breakParagraph(state, inline, block) }
        if original, isBlock { state.margin = max(state.margin, block.css?.bottom ?? 0) }
    }

    /// The reader's own look for book markup, like the desktop app's book stylesheet.
    private func readerLook(_ name: String, _ inline: inout Inline, _ block: inout Block) {
        switch name {
        case "em", "i", "cite", "dfn", "var": inline.italic = true
        case "strong", "b", "th": inline.bold = true
        case "sup": inline.scale *= 0.7; inline.baseline += style.fontSize * 0.35
        case "sub": inline.scale *= 0.7; inline.baseline -= style.fontSize * 0.2
        case "s", "strike", "del": inline.strike = true
        case "u", "ins": inline.underline = true
        case "small": inline.scale *= 0.85
        case "h1", "h2", "h3", "h4", "h5", "h6":
            block.heading = Self.headingScale[name]
            inline.bold = true
        case "p": block.paragraph = true
        case "blockquote": block.indent += style.fontSize; block.quote = true
        case "center": block.center = true
        default: break
        }
    }

    // MARK: - Text

    private func appendText(_ text: String, _ state: State, _ inline: Inline, _ block: Block) {
        let units = Array(text.utf16)
        defer { state.dom += units.count }
        guard state.hidden == 0 else { return }

        if state.cascade != nil, block.pre ? !units.isEmpty : units.contains(where: { !Self.isSpace($0) }) { beginParagraph(state) }
        let attributes = self.attributes(inline, block, state)
        let start = state.units.count
        for (k, u) in units.enumerated() {
            let offset = Int32(state.dom + k)
            if block.pre {
                state.units.append(transformed(u, inline.transform, state))
                state.domOffsets.append(offset)
                state.synthetic.append(false)
                continue
            }
            if Self.isSpace(u) {
                if state.pendingSpace == nil { state.pendingSpace = state.dom + k }
                continue
            }
            if let space = state.pendingSpace, !state.lineStart {
                state.units.append(0x20)
                state.domOffsets.append(Int32(space))
                state.synthetic.append(false)
            }
            let shown = transformed(u, inline.transform, state)
            state.pendingSpace = nil
            state.lineStart = false
            state.units.append(shown)
            state.domOffsets.append(offset)
            state.synthetic.append(false)
        }
        if state.units.count > start {
            state.runs.append((NSRange(location: start, length: state.units.count - start), attributes))
        }
    }

    private static func isSpace(_ u: UInt16) -> Bool {
        u == 0x20 || u == 0x09 || u == 0x0A || u == 0x0C
    }

    /// A unit in another case for text-transform, only where that keeps it one unit, so the
    /// text stays aligned with its DOM offsets.
    private func transformed(_ u: UInt16, _ transform: CSSStyle.Transform, _ state: State) -> UInt16 {
        guard transform != .none, let scalar = Unicode.Scalar(u) else { return u }
        let upper: Bool
        switch transform {
        case .uppercase: upper = true
        case .lowercase: upper = false
        case .capitalize:
            let previous = state.pendingSpace != nil ? 0x20 : state.units.last
            guard previous.map({ Self.isSpace($0) || $0 == 0x2028 || $0 == 0x0A || $0 == 0x28 || $0 == 0x2D }) ?? true else { return u }
            upper = true
        case .none: return u
        }
        let character = String(Character(scalar))
        let out = Array((upper ? character.uppercased() : character.lowercased()).utf16)
        return out.count == 1 ? out[0] : u
    }

    /// Starts a paragraph with original styles: it takes the collapsed margin before it.
    private func beginParagraph(_ state: State) {
        guard state.units.last.map({ $0 == 0x0A }) ?? true else { return }
        state.spaceBefore = state.margin
        state.margin = 0
    }

    private func appendSynthetic(_ text: String, _ state: State, _ inline: Inline, _ block: Block, attributes: [NSAttributedString.Key: Any]? = nil) {
        guard state.hidden == 0 else { return }
        // A space waiting before this would land after it, out of order; it isn't needed.
        state.pendingSpace = nil
        if state.cascade != nil, attributes == nil, text != "\n" { beginParagraph(state) }
        let units = Array(text.utf16)
        let start = state.units.count
        state.units += units
        state.domOffsets += Array(repeating: Int32(state.dom), count: units.count)
        state.synthetic += Array(repeating: true, count: units.count)
        state.runs.append((NSRange(location: start, length: units.count), attributes ?? self.attributes(inline, block, state)))
    }

    /// Ends the current paragraph, if any text was written since the last break.
    private func breakParagraph(_ state: State, _ inline: Inline, _ block: Block) {
        state.pendingSpace = nil
        state.lineStart = true
        guard let last = state.units.last, last != 0x0A else { return }
        // The break belongs to the paragraph it ends, so it takes that paragraph's style.
        let attributes = state.runs.last?.attributes ?? self.attributes(inline, block, state)
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
            if state.cascade != nil { beginParagraph(state) }
            if let space = state.pendingSpace, !state.lineStart {
                state.units.append(0x20)
                state.domOffsets.append(Int32(space))
                state.synthetic.append(false)
                state.runs.append((NSRange(location: state.units.count - 1, length: 1), attributes(inline, block, state)))
            }
            appendSynthetic("\u{FFFC}", state, inline, block, attributes: attributes(inline, block, state).merging([.attachment: attachment]) { $1 })
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

    private func attributes(_ inline: Inline, _ block: Block, _ state: State) -> [NSAttributedString.Key: Any] {
        if block.css != nil { return originalAttributes(inline, block, state) }
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

    /// With original styles: what the book's CSS resolved to, with the user's font, line
    /// height, hyphenation and colors.
    private func originalAttributes(_ inline: Inline, _ block: Block, _ state: State) -> [NSAttributedString.Key: Any] {
        let s = style.settings
        let size = style.fontSize * inline.size * inline.scale
        var font = BookFonts.font(s.font, size: size, weight: inline.weight.map(Double.init) ?? s.weight, italic: inline.italic, monospace: inline.mono)
        if inline.smallCaps { font = Self.smallCaps(font) }

        let paragraph = NSMutableParagraphStyle()
        let lineHeight = style.fontSize * block.size * s.lineHeight
        // Larger type in the line (a dropped capital) makes the line taller, as in CSS.
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = max(lineHeight, size * s.lineHeight)
        let limit = style.columnWidth * 0.4
        let indent = min(limit, max(0, block.indent))
        paragraph.headIndent = indent
        paragraph.firstLineHeadIndent = min(style.columnWidth * 0.6, max(0, indent + block.textIndent))
        paragraph.tailIndent = -min(limit, max(0, block.tailIndent))
        paragraph.lineBreakStrategy = .pushOut
        paragraph.alignment = block.align ?? .natural
        paragraph.hyphenationFactor = s.hyphenate && !block.pre ? 1 : 0
        paragraph.paragraphSpacingBefore = state.spaceBefore

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: style.text,
            .paragraphStyle: paragraph,
            .baselineOffset: max(0, (lineHeight - font.lineHeight) / 2) + inline.baseline,
        ]
        if s.tracking != 0 { attributes[.kern] = s.tracking * size }
        if let language = style.language, !language.isEmpty { attributes[.languageIdentifier] = language }
        if let link = inline.link { attributes[.bookLink] = link }
        if inline.underline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            if inline.link != nil { attributes[.underlineColor] = style.text.withAlphaComponent(0.35) }
        }
        if inline.strike { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return attributes
    }

    private static func smallCaps(_ font: UIFont) -> UIFont {
        let features: [[UIFontDescriptor.FeatureKey: Int]] = [[.type: kLowerCaseType, .selector: kLowerCaseSmallCapsSelector]]
        return UIFont(descriptor: font.fontDescriptor.addingAttributes([.featureSettings: features]), size: font.pointSize)
    }
}

extension NSAttributedString.Key {
    static let languageIdentifier = NSAttributedString.Key(kCTLanguageAttributeName as String)
}
