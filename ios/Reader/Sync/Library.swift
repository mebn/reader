import Foundation
import Observation

/// Everything synced for the signed-in account. Records merge by last-write-wins and
/// tombstones remove entries.
@MainActor @Observable
final class Library {
    var folders: [String: Folder] = [:]
    var books: [String: Book] = [:]
    var progress: [String: Progress] = [:]
    var annotations: [String: Annotation] = [:]
    var settings: [String: Setting] = [:]
    /// Server version of the last applied pull.
    var version: Int64 = 0
    var ready = false

    /// Bumped on every change, so the snapshot is written after edits.
    @ObservationIgnored var onChange: (() -> Void)?

    func merge<T: SyncRecord>(_ records: [T]) {
        guard !records.isEmpty else { return }
        switch T.self {
        case is Folder.Type: Self.merge(&folders, records as! [Folder])
        case is Book.Type: Self.merge(&books, records as! [Book])
        case is Progress.Type: Self.merge(&progress, records as! [Progress])
        case is Annotation.Type: Self.merge(&annotations, records as! [Annotation])
        case is Setting.Type: Self.merge(&settings, records as! [Setting])
        default: break
        }
        onChange?()
    }

    func apply(_ changes: Changes) {
        Self.merge(&folders, changes.folders ?? [])
        Self.merge(&books, changes.books ?? [])
        Self.merge(&progress, changes.progress ?? [])
        Self.merge(&annotations, changes.annotations ?? [])
        Self.merge(&settings, changes.settings ?? [])
        version = max(version, changes.version)
        ready = true
        onChange?()
    }

    func reset(_ snapshot: Snapshot? = nil) {
        folders = snapshot?.folders ?? [:]
        books = snapshot?.books ?? [:]
        progress = snapshot?.progress ?? [:]
        annotations = snapshot?.annotations ?? [:]
        settings = snapshot?.settings ?? [:]
        version = snapshot?.version ?? 0
        ready = snapshot != nil
    }

    var snapshot: Snapshot {
        Snapshot(folders: folders, books: books, progress: progress, annotations: annotations, settings: settings, version: version)
    }

    private static func merge<T: SyncRecord>(_ table: inout [String: T], _ records: [T]) {
        for record in records {
            if let existing = table[record.id], existing.modifiedAt > record.modifiedAt { continue }
            if record.isDeleted { table[record.id] = nil } else if table[record.id] != record { table[record.id] = record }
        }
    }

    struct Snapshot: Codable {
        var folders: [String: Folder]
        var books: [String: Book]
        var progress: [String: Progress]
        var annotations: [String: Annotation]
        var settings: [String: Setting]
        var version: Int64
    }

    // MARK: - Settings

    var appSettings: AppSettings {
        decodeSettings(settingsObject(settings[Scope.app]?.data), over: AppSettings())
    }

    /// Reader defaults for every book.
    var defaultReaderSettings: ReaderSettings {
        decodeSettings(settingsObject(settings[Scope.reader]?.data), over: ReaderSettings.defaults)
    }

    /// Effective settings for a book: defaults, then the book's own overrides.
    func readerSettings(for bookId: String) -> (settings: ReaderSettings, hasOverride: Bool) {
        let override = settingsObject(settings[Scope.book(bookId)]?.data).filter { k, _ in ReaderSettings.keys.contains(k) }
        return (decodeSettings(override, over: defaultReaderSettings), !override.isEmpty)
    }

    // MARK: - Views of the library

    func folderPath(_ folderId: String?) -> [Folder] {
        var path: [Folder] = []
        var current = folderId.flatMap { folders[$0] }
        while let f = current, path.count < 32 {
            path.insert(f, at: 0)
            current = f.parentId.flatMap { folders[$0] }
        }
        return path
    }

    func childFolders(of parent: String?) -> [Folder] {
        folders.values.filter { $0.parentId == parent }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func books(in folderId: String?) -> [Book] {
        books.values.filter { $0.folderId == folderId }.sorted { $0.addedAt > $1.addedAt }
    }

    /// A folder and every folder inside it.
    func descendants(of folderId: String) -> Set<String> {
        var ids: Set<String> = [folderId]
        var grew = true
        while grew {
            grew = false
            for f in folders.values where f.parentId.map(ids.contains) == true && !ids.contains(f.id) {
                ids.insert(f.id)
                grew = true
            }
        }
        return ids
    }

    /// Folders as an indented tree, skipping `exclude` and its descendants.
    func folderTree(excluding exclude: String? = nil) -> [(folder: Folder, depth: Int)] {
        var out: [(Folder, Int)] = []
        func walk(_ parent: String?, _ depth: Int) {
            for f in childFolders(of: parent) where f.id != exclude {
                out.append((f, depth))
                walk(f.id, depth + 1)
            }
        }
        walk(nil, 0)
        return out
    }

    func annotations(for bookId: String) -> [Annotation] {
        annotations.values.filter { $0.bookId == bookId }
    }
}
