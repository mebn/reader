import UIKit

/// Page counts per layout, shared across books opened in this session.
@MainActor private var pageCountCache: [String: [Int]] = [:]

private struct Geometry: Equatable {
    var size: CGSize = .zero
    var column: CGFloat = 0
    var gap: CGFloat = 0
    var height: CGFloat = 0
    /// Pages visible at once.
    var span = 1
    /// Where the first page's text starts.
    var origin: CGPoint = .zero

    var pageSize: CGSize { CGSize(width: column, height: height) }
}

private struct PageKey: Hashable {
    var chapter: Int
    var page: Int
}

private final class Box<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// Shows reflowable books (EPUB, FB2, TXT) as pages to swipe through. Each chapter is
/// flowed through page-sized text containers; the whole book is counted in the background
/// so pages have numbers.
final class ReflowController: UIViewController, ReaderEngine {
    weak var delegate: ReaderEngineDelegate?

    private let doc: ReflowDocument
    private let bookId: String
    private lazy var turner = PageTurner(host: self)

    private var appearance: Appearance?
    private var annotations: [Annotation] = []
    private var geometry = Geometry()
    private var layouts: [Int: ChapterLayout] = [:]
    private var pages: [PageKey: ReflowPageController] = [:]
    private var chapter = 0
    private var page = 0
    private var bookPages: [Int]?
    private var paginateTask: Task<Void, Never>?
    /// Where to go once the first layout is done.
    private var pendingLocator: Locator?
    private var hadSelection = false
    private var tapGesture: UITapGestureRecognizer!
    /// Swipes turn the page; they're off while text is selected, so dragging a selection
    /// handle can't turn it.
    private var swipes: [UISwipeGestureRecognizer] = []

    init(doc: ReflowDocument, bookId: String) {
        self.doc = doc
        self.bookId = bookId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        tapGesture = tap

        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
            swipe.direction = direction
            view.addGestureRecognizer(swipe)
            swipes.append(swipe)
        }

