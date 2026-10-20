import Foundation

enum Format: String, Codable, CaseIterable {
    case epub, pdf, fb2, cbz, txt

    init?(fileName: String) {
        self.init(rawValue: (fileName as NSString).pathExtension.lowercased())
    }
}

/// A signed-in app on the account, as the server lists it.
struct Device: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var platform: String
    var createdAt: Date
    var lastSeenAt: Date
    var current: Bool
    /// Connected for live updates right now.
    var online: Bool
}

enum Collection: String, Codable, CaseIterable {
    case folders, books, progress, annotations, settings
}

/// Every synced record carries a client `modifiedAt` (ms) and a server-assigned `version`.
protocol SyncRecord: Codable, Identifiable, Equatable {
    var id: String { get }
    var modifiedAt: Int64 { get set }
    var version: Int64? { get }
    var deleted: Bool? { get set }
    static var collection: Collection { get }
}

extension SyncRecord {
    var isDeleted: Bool { deleted ?? false }
}

struct Folder: SyncRecord, Hashable {
    static let collection = Collection.folders
    var id: String
    var modifiedAt: Int64
    var version: Int64?
    var deleted: Bool?
    var name: String
    var parentId: String?

    // The server reads a missing parentId as "unchanged", so null is always sent.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encodeIfPresent(version, forKey: .version)
        try c.encode(deleted ?? false, forKey: .deleted)
        try c.encode(name, forKey: .name)
        try c.encode(parentId, forKey: .parentId)
    }
}

struct Book: SyncRecord, Hashable {
    static let collection = Collection.books
    var id: String
    var modifiedAt: Int64
    var version: Int64?
    var deleted: Bool?
    var folderId: String?
    var title: String
    var author: String
    var format: Format
    var fileName: String
    var size: Int64
    var hash: String
    var hasCover: Bool
    var addedAt: Int64

    // folderId is always sent; null moves the book to the root.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encodeIfPresent(version, forKey: .version)
        try c.encode(deleted ?? false, forKey: .deleted)
        try c.encode(folderId, forKey: .folderId)
        try c.encode(title, forKey: .title)
        try c.encode(author, forKey: .author)
        try c.encode(format, forKey: .format)
        try c.encode(fileName, forKey: .fileName)
        try c.encode(size, forKey: .size)
        try c.encode(hash, forKey: .hash)
        try c.encode(hasCover, forKey: .hasCover)
        try c.encode(addedAt, forKey: .addedAt)
    }
}

/// Progress uses the book ID as its ID. `locator` is a serialized ``Locator``.
struct Progress: SyncRecord {
    static let collection = Collection.progress
    var id: String
    var modifiedAt: Int64
    var version: Int64?
    var deleted: Bool?
    var locator: String
    var percent: Double
}

enum AnnotationKind: String, Codable {
    case highlight, bookmark
}

struct Annotation: SyncRecord, Hashable {
    static let collection = Collection.annotations
    var id: String
    var modifiedAt: Int64
    var version: Int64?
    var deleted: Bool?
    var bookId: String
    var kind: AnnotationKind
    var locator: String
    var text: String
    var note: String
    var color: String
    var label: String

    var position: Locator { Locator(json: locator) }
    var hasNote: Bool { !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Settings use their scope as ID: "app", "reader" or "reader:<bookId>".
struct Setting: SyncRecord {
    static let collection = Collection.settings
    var id: String
    var modifiedAt: Int64
    var version: Int64?
    var deleted: Bool?
    var data: String
}

struct Changes: Decodable {
    var version: Int64
    var folders: [Folder]?
    var books: [Book]?
    var progress: [Progress]?
    var annotations: [Annotation]?
    var settings: [Setting]?
}

struct User: Codable {
    var id: String
    var email: String
}

/// A position in a book. Reflowable books use chapter + fraction so positions survive
/// font and window changes; fixed layouts use the page. Text ranges add character offsets,
/// counted the way the desktop app's DOM counts them.
struct Locator: Codable, Equatable, Hashable {
    var chapter: Int?
    var fraction: Double?
    var page: Int?
    var start: Int?
    var end: Int?

    init(chapter: Int? = nil, fraction: Double? = nil, page: Int? = nil, start: Int? = nil, end: Int? = nil) {
        self.chapter = chapter
        self.fraction = fraction
        self.page = page
        self.start = start
        self.end = end
    }

    init(json: String) {
        self = (try? JSONDecoder().decode(Locator.self, from: Data(json.utf8))) ?? Locator()
    }

    var json: String {
        String(decoding: (try? JSONEncoder().encode(self)) ?? Data("{}".utf8), as: UTF8.self)
    }

    /// Orders annotations by where they are in the book.
    var sortKey: Double {
        Double(chapter ?? page ?? 0) * 1e7 + (start.map(Double.init) ?? (fraction ?? 0) * 1e6)
    }
}

func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
