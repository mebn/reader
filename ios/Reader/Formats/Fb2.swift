import UIKit

/// FictionBook, converted to the same HTML-like tree the desktop app builds.
final class Fb2Document: ReflowDocument {
    /// FictionBook element → HTML tag. Unlisted elements become their children.
    private static let tags: [String: String] = [
        "p": "p", "title": "h2", "subtitle": "h3", "emphasis": "em", "strong": "strong", "strikethrough": "s",
        "sup": "sup", "sub": "sub", "code": "code", "epigraph": "blockquote", "cite": "blockquote", "poem": "div",
        "stanza": "p", "v": "div", "text-author": "p", "section": "section", "table": "table", "tr": "tr", "td": "td", "th": "th",
    ]

    let metadata: BookMetadata
    let toc: [TocEntry]
    var chapterCount: Int { chapters.count }

    private let info: Node?
    private let chapters: [Node]
    private var binaries: [String: Data] = [:]
    private var anchors: [String: Int] = [:]
    private let images = NSCache<NSString, UIImage>()

    init(url: URL, fileName: String) throws {
        let data = try Data(contentsOf: url)
        let doc = Markup.parse(Self.decode(data))
        info = doc.first("title-info")
        let author = info?.first("author")
        let title = info?.text(of: "book-title") ?? ""

        var binaries: [String: Data] = [:]
        for bin in doc.all("binary") {
            let base64 = bin.textContent.components(separatedBy: .whitespacesAndNewlines).joined()
            if let bytes = Data(base64Encoded: base64) { binaries[bin["id"] ?? ""] = bytes }
        }
        self.binaries = binaries

        let body = doc.all("body").first { $0["name"] != "notes" }
        let sections = body?.childElements("section") ?? []
        let chapters = sections.isEmpty ? (body.map { [$0] } ?? []) : sections
        self.chapters = chapters

        var anchors: [String: Int] = [:]
        for (i, chapter) in chapters.enumerated() {
            func walk(_ node: Node) {
                if let id = node["id"] { anchors[id] = i }
                node.children.forEach(walk)
            }
            walk(chapter)
        }
        self.anchors = anchors

        toc = chapters.enumerated().map { i, chapter in
            let label = chapter.childElements("title").first?.trimmedText ?? ""
            return TocEntry(id: i, label: label.isEmpty ? "\(i + 1)" : label, depth: 0, chapter: i)
        }
        metadata = BookMetadata(
            title: title.isEmpty ? Paths.nameWithoutExtension(fileName) : title,
            author: [author?.text(of: "first-name") ?? "", author?.text(of: "last-name") ?? ""].filter { !$0.isEmpty }.joined(separator: " "),
            language: info?.text(of: "lang"))
    }

    private static func decode(_ data: Data) -> String {
        let head = String(decoding: data.prefix(200), as: UTF8.self).lowercased()
        if head.contains("windows-1251") { return String(data: data, encoding: .windowsCP1251) ?? "" }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) ?? ""
    }

    func chapter(_ index: Int) throws -> Node {
        let root = Node.element("body")
        chapters[index].children.forEach { convert($0).forEach(root.append) }
        return root
    }

    private func convert(_ node: Node) -> [Node] {
        guard let name = node.name else { return [Node.text(node.textContent)] }
        switch name {
        case "image":
            return [Node.element("img", ["src": (node["href"] ?? "").replacingOccurrences(of: "#", with: "")])]
        case "empty-line":
            return [Node.element("br")]
        case "a":
            let href = node["href"] ?? ""
            let key = href.hasPrefix("#") ? "data-href" : "data-external"
            return [Node.element("a", [key: href.replacingOccurrences(of: "^#", with: "", options: .regularExpression)], node.children.flatMap(convert))]
        default:
            let children = node.children.flatMap(convert)
            guard let tag = Self.tags[name] else { return children }
            return [Node.element(tag, node["id"].map { ["id": $0] } ?? [:], children)]
        }
    }

    func resolveLink(_ href: String) -> LinkTarget? {
        anchors[href].map { .chapter($0, anchor: href) }
    }

    func image(_ src: String) -> UIImage? {
        if let cached = images.object(forKey: src as NSString) { return cached }
        guard let data = binaries[src], let image = UIImage(data: data) else { return nil }
        images.setObject(image, forKey: src as NSString)
        return image
    }

    func cover() -> Data? {
        let id = (info?.first("coverpage")?.first("image")?["href"] ?? "").replacingOccurrences(of: "#", with: "")
        return binaries[id]
    }
}