        // Selecting is done here rather than by the text views, whose gestures lose to page
        // turns and taps: hold on a word and drag to select more. There's no double tap, so
        // a tap turns the page at once.
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(selectWords(_:)))
        hold.minimumPressDuration = 0.35
        hold.delegate = self
        view.addGestureRecognizer(hold)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if computeGeometry() != geometry { relayout() }
    }

    override var canBecomeFirstResponder: Bool { true }
    override var keyCommands: [UIKeyCommand]? { PageKeys.commands(#selector(keyNext), #selector(keyPrev)) }
    @objc private func keyNext() { turn(forward: true) }
    @objc private func keyPrev() { turn(forward: false) }

    // MARK: - ReaderEngine

    var position: Position? {
        guard let layout = layouts[chapter] else { return nil }
        let chapterPages = layout.pageCount
        let fraction = Double(page) / Double(chapterPages)
        // The first character on the page pins the position exactly on any device; the
        // fraction is for readers that don't know it.
        let first = layout.text.domRange(layout.characterRange(page: page))?.start
        let locator = Locator(chapter: chapter, fraction: fraction, start: first)
        let total = bookPages?.reduce(0, +)
        let before = bookPages?.prefix(chapter).reduce(0, +) ?? 0
        let bookPage = bookPages != nil ? before + page + 1 : nil
        let percent: Double = if let total, let bookPage, total > 0 {
            min(1, Double(bookPage + geometry.span - 1) / Double(total))
        } else {
            (Double(chapter) + fraction) / Double(max(1, doc.chapterCount))
        }
        return Position(chapter: chapter, chapterCount: doc.chapterCount, page: bookPage, pageCount: total,
                        chapterPage: page + 1, chapterPageCount: chapterPages, percent: percent, locator: locator)
    }

    func setAppearance(_ appearance: Appearance) {
        guard appearance != self.appearance else { return }
        let first = self.appearance == nil
        self.appearance = appearance
        view.backgroundColor = appearance.background.uiColor
        if !first || geometry.size != .zero { relayout(force: true) }
    }

    func setAnnotations(_ annotations: [Annotation]) {
        self.annotations = annotations.filter { $0.kind == .highlight }
        for layout in layouts.values { layout.setHighlights(highlights(in: layout.index)) }
        for page in pages.values { page.redraw() }
    }

    func goTo(_ locator: Locator) {
        guard geometry.size != .zero, appearance != nil else {
            pendingLocator = locator
            return
        }
        let target = clamp(locator.chapter ?? 0, 0, doc.chapterCount - 1)
        let layout = self.layout(target)
        chapter = target
        if let start = locator.start {
            page = align(layout.page(ofDom: start), layout)
        } else {
            page = align(Int(floor((locator.fraction ?? 0) * Double(layout.pageCount) + 1e-6)), layout)
        }
        show()
    }

    func goTo(_ entry: TocEntry) {
        guard let chapter = entry.chapter else { return }
        goToAnchor(chapter, entry.anchor)
    }

    func turn(forward: Bool) {
        guard current != nil else { return }
        clearSelection()
        let from = PageKey(chapter: chapter, page: page)
        guard let next = forward ? pageAfter(from) : pageBefore(from) else { return }
        let controller = pageController(next)
        settle(on: next)
        turner.show(controller, style: appearance?.settings.pageTurn ?? .slide, forward: forward)
    }

    func isVisible(_ locator: Locator) -> Bool {
        guard locator.chapter == chapter, let layout = layouts[chapter] else { return false }
        let target = locator.start.map { layout.page(ofDom: $0) } ?? Int(floor((locator.fraction ?? 0) * Double(layout.pageCount) + 1e-6))
        return target >= page && target < page + geometry.span
    }

    func pageOf(_ locator: Locator) -> Int? {
        guard let bookPages else { return nil }
        let target = clamp(locator.chapter ?? 0, 0, bookPages.count - 1)
        let before = bookPages.prefix(target).reduce(0, +)
        let inChapter: Int = if target == chapter, let start = locator.start, let layout = layouts[chapter] {
            layout.page(ofDom: start)
        } else {
            Int(floor((locator.fraction ?? 0) * Double(bookPages[target]) + 1e-6))
        }
        return before + clamp(inChapter, 0, bookPages[target] - 1) + 1
    }

    func text(of locator: Locator) -> String? {
        guard let chapter = locator.chapter, let start = locator.start, let end = locator.end,
              let layout = layouts[chapter], let range = layout.text.displayRange(domStart: start, domEnd: end) else { return nil }
        return normalizedSelection((layout.storage.string as NSString).substring(with: range))
    }

    func clearSelection() {
        for controller in pages.values { controller.clearSelection() }
        for swipe in swipes { swipe.isEnabled = true }
    }

    private var current: ReflowPageController? { turner.page as? ReflowPageController }

    /// Entries inside the current chapter count by their anchor's page, since one file
    /// often holds several chapters.
    func hasReached(_ entry: TocEntry) -> Bool {
        guard let target = entry.chapter else { return false }
        if target != chapter { return target < chapter }
        guard let anchor = entry.anchor, let layout = layouts[chapter], let index = layout.text.anchors[anchor] else { return true }
        return layout.page(ofCharacter: index) < page + geometry.span
    }

    // MARK: - Layout

    private func computeGeometry() -> Geometry {
        let size = view.bounds.size
        guard size.width > 0, size.height > 0, let settings = appearance?.settings else { return Geometry() }
        let safe = view.safeAreaInsets
        let top = max(52, safe.top + 34)
        let bottom = max(52, safe.bottom + 34)
        let width = size.width - safe.left - safe.right
        let height = max(120, size.height - top - bottom)
        // The margin is a share of the width, as on the desktop, but scaled down on narrow
        // screens where a fifth of the width each side would leave a sliver of text.
        let scale = min(1, max(0.35, width / 900))
        let margin = max(16, (width * settings.sideMargin / 100 * scale).rounded())
        let span = settings.pages == 2 && width > 760 ? 2 : 1
        let gap: CGFloat = span == 2 ? min(96, max(40, width * 0.05)).rounded() : 0
        let column = floor(span == 2 ? (width - margin * 2 - gap) / 2 : width - margin * 2)
        return Geometry(size: size, column: column, gap: gap, height: floor(height), span: span, origin: CGPoint(x: safe.left + margin, y: top))
    }

    /// Lays everything out again, keeping the reading position.
    private func relayout(force: Bool = false) {
        let next = computeGeometry()
        guard next.size != .zero, force || next != geometry else { return }
        // Keeps the same text at the top of the page, not the same share of the chapter.
        let here = position?.locator
        geometry = next
        layouts = [:]
        pages = [:]
        paginateTask?.cancel()
        bookPages = pageCountCache[cacheKey]

        if let pending = pendingLocator {
            pendingLocator = nil
            goTo(pending)
        } else {
            goTo(here ?? Locator(chapter: chapter, fraction: 0))
        }
        if bookPages == nil { paginate() }
    }

    private func layout(_ index: Int) -> ChapterLayout {
        if let layout = layouts[index] { return layout }
        let text = buildText(index, doc: doc, style: style)
        let layout = ChapterLayout(index: index, text: text, pageSize: geometry.pageSize)
        layout.setHighlights(highlights(in: index))
        layouts[index] = layout
        return layout
    }

    private var style: TextStyle {
        TextStyle(settings: appearance!.settings, text: appearance!.background.uiText, columnWidth: geometry.column, pageHeight: geometry.height, language: doc.metadata.language)
    }

    private func highlights(in chapter: Int) -> [Annotation] {
        annotations.filter { $0.position.chapter == chapter }
    }

    private func align(_ page: Int, _ layout: ChapterLayout) -> Int {
        let clamped = clamp(page, 0, layout.pageCount - 1)
        return clamped - clamped % geometry.span
    }

    private var cacheKey: String {
        "\(bookId)|\(appearance?.settings.layoutKey(width: geometry.column, height: geometry.height) ?? "")|\(geometry.span)"
    }

    /// Counts every chapter's pages in the background to number pages across the book.
    private func paginate() {
        let key = cacheKey
        let doc = Box(doc)
        let style = self.style
        let size = geometry.pageSize
        let count = doc.value.chapterCount
        paginateTask = Task { [weak self] in
            // Wait for resizing to settle before starting.
            try? await Task.sleep(for: .milliseconds(300))
            var counts: [Int] = []
            for i in 0..<count {
                guard !Task.isCancelled else { return }
                let pages = await Task.detached(priority: .utility) {
                    ChapterLayout.countPages(buildText(i, doc: doc.value, style: style), pageSize: size)
                }.value
                counts.append(pages)
            }
            guard !Task.isCancelled, let self else { return }
            pageCountCache[key] = counts
            if key == cacheKey {
                bookPages = counts
                emit()
            }
        }
    }

    // MARK: - Pages

    private func pageController(_ key: PageKey) -> ReflowPageController {
        if let existing = pages[key] { return existing }
        let controller = ReflowPageController(key: key, layout: layout(key.chapter), span: geometry.span, geometry: (geometry.origin, geometry.pageSize, geometry.gap), owner: self)
        controller.view.backgroundColor = appearance?.background.uiColor
        pages[key] = controller
        return controller
    }

    private func pageAfter(_ key: PageKey) -> PageKey? {
        let layout = self.layout(key.chapter)
        if key.page + geometry.span < layout.pageCount { return PageKey(chapter: key.chapter, page: key.page + geometry.span) }
        return key.chapter + 1 < doc.chapterCount ? PageKey(chapter: key.chapter + 1, page: 0) : nil
    }

    private func pageBefore(_ key: PageKey) -> PageKey? {
        if key.page > 0 { return PageKey(chapter: key.chapter, page: max(0, key.page - geometry.span)) }
        guard key.chapter > 0 else { return nil }
        let previous = layout(key.chapter - 1)
        return PageKey(chapter: key.chapter - 1, page: align(previous.pageCount - 1, previous))
    }

    /// Shows the current page at once, as after a jump or a relayout.
    private func show() {
        let key = PageKey(chapter: chapter, page: page)
        turner.show(pageController(key), style: nil, forward: true)
        settle(on: key)
    }

    /// Makes a page the current one, and drops chapters that are far away.
    private func settle(on key: PageKey) {
        chapter = key.chapter
        page = key.page
        for index in layouts.keys where abs(index - chapter) > 1 { layouts[index] = nil }
        // A page's text view owns its text container, so a page is kept as long as its
        // chapter's layout is, never built twice.
        pages = pages.filter { layouts[$0.key.chapter] != nil }
        emit()
    }

    private func emit() {
        if let position { delegate?.engineChanged(position) }
    }

    private func goToAnchor(_ chapter: Int, _ anchor: String?) {
        let layout = self.layout(chapter)
        self.chapter = chapter
        page = 0
        if let anchor, let index = layout.text.anchors[anchor] {
            page = align(layout.page(ofCharacter: index), layout)
        }
        show()
    }

    // MARK: - Interaction

    fileprivate func selectionChanged(_ range: NSRange?, layout: ChapterLayout) {
        for swipe in swipes { swipe.isEnabled = range == nil }
        delegate?.engineSelected(range.flatMap { selection(layout, $0) })
    }

    private func selection(_ layout: ChapterLayout, _ range: NSRange) -> TextSelection? {
        guard let dom = layout.text.domRange(range) else { return nil }
        let text = normalizedSelection((layout.storage.string as NSString).substring(with: range))
        return text.isEmpty ? nil : TextSelection(locator: Locator(chapter: layout.index, start: dom.start, end: dom.end), text: text)
    }

    fileprivate func menu(layout: ChapterLayout, range: NSRange) -> UIMenu? {
        guard let selection = selection(layout, range) else { return nil }
        let raw = (layout.storage.string as NSString).substring(with: range)
        let copy = UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
            UIPasteboard.general.string = raw
            self?.clearSelection()
        }
        let lookUp = UIAction(title: "Look Up", image: UIImage(systemName: "character.book.closed")) { [weak self] _ in
            self?.present(UIReferenceLibraryViewController(term: selection.text), animated: true)
        }
        return UIMenu(children: highlightMenu(selection) + [UIMenu(options: .displayInline, children: [copy, lookUp])])
    }

    /// Highlight and note, as on the desktop; a highlight's color is changed by tapping it.
    private func highlightMenu(_ selection: TextSelection) -> [UIMenuElement] {
        let highlight = UIAction(title: "Highlight", image: UIImage(systemName: "highlighter")) { [weak self] _ in
            self?.delegate?.engineHighlight(selection, withNote: false)
            self?.clearSelection()
        }
        let note = UIAction(title: "Add Note", image: UIImage(systemName: "note.text.badge.plus")) { [weak self] _ in
            self?.delegate?.engineHighlight(selection, withNote: true)
            self?.clearSelection()
        }
        let search = UIAction(title: "Search Web", image: UIImage(systemName: "magnifyingglass")) { [weak self] _ in
            var components = URLComponents(string: "https://www.google.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: selection.text)]
            if let url = components.url { self?.delegate?.engineOpen(url) }
        }
        return [UIMenu(options: .displayInline, children: [highlight, note]), search]
    }

    /// Selects the word under the finger, then word by word up to wherever it is dragged.
    @objc private func selectWords(_ gesture: UILongPressGestureRecognizer) {
        guard let current else { return }
        let point = gesture.location(in: current.view)
        switch gesture.state {
        case .began:
            guard current.beginSelecting(at: point) else { return }
            for swipe in swipes { swipe.isEnabled = false }
            UISelectionFeedbackGenerator().selectionChanged()
        case .changed:
            current.extendSelecting(to: point)
        case .ended:
            current.endSelecting(showMenu: true)
        case .cancelled, .failed:
            current.endSelecting(showMenu: false)
        default:
            break
        }
    }

    @objc private func swiped(_ gesture: UISwipeGestureRecognizer) {
        turn(forward: gesture.direction == .left)
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard let current else { return }
        // A tap with text selected only clears the selection. Whether there was one is read
        // when the touch began: the text view clears it on the same tap.
        if hadSelection {
            clearSelection()
            delegate?.engineSelected(nil)
            return
        }
        let point = gesture.location(in: current.view)
        if let hit = current.hit(at: point) {
            switch hit {
            case let .highlight(id):
                delegate?.engineTappedAnnotation(id)
            case let .link(link):
                follow(link)
            }
            return
        }
        delegate?.engineTapped(atFraction: gesture.location(in: view).x / max(1, view.bounds.width))
    }

    private func follow(_ link: String) {
        if link.hasPrefix("ext:"), let url = URL(string: String(link.dropFirst(4))) {
            delegate?.engineOpen(url)
        } else if link.hasPrefix("int:"), let target = doc.resolveLink(String(link.dropFirst(4))), case let .chapter(chapter, anchor) = target {
            goToAnchor(chapter, anchor)
        }
    }
}

/// Lays out a chapter's text, off the main thread or on it.
private func buildText(_ index: Int, doc: ReflowDocument, style: TextStyle) -> ChapterText {
    let root = (try? doc.chapter(index)) ?? Node.element("body")
    return ChapterTextBuilder(style: style, image: doc.image).build(root)
}

private func clamp(_ n: Int, _ lo: Int, _ hi: Int) -> Int { min(max(n, lo), max(lo, hi)) }

extension ReflowController: UIGestureRecognizerDelegate {
    /// Taps are only watched; selecting takes the touch for itself.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { g === tapGesture }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if g === tapGesture { hadSelection = current?.hasSelection ?? false }
        return true
    }
}

