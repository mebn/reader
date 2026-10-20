import PDFKit
import UIKit

struct BookMetadata {
    var title: String
    var author: String
    /// BCP 47 language tag, used for hyphenation.
    var language: String?
}

struct TocEntry: Identifiable, Hashable {
    var id: Int
    var label: String
    var depth: Int
    var chapter: Int?
    var anchor: String?
    var page: Int?
}

enum LinkTarget {
    case chapter(Int, anchor: String?)
    case external(URL)
}

/// Text that flows into pages: EPUB, FB2, TXT.
protocol ReflowDocument: AnyObject {
    var metadata: BookMetadata { get }
    var toc: [TocEntry] { get }
    var chapterCount: Int { get }
    /// A sanitized copy of a chapter's body. Images carry a `src` that ``image(_:)`` loads;
    /// links carry `data-href` (inside the book) or `data-external`.
    func chapter(_ index: Int) throws -> Node
    func resolveLink(_ href: String) -> LinkTarget?
    func image(_ src: String) -> UIImage?
    func cover() -> Data?
}

/// Pre-laid-out pages: PDF, comics.
enum FixedDocument {
    case pdf(PDFDocument, BookMetadata, [TocEntry])
    case comic(ComicDocument)

    var metadata: BookMetadata {
        switch self {
        case let .pdf(_, metadata, _): metadata
        case let .comic(doc): doc.metadata
        }
    }

    var toc: [TocEntry] {
        switch self {
        case let .pdf(_, _, toc): toc
        case .comic: []
        }
    }

    var pageCount: Int {
        switch self {
        case let .pdf(doc, _, _): doc.pageCount
        case let .comic(doc): doc.pages.count
        }
    }
}

enum BookDocument {
    case reflow(ReflowDocument)
    case fixed(FixedDocument)

    var metadata: BookMetadata {
        switch self {
        case let .reflow(doc): doc.metadata
        case let .fixed(doc): doc.metadata
        }
    }

    var toc: [TocEntry] {
        switch self {
        case let .reflow(doc): doc.toc
        case let .fixed(doc): doc.toc
        }
    }

    static func open(_ url: URL, format: Format, fileName: String) throws -> BookDocument {
        switch format {
        case .epub: .reflow(try EpubDocument(url: url))
        case .fb2: .reflow(try Fb2Document(url: url, fileName: fileName))
        case .txt: .reflow(try TxtDocument(url: url, fileName: fileName))
        case .pdf: .fixed(try openPdf(url, fileName: fileName))
        case .cbz: .fixed(.comic(try ComicDocument(url: url, fileName: fileName)))
        }
    }

    /// A cover image, if the book has one.
    func cover() -> Data? {
        switch self {
        case let .reflow(doc):
            return doc.cover()
        case let .fixed(.pdf(doc, _, _)):
            guard let page = doc.page(at: 0) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let width: CGFloat = 480
            let image = page.thumbnail(of: CGSize(width: width, height: width * bounds.height / max(1, bounds.width)), for: .mediaBox)
            return image.jpegData(compressionQuality: 0.85)
        case let .fixed(.comic(doc)):
            return doc.pages.first.flatMap { try? doc.archive.data($0) }
        }
    }
}

// MARK: - PDF

private func openPdf(_ url: URL, fileName: String) throws -> FixedDocument {
    guard let doc = PDFDocument(url: url) else { throw BookError("not a PDF") }
    let attributes = doc.documentAttributes ?? [:]
    let title = usableTitle(attributes[PDFDocumentAttribute.titleAttribute] as? String)
    let author = (attributes[PDFDocumentAttribute.authorAttribute] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""

    var toc: [TocEntry] = []
    func walk(_ outline: PDFOutline, depth: Int) {
        for i in 0..<outline.numberOfChildren {
            guard let item = outline.child(at: i) else { continue }
            if let page = item.destination?.page {
                toc.append(TocEntry(id: toc.count, label: (item.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines), depth: depth, page: doc.index(for: page)))
            }
            walk(item, depth: depth + 1)
        }
    }
    if let root = doc.outlineRoot { walk(root, depth: 0) }

    let metadata = BookMetadata(title: title.isEmpty ? Paths.nameWithoutExtension(fileName) : title, author: author)
    return .pdf(doc, metadata, toc)
}

/// PDF titles are often left as the source file name or a tool's default.
private func usableTitle(_ title: String?) -> String {
    let t = title?.trimmingCharacters(in: .whitespaces) ?? ""
    if t.range(of: #"\.[a-z0-9]{2,5}$"#, options: [.regularExpression, .caseInsensitive]) != nil { return "" }
    if t.range(of: "^(untitled|microsoft word)", options: [.regularExpression, .caseInsensitive]) != nil { return "" }
    return t
}

// MARK: - Comics

final class ComicDocument {
    let archive: ZipArchive
    let pages: [String]
    let metadata: BookMetadata
    private let cache = NSCache<NSString, UIImage>()

    init(url: URL, fileName: String) throws {
        archive = try ZipArchive(url: url)
        pages = archive.paths
            .filter { $0.range(of: #"\.(jpe?g|png|gif|webp|avif|bmp)$"#, options: [.regularExpression, .caseInsensitive]) != nil && !$0.hasPrefix("__MACOSX") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        metadata = BookMetadata(title: Paths.nameWithoutExtension(fileName), author: "")
    }

    func image(_ index: Int) -> UIImage? {
        guard pages.indices.contains(index) else { return nil }
        let key = pages[index] as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = try? archive.data(pages[index]), let image = UIImage(data: data)?.preparingForDisplay() else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
