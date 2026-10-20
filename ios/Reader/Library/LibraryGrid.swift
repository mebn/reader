import SwiftUI

/// Folders, then books, as a grid of covers.
struct LibraryGrid: View {
    var folders: [Folder]
    var books: [Book]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 180), spacing: 18, alignment: .top)], alignment: .leading, spacing: 26) {
            ForEach(folders) { FolderCard(folder: $0) }
            ForEach(books) { BookCard(book: $0) }
        }
    }
}

struct BookCard: View {
    let book: Book
    @State private var renaming = false
    @State private var deleting = false
    @Environment(BookOpener.self) private var opener
    @Environment(\.zoomNamespace) private var zoom

    private var percent: Double { SyncEngine.shared.library.progress[book.id]?.percent ?? 0 }

    var body: some View {
        Button { opener.open(book) } label: {
            VStack(alignment: .leading, spacing: 0) {
                cover
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                Text(book.title)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .padding(.top, 10)
                Text("\(Int((percent * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .draggable("book:\(book.id)") {
            BookCover(book: book).frame(width: 80)
        }
        .contextMenu {
            Button("Open", systemImage: "book") { opener.open(book, newWindow: false) }
            if BookOpener.supportsWindows {
                Button("Open in New Window", systemImage: "macwindow.badge.plus") { opener.open(book, newWindow: true) }
            }
            Divider()
            Button("Rename", systemImage: "pencil") { renaming = true }
            MoveToMenu(current: book.folderId) { Actions.move(book, to: $0) }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { deleting = true }
        } preview: {
            BookDetails(book: book)
        }
        .nameAlert("Rename book", isPresented: $renaming, initial: book.title, action: "Save") { Actions.rename(book, to: $0) }
        .alert("Delete “\(book.title)”?", isPresented: $deleting) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Actions.delete(book) }
        } message: {
            Text("It will be removed from all your devices, with its notes and highlights.")
        }
    }

    @ViewBuilder private var cover: some View {
        if let zoom {
            BookCover(book: book).matchedTransitionSource(id: book.id, in: zoom)
        } else {
            BookCover(book: book)
        }
    }
}

/// Up to three covers fanned out like a small stack.
struct FolderCard: View {
    let folder: Folder
    @State private var renaming = false
    @State private var deleting = false
    @State private var targeted = false

    private static let fan: [(rotate: Double, x: CGFloat)] = [(-7, -0.14), (6, 0.14), (0, 0)]

    private var books: [Book] { SyncEngine.shared.library.books(in: folder.id) }

