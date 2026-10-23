import UIKit

final class EpubDocument: ReflowDocument {
    private struct Item {
        var id: String
        var path: String
        var type: String
        var properties: [String]
    }

    let metadata: BookMetadata
    let toc: [TocEntry]
    var chapterCount: Int { spine.count }

    private let zip: ZipArchive
    private let opf: Node
    private var manifest: [String: Item] = [:]
    private var spine: [Item] = []
    private var chapterIndex: [String: Int] = [:]
    private let images = NSCache<NSString, UIImage>()
    private var sheets: [String: [Stylesheet]] = [:]
    private let sheetsLock = NSLock()

    init(url: URL) throws {
        zip = try ZipArchive(url: url)
        let container = Markup.parse(try zip.text("META-INF/container.xml"))
        guard let opfPath = container.first("rootfile")?["full-path"] else { throw BookError("not an EPUB") }
        opf = Markup.parse(try zip.text(opfPath))

        var order: [Item] = []
        var manifest: [String: Item] = [:]
        for el in opf.all("item") {
            guard let href = el["href"] else { continue }
            let id = el["id"] ?? href
            let item = Item(id: id, path: Paths.resolve(opfPath, href).path, type: el["media-type"] ?? "", properties: (el["properties"] ?? "").split(separator: " ").map(String.init))
            manifest[id] = item
            order.append(item)
        }
        let spine = (opf.first("spine")?.all("itemref") ?? []).compactMap { manifest[$0["idref"] ?? ""] }
        var chapterIndex: [String: Int] = [:]
        for (i, item) in spine.enumerated() { chapterIndex[item.path] = i }
        self.manifest = manifest
        self.spine = spine
        self.chapterIndex = chapterIndex

        metadata = BookMetadata(title: opf.text(of: "title"), author: opf.text(of: "creator"), language: opf.text(of: "language"))
        toc = Self.readToc(zip: zip, opf: opf, manifest: order, chapterIndex: chapterIndex)
    }

    /// A chapter's markup as stored in the book.
    func chapterSource(_ index: Int) throws -> String {
        try zip.text(spine[index].path)
    }

    func chapter(_ index: Int) throws -> Node {
        let path = spine[index].path
        let doc = Markup.parse(try chapterSource(index))
        let body = doc.first("body") ?? doc.first("html") ?? doc
        body.stylesheet = stylesheet(doc, path: path)
        body.sanitize()

        func rewrite(_ node: Node) {
            switch node.name {
            case "img", "image":
                let src = node["src"] ?? node["href"]
                if let src, !Paths.isExternal(src) { node.attributes["src"] = Paths.resolve(path, src).path }
            case "a":
                if let href = node.attributes.removeValue(forKey: "href") {
                    if Paths.isExternal(href) {
                        node.attributes["data-external"] = href
                    } else {
                        let (target, hash) = Paths.resolve(path, href)
                        node.attributes["data-href"] = hash.map { "\(target)#\($0)" } ?? target
                    }
                }
            default: break
            }
            node.children.forEach(rewrite)
        }
        rewrite(body)
        return body
    }

    /// A chapter's CSS: its linked style sheets and style blocks, in document order.
    private func stylesheet(_ doc: Node, path: String) -> Stylesheet {
        var parts: [Stylesheet] = []
        func walk(_ node: Node) {
            switch node.name {
            case "style":
                let sheet = Stylesheet(node.textContent)
                for href in sheet.imports where !Paths.isExternal(href) { parts += loadSheet(Paths.resolve(path, href).path, depth: 1) }
                parts.append(sheet)
            case "link":
                let rel = (node["rel"] ?? "").lowercased().split(separator: " ")
                if rel.contains("stylesheet"), !rel.contains("alternate"), let href = node["href"], !Paths.isExternal(href) {
                    parts += loadSheet(Paths.resolve(path, href).path, depth: 0)
                }
            default:
                node.children.forEach(walk)
            }
        }
        walk(doc)
        return Stylesheet(parts)
    }

