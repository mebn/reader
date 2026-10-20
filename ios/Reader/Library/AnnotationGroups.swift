import SwiftUI

/// "plain" is highlights without a note, for when notes are listed on their own.
enum AnnotationFilter: Hashable {
    case highlights, plain, notes, bookmarks

    var title: String {
        switch self {
        case .highlights, .plain: "Highlights"
        case .notes: "Notes"
        case .bookmarks: "Bookmarks"
        }
    }

    func matches(_ a: Annotation, _ query: String) -> Bool {
        switch self {
        case .highlights where a.kind != .highlight: return false
        case .plain where a.kind != .highlight || a.hasNote: return false
        case .notes where !a.hasNote: return false
        case .bookmarks where a.kind != .bookmark: return false
        default: break
        }
        return query.isEmpty || [a.text, a.note, a.label].contains { $0.lowercased().contains(query) }
    }
}

struct AnnotationGroup: Identifiable {
    var book: Book
    var list: [Annotation]
    var id: String { book.id }
}

/// Highlights, notes and bookmarks grouped by book; picking one opens the book there.
struct AnnotationGroups: View {
    var groups: [AnnotationGroup]
    @Environment(BookOpener.self) private var opener

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 32) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        BookCover(book: group.book, cornerRadius: 3).frame(width: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(group.book.title).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text((group.book.author.isEmpty ? "" : "\(group.book.author) · ") + "\(group.list.count) \(group.list.count == 1 ? "item" : "items")")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .padding(.bottom, 4)

                    ForEach(group.list) { a in
                        Button { opener.open(group.book, at: a.position) } label: {
                            AnnotationRow(annotation: a)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(.fill.quinary, in: .rect(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Open", systemImage: "book") { opener.open(group.book, at: a.position) }
                            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = a.kind == .bookmark ? a.label : a.text }
                            Button("Remove", systemImage: "trash", role: .destructive) { Actions.remove(a) }
                        }
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
            }
        }
    }
}
