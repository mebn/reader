import Observation
import SwiftUI

/// Where another device read up to, and how to say so.
struct ContinueOffer: Equatable {
    var locator: Locator
    var label: String
}

/// Where to open a book instead of its saved position, such as a highlight picked from
/// the library's notes. Taken once.
@MainActor
enum BookJump {
    private static var pending: (bookId: String, locator: Locator)?

    static func set(_ bookId: String, _ locator: Locator) { pending = (bookId, locator) }

    static func take(_ bookId: String) -> Locator? {
        guard let jump = pending, jump.bookId == bookId else { return nil }
        pending = nil
        return jump.locator
    }
}

private final class DocumentBox: @unchecked Sendable {
    let document: BookDocument
    init(_ document: BookDocument) { self.document = document }
}

/// One open book: its document, where the reader is, and the reader's own panels.
@MainActor @Observable
final class ReaderModel: ReaderEngineDelegate {
    enum Status: Equatable {
        case loading
        case ready
        case failed(String)
    }

    let bookId: String
    private(set) var status = Status.loading
    private(set) var document: BookDocument?
    private(set) var position: Position?
    var chrome = true
    var selection: TextSelection?
    /// The highlight whose color and note are being edited.
    var editing: String?
    /// Where another device read up to, offered while it's ahead of this one.
    private(set) var offer: ContinueOffer?
    /// Where reading was before going to a highlight, note or bookmark, to get back to. Going
    /// to another one keeps the first place; page turns and contents don't touch it.
    private(set) var returnTo: Locator?
    var focusNote = false
    var showContents = false
    var showAppearance = false
    /// Unsaved appearance changes for this book.
    var draft: ReaderSettings?

    @ObservationIgnored weak var engine: ReaderEngine?
    @ObservationIgnored private var lastSaved = (locator: "", at: Int64(0))
    /// Opened at a highlight or note: only a page turn or a jump makes it the reading position.
    @ObservationIgnored private var holdPosition = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var draftTask: Task<Void, Never>?
    @ObservationIgnored private var chromeTask: Task<Void, Never>?
    @ObservationIgnored var startLocator = Locator()

    private var library: Library { SyncEngine.shared.library }

    init(bookId: String) {
        self.bookId = bookId
    }

    var book: Book? { library.books[bookId] }

    var isFixed: Bool {
        if case .fixed = document { return true }
        return false
    }

    var toc: [TocEntry] { document?.toc ?? [] }

    var annotations: [Annotation] { library.annotations(for: bookId) }

    // MARK: - Loading

    func load() async {
        guard status != .ready, let book, let session = SyncEngine.shared.session else { return }
        status = .loading
        do {
            let file = try await BookFiles.file(for: book, session: session)
            let format = book.format, name = book.fileName
            let box = try await Task.detached(priority: .userInitiated) {
                DocumentBox(try BookDocument.open(file, format: format, fileName: name))
            }.value
            let saved = library.progress[bookId]
            lastSaved = (saved?.locator ?? "", saved?.modifiedAt ?? 0)
            let jump = BookJump.take(bookId)
            holdPosition = jump != nil
            startLocator = jump ?? saved.map { Locator(json: $0.locator) } ?? Locator()
            // Opened at a highlight or note, going back returns to where reading had got to.
            returnTo = jump != nil ? saved.map { Locator(json: $0.locator) } : nil
            document = box.document
            status = .ready
            showChromeBriefly()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: - Appearance

    var savedSettings: (settings: ReaderSettings, hasOverride: Bool) { library.readerSettings(for: bookId) }

    var settings: ReaderSettings { draft ?? savedSettings.settings }

    func background(dark: Bool) -> PageBackground { settings.background(dark: dark) }

    /// Changes this book's settings now and saves them shortly after, so dragging a slider saves once.
    func change(_ edit: (inout ReaderSettings) -> Void) {
        var next = settings
        edit(&next)
        draft = next
        draftTask?.cancel()
        draftTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            saveForBook(next)
            draft = nil
        }
    }

    /// Only what differs from the defaults, so the book keeps following the rest.
    private func saveForBook(_ settings: ReaderSettings) {
        let diff = settingsDiff(settings, from: library.defaultReaderSettings)
        Actions.saveSettings(Scope.book(bookId), diff.isEmpty ? nil : diff)
    }

    func makeDefault() {
        draftTask?.cancel()
        Actions.saveSettings(Scope.reader, settings)
        Actions.saveSettings(Scope.book(bookId), nil)
        draft = nil
    }

    func useDefaults() {
        draftTask?.cancel()
        Actions.saveSettings(Scope.book(bookId), nil)
        draft = nil
    }

    var hasOverride: Bool { savedSettings.hasOverride || draft != nil }

    func setFontSize(_ size: Double) {
        change { $0.fontSize = min(34, max(12, size)) }
    }

    // MARK: - Chrome

    func toggleChrome() {
        chromeTask?.cancel()
        withAnimation(.smooth(duration: 0.25)) { chrome.toggle() }
    }

    private func hideChrome() {
        chromeTask?.cancel()
        guard chrome else { return }
        withAnimation(.smooth(duration: 0.25)) { chrome = false }
    }

    /// Shows the toolbar when a book opens, then gets out of the way.
    private func showChromeBriefly() {
        chrome = true
        chromeTask?.cancel()
        chromeTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled, !showContents, !showAppearance { hideChrome() }
        }
    }

    // MARK: - Navigation

    func turn(forward: Bool) {
        holdPosition = false
        engine?.turn(forward: forward)
    }

    func go(_ locator: Locator) {
        holdPosition = false
        engine?.goTo(locator)
    }