// MARK: - A page

/// One screen of text: one or two pages of a chapter, each drawn from its own container
/// of the chapter's layout.
private final class ReflowPageController: UIViewController {
    enum Hit {
        case highlight(String)
        case link(String)
    }

    let key: PageKey
    private let layout: ChapterLayout
    private let span: Int
    private let geometry: (origin: CGPoint, size: CGSize, gap: CGFloat)
    private weak var owner: ReflowController?
    private var pageViews: [PageTextView] = []

    init(key: PageKey, layout: ChapterLayout, span: Int, geometry: (CGPoint, CGSize, CGFloat), owner: ReflowController) {
        self.key = key
        self.layout = layout
        self.span = span
        self.geometry = geometry
        self.owner = owner
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        for i in 0..<span {
            let index = key.page + i
            guard layout.containers.indices.contains(index) else { break }
            let frame = CGRect(x: geometry.origin.x + CGFloat(i) * (geometry.size.width + geometry.gap), y: geometry.origin.y, width: geometry.size.width, height: geometry.size.height)
            let page = PageTextView(frame: frame, layout: layout, container: layout.containers[index])
            page.onSelectionChange = { [weak self, weak page] range in
                guard let self, let page else { return }
                // One selection at a time across facing pages.
                if range != nil {
                    for other in self.pageViews where other !== page { other.selection = nil }
                }
                self.owner?.selectionChanged(range, layout: self.layout)
            }
            page.menuProvider = { [weak self] range in
                guard let self else { return nil }
                return self.owner?.menu(layout: self.layout, range: range)
            }
            view.addSubview(page)
            pageViews.append(page)
        }
    }

