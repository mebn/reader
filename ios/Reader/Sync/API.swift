import Foundation

struct APIError: LocalizedError {
    var message: String
    /// 0 when the server couldn't be reached.
    var status: Int

    var errorDescription: String? { message }
}

private struct ErrorBody: Decodable {
    var error: String?
}

private struct AuthResponse: Decodable {
    var token: String
    var user: User
}

/// The sync server's REST API.
enum API {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // Go writes RFC 3339 with fractional seconds, which .iso8601 doesn't accept.
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
            if let date = try? Date(string, strategy: .iso8601) { return date }
            return .distantPast
        }
        return decoder
    }()

    private static func request<T: Decodable>(_ session: Session, _ method: String, _ path: String, json: Encodable? = nil, body: Data? = nil, contentType: String? = nil) async throws -> T {
        var req = URLRequest(url: session.url(path))
        req.httpMethod = method
        if !session.token.isEmpty { req.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization") }
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(json)
        } else if let body {
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError(message: "Can't reach the server", status: 0)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? HTTPURLResponse.localizedString(forStatusCode: status)
            throw APIError(message: message, status: status)
        }
        if T.self == Empty.self { return Empty() as! T }
        return try decoder.decode(T.self, from: data)
    }

    struct Empty: Decodable {}

    private struct Credentials: Encodable {
        var email: String
        var password: String
        var device: DeviceInfo
    }

    static func login(server: String, email: String, password: String, device: DeviceInfo) async throws -> (token: String, user: User) {
        let r: AuthResponse = try await request(Session(serverUrl: server, token: "", email: ""), "POST", "/auth/login", json: Credentials(email: email, password: password, device: device))
        return (r.token, r.user)
    }

    static func register(server: String, email: String, password: String, device: DeviceInfo) async throws -> (token: String, user: User) {
        let r: AuthResponse = try await request(Session(serverUrl: server, token: "", email: ""), "POST", "/auth/register", json: Credentials(email: email, password: password, device: device))
        return (r.token, r.user)
    }

    static func devices(_ s: Session) async throws -> [Device] {
        try await request(s, "GET", "/devices")
    }

    static func removeDevice(_ s: Session, id: String) async throws {
        let _: Empty = try await request(s, "DELETE", "/devices/\(id)")
    }

    static func sync(_ s: Session, since: Int64) async throws -> Changes {
        try await request(s, "GET", "/sync?since=\(since)")
    }

    static func put<T: SyncRecord>(_ s: Session, _ record: T) async throws -> T {
        try await request(s, "PUT", "/\(T.collection.rawValue)/\(escape(record.id))", json: record)
    }

    static func deleteFolder(_ s: Session, id: String) async throws {
        let _: Empty = try await request(s, "DELETE", "/folders/\(escape(id))")
    }

    static func uploadBook(_ s: Session, book: Book, file: URL, cover: Data?) async throws -> Book {
        var form = MultipartForm()
        form.add(name: "meta", value: String(decoding: try JSONEncoder().encode(book), as: UTF8.self))
        form.add(name: "file", fileName: book.fileName, data: try Data(contentsOf: file))
        if let cover { form.add(name: "cover", fileName: "cover", data: cover) }
        return try await request(s, "POST", "/books/\(book.id)", body: form.finish(), contentType: form.contentType)
    }

    static func bookFileURL(_ s: Session, id: String) -> URL { s.url("/books/\(id)/file") }

    static func coverURL(_ s: Session, book: Book) -> URL {
        s.url("/books/\(book.id)/cover?v=\(book.modifiedAt)&token=\(escape(s.token))")
    }

    static func eventsURL(_ s: Session) -> URL { s.url("/events?token=\(escape(s.token))") }

    /// Like encodeURIComponent.
    static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.!~*'()"))) ?? s
    }
}

private struct MultipartForm {
    let boundary = "reader-\(UUID().uuidString)"
    private var body = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func add(name: String, value: String) {
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
    }

    mutating func add(name: String, fileName: String, data: Data) {
        let safe = fileName.replacingOccurrences(of: "\"", with: "'")
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(safe)\"\r\nContent-Type: application/octet-stream\r\n\r\n")
        body.append(data)
        body.append("\r\n")
    }

    func finish() -> Data {
        var out = body
        out.append("--\(boundary)--\r\n")
        return out
    }
}

private extension Data {
    mutating func append(_ string: String) { append(Data(string.utf8)) }
}
