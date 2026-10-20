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
    private let pager = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: [.interPageSpacing: 0])

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

    init(doc: ReflowDocument, bookId: String) {
        self.doc = doc
        self.bookId = bookId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(pager)
        pager.view.frame = view.bounds
        pager.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(pager.view)
        pager.didMove(toParent: self)
        pager.dataSource = self
        pager.delegate = self

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
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
        let locator = Locator(chapter: chapter, fraction: fraction)
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
        show(animated: false)
    }

    func goTo(_ entry: TocEntry) {
        guard let chapter = entry.chapter else { return }
        goToAnchor(chapter, entry.anchor)
    }

    func turn(forward: Bool) {
        guard let current = pager.viewControllers?.first as? ReflowPageController else { return }
        clearSelection()
        let next = forward ? pageAfter(current.key) : pageBefore(current.key)
        guard let next else { return }
        let controller = pageController(next)
        pager.setViewControllers([controller], direction: forward ? .forward : .reverse, animated: true) { [weak self] _ in
            self?.settle(on: next)
        }
        settle(on: next)
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

    func clearSelection() {
        for controller in pages.values { controller.clearSelection() }
    }

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
        let fraction = layouts[chapter].map { Double(page) / Double($0.pageCount) }
        geometry = next
        layouts = [:]
        pages = [:]
        paginateTask?.cancel()
        bookPages = pageCountCache[cacheKey]

        if let pending = pendingLocator {
            pendingLocator = nil
            goTo(pending)
        } else {
            goTo(Locator(chapter: chapter, fraction: fraction ?? 0))
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

    private func show(animated: Bool) {
        let key = PageKey(chapter: chapter, page: page)
        pager.setViewControllers([pageController(key)], direction: .forward, animated: animated)
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
        show(animated: false)
    }

    // MARK: - Interaction

    fileprivate func selectionChanged(_ textView: UITextView, layout: ChapterLayout) {
        let range = textView.selectedRange
        guard range.length > 0, let dom = layout.text.domRange(range) else {
            delegate?.engineSelected(nil)
            return
        }
        let text = normalizedSelection((layout.storage.string as NSString).substring(with: range))
        delegate?.engineSelected(text.isEmpty ? nil : TextSelection(locator: Locator(chapter: layout.index, start: dom.start, end: dom.end), text: text))
    }

    fileprivate func menu(for textView: UITextView, layout: ChapterLayout, range: NSRange, suggested: [UIMenuElement]) -> UIMenu? {
        guard let dom = layout.text.domRange(range) else { return nil }
        let text = normalizedSelection((layout.storage.string as NSString).substring(with: range))
        guard !text.isEmpty else { return UIMenu(children: suggested) }
        let selection = TextSelection(locator: Locator(chapter: layout.index, start: dom.start, end: dom.end), text: text)
        return UIMenu(children: highlightMenu(selection) + suggested)
    }

    /// Highlight and note, as on the desktop; a highlight's color is changed by tapping it.
    private func highlightMenu(_ selection: TextSelection) -> [UIMenuElement] {
        let highlight = UIAction(title: "Highlight", image: UIImage(systemName: "highlighter")) { [weak self] _ in
            self?.delegate?.engineHighlight(selection, color: "yellow", withNote: false)
            self?.clearSelection()
        }
        let note = UIAction(title: "Add Note", image: UIImage(systemName: "note.text.badge.plus")) { [weak self] _ in
            self?.delegate?.engineHighlight(selection, color: "yellow", withNote: true)
            self?.clearSelection()
        }
        let search = UIAction(title: "Search Web", image: UIImage(systemName: "magnifyingglass")) { [weak self] _ in
            var components = URLComponents(string: "https://www.google.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: selection.text)]
            if let url = components.url { self?.delegate?.engineOpen(url) }
        }
        return [UIMenu(options: .displayInline, children: [highlight, note]), search]
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard let current = pager.viewControllers?.first as? ReflowPageController else { return }
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

extension ReflowController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
        guard let key = (vc as? ReflowPageController)?.key, let next = pageAfter(key) else { return nil }
        return pageController(next)
    }

    func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
        guard let key = (vc as? ReflowPageController)?.key, let previous = pageBefore(key) else { return nil }
        return pageController(previous)
    }

    func pageViewController(_ pvc: UIPageViewController, willTransitionTo pending: [UIViewController]) {
        clearSelection()
    }

    func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let key = (pvc.viewControllers?.first as? ReflowPageController)?.key else { return }
        settle(on: key)
    }
}

extension ReflowController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        hadSelection = (pager.viewControllers?.first as? ReflowPageController)?.hasSelection ?? false
        return true
    }
}

// MARK: - A page

/// One screen of text: one or two pages of a chapter, each a text view on its own
/// container of the chapter's layout.
private final class ReflowPageController: UIViewController, UITextViewDelegate {
    enum Hit {
        case highlight(String)
        case link(String)
    }

    let key: PageKey
    private let layout: ChapterLayout
    private let span: Int
    private let geometry: (origin: CGPoint, size: CGSize, gap: CGFloat)
    private weak var owner: ReflowController?
    private var textViews: [UITextView] = []

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
            let textView = UITextView(frame: frame, textContainer: layout.containers[index])
            textView.isEditable = false
            textView.isSelectable = true
            textView.isScrollEnabled = false
            textView.backgroundColor = .clear
            textView.textContainerInset = .zero
            textView.delegate = self
            textView.linkTextAttributes = [:]
            textView.tintColor = UIColor.tintColor
            view.addSubview(textView)
            textViews.append(textView)
        }
    }

    var hasSelection: Bool { textViews.contains { $0.selectedRange.length > 0 } }

    func clearSelection() {
        for textView in textViews where textView.selectedRange.length > 0 {
            textView.selectedRange = NSRange(location: 0, length: 0)
        }
    }

    func hit(at point: CGPoint) -> Hit? {
        for textView in textViews where textView.frame.contains(point) {
            let local = CGPoint(x: point.x - textView.frame.minX, y: point.y - textView.frame.minY)
            let manager = layout.layoutManager
            let container = textView.textContainer
            let glyph = manager.glyphIndex(for: local, in: container)
            let rect = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            guard rect.insetBy(dx: -4, dy: -4).contains(local) else { return nil }
            let index = manager.characterIndexForGlyph(at: glyph)
            if let id = layout.storage.attribute(.highlight, at: index, effectiveRange: nil) as? String { return .highlight(id) }
            if let link = layout.storage.attribute(.bookLink, at: index, effectiveRange: nil) as? String { return .link(link) }
        }
        return nil
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        // One selection at a time across facing pages.
        if textView.selectedRange.length > 0 {
            for other in textViews where other !== textView && other.selectedRange.length > 0 {
                other.selectedRange = NSRange(location: 0, length: 0)
            }
        }
        owner?.selectionChanged(textView, layout: layout)
    }

    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        owner?.menu(for: textView, layout: layout, range: range, suggested: suggestedActions)
    }
}