    var body: some View {
        let books = self.books
        let stack = Array(books.prefix(3).reversed())
        NavigationLink(value: FolderRoute(id: folder.id)) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .overlay {
                        GeometryReader { geo in
                            ZStack {
                                ForEach(Array(stack.enumerated()), id: \.element.id) { i, book in
                                    let fan = Self.fan[Self.fan.count - stack.count + i]
                                    BookCover(book: book, cornerRadius: 4)
                                        .frame(width: geo.size.width * 0.52)
                                        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                                        .rotationEffect(.degrees(fan.rotate))
                                        .offset(x: geo.size.width * 0.52 * fan.x)
                                }
                                if stack.isEmpty {
                                    Image(systemName: "folder").font(.largeTitle).foregroundStyle(.tertiary)
                                }
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
                    .background(.fill.tertiary, in: .rect(cornerRadius: 10))
                    .glassEffect(targeted ? .regular.tint(.accentColor.opacity(0.25)) : .identity, in: .rect(cornerRadius: 10))
                    .scaleEffect(targeted ? 1.04 : 1)
                    .animation(.spring(duration: 0.3), value: targeted)
                Text(folder.name)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .padding(.top, 10)
                Text("\(books.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .draggable("folder:\(folder.id)")
        .dropDestination(for: String.self) { items, _ in
            items.map { Actions.drop($0, into: folder.id) }.contains(true)
        } isTargeted: { targeted = $0 }
        .contextMenu {
            Button("Rename", systemImage: "pencil") { renaming = true }
            MoveToMenu(current: folder.parentId, exclude: folder.id) { Actions.move(folder, to: $0) }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { deleting = true }
        }
        .nameAlert("Rename folder", isPresented: $renaming, initial: folder.name, action: "Save") { Actions.rename(folder, to: $0) }
        .alert("Delete “\(folder.name)”?", isPresented: $deleting) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Actions.delete(folder) }
        } message: {
            Text("Books inside are kept and moved up one level.")
        }
    }
}

/// Every folder as a place to move something to.
struct MoveToMenu: View {
    var current: String?
    var exclude: String?
    var onMove: (String?) -> Void

    var body: some View {
        Menu("Move to", systemImage: "folder") {
            Button("Library") { onMove(nil) }.disabled(current == nil)
            ForEach(SyncEngine.shared.library.folderTree(excluding: exclude), id: \.folder.id) { folder, depth in
                Button(String(repeating: "    ", count: depth) + folder.name) { onMove(folder.id) }
                    .disabled(folder.id == current)
            }
        }
    }
}

/// A wide card for picking up where you left off, on a soft wash of the book's own cover.
struct ContinueReadingCard: View {
    let book: Book
    let percent: Double
    let at: Int64
    @Environment(BookOpener.self) private var opener
    @Environment(\.zoomNamespace) private var zoom
    @State private var image: UIImage?

    var body: some View {
        Button { opener.open(book) } label: {
            HStack(spacing: 24) {
                cover
                    .frame(width: 96)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                VStack(alignment: .leading, spacing: 6) {
                    Text("CONTINUE READING")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.6)
                        .foregroundStyle(.secondary)
                    Text(book.title)
                        .font(.custom("Literata", size: 24, relativeTo: .title2).weight(.medium))
                        .lineLimit(2)
                    if !book.author.isEmpty {
                        Text(book.author).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    HStack(spacing: 10) {
                        ProgressView(value: percent).tint(.primary.opacity(0.7))
                        Text("\(Int((percent * 100).rounded()))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 320)
                    .padding(.top, 8)
                    Text("Last read \(formatWhen(at))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(22)
            .background {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().blur(radius: 40).saturation(1.5).opacity(0.55)
                }
            }
            .clipShape(.rect(cornerRadius: 28))
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 28))
            .contentShape(.rect(cornerRadius: 28))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue reading \(book.title)")
        .contextMenu {
            Button("Open", systemImage: "book") { opener.open(book, newWindow: false) }
            if BookOpener.supportsWindows {
                Button("Open in New Window", systemImage: "macwindow.badge.plus") { opener.open(book, newWindow: true) }
            }
        }
        .task(id: book.id) { image = await Covers.shared.load(book) }
    }

    @ViewBuilder private var cover: some View {
        if let zoom {
            BookCover(book: book).matchedTransitionSource(id: book.id, in: zoom)
        } else {
            BookCover(book: book)
        }
    }
}

/// Everything known about a book, shown when it's pressed and held.
struct BookDetails: View {
    let book: Book

    var body: some View {
        let library = SyncEngine.shared.library
        let progress = library.progress[book.id]
        let mine = library.annotations(for: book.id)
        let counts = [
            (mine.filter { $0.kind == .highlight }.count, "highlight"),
            (mine.filter { $0.kind == .highlight && $0.hasNote }.count, "note"),
            (mine.filter { $0.kind == .bookmark }.count, "bookmark"),
        ].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }
        let percent = Int(((progress?.percent ?? 0) * 100).rounded())

        HStack(alignment: .top, spacing: 18) {
            BookCover(book: book).frame(width: 110)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title).font(.headline)
                    if !book.author.isEmpty { Text(book.author).font(.subheadline).foregroundStyle(.secondary) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(percent == 0 ? "Not started" : percent >= 100 ? "Finished" : "\(percent)% read")
                        Spacer()
                        if let progress, percent > 0 { Text(formatWhen(progress.modifiedAt)) }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    ProgressView(value: Double(percent) / 100).tint(.primary.opacity(0.7))
                }
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                    if !counts.isEmpty { row("Notes", counts.joined(separator: " · ")) }
                    if let folder = book.folderId.flatMap({ library.folders[$0] }) { row("Folder", folder.name) }
                    row("Format", "\(book.format.rawValue.uppercased()) · \(formatSize(book.size))")
                    row("Added", Date(timeIntervalSince1970: Double(book.addedAt) / 1000).formatted(date: .abbreviated, time: .omitted))
                }
                .font(.caption)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).lineLimit(1)
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        bytes < 1024 * 1024 ? "\(max(1, Int((Double(bytes) / 1024).rounded()))) KB" : String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}

/// "today", "yesterday", "3 days ago", then a date.
func formatWhen(_ at: Int64) -> String {
    let date = Date(timeIntervalSince1970: Double(at) / 1000)
    let calendar = Calendar.current
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: date)).day ?? 0
    if days > -7 {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(from: DateComponents(day: days))
    }
    return date.formatted(date: .abbreviated, time: .omitted)
}
