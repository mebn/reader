import Compression
import Foundation

/// Reads entries from a ZIP archive (EPUB, CBZ): stored or deflated, no ZIP64.
final class ZipArchive {
    struct Entry {
        var path: String
        var method: UInt16
        var compressedSize: Int
        var size: Int
        var localHeader: Int
    }

    private let data: Data
    private(set) var entries: [String: Entry] = [:]
    /// Paths in archive order.
    private(set) var paths: [String] = []

    init(url: URL) throws {
        data = try Data(contentsOf: url, options: .mappedIfSafe)
        try readDirectory()
    }

    func contains(_ path: String) -> Bool { entries[path] != nil }

    func data(_ path: String) throws -> Data {
        guard let entry = entries[path] else { throw BookError("missing \(path)") }
        let nameLength = Int(u16(entry.localHeader + 26))
        let extraLength = Int(u16(entry.localHeader + 28))
        let start = entry.localHeader + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= data.count else { throw BookError("damaged archive") }
        let raw = data.subdata(in: start..<start + entry.compressedSize)
        switch entry.method {
        case 0: return raw
        case 8: return try inflate(raw, size: entry.size)
        default: throw BookError("unsupported compression in \(path)")
        }
    }

    func text(_ path: String) throws -> String {
        let bytes = try data(path)
        return String(data: bytes, encoding: .utf8) ?? String(decoding: bytes, as: UTF8.self)
    }

    private func readDirectory() throws {
        // The end-of-central-directory record sits in the last 64 KB.
        let floor = max(0, data.count - 65_557)
        var eocd = -1
        var i = data.count - 22
        while i >= floor {
            if u32(i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw BookError("not a ZIP archive") }
        let count = Int(u16(eocd + 10))
        var offset = Int(u32(eocd + 16))

        for _ in 0..<count {
            guard offset + 46 <= data.count, u32(offset) == 0x02014b50 else { break }
            let flags = u16(offset + 8)
            let method = u16(offset + 10)
            let compressed = Int(u32(offset + 20))
            let size = Int(u32(offset + 24))
            let nameLength = Int(u16(offset + 28))
            let extraLength = Int(u16(offset + 30))
            let commentLength = Int(u16(offset + 32))
            let local = Int(u32(offset + 42))
            let nameData = data.subdata(in: offset + 46..<offset + 46 + nameLength)
            let name = (flags & 0x800 != 0 ? String(data: nameData, encoding: .utf8) : nil)
                ?? String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1) ?? ""
            if !name.hasSuffix("/") {
                entries[name] = Entry(path: name, method: method, compressedSize: compressed, size: size, localHeader: local)
                paths.append(name)
            }
            offset += 46 + nameLength + extraLength + commentLength
        }
    }

    private func inflate(_ input: Data, size: Int) throws -> Data {
        if size == 0 { return Data() }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { out in
            input.withUnsafeBytes { inp in
                compression_decode_buffer(
                    out.bindMemory(to: UInt8.self).baseAddress!, size,
                    inp.bindMemory(to: UInt8.self).baseAddress!, input.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { throw BookError("damaged archive") }
        output.count = written
        return output
    }

    private func u16(_ at: Int) -> UInt16 {
        UInt16(data[data.startIndex + at]) | UInt16(data[data.startIndex + at + 1]) << 8
    }

    private func u32(_ at: Int) -> UInt32 {
        UInt32(u16(at)) | UInt32(u16(at + 2)) << 16
    }
}

struct BookError: LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
