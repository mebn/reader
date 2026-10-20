import UIKit

/// Plain text, split into chapters at headings or into evenly sized parts.
final class TxtDocument: ReflowDocument {
    private struct Chapter {
        var title: String?
        var paragraphs: [String] = []
    }

    private static let heading = try! NSRegularExpression(pattern: #"^\s*(chapter|kapitel|part|book|del)\s+([0-9]+|[ivxlcdm]+)\b.*$"#, options: .caseInsensitive)
    private static let maxChapterChars = 40_000

    let metadata: BookMetadata
    let toc: [TocEntry]
    var chapterCount: Int { chapters.count }
    private let chapters: [Chapter]

    init(url: URL, fileName: String) throws {
        chapters = Self.split(Self.decode(try Data(contentsOf: url)))
        metadata = BookMetadata(title: Paths.nameWithoutExtension(fileName), author: "")
        toc = chapters.enumerated().compactMap { i, c in c.title.map { TocEntry(id: i, label: $0, depth: 0, chapter: i) } }
    }

    private static func decode(_ data: Data) -> String {
        let utf8 = String(decoding: data, as: UTF8.self)
        let broken = utf8.filter { $0 == "\u{FFFD}" }.count
        return broken > utf8.count / 1000 ? (String(data: data, encoding: .windowsCP1252) ?? utf8) : utf8
    }

    private static func split(_ text: String) -> [Chapter] {
        let normalized = text.replacingOccurrences(of: "\r\n?", with: "\n", options: .regularExpression)
        let blocks = normalized.range(of: #"\n\s*\n"#, options: .regularExpression) != nil
            ? normalized.components(separatedBy: try! NSRegularExpression(pattern: #"\n\s*\n+"#))
            : normalized.components(separatedBy: "\n")
        let paragraphs = blocks
            .map { $0.replacingOccurrences(of: #"\s*\n\s*"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chapters: [Chapter] = []
        var current = Chapter()
        var size = 0
        for p in paragraphs {
            let ns = p as NSString
            let isHeading = p.count < 80 && heading.firstMatch(in: p, range: NSRange(location: 0, length: ns.length)) != nil
            if (isHeading || size > maxChapterChars) && !current.paragraphs.isEmpty {
                chapters.append(current)
                current = Chapter()
                size = 0
            }
            if isHeading { current.title = p } else { current.paragraphs.append(p) }
            size += ns.length
        }
        if !current.paragraphs.isEmpty || current.title != nil { chapters.append(current) }
        return chapters.isEmpty ? [Chapter()] : chapters
    }

    func chapter(_ index: Int) throws -> Node {
        let chapter = chapters[index]
        let root = Node.element("body")
        if let title = chapter.title { root.append(.element("h2", [:], [.text(title)])) }
        for p in chapter.paragraphs { root.append(.element("p", [:], [.text(p)])) }
        return root
    }

    func resolveLink(_ href: String) -> LinkTarget? { nil }
    func image(_ src: String) -> UIImage? { nil }
    func cover() -> Data? { nil }
}

private extension String {
    func components(separatedBy regex: NSRegularExpression) -> [String] {
        let ns = self as NSString
        var out: [String] = []
        var last = 0
        for match in regex.matches(in: self, range: NSRange(location: 0, length: ns.length)) {
            out.append(ns.substring(with: NSRange(location: last, length: match.range.location - last)))
            last = match.range.location + match.range.length
        }
        out.append(ns.substring(from: last))
        return out
    }
}