    var hasSelection: Bool { pageViews.contains { $0.selection != nil } }

    func clearSelection() {
        for page in pageViews where page.selection != nil { page.selection = nil }
    }

    /// Shows highlights changed in the layout.
    func redraw() {
        for page in pageViews { page.setNeedsDisplay() }
    }

    private var selecting: (page: PageTextView, anchor: NSRange)?

    /// Starts a selection at the word under a point in this page; false when there's no text there.
    func beginSelecting(at point: CGPoint) -> Bool {
        guard let page = pageViews.first(where: { $0.frame.contains(point) }),
              let index = page.characterIndex(at: convert(point, to: page), onText: true) else { return false }
        let word = layout.word(at: index)
        // Holding between words selects nothing, rather than a lone space.
        guard (layout.storage.string as NSString).substring(with: word).contains(where: { !$0.isWhitespace }) else { return false }
        clearSelection()
        selecting = (page, word)
        page.selection = word
        return true
    }

    func extendSelecting(to point: CGPoint) {
        guard let (page, anchor) = selecting, let index = page.characterIndex(at: convert(point, to: page), onText: false) else { return }
        let word = layout.word(at: index)
        let start = min(anchor.location, word.location), end = max(NSMaxRange(anchor), NSMaxRange(word))
        let range = NSRange(location: start, length: end - start)
        if range != page.selection {
            page.selection = range
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    func endSelecting(showMenu: Bool) {
        guard let (page, _) = selecting else { return }
        selecting = nil
        if showMenu { page.showMenu() }
    }

    private func convert(_ point: CGPoint, to page: UIView) -> CGPoint {
        view.convert(point, to: page)
    }

    func hit(at point: CGPoint) -> Hit? {
        for page in pageViews where page.frame.contains(point) {
            guard let index = page.characterIndex(at: convert(point, to: page), onText: true) else { return nil }
            if let id = layout.storage.attribute(.highlight, at: index, effectiveRange: nil) as? String { return .highlight(id) }
            if let link = layout.storage.attribute(.bookLink, at: index, effectiveRange: nil) as? String { return .link(link) }
        }
        return nil
    }
}

private extension ChapterLayout {
    /// The word around a character, or the character itself when it isn't part of one.
    func word(at index: Int) -> NSRange {
        let string = storage.string as NSString
        var found: NSRange?
        string.enumerateSubstrings(in: string.paragraphRange(for: NSRange(location: index, length: 0)), options: [.byWords, .substringNotRequired]) { _, range, _, stop in
            if NSLocationInRange(index, range) {
                found = range
                stop.pointee = true
            }
        }
        return found ?? string.rangeOfComposedCharacterSequence(at: index)
    }
}

/// A page of a chapter, drawn straight from the chapter's layout, with its own selection.
/// UITextView can't select anything past the first container of a shared layout, so
/// selecting, its handles and its menu are done here.
private final class PageTextView: UIView, UIEditMenuInteractionDelegate {
    let layout: ChapterLayout
    let container: NSTextContainer
    var onSelectionChange: ((NSRange?) -> Void)?
    var menuProvider: ((NSRange) -> UIMenu?)?

    var selection: NSRange? {
        didSet {
            guard selection != oldValue else { return }
            if selection == nil { menu.dismissMenu() }
            updateSelection()
            onSelectionChange?(selection)
        }
    }

    private let selectionLayer = CAShapeLayer()
    private let startHandle = SelectionHandle(atStart: true)
    private let endHandle = SelectionHandle(atStart: false)
    private lazy var menu = UIEditMenuInteraction(delegate: self)

    init(frame: CGRect, layout: ChapterLayout, container: NSTextContainer) {
        self.layout = layout
        self.container = container
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        layer.addSublayer(selectionLayer)
        addInteraction(menu)
        for handle in [startHandle, endHandle] {
            handle.isHidden = true
            handle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragHandle(_:))))
            addSubview(handle)
        }
        isAccessibilityElement = true
        accessibilityTraits = .staticText
    }

    required init?(coder: NSCoder) { fatalError() }

    override var accessibilityLabel: String? {
        get { (layout.storage.string as NSString).substring(with: characterRange) }
        set {}
    }

    private var glyphRange: NSRange { layout.layoutManager.glyphRange(for: container) }
    private var characterRange: NSRange { layout.layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil) }

    override func draw(_ rect: CGRect) {
        let glyphs = glyphRange
        layout.layoutManager.drawBackground(forGlyphRange: glyphs, at: .zero)
        layout.layoutManager.drawGlyphs(forGlyphRange: glyphs, at: .zero)
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateSelection()
    }

    /// The character under a point in this view, or nearest to it unless `onText`.
    func characterIndex(at point: CGPoint, onText: Bool) -> Int? {
        let manager = layout.layoutManager
        guard glyphRange.length > 0 else { return nil }
        let glyph = manager.glyphIndex(for: point, in: container)
        if onText {
            let rect = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            guard rect.insetBy(dx: -6, dy: -6).contains(point) else { return nil }
        }
        let index = manager.characterIndexForGlyph(at: glyph)
        return index < layout.storage.length ? index : nil
    }

    /// The gap between characters nearest a point, for dragging a handle.
    private func boundary(at point: CGPoint) -> Int {
        let manager = layout.layoutManager
        var fraction: CGFloat = 0
        let index = manager.characterIndex(for: point, in: container, fractionOfDistanceBetweenInsertionPoints: &fraction)
        let chars = characterRange
        return min(max(index + (fraction > 0.5 ? 1 : 0), chars.location), NSMaxRange(chars))
    }

    /// The selection's rects, a line each.
    private func lineRects(_ range: NSRange) -> [CGRect] {
        let manager = layout.layoutManager
        let glyphs = NSIntersectionRange(manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil), glyphRange)
        guard glyphs.length > 0 else { return [] }
        var rects: [CGRect] = []
        manager.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, lineGlyphs, _ in
            let onLine = NSIntersectionRange(lineGlyphs, glyphs)
            var rect = manager.boundingRect(forGlyphRange: onLine, in: self.container)
            rect.size.width = min(rect.width, used.maxX - rect.minX)
            rect.origin.y = used.minY
            rect.size.height = used.height
            if rect.width > 0 { rects.append(rect) }
        }
        return rects
    }

    private func updateSelection() {
        guard let selection, selection.length > 0 else {
            selectionLayer.path = nil
            startHandle.isHidden = true
            endHandle.isHidden = true
            return
        }
        let rects = lineRects(selection)
        let path = UIBezierPath()
        for rect in rects { path.append(UIBezierPath(rect: rect)) }
        selectionLayer.path = path.cgPath
        selectionLayer.fillColor = tintColor.withAlphaComponent(0.28).cgColor
        startHandle.tintColor = tintColor
        endHandle.tintColor = tintColor
        if let first = rects.first, let last = rects.last {
            startHandle.place(at: CGPoint(x: first.minX, y: first.minY), lineHeight: first.height)
            endHandle.place(at: CGPoint(x: last.maxX, y: last.minY), lineHeight: last.height)
        }
        startHandle.isHidden = rects.isEmpty
        endHandle.isHidden = rects.isEmpty
    }

    @objc private func dragHandle(_ gesture: UIPanGestureRecognizer) {
        guard let selection, let handle = gesture.view as? SelectionHandle else { return }
        switch gesture.state {
        case .began:
            menu.dismissMenu()
        case .changed:
            // Aim at the middle of the line the finger is on, not the handle's knob.
            var point = gesture.location(in: self)
            point.y += handle.atStart ? handle.lineHeight / 2 : -handle.lineHeight / 2
            let at = boundary(at: point)
            var start = selection.location, end = NSMaxRange(selection)
            if handle.atStart { start = min(at, end - 1) } else { end = max(at, start + 1) }
            let range = NSRange(location: start, length: end - start)
            if range != selection {
                self.selection = range
                UISelectionFeedbackGenerator().selectionChanged()
            }
        case .ended, .cancelled:
            showMenu()
        default:
            break
        }
    }

    func showMenu() {
        guard let selection, let rect = lineRects(selection).first else { return }
        menu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: CGPoint(x: rect.midX, y: rect.minY)))
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let selection else { return nil }
        return menuProvider?(selection)
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        guard let selection else { return .null }
        return lineRects(selection).reduce(CGRect.null) { $0.union($1) }
    }
}

