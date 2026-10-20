import Foundation
import Network
import Observation

/// One write waiting for the server, kept on disk until it's accepted.
private enum Op: Codable, Equatable {
    case put(collection: Collection, id: String, record: Data)
    case deleteFolder(id: String)

    func replaces(_ other: Op) -> Bool {
        if case let .put(c1, id1, _) = self, case let .put(c2, id2, _) = other { return c1 == c2 && id1 == id2 }
        return false
    }
}

/// Keeps the local library in sync with the server: writes are applied locally first and
/// queued in a persistent outbox, and other devices are heard through the server's event
/// stream, which triggers an incremental pull.
@MainActor @Observable
final class SyncEngine {
    static let shared = SyncEngine()

    let library = Library()
    private(set) var session: Session?
    /// True while the event stream is connected.
    private(set) var live = false

    @ObservationIgnored private var outbox: [Op] = []
    @ObservationIgnored private var flushing = false
    @ObservationIgnored private var pulling = false
    @ObservationIgnored private var pullAgain = false
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let monitor = NWPathMonitor()
    /// Called when the server no longer accepts this device's token.
    @ObservationIgnored var onSignedOut: (() -> Void)?

    private static let retryDelay: Duration = .seconds(5)
    private static let pollInterval: Duration = .seconds(60)

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.wake() }
        }
        monitor.start(queue: .main)
    }

    func start(_ session: Session) {
        stop()
        self.session = session
        library.reset(read(Library.Snapshot.self, "snapshot"))
        outbox = read([Op].self, "outbox") ?? []
        library.onChange = { [weak self] in self?.scheduleSave() }

        tasks.append(Task { [weak self] in await self?.listen() })
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                await self?.pull()
            }
        })
        Task { await pull() }
        flush()
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
        retryTask?.cancel()
        if session != nil { writeSnapshot() }
        library.onChange = nil
        session = nil
        live = false
    }

    /// Back in the foreground or online again: catch up both ways.
    func wake() {
        guard session != nil else { return }
        flush()
        Task { await pull() }
    }

    // MARK: - Writes

    /// Saves a record locally and queues it for the server.
    @discardableResult
    func put<T: SyncRecord>(_ record: T) -> T {
        var stamped = record
        stamped.modifiedAt = max(now(), record.modifiedAt + 1)
        library.merge([stamped])
        if let data = try? JSONEncoder().encode(stamped) {
            enqueue(.put(collection: T.collection, id: stamped.id, record: data))
        }
        return stamped
    }

    /// Deletes a folder; its books and subfolders move up one level.
    func deleteFolder(_ id: String) {
        guard let folder = library.folders[id] else { return }
        let parent = folder.parentId
        let time = now()
        library.merge(library.books.values.filter { $0.folderId == id }.map { var b = $0; b.folderId = parent; b.modifiedAt = time; return b })
        var tombstone = folder
        tombstone.deleted = true
        tombstone.modifiedAt = time
        library.merge(library.folders.values.filter { $0.parentId == id }.map { var f = $0; f.parentId = parent; f.modifiedAt = time; return f } + [tombstone])
        enqueue(.deleteFolder(id: id))
    }

    /// Records that were created on the server directly (uploads).
    func received<T: SyncRecord>(_ record: T) {
        library.merge([record])
    }

    private func enqueue(_ op: Op) {
        outbox = outbox.filter { !op.replaces($0) } + [op]
        write(outbox, "outbox")
        flush()
    }

    func flush() {
        guard !flushing, session != nil else { return }
        flushing = true
        Task {
            defer { flushing = false }
            while let op = outbox.first, let session {
                do {
                    switch op {
                    case let .put(collection, _, data):
                        try await send(collection, data, session)
                    case let .deleteFolder(id):
                        try await API.deleteFolder(session, id: id)
                    }
                } catch let error as APIError where error.status == 0 || error.status >= 500 {
                    scheduleRetry()
                    return
                } catch {
                    handle(error)
                }
                outbox.removeAll { $0 == op }
                write(outbox, "outbox")
            }
        }
    }

    private func send(_ collection: Collection, _ data: Data, _ session: Session) async throws {
        func put<T: SyncRecord>(_ type: T.Type) async throws {
            let record = try JSONDecoder().decode(T.self, from: data)
            library.merge([try await API.put(session, record)])
        }
        switch collection {
        case .folders: try await put(Folder.self)
        case .books: try await put(Book.self)
        case .progress: try await put(Progress.self)
        case .annotations: try await put(Annotation.self)
        case .settings: try await put(Setting.self)
        }
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task {
            try? await Task.sleep(for: Self.retryDelay)
            if !Task.isCancelled { flush() }
        }
    }

    // MARK: - Reads

    func pull() async {
        guard let session else { return }
        if pulling {
            pullAgain = true
            return
        }
        pulling = true
        defer { pulling = false }
        do {
            repeat {
                pullAgain = false
                let changes = try await API.sync(session, since: library.version)
                guard self.session == session else { return }
                library.apply(changes)
            } while pullAgain
        } catch {
            handle(error)
            library.ready = true
        }
    }

    /// Listens to the server's event stream, which names the newest version whenever
    /// something changes, and reconnects when it drops.
    private func listen() async {
        while !Task.isCancelled, let session {
            do {
                var req = URLRequest(url: API.eventsURL(session))
                req.timeoutInterval = 120
                let (bytes, response) = try await URLSession.shared.bytes(for: req)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 401 {
                    handle(APIError(message: "unauthorized", status: 401))
                    return
                }
                guard status == 200 else { throw APIError(message: "events", status: status) }
                live = true
                flush()
                var event = ""
                for try await line in bytes.lines {
                    if line.hasPrefix("event:") {
                        event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                    } else if line.hasPrefix("data:"), event == "version" {
                        let version = Int64(line.dropFirst(5).trimmingCharacters(in: .whitespaces)) ?? 0
                        if version > library.version { await pull() }
                    }
                }
            } catch {}
            live = false
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func handle(_ error: Error) {
        if let error = error as? APIError, error.status == 401 {
            onSignedOut?()
        } else {
            print("sync:", error)
        }
    }

    // MARK: - Storage

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            if !Task.isCancelled { writeSnapshot() }
        }
    }

    private func writeSnapshot() {
        write(library.snapshot, "snapshot")
    }

    private var directory: URL? {
        guard let email = session?.email else { return nil }
        let dir = URL.applicationSupportDirectory.appending(path: "accounts/\(API.escape(email))", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let url = directory?.appending(path: "\(name).json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, _ name: String) {
        guard let url = directory?.appending(path: "\(name).json") else { return }
        do {
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            print("storage:", error)
        }
    }
}
