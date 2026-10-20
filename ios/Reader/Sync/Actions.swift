import UIKit
import UniformTypeIdentifiers

/// Changes to the library, applied locally and synced.
@MainActor
enum Actions {
    private static var sync: SyncEngine { .shared }
    private static var library: Library { sync.library }

    // MARK: Folders

    @discardableResult
    static func createFolder(_ name: String, in parentId: String?) -> Folder {
        sync.put(Folder(id: UUID().uuidString.lowercased(), modifiedAt: 0, name: name, parentId: parentId))
    }

    static func rename(_ folder: Folder, to name: String) {
        var f = folder
        f.name = name
        sync.put(f)
    }

    static func move(_ folder: Folder, to parentId: String?) {
        guard folder.id != parentId, !(parentId.map { library.descendants(of: folder.id).contains($0) } ?? false) else { return }
        var f = folder
        f.parentId = parentId
        sync.put(f)
    }

    static func delete(_ folder: Folder) {
        sync.deleteFolder(folder.id)
    }

    // MARK: Books

    static func rename(_ book: Book, to title: String) {
        var b = book
        b.title = title
        sync.put(b)
    }

    static func move(_ book: Book, to folderId: String?) {
        var b = book
        b.folderId = folderId
        sync.put(b)
    }

    static func delete(_ book: Book) {
        var b = book
        b.deleted = true
        sync.put(b)
        BookFiles.remove(book.id)
    }

    /// Moves a dragged book or folder ("book:<id>" / "folder:<id>") into a folder.
    static func drop(_ item: String, into folderId: String?) -> Bool {
        let parts = item.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        if parts[0] == "book", let book = library.books[parts[1]], book.folderId != folderId {
            move(book, to: folderId)
            return true
        }
        if parts[0] == "folder", let folder = library.folders[parts[1]], folder.id != folderId, folder.parentId != folderId {
            move(folder, to: folderId)
            return true
        }
        return false
    }

    // MARK: Reading

    static func saveProgress(_ bookId: String, _ locator: Locator, _ percent: Double) {
        let existing = library.progress[bookId]
        sync.put(Progress(id: bookId, modifiedAt: existing?.modifiedAt ?? 0, locator: locator.json, percent: percent))
    }

    @discardableResult
    static func addAnnotation(bookId: String, kind: AnnotationKind, locator: Locator, text: String, note: String = "", color: String = "", label: String = "") -> Annotation {
        sync.put(Annotation(id: UUID().uuidString.lowercased(), modifiedAt: 0, bookId: bookId, kind: kind, locator: locator.json, text: text, note: note, color: color, label: label))
    }

    static func update(_ annotation: Annotation, note: String? = nil, color: String? = nil) {
        var a = annotation
        if let note { a.note = note }
        if let color { a.color = color }
        sync.put(a)
    }

    static func remove(_ annotation: Annotation) {
        var a = annotation
        a.deleted = true
        sync.put(a)
    }

    // MARK: Settings

    static func saveSettings(_ scope: String, _ object: [String: Any]?) {
        let existing = library.settings[scope]
        let data = object.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: .sortedKeys) }.map { String(decoding: $0, as: UTF8.self) } ?? ""
        sync.put(Setting(id: scope, modifiedAt: existing?.modifiedAt ?? 0, deleted: object == nil, data: data))
    }

    static func saveSettings<T: Codable>(_ scope: String, _ settings: T) {
        let object = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(settings))) as? [String: Any]
        saveSettings(scope, object)
    }

    static func setApp(_ change: (inout AppSettings) -> Void) {
        var app = library.appSettings
        change(&app)
        // Keys this app doesn't know stay as they were.
        var object = settingsObject(library.settings[Scope.app]?.data)
        for (k, v) in (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(app))) as? [String: Any] ?? [:] { object[k] = v }
        saveSettings(Scope.app, object)
    }

    // MARK: Import

    static let importTypes: [UTType] = [.epub, .pdf, .plainText, UTType("org.gribuser.fb2") ?? .xml, UTType("com.reader.cbz") ?? .zip]
    private static let coverWidth: CGFloat = 600

    /// Parses, uploads and adds books. Unsupported files are skipped with a notice.
    static func importFiles(_ urls: [URL], into folderId: String?) async {
        guard let session = sync.session else { return }
        let supported = urls.filter { Format(fileName: $0.lastPathComponent) != nil }
        let skipped = urls.count - supported.count
        if skipped > 0 { Toasts.shared.show("\(skipped) file\(skipped > 1 ? "s" : "") skipped", detail: "Supported: EPUB, PDF, FB2, CBZ, TXT") }
        guard !supported.isEmpty else { return }

        Toasts.shared.show(supported.count > 1 ? "Adding \(supported.count) books" : "Adding \(supported[0].lastPathComponent)", progress: true)
        var added = 0
        for url in supported {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let fileName = url.lastPathComponent
                let format = Format(fileName: fileName)!
                // Parsed off the main thread; large books take a moment.
                let local = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)-\(fileName)")
                try FileManager.default.copyItem(at: url, to: local)
                defer { try? FileManager.default.removeItem(at: local) }
                let info = try await Task.detached(priority: .userInitiated) { () -> (BookMetadata, Data?) in
                    let doc = try BookDocument.open(local, format: format, fileName: fileName)
                    return (doc.metadata, doc.cover().map { shrink($0) })
                }.value
                let size = (try? FileManager.default.attributesOfItem(atPath: local.path)[.size] as? Int64) ?? 0
                let time = now()
                let book = Book(id: UUID().uuidString.lowercased(), modifiedAt: time, folderId: folderId,
                                title: info.0.title.isEmpty ? fileName : info.0.title, author: info.0.author, format: format,
                                fileName: fileName, size: size, hash: "", hasCover: info.1 != nil, addedAt: time)
                let saved = try await API.uploadBook(session, book: book, file: local, cover: info.1)
                BookFiles.store(local, for: saved)
                sync.received(saved)
                added += 1
            } catch {
                Toasts.shared.show("Couldn't add \(url.lastPathComponent)", detail: error.localizedDescription, error: true)
            }
        }
        if added > 0 { Toasts.shared.show(added > 1 ? "Added \(added) books" : "Book added") }
    }

    nonisolated private static func shrink(_ data: Data) -> Data {
        guard let image = UIImage(data: data), image.size.width > coverWidth else { return data }
        let size = CGSize(width: coverWidth, height: (image.size.height / image.size.width * coverWidth).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.86) ?? data
    }
}

/// Book files, downloaded once and kept on the device.
enum BookFiles {
    private static var directory: URL {
        let dir = URL.cachesDirectory.appending(path: "books", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for book: Book) -> URL {
        directory.appending(path: "\(book.id).\(book.format.rawValue)")
    }

    static func store(_ file: URL, for book: Book) {
        try? FileManager.default.copyItem(at: file, to: url(for: book))
    }

    static func remove(_ id: String) {
        for format in Format.allCases { try? FileManager.default.removeItem(at: directory.appending(path: "\(id).\(format.rawValue)")) }
    }

    /// The book's file on this device, downloading it if needed.
    static func file(for book: Book, session: Session) async throws -> URL {
        let target = url(for: book)
        if FileManager.default.fileExists(atPath: target.path) { return target }
        var req = URLRequest(url: API.bookFileURL(session, id: book.id))
        req.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        let (temp, response) = try await URLSession.shared.download(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw APIError(message: status == 404 ? "The file is missing on the server." : "Couldn't download the book.", status: status) }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temp, to: target)
        return target
    }
}