    func go(_ entry: TocEntry) {
        holdPosition = false
        engine?.goTo(entry)
    }

    /// Goes to a highlight, note or bookmark, remembering where reading was.
    func go(toAnnotation locator: Locator) {
        if returnTo == nil { returnTo = position?.locator }
        go(locator)
    }

    func goBack() {
        guard let returnTo else { return }
        self.returnTo = nil
        go(returnTo)
    }

    /// The way back, named by its page while pages are numbered.
    var returnLabel: String? {
        guard let returnTo else { return nil }
        return engine?.pageOf(returnTo).map { "Back to page \($0)" } ?? "Back"
    }

    /// The chapter being read, by the contents' last entry at or before this position.
    var chapterTitle: String? { currentEntry?.label }

    /// The contents entry for where the reader is: the last one at or before this position.
    var currentEntry: TocEntry? {
        guard position != nil, let engine else { return nil }
        return toc.last { engine.hasReached($0) }
    }

    // MARK: - Bookmarks and highlights

    /// A bookmark on the page(s) showing.
    var bookmark: Annotation? {
        guard position != nil, let engine else { return nil }
        return annotations.first { $0.kind == .bookmark && engine.isVisible($0.position) }
    }

    func toggleBookmark() {
        if let bookmark { return Actions.remove(bookmark) }
        guard let position, let book else { return }
        Actions.addAnnotation(bookId: bookId, kind: .bookmark, locator: position.locator,
                              text: position.page.map { "Page \($0)" } ?? "\(Int((position.percent * 100).rounded()))%",
                              label: chapterTitle ?? book.title)
    }

    /// Highlights the selection and opens it to pick a color or write a note, unless a
    /// color was already picked.
    func highlight(_ selection: TextSelection, color: String? = nil, withNote: Bool = false) {
        let created = mergeIntoHighlights(selection, color: color)
            ?? Actions.addAnnotation(bookId: bookId, kind: .highlight, locator: selection.locator, text: selection.text, color: color ?? "yellow")
        engine?.clearSelection()
        self.selection = nil
        if withNote || color == nil {
            focusNote = withNote
            editing = created.id
        }
    }

    /// A selection that overlaps highlights already there grows the newest of them to cover
    /// it all, keeping every note, instead of piling another highlight on top. Nil when
    /// nothing overlaps.
    private func mergeIntoHighlights(_ selection: TextSelection, color: String?) -> Annotation? {
        let new = selection.locator
        guard let start = new.start, let end = new.end else { return nil }
        let overlapping = annotations
            .filter { a in
                let l = a.position
                guard a.kind == .highlight, a.deleted != true, l.chapter == new.chapter, l.page == new.page,
                      let s = l.start, let e = l.end else { return false }
                return s < end && start < e
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
        guard let keep = overlapping.first else { return nil }
        var merged = new
        merged.start = overlapping.compactMap(\.position.start).reduce(start, min)
        merged.end = overlapping.compactMap(\.position.end).reduce(end, max)
        let note = overlapping.map { $0.note.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        Actions.update(keep, note: note, color: color, locator: merged, text: engine?.text(of: merged) ?? selection.text)
        for other in overlapping.dropFirst() { Actions.remove(other) }
        return keep
    }

    // MARK: - Progress

    /// Saves the reading position shortly after it settles.
    private func scheduleSave() {
        guard status == .ready, let position, !holdPosition else { return }
        let locator = position.locator.json
        guard locator != lastSaved.locator else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            Actions.saveProgress(bookId, position.locator, position.percent)
            lastSaved = (locator, now())
        }
    }

    /// Offers to jump when another device reads further while this one is open.
    func remoteProgressChanged() {
        guard let remote = library.progress[bookId], remote.modifiedAt > lastSaved.at + 1000,
              remote.locator != lastSaved.locator, let engine else { return }
        let locator = Locator(json: remote.locator)
        guard !engine.isVisible(locator) else { return }
        lastSaved = (remote.locator, remote.modifiedAt)
        let page = engine.pageOf(locator)
        offer = ContinueOffer(locator: locator, label: page.map { "Continue on page \($0)?" } ?? "Continue at \(Int((remote.percent * 100).rounded()))%?")
    }

    func acceptOffer() {
        guard let offer else { return }
        self.offer = nil
        go(offer.locator)
    }

    // MARK: - ReaderEngineDelegate

    func engineChanged(_ position: Position) {
        // Swiping away from where a jump landed makes reading resume from here.
        if holdPosition, let previous = self.position, previous.locator.chapter != position.locator.chapter || previous.locator.page != position.locator.page || abs((previous.locator.fraction ?? 0) - (position.locator.fraction ?? 0)) > 1e-6 {
            holdPosition = false
        }
        self.position = position
        // Once the offered page is showing, by any route, there's nothing left to offer.
        if let offer, engine?.isVisible(offer.locator) == true { self.offer = nil }
        scheduleSave()
    }

    func engineTapped(atFraction x: CGFloat) {
        if showContents || showAppearance || editing != nil { return }
        if x < 0.3 {
            hideChrome()
            turn(forward: false)
        } else if x > 0.7 {
            hideChrome()
            turn(forward: true)
        } else {
            toggleChrome()
        }
    }

    func engineTappedAnnotation(_ id: String) {
        focusNote = false
        editing = id
    }

    func engineSelected(_ selection: TextSelection?) {
        self.selection = selection
    }

    func engineHighlight(_ selection: TextSelection, withNote: Bool) {
        highlight(selection, withNote: withNote)
    }

    func engineOpen(_ url: URL) {
        UIApplication.shared.open(url)
    }
}
