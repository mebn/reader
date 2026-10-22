import PDFKit
import UIKit

/// Shows a PDF a page (or two) at a time with PDFKit. Highlights are stored as character
/// offsets into a page's text and drawn as PDF highlight annotations.
final class PdfController: UIViewController, ReaderEngine {
    weak var delegate: ReaderEngineDelegate?

    private let doc: PDFDocument
    private let toc: [TocEntry]
    private let pdfView = PDFView()
    private var appearance: Appearance?
    private var drawn: [String: [PDFAnnotation]] = [:]
    private var span = 1
    private var hadSelection = false
    private var pendingLocator: Locator?
    private var observers: [NSObjectProtocol] = []

    private static let prefix = "reader:"

    init(doc: PDFDocument, toc: [TocEntry]) {
        self.doc = doc
        self.toc = toc.filter { $0.depth == 0 && $0.page != nil }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        pdfView.frame = view.bounds
        pdfView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pdfView.document = doc
        pdfView.displayDirection = .horizontal
        pdfView.autoScales = true
        pdfView.pageShadowsEnabled = false
        configureMode()
        view.addSubview(pdfView)

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .PDFViewPageChanged, object: pdfView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.emit() }
        })
        observers.append(center.addObserver(forName: .PDFViewSelectionChanged, object: pdfView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.selectionChanged() }
        })

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        pdfView.addGestureRecognizer(tap)
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
            swipe.direction = direction
            swipe.delegate = self
            pdfView.addGestureRecognizer(swipe)
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        configureMode()
        if let pending = pendingLocator, view.bounds.width > 0 {
            pendingLocator = nil
            goTo(pending)
        }
    }

    override var canBecomeFirstResponder: Bool { true }
    override var keyCommands: [UIKeyCommand]? { PageKeys.commands(#selector(keyNext), #selector(keyPrev)) }
    @objc private func keyNext() { turn(forward: true) }
    @objc private func keyPrev() { turn(forward: false) }

    /// One page swiped like a book, or two facing pages on a wide screen.
    private func configureMode() {
        let wanted = (appearance?.settings.pages ?? 1) == 2 && view.bounds.width > 760 ? 2 : 1
        guard wanted != span || pdfView.displayMode == .singlePageContinuous else { return }
        let page = currentIndex
        span = wanted
        if span == 2 {
            pdfView.usePageViewController(false)
            pdfView.displayMode = .twoUp
        } else {
            pdfView.displayMode = .singlePage
            pdfView.usePageViewController(true)
        }
        pdfView.autoScales = true
        if let target = doc.page(at: page) { pdfView.go(to: target) }
    }

    private var currentIndex: Int {
        pdfView.currentPage.map { doc.index(for: $0) } ?? 0
    }

    // MARK: - ReaderEngine

    var position: Position? {
        let page = currentIndex
        let chapter = toc.isEmpty ? nil : max(0, toc.lastIndex { $0.page! <= page } ?? 0)
        let lastVisible = min(doc.pageCount, page + span)
        let chapterStart = chapter.map { toc[$0].page! } ?? 0
        let chapterEnd = chapter.map { $0 + 1 < toc.count ? toc[$0 + 1].page! : doc.pageCount } ?? doc.pageCount
        return Position(chapter: chapter, chapterCount: toc.count, page: page + 1, pageCount: doc.pageCount,
                        chapterPage: chapter == nil ? nil : max(1, page - chapterStart + 1),
                        chapterPageCount: chapter == nil ? nil : max(1, chapterEnd - chapterStart),
                        percent: Double(lastVisible) / Double(max(1, doc.pageCount)), locator: Locator(page: page))
    }

    func setAppearance(_ appearance: Appearance) {
        let changed = appearance.settings.pages != self.appearance?.settings.pages
        self.appearance = appearance
        // Dark pages are drawn inverted by the reader screen, so the backdrop is inverted to match.
        pdfView.backgroundColor = appearance.background.dark ? inverted(appearance.background.uiColor) : appearance.background.uiColor
        view.backgroundColor = pdfView.backgroundColor
        if changed { configureMode() }
    }

    func setAnnotations(_ annotations: [Annotation]) {
        for marks in drawn.values {
            for mark in marks { mark.page?.removeAnnotation(mark) }
        }
        drawn = [:]
        for a in annotations where a.kind == .highlight {
            let loc = a.position
            guard let index = loc.page, let page = doc.page(at: index), let range = resolve(a, on: page),
                  let selection = page.selection(for: range) else { continue }
            drawn[a.id] = selection.selectionsByLine().map { line in
                let mark = PDFAnnotation(bounds: line.bounds(for: page), forType: .highlight, withProperties: nil)
                mark.color = highlightColor(a.color).withAlphaComponent(0.4)
                mark.userName = Self.prefix + a.id
                if a.hasNote { mark.contents = a.note }
                page.addAnnotation(mark)
                return mark
            }
        }
    }

    func goTo(_ locator: Locator) {
        guard view.bounds.width > 0 else {
            pendingLocator = locator
            return
        }
        let index = min(max(0, locator.page ?? 0), doc.pageCount - 1)
        if let page = doc.page(at: span == 2 ? index - index % 2 : index) { pdfView.go(to: page) }
        emit()
    }

    func goTo(_ entry: TocEntry) {
        if let page = entry.page { goTo(Locator(page: page)) }
    }

    func turn(forward: Bool) {
        pdfView.clearSelection()
        if forward { pdfView.goToNextPage(nil) } else { pdfView.goToPreviousPage(nil) }
    }

    func isVisible(_ locator: Locator) -> Bool {
        let page = locator.page ?? -1
        return page >= currentIndex && page < currentIndex + span
    }

    func pageOf(_ locator: Locator) -> Int? { (locator.page ?? 0) + 1 }

    func hasReached(_ entry: TocEntry) -> Bool { (entry.page ?? .max) <= (position?.locator.page ?? 0) }

    func clearSelection() { pdfView.clearSelection() }

    func text(of locator: Locator) -> String? {
        guard let index = locator.page, let start = locator.start, let end = locator.end,
              let text = doc.page(at: index)?.string as NSString?, start <= end, end <= text.length else { return nil }
        return normalizedSelection(text.substring(with: NSRange(location: start, length: end - start)))
    }

    // MARK: - Selection and taps

    private func emit() {
        if let position { delegate?.engineChanged(position) }
    }

    private func selectionChanged() {
        guard let selection = pdfView.currentSelection, let page = selection.pages.first, selection.pages.count == 1 else {
            delegate?.engineSelected(nil)
            return
        }
        let range = selection.range(at: 0, on: page)
        let text = normalizedSelection(selection.string ?? "")
        guard range.location != NSNotFound, range.length > 0, !text.isEmpty else {
            delegate?.engineSelected(nil)
            return
        }
        let locator = Locator(page: doc.index(for: page), start: range.location, end: NSMaxRange(range))
        delegate?.engineSelected(TextSelection(locator: locator, text: text))
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: pdfView)
        if let page = pdfView.page(for: point, nearest: false),
           let mark = page.annotation(at: pdfView.convert(point, to: page)),
           let name = mark.userName, name.hasPrefix(Self.prefix) {
            delegate?.engineTappedAnnotation(String(name.dropFirst(Self.prefix.count)))
            return
        }
        if hadSelection {
            pdfView.clearSelection()
            return
        }
        delegate?.engineTapped(atFraction: point.x / max(1, pdfView.bounds.width))
    }

    @objc private func swiped(_ gesture: UISwipeGestureRecognizer) {
        // Two-up pages don't scroll as a book; swipes turn them.
        guard span == 2 else { return }
        turn(forward: gesture.direction == .left)
    }

    /// The range of a highlight on its page. Offsets from another device's PDF text may
    /// differ slightly, so the stored text is looked for when they don't match.
    private func resolve(_ a: Annotation, on page: PDFPage) -> NSRange? {
        guard let text = page.string as NSString?, let start = a.position.start, let end = a.position.end else { return nil }
        let wanted = normalizedSelection(a.text)
        let range = NSRange(location: start, length: end - start)
        if NSMaxRange(range) <= text.length, normalizedSelection(text.substring(with: range)) == wanted { return range }
        guard !wanted.isEmpty else { return nil }
        let pattern = wanted.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "\\s+")
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        return matches.min { abs($0.range.location - start) < abs($1.range.location - start) }?.range
    }

    private func inverted(_ color: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: 1 - r, green: 1 - g, blue: 1 - b, alpha: a)
    }
}

extension PdfController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if g is UITapGestureRecognizer { hadSelection = pdfView.currentSelection?.string?.isEmpty == false }
        return true
    }
}
