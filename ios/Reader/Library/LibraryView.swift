import SwiftUI
import UniformTypeIdentifiers

/// The library's tab and search, kept while a book is open so they're still there on
/// return. The tab is nil until picked, so each launch starts on the default tab.
@MainActor @Observable
final class LibraryFilter {
    static let shared = LibraryFilter()
    var tab: LibraryTab?
    var query = ""
}

struct FolderRoute: Hashable {
    var id: String
}

/// Opens books: full screen here, or in a window of their own on iPad.
@MainActor @Observable
final class BookOpener {
    var open: BookRoute?
    @ObservationIgnored var openWindow: OpenWindowAction?

    struct BookRoute: Identifiable, Hashable {
        var id: String
    }

    static var supportsWindows: Bool { UIApplication.shared.supportsMultipleScenes && UIDevice.current.userInterfaceIdiom == .pad }

    func open(_ book: Book, newWindow: Bool? = nil) {
        if newWindow ?? SyncEngine.shared.library.appSettings.openInNewWindow, Self.supportsWindows, let openWindow {
            openWindow(id: "reader", value: book.id)
        } else {
            open = BookRoute(id: book.id)
        }
    }

    /// Opens a book at a highlight, note or bookmark.
    func open(_ book: Book, at locator: Locator) {
        BookJump.set(book.id, locator)
        open = BookRoute(id: book.id)
    }
}

struct LibraryRoot: View {
    @State private var path: [FolderRoute] = []
    @State private var opener = BookOpener()
    @State private var showSettings = false
    @Namespace private var zoom
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationStack(path: $path) {
            LibraryScreen(folderId: nil, showSettings: $showSettings)
                .navigationDestination(for: FolderRoute.self) { route in
                    LibraryScreen(folderId: route.id, showSettings: $showSettings)
                }
        }
        .environment(opener)
        .environment(\.zoomNamespace, zoom)
        .fullScreenCover(item: $opener.open) { route in
            ReaderView(bookId: route.id) { opener.open = nil }
                .navigationTransition(.zoom(sourceID: route.id, in: zoom))
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear { opener.openWindow = openWindow }
        .background(LibraryShortcuts(showSettings: $showSettings, path: $path))
    }
}

extension EnvironmentValues {
    @Entry var zoomNamespace: Namespace.ID?
}

struct LibraryScreen: View {
    let folderId: String?
    @Binding var showSettings: Bool

    @State private var filter = LibraryFilter.shared
    @State private var importing = false
    @State private var naming = false
    @State private var dropTargeted = false
    @Environment(BookOpener.self) private var opener

    private var library: Library { SyncEngine.shared.library }