    /// A style sheet in the book, after the ones it imports.
    private func loadSheet(_ path: String, depth: Int) -> [Stylesheet] {
        sheetsLock.lock()
        let cached = sheets[path]
        sheetsLock.unlock()
        if let cached { return cached }
        guard let text = try? zip.text(path) else { return [] }
        let sheet = Stylesheet(text)
        var out: [Stylesheet] = []
        if depth < 4 {
            for href in sheet.imports where !Paths.isExternal(href) { out += loadSheet(Paths.resolve(path, href).path, depth: depth + 1) }
        }
        out.append(sheet)
        sheetsLock.lock()
        sheets[path] = out
        sheetsLock.unlock()
        return out
    }

    func resolveLink(_ href: String) -> LinkTarget? {
        let parts = href.split(separator: "#", maxSplits: 1).map(String.init)
        guard let chapter = chapterIndex[parts[0]] else { return nil }
        return .chapter(chapter, anchor: parts.count > 1 ? parts[1] : nil)
    }

    func image(_ src: String) -> UIImage? {
        if let cached = images.object(forKey: src as NSString) { return cached }
        guard let data = try? zip.data(src), let image = UIImage(data: data) else { return nil }
        images.setObject(image, forKey: src as NSString)
        return image
    }

    func cover() -> Data? {
        let items = Array(manifest.values)
        let coverId = opf.all("meta").first { $0["name"] == "cover" }?["content"]
        let item = items.first { $0.properties.contains("cover-image") }
            ?? coverId.flatMap { manifest[$0] }
            ?? items.first { $0.type.hasPrefix("image/") && ($0.id + $0.path).range(of: "cover", options: .caseInsensitive) != nil }
        return item.flatMap { try? zip.data($0.path) }
    }

    private static func readToc(zip: ZipArchive, opf: Node, manifest: [Item], chapterIndex: [String: Int]) -> [TocEntry] {
        var entries: [TocEntry] = []
        func add(_ label: String, _ base: String, _ href: String, _ depth: Int) {
            let (path, hash) = Paths.resolve(base, href)
            if !label.isEmpty, let chapter = chapterIndex[path] {
                entries.append(TocEntry(id: entries.count, label: label, depth: depth, chapter: chapter, anchor: hash))
            }
        }

        if let nav = manifest.first(where: { $0.properties.contains("nav") }), let text = try? zip.text(nav.path) {
            let doc = Markup.parse(text)
            let navs = doc.all("nav")
            let tocNav = navs.first { ($0["epub:type"] ?? $0["type"] ?? "").contains("toc") } ?? navs.first
            func walk(_ ol: Node?, _ depth: Int) {
                for li in ol?.childElements("li") ?? [] {
                    if let a = li.childElements().first(where: { $0.name == "a" || $0.name == "span" }), let href = a["href"] {
                        add(a.trimmedText, nav.path, href, depth)
                    }
                    walk(li.childElements("ol").first, depth + 1)
                }
            }
            walk(tocNav?.childElements("ol").first, 0)
            if !entries.isEmpty { return entries }
        }

        let ncxId = opf.first("spine")?["toc"]
        let ncx = manifest.first { $0.id == ncxId } ?? manifest.first { $0.type == "application/x-dtbncx+xml" }
        if let ncx, let text = try? zip.text(ncx.path) {
            let doc = Markup.parse(text)
            func walk(_ parent: Node, _ depth: Int) {
                for point in parent.childElements("navpoint") {
                    let label = point.first("navlabel")?.text(of: "text") ?? ""
                    if let src = point.first("content")?["src"] { add(label, ncx.path, src, depth) }
                    walk(point, depth + 1)
                }
            }
            if let map = doc.first("navmap") { walk(map, 0) }
        }
        return entries
    }
}
