import SwiftUI

/// An open book: the pages, a glass toolbar that comes and goes, the running header and
/// footer, and the panels for contents, appearance and notes.
struct ReaderView: View {
    let bookId: String
    var onClose: (() -> Void)?

    @State private var model: ReaderModel
    /// Re-renders when the system appearance changes.
    @Environment(\.colorScheme) private var scheme

    init(bookId: String, onClose: (() -> Void)?) {
        self.bookId = bookId
        self.onClose = onClose
        _model = State(initialValue: ReaderModel(bookId: bookId))
    }

    private var library: Library { SyncEngine.shared.library }

    /// Whether the app is dark, from its theme setting. The reader overrides its own color
    /// scheme to match the page, so the environment can't say.
    private var appDark: Bool {
        _ = scheme
        switch library.appSettings.theme {
        case .dark: return true
        case .light: return false
        case .system: return UIScreen.main.traitCollection.userInterfaceStyle == .dark
        }
    }

    var body: some View {
        Group {
            if let book = model.book {
                content(book)
            } else {
                missing
            }
        }
        .task { await model.load() }
    }

    private var missing: some View {
        VStack(spacing: 16) {
            if library.ready {
                Text("This book is no longer in your library.").foregroundStyle(.secondary)
                if let onClose { Button("Close", action: onClose).buttonStyle(.glass) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(_ book: Book) -> some View {
        let background = model.background(dark: appDark)
        let scheme: ColorScheme = background.dark ? .dark : .light
        return ZStack {
            background.color.ignoresSafeArea()

            if let document = model.document {
                EngineView(document: document, model: model, appearance: Appearance(settings: model.settings, background: background), annotations: model.annotations)
                    .ignoresSafeArea()
                    .modifier(InvertedPages(active: model.isFixed && isPdf && background.dark))
                    .opacity(model.position == nil ? 0 : 1)
                    .animation(.easeOut(duration: 0.3), value: model.position == nil)
            }

            RunningHeader(header: header(book), visible: !model.chrome && model.status == .ready, color: background.text)
            RunningFooter(model: model, color: background.text)

            if model.chrome || model.status != .ready {
                ReaderToolbar(model: model, header: header(book), onClose: onClose)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if model.isFixed, let selection = model.selection {
                SelectionBar(model: model, selection: selection)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            switch model.status {
            case .loading:
                ProgressView().controlSize(.large)
            case let .failed(message):
                VStack(spacing: 16) {
                    Text("Couldn't open this book. \(message)")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(background.text.opacity(0.7))
                    if let onClose { Button("Close", action: onClose).buttonStyle(.glass) }
                }
                .padding(32)
            case .ready:
                EmptyView()
            }

            ReaderShortcuts(model: model, onClose: onClose)
        }
        .animation(.smooth(duration: 0.25), value: model.selection != nil)
        .environment(\.colorScheme, scheme)
        .statusBarHidden(!model.chrome)
        .persistentSystemOverlays(model.chrome ? .automatic : .hidden)
        .sheet(isPresented: $model.showContents) {
            ContentsSheet(model: model)
                .presentationDetents([.medium, .large])
                .environment(\.colorScheme, scheme)
        }
        .sheet(isPresented: $model.showAppearance) {
            AppearanceSheet(model: model, appDark: appDark)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .environment(\.colorScheme, scheme)
        }
        .sheet(item: Binding(get: { model.editing.map(EditingID.init) }, set: { model.editing = $0?.id })) { item in
            if let annotation = library.annotations[item.id] {
                AnnotationEditor(annotation: annotation, focusNote: model.focusNote)
                    .presentationDetents([.height(300), .large])
                    .environment(\.colorScheme, scheme)
            }
        }
        .onChange(of: library.progress[bookId]?.modifiedAt) { model.remoteProgressChanged() }
    }

    private var isPdf: Bool { model.book?.format == .pdf }

    private func header(_ book: Book) -> HeaderLine? {
        let s = model.settings
        let parts = [s.headerTitle ? book.title : nil, s.headerAuthor ? book.author : nil, s.headerChapter ? model.chapterTitle : nil]
            .compactMap { $0 }.filter { !$0.isEmpty }
        guard !parts.isEmpty || s.headerClock else { return nil }
        return HeaderLine(parts: parts, clock: s.headerClock)
    }
}

private struct EditingID: Identifiable {
    var id: String
}

/// Dark PDF pages are inverted with their hues kept, as the desktop app does.
private struct InvertedPages: ViewModifier {
    var active: Bool
    func body(content: Content) -> some View {
        if active {
            content.colorInvert().hueRotation(.degrees(180)).brightness(0.04)
        } else {
            content
        }
    }
}

// MARK: - Pages

/// The UIKit view that shows the pages, picked by the book's layout.
private struct EngineView: UIViewControllerRepresentable {
    let document: BookDocument
    let model: ReaderModel
    var appearance: Appearance
    var annotations: [Annotation]

    func makeUIViewController(context: Context) -> UIViewController {
        let controller: UIViewController & ReaderEngine
        switch document {
        case let .reflow(doc):
            let c = ReflowController(doc: doc, bookId: model.bookId)
            c.delegate = model
            controller = c
        case let .fixed(.pdf(doc, _, toc)):
            let c = PdfController(doc: doc, toc: toc)
            c.delegate = model
            controller = c
        case let .fixed(.comic(doc)):
            let c = ComicController(doc: doc)
            c.delegate = model
            controller = c
        }
        model.engine = controller
        controller.setAppearance(appearance)
        controller.setAnnotations(annotations)
        controller.goTo(model.startLocator)
        DispatchQueue.main.async { controller.becomeFirstResponder() }
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard let engine = controller as? ReaderEngine else { return }
        engine.setAppearance(appearance)
        if context.coordinator.annotations != annotations {
            context.coordinator.annotations = annotations
            engine.setAnnotations(annotations)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var annotations: [Annotation] = []
    }
}

// MARK: - Chrome

private struct ReaderToolbar: View {
    let model: ReaderModel
    var header: HeaderLine?
    var onClose: (() -> Void)?

    var body: some View {
        VStack {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    if let onClose {
                        Button(action: onClose) {
                            Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 24, height: 24)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .accessibilityLabel("Close book")
                        .accessibilityIdentifier("reader.close")
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 2) {
                        ToolbarIcon(symbol: "list.bullet", label: "Contents and notes", id: "contents") { model.showContents = true }
                        ToolbarIcon(symbol: model.bookmark != nil ? "bookmark.fill" : "bookmark", label: model.bookmark != nil ? "Remove bookmark" : "Bookmark this page", id: "bookmark") {
                            model.toggleBookmark()
                        }
                        .disabled(model.position == nil)
                        ToolbarIcon(symbol: "textformat.size", label: "Appearance", id: "appearance") { model.showAppearance = true }
                    }
                    .padding(.horizontal, 6)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
            .overlay {
                if let header, model.status == .ready {
                    header
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 150)
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            Spacer()
        }
    }
}

private struct ToolbarIcon: View {
    var symbol: String
    var label: String
    var id: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("reader.\(id)")
    }
}

/// What the header shows: the book, author and chapter, and the time kept current.
private struct HeaderLine: View {
    var parts: [String]
    var clock: Bool

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text((parts + (clock ? [context.date.formatted(date: .omitted, time: .shortened)] : [])).joined(separator: "  ·  "))
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

/// The line above the text once the toolbar hides.
private struct RunningHeader: View {
    var header: HeaderLine?
    var visible: Bool
    var color: Color

    var body: some View {
        VStack {
            if let header {
                header
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(color)
                    .padding(.horizontal, 48)
                    .padding(.top, 14)
                    .opacity(visible ? 0.45 : 0)
                .animation(.easeOut(duration: 0.2), value: visible)
            }
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

/// Whatever the settings ask for, under the text.
private struct RunningFooter: View {
    let model: ReaderModel
    var color: Color

    var body: some View {
        VStack {
            Spacer()
            if let position = model.position {
                Text(parts(position).joined(separator: "  ·  "))
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .opacity(0.45)
                    .padding(.horizontal, 48)
                    .padding(.bottom, 8)
            }
        }
        .allowsHitTesting(false)
    }

    private func parts(_ p: Position) -> [String] {
        let s = model.settings
        var out: [String] = []
        if s.footerChapter, let chapter = model.chapterTitle { out.append(chapter) }
        if s.footerChapterPages, let page = p.chapterPage, let count = p.chapterPageCount { out.append("\(page) / \(count) in chapter") }
        if s.footerBookPages { out.append(p.page.flatMap { page in p.pageCount.map { "\(page) / \($0)" } } ?? "…") }
        if s.footerPercent { out.append("\(Int((p.percent * 100).rounded()))%") }
        return out
    }
}

/// Highlight colors and a note for text selected in a PDF.
private struct SelectionBar: View {
    let model: ReaderModel
    let selection: TextSelection

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 14) {
                ColorDots { model.highlight(selection, color: $0) }
                Divider().frame(height: 22)
                Button("Note") { model.highlight(selection, withNote: true) }
                    .fontWeight(.medium)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular.interactive(), in: .capsule)
            .padding(.bottom, 36)
        }
    }
}

struct ColorDots: View {
    var selected: String?
    var onPick: (String) -> Void

    init(selected: String? = nil, onPick: @escaping (String) -> Void) {
        self.selected = selected
        self.onPick = onPick
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(highlightColors, id: \.name) { name, color in
                Button { onPick(name) } label: {
                    Circle()
                        .fill(Color(uiColor: color))
                        .frame(width: 26, height: 26)
                        .padding(3)
                        .overlay(Circle().strokeBorder(selected == name ? Color.primary.opacity(0.7) : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name.capitalized)
            }
        }
    }
}

/// Keyboard shortcuts while reading, for a hardware keyboard.
private struct ReaderShortcuts: View {
    let model: ReaderModel
    var onClose: (() -> Void)?

    var body: some View {
        ZStack {
            Button("Bookmark") { model.toggleBookmark() }.keyboardShortcut("d", modifiers: .command)
            Button("Contents") { model.showContents.toggle() }.keyboardShortcut("c", modifiers: [])
            Button("Appearance") { model.showAppearance.toggle() }.keyboardShortcut("a", modifiers: [])
            Button("Bookmark page") { model.toggleBookmark() }.keyboardShortcut("b", modifiers: [])
            Button("Larger text") { model.setFontSize(model.settings.fontSize + 1) }.keyboardShortcut("=", modifiers: .command)
            Button("Smaller text") { model.setFontSize(model.settings.fontSize - 1) }.keyboardShortcut("-", modifiers: .command)
            Button("Default text size") { model.setFontSize(ReaderSettings.defaults.fontSize) }.keyboardShortcut("0", modifiers: .command)
            Button("Highlight") { if let s = model.selection { model.highlight(s) } }.keyboardShortcut("h", modifiers: [])
            Button("Note") { if let s = model.selection { model.highlight(s, withNote: true) } }.keyboardShortcut("n", modifiers: [])
            if let onClose { Button("Close book", action: onClose).keyboardShortcut(.escape, modifiers: []) }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
