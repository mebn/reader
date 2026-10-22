import UIKit

extension NSAttributedString.Key {
    /// The annotation id of a highlight.
    static let highlight = NSAttributedString.Key("reader.highlight")
    /// Set on the last character of a highlight with a note.
    static let highlightNote = NSAttributedString.Key("reader.highlightNote")
}

/// A chapter flowed through one text container per page.
final class ChapterLayout {
    let index: Int
    let text: ChapterText
    let storage: NSTextStorage
    let layoutManager = HighlightLayoutManager()
    private(set) var containers: [NSTextContainer] = []

    var pageCount: Int { max(1, containers.count) }

    init(index: Int, text: ChapterText, pageSize: CGSize) {
        self.index = index
        self.text = text
        storage = NSTextStorage(attributedString: text.string)
        storage.addLayoutManager(layoutManager)
        Self.flow(layoutManager, pageSize) { containers.append($0) }
    }

    /// Only counts pages, for numbering the whole book.
    static func countPages(_ text: ChapterText, pageSize: CGSize) -> Int {
        let storage = NSTextStorage(attributedString: text.string)
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        var count = 0
        flow(manager, pageSize) { _ in count += 1 }
        return max(1, count)
    }

    private static func flow(_ manager: NSLayoutManager, _ size: CGSize, _ add: (NSTextContainer) -> Void) {
        manager.allowsNonContiguousLayout = false
        manager.usesFontLeading = false
        var empty = 0
        while true {
            let container = NSTextContainer(size: size)
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)
            add(container)
            let range = manager.glyphRange(for: container)
            if NSMaxRange(range) >= manager.numberOfGlyphs { break }
            // Something that never fits would add pages forever.
            empty = range.length == 0 ? empty + 1 : 0
            if empty > 2 { break }
        }
    }

    func characterRange(page: Int) -> NSRange {
        guard containers.indices.contains(page) else { return NSRange(location: storage.length, length: 0) }
        let glyphs = layoutManager.glyphRange(for: containers[page])
        return layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
    }

    /// The page a character is on.
    func page(ofCharacter index: Int) -> Int {
        guard storage.length > 0, !containers.isEmpty else { return 0 }
        let glyph = layoutManager.glyphIndexForCharacter(at: min(index, storage.length - 1))
        guard let container = layoutManager.textContainer(forGlyphAt: glyph, effectiveRange: nil) else { return 0 }
        return containers.firstIndex { $0 === container } ?? 0
    }

    func page(ofDom offset: Int) -> Int {
        page(ofCharacter: text.displayIndex(forDom: offset))
    }

    /// Marks highlights in the text, replacing earlier marks.
    func setHighlights(_ highlights: [Annotation]) {
        storage.beginEditing()
        let all = NSRange(location: 0, length: storage.length)
        storage.removeAttribute(.highlight, range: all)
        storage.removeAttribute(.highlightNote, range: all)
        storage.removeAttribute(.backgroundColor, range: all)
        for a in highlights {
            let loc = a.position
            guard let start = loc.start, let end = loc.end, let range = text.displayRange(domStart: start, domEnd: end) else { continue }
            storage.addAttributes([.highlight: a.id, .backgroundColor: highlightColor(a.color).withAlphaComponent(0.42)], range: range)
            if a.hasNote { storage.addAttribute(.highlightNote, value: highlightColor(a.color), range: NSRange(location: NSMaxRange(range) - 1, length: 1)) }
        }
        storage.endEditing()
    }
}

/// Draws highlights as soft rounded marks behind the text, with a dot after ones that
/// carry a note.
final class HighlightLayoutManager: NSLayoutManager {
    /// Where the container being drawn sits, which the rects below don't say.
    private var drawingOrigin = CGPoint.zero

    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<CGRect>, count rectCount: Int, forCharacterRange charRange: NSRange, color: UIColor) {
        guard let context = UIGraphicsGetCurrentContext(), let storage = textStorage else { return }
        let font = storage.attribute(.font, at: charRange.location, effectiveRange: nil) as? UIFont
        let height = (font?.lineHeight ?? 20) * 1.08
        // The rects can cover several whole lines at once, so marks are made line by line
        // rather than from them, and only where they fall inside the rects being filled.
        let rects = (0..<rectCount).map { rectArray[$0] }
        let glyphs = glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        context.saveGState()
        color.setFill()
        enumerateLineFragments(forGlyphRange: glyphs) { _, usedRect, container, lineGlyphs, _ in
            let onLine = NSIntersectionRange(lineGlyphs, glyphs)
            guard onLine.length > 0 else { return }
            var span = self.boundingRect(forGlyphRange: onLine, in: container).offsetBy(dx: self.drawingOrigin.x, dy: self.drawingOrigin.y)
            // A line's trailing space or break isn't marked.
            span.size.width = min(span.width, usedRect.maxX + self.drawingOrigin.x - span.minX)
            // Rects can touch the next line too; each line is marked from its own rect only.
            guard span.width > 0, rects.contains(where: { $0.contains(CGPoint(x: span.midX, y: span.midY)) }) else { return }
            // The line box is taller than the type, which sits centered in it; the mark hugs the letters.
            let midY = usedRect.midY + self.drawingOrigin.y
            // Overlapping marks would show darker stripes where lines meet.
            let markHeight = min(height, usedRect.height - 2)
            let mark = CGRect(x: span.minX - 1, y: midY - markHeight / 2, width: span.width + 2, height: markHeight)
            UIBezierPath(roundedRect: mark, cornerRadius: 3).fill()
        }
        context.restoreGState()
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        drawingOrigin = origin
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.highlightNote, in: chars) { value, range, _ in
            guard let color = value as? UIColor, let container = textContainer(forGlyphAt: glyphIndexForCharacter(at: range.location), effectiveRange: nil) else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = boundingRect(forGlyphRange: glyphs, in: container)
            let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont
            let size: CGFloat = 5
            let y = rect.midY - (font?.lineHeight ?? 20) * 0.45
            color.setFill()
            UIBezierPath(ovalIn: CGRect(x: rect.maxX + origin.x + 1.5, y: y + origin.y, width: size, height: size)).fill()
        }
    }
}