    /// Inside a folder there are no tabs: just its books and subfolders.
    private var tab: LibraryTab { folderId != nil ? .books : (filter.tab ?? library.appSettings.defaultTab) }
    private var folder: Folder? { folderId.flatMap { library.folders[$0] } }
    private var query: String { filter.query.trimmingCharacters(in: .whitespaces).lowercased() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                if folderId == nil { TabChips(selection: Binding(get: { tab }, set: { filter.tab = $0 })) }
                content
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: 1400)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle(folder?.name ?? "Library")
        .searchable(text: $filter.query, prompt: "Search")
        .refreshable { await SyncEngine.shared.pull() }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("Book", systemImage: "book") { importing = true }
                    Button("Folder", systemImage: "folder.badge.plus") { naming = true }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                Button("Settings", systemImage: "gearshape") { showSettings = true }
                    .accessibilityIdentifier("library.settings")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: Actions.importTypes, allowsMultipleSelection: true) { result in
            if case let .success(urls) = result { Task { await Actions.importFiles(urls, into: folderId) } }
        }
        .nameAlert("New folder", isPresented: $naming, action: "Create") { Actions.createFolder($0, in: folderId) }
        .onDrop(of: [.item], isTargeted: $dropTargeted) { providers in
            importDropped(providers)
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 24).strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .padding(8).allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder private var content: some View {
        let inScope = scope
        let shown = searched
        let showBooks = tab == .all || tab == .books
        let noBooks = shown.folders.isEmpty && shown.books.isEmpty
        // In All, each kind gets its own section, and a highlight with a note shows only under Notes.
        let kinds: [AnnotationFilter] = tab == .all ? [.plain, .notes, .bookmarks] : tab == .highlights ? [.highlights] : tab == .notes ? [.notes] : tab == .bookmarks ? [.bookmarks] : []
        let groups = kinds.map { ($0, annotationGroups($0, inScope)) }
        let anyNotes = groups.contains { !$0.1.isEmpty }

        if showBooks, folderId == nil, query.isEmpty, let last = lastRead(inScope) {
            ContinueReadingCard(book: last.book, percent: last.percent, at: last.at)
        }

        if showBooks {
            if noBooks {
                if library.ready && !(tab == .all && anyNotes) {
                    EmptyState(text: query.isEmpty ? "Add books with the + button" : "No books match")
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if tab == .all { SectionTitle("Books") }
                    LibraryGrid(folders: shown.folders, books: shown.books)
                }
            }
        }

        ForEach(groups, id: \.0) { kind, list in
            if !list.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    if tab == .all { SectionTitle(kind.title) }
                    AnnotationGroups(groups: list)
                }
            }
        }
        if tab != .all, tab != .books, !anyNotes, library.ready {
            EmptyState(text: query.isEmpty ? "Your \(tab.rawValue) from \(folderId != nil ? "books in this folder" : "your books") show up here" : "Nothing matches")
        }
    }

    // MARK: - What's shown

    /// Whether a book is in this folder or any folder inside it; everything at the top.
    private var scope: (Book) -> Bool {
        guard let folderId else { return { _ in true } }
        let ids = library.descendants(of: folderId)
        return { book in book.folderId.map(ids.contains) ?? false }
    }

    /// With a search: from the top of the library, every matching book and folder anywhere;
    /// inside a folder, only that folder's own books and subfolders.
    private var searched: (folders: [Folder], books: [Book]) {
        let folders = library.childFolders(of: folderId)
        let books = library.books(in: folderId)
        guard !query.isEmpty else { return (folders, books) }
        let matches = { (b: Book) in b.title.lowercased().contains(query) || b.author.lowercased().contains(query) }
        if folderId != nil {
            return (folders.filter { $0.name.lowercased().contains(query) }, books.filter(matches))
        }
        return (library.folders.values.filter { $0.name.lowercased().contains(query) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                library.books.values.filter(matches).sorted { $0.addedAt > $1.addedAt })
    }

    /// The unfinished book read most recently, if any.
    private func lastRead(_ inScope: (Book) -> Bool) -> (book: Book, percent: Double, at: Int64)? {
        var best: (book: Book, percent: Double, at: Int64)?
        for p in library.progress.values {
            guard let book = library.books[p.id], p.percent > 0, p.percent < 0.995, inScope(book) else { continue }
            if best == nil || p.modifiedAt > best!.at { best = (book, p.percent, p.modifiedAt) }
        }
        return best
    }

    /// Highlights, notes and bookmarks grouped by book, most recently touched first.
    private func annotationGroups(_ kind: AnnotationFilter, _ inScope: (Book) -> Bool) -> [AnnotationGroup] {
        var byBook: [String: [Annotation]] = [:]
        for a in library.annotations.values {
            guard let book = library.books[a.bookId], inScope(book), kind.matches(a, query) else { continue }
            byBook[a.bookId, default: []].append(a)
        }
        return byBook.map { id, list in AnnotationGroup(book: library.books[id]!, list: list.sorted { $0.position.sortKey < $1.position.sortKey }) }
            .sorted { ($0.list.map(\.modifiedAt).max() ?? 0) > ($1.list.map(\.modifiedAt).max() ?? 0) }
    }

    // MARK: - Dropped files

    private func importDropped(_ providers: [NSItemProvider]) {
        Task {
            var urls: [URL] = []
            for provider in providers {
                guard let type = provider.registeredContentTypes.first(where: { $0.conforms(to: .data) || $0.conforms(to: .content) }) else { continue }
                let name = provider.suggestedName
                if let url = await copyFile(provider, type: type, name: name) { urls.append(url) }
            }
            await Actions.importFiles(urls, into: folderId)
            urls.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    private func copyFile(_ provider: NSItemProvider, type: UTType, name: String?) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(for: type, openInPlace: false) { url, _, _ in
                guard let url else { return continuation.resume(returning: nil) }
                let fileName = url.pathExtension.isEmpty ? (name ?? url.lastPathComponent) + "." + (type.preferredFilenameExtension ?? "") : url.lastPathComponent
                let copy = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
                try? FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
                let target = copy.appending(path: fileName)
                try? FileManager.default.copyItem(at: url, to: target)
                continuation.resume(returning: target)
            }
        }
    }
}

/// The library's tabs as a row of glass chips.
private struct TabChips: View {
    @Binding var selection: LibraryTab
    @Namespace private var glass

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(LibraryTab.allCases) { tab in
                        let selected = tab == selection
                        Button {
                            withAnimation(.smooth(duration: 0.3)) { selection = tab }
                        } label: {
                            Text(tab.label)
                                .font(.subheadline.weight(selected ? .semibold : .regular))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(selected ? Color.primary : .secondary)
                        .glassEffect(selected ? .regular.tint(.accentColor.opacity(0.18)).interactive() : .regular.interactive(), in: .capsule)
                        .glassEffectID(tab.rawValue, in: glass)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .scrollClipDisabled()
    }
}

struct SectionTitle: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

private struct EmptyState: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 320)
            .transition(.opacity)
    }
}

/// Keyboard shortcuts in the library, for a hardware keyboard.
private struct LibraryShortcuts: View {
    @Binding var showSettings: Bool
    @Binding var path: [FolderRoute]

    var body: some View {
        ZStack {
            Button("Settings") { showSettings = true }.keyboardShortcut(",", modifiers: .command)
            Button("Library") { path = [] }.keyboardShortcut("1", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Asks for a name, as for a new folder or a rename.
    func nameAlert(_ title: String, isPresented: Binding<Bool>, initial: String = "", action: String, onSubmit: @escaping (String) -> Void) -> some View {
        modifier(NameAlert(title: title, isPresented: isPresented, initial: initial, action: action, onSubmit: onSubmit))
    }
}

private struct NameAlert: ViewModifier {
    var title: String
    @Binding var isPresented: Bool
    var initial: String
    var action: String
    var onSubmit: (String) -> Void
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: $isPresented) {
                TextField("Name", text: $name)
                Button("Cancel", role: .cancel) {}
                Button(action) {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { onSubmit(trimmed) }
                }
            }
            .onChange(of: isPresented) { if isPresented { name = initial } }
    }
}