/// A selection handle: a bar along the line with a knob above the start or below the end,
/// in a bigger box to grab.
private final class SelectionHandle: UIView {
    let atStart: Bool
    private(set) var lineHeight: CGFloat = 20
    private let bar = UIView()
    private let knob = UIView()
    private static let knobSize: CGFloat = 10
    private static let grab: CGFloat = 44

    init(atStart: Bool) {
        self.atStart = atStart
        super.init(frame: .zero)
        knob.layer.cornerRadius = Self.knobSize / 2
        addSubview(bar)
        addSubview(knob)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        bar.backgroundColor = tintColor
        knob.backgroundColor = tintColor
    }

    /// Puts the bar at a line's edge, `top` being the line's top.
    func place(at top: CGPoint, lineHeight: CGFloat) {
        self.lineHeight = lineHeight
        let height = lineHeight + Self.knobSize
        let box = max(Self.grab, height)
        frame = CGRect(x: top.x - Self.grab / 2, y: top.y - (atStart ? Self.knobSize : 0) - (box - height) / 2, width: Self.grab, height: box)
        let barTop = (box - height) / 2 + (atStart ? Self.knobSize : 0)
        bar.frame = CGRect(x: Self.grab / 2 - 1, y: barTop, width: 2, height: lineHeight)
        knob.frame = CGRect(x: (Self.grab - Self.knobSize) / 2, y: atStart ? barTop - Self.knobSize + 1 : barTop + lineHeight - 1, width: Self.knobSize, height: Self.knobSize)
    }
}
