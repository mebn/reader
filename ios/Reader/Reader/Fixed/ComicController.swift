import UIKit

/// Shows comic pages (CBZ) one or two at a time, swiped like a book.
final class ComicController: UIViewController, ReaderEngine {
    weak var delegate: ReaderEngineDelegate?

    private let doc: ComicDocument
    private let pager = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: [.interPageSpacing: 0])
    private var appearance: Appearance?
    private var page = 0
    private var span = 1
    private var pendingLocator: Locator?

    init(doc: ComicDocument) {
        self.doc = doc
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
        view.addGestureRecognizer(tap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let wanted = (appearance?.settings.pages ?? 1) == 2 && view.bounds.width > 760 ? 2 : 1
        if wanted != span || pager.viewControllers?.isEmpty != false {
            span = wanted
            goTo(pendingLocator ?? Locator(page: page))
            pendingLocator = nil
        }
    }

    override var canBecomeFirstResponder: Bool { true }
    override var keyCommands: [UIKeyCommand]? { PageKeys.commands(#selector(keyNext), #selector(keyPrev)) }
    @objc private func keyNext() { turn(forward: true) }
    @objc private func keyPrev() { turn(forward: false) }

    var position: Position? {
        let lastVisible = min(doc.pages.count, page + span)
        return Position(chapter: nil, chapterCount: 0, page: page + 1, pageCount: doc.pages.count, chapterPage: nil, chapterPageCount: nil,
                        percent: Double(lastVisible) / Double(max(1, doc.pages.count)), locator: Locator(page: page))
    }

    func setAppearance(_ appearance: Appearance) {
        self.appearance = appearance
        view.backgroundColor = appearance.background.uiColor
        for case let controller as ComicPageController in pager.viewControllers ?? [] {
            controller.view.backgroundColor = appearance.background.uiColor
        }
        view.setNeedsLayout()
    }

    func setAnnotations(_ annotations: [Annotation]) {}

    func goTo(_ locator: Locator) {
        guard view.bounds.width > 0 else {
            pendingLocator = locator
            return
        }
        page = align(locator.page ?? 0)
        pager.setViewControllers([controller(page)], direction: .forward, animated: false)
        emit()
    }

    func goTo(_ entry: TocEntry) {
        if let page = entry.page { goTo(Locator(page: page)) }
    }

    func turn(forward: Bool) {
        let next = forward ? page + span : page - span
        guard next >= 0, next < doc.pages.count else { return }
        page = align(next)
        pager.setViewControllers([controller(page)], direction: forward ? .forward : .reverse, animated: true)
        emit()
    }

    func isVisible(_ locator: Locator) -> Bool {
        let target = locator.page ?? -1
        return target >= page && target < page + span
    }

    func pageOf(_ locator: Locator) -> Int? { (locator.page ?? 0) + 1 }

    func hasReached(_ entry: TocEntry) -> Bool { (entry.page ?? .max) <= (position?.locator.page ?? 0) }
    func clearSelection() {}

    func text(of locator: Locator) -> String? { nil }

    private func align(_ index: Int) -> Int {
        let clamped = min(max(0, index), max(0, doc.pages.count - 1))
        return span == 2 ? clamped - clamped % 2 : clamped
    }

    private func controller(_ index: Int) -> ComicPageController {
        let controller = ComicPageController(doc: doc, index: index, span: span)
        controller.view.backgroundColor = appearance?.background.uiColor
        return controller
    }

    private func emit() {
        if let position { delegate?.engineChanged(position) }
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        delegate?.engineTapped(atFraction: gesture.location(in: view).x / max(1, view.bounds.width))
    }
}

extension ComicController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
        guard let index = (vc as? ComicPageController)?.index, index + span < doc.pages.count else { return nil }
        return controller(index + span)
    }

    func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
        guard let index = (vc as? ComicPageController)?.index, index > 0 else { return nil }
        return controller(max(0, index - span))
    }

    func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let index = (pvc.viewControllers?.first as? ComicPageController)?.index else { return }
        page = index
        emit()
    }
}

private final class ComicPageController: UIViewController {
    let index: Int
    private let doc: ComicDocument
    private let span: Int

    init(doc: ComicDocument, index: Int, span: Int) {
        self.doc = doc
        self.index = index
        self.span = span
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: guide.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -28),
        ])
        for i in index..<min(index + span, doc.pages.count) {
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFit
            stack.addArrangedSubview(imageView)
            let doc = self.doc
            Task.detached(priority: .userInitiated) {
                let image = doc.image(i)
                await MainActor.run { imageView.image = image }
            }
        }
    }
}
