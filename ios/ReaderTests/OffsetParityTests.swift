import WebKit
import XCTest
@testable import Reader

/// Highlights are stored as character offsets into a chapter's text as the desktop app's
/// browser DOM counts it. These check the native parser counts the same text.
@MainActor
final class OffsetParityTests: XCTestCase {
    private var books: URL {
        get throws {
            guard let dir = ProcessInfo.processInfo.environment["BOOKS_DIR"] else { throw XCTSkip("Set TEST_RUNNER_BOOKS_DIR to a folder of sample books") }
            return URL(fileURLWithPath: dir)
        }
    }

    private func epubs() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: books, includingPropertiesForKeys: nil).filter { $0.pathExtension == "epub" }
    }

    /// The sanitized body text the desktop app would count offsets in.
    private func browserText(_ source: String, in webView: WKWebView) async throws -> String {
        let script = """
        let doc = new DOMParser().parseFromString(src, "application/xhtml+xml");
        if (doc.getElementsByTagName("parsererror").length) doc = new DOMParser().parseFromString(src, "text/html");
        const body = doc.body ?? doc.getElementsByTagName("body")[0] ?? doc.documentElement;
        body.querySelectorAll("script, style, link, meta, iframe, object, embed, form, input, button, textarea, select, noscript, audio, video").forEach((el) => el.remove());
        const range = document.createRange();
        range.selectNodeContents(body);
        return range.toString();
        """
        return try await webView.callAsyncJavaScript(script, arguments: ["src": source], contentWorld: .page) as? String ?? ""
    }

    func testEpubTextMatchesBrowser() async throws {
        let webView = WKWebView()
        webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
        try await Task.sleep(for: .milliseconds(300))
        var checked = 0
        for url in try epubs() {
            let doc = try EpubDocument(url: url)
            for i in 0..<doc.chapterCount {
                let expected = try await browserText(try doc.chapterSource(i), in: webView)
                let mine = try doc.chapter(i).textContent
                XCTAssertEqual(mine.utf16.count, expected.utf16.count, "\(url.lastPathComponent) chapter \(i) length")
                if mine != expected {
                    let a = Array(mine.utf16), b = Array(expected.utf16)
                    let at = (0..<min(a.count, b.count)).first { a[$0] != b[$0] } ?? min(a.count, b.count)
                    let near = { (u: [UInt16]) in String(decoding: u[max(0, at - 20)..<min(u.count, at + 20)], as: UTF16.self).debugDescription }
                    XCTFail("\(url.lastPathComponent) chapter \(i) differs at \(at): \(near(a)) vs \(near(b))")
                }
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0)
    }

    /// Every character on the page maps back to the same character in the DOM text.
    func testDisplayMapsBackToDom() throws {
        BookFonts.register()
        for url in try epubs() {
            let doc = try EpubDocument(url: url)
            for i in 0..<doc.chapterCount {
                let root = try doc.chapter(i)
                let dom = Array(root.textContent.utf16)
                let style = TextStyle(settings: .defaults, text: .black, columnWidth: 320, pageHeight: 600, language: "en")
                let text = ChapterTextBuilder(style: style, image: doc.image).build(root)
                let shown = Array(text.string.string.utf16)
                XCTAssertEqual(text.domLength, dom.count)
                var last: Int32 = -1
                for (j, unit) in shown.enumerated() {
                    let offset = text.domOffsets[j]
                    XCTAssertGreaterThanOrEqual(offset, last, "offsets must not go backwards")
                    last = offset
                    if text.synthetic[j] { continue }
                    let source = dom[Int(offset)]
                    if unit == 0x20 { XCTAssertTrue([0x20, 0x09, 0x0A, 0x0C].contains(source), "space maps to whitespace") }
                    else { XCTAssertEqual(unit, source, "\(url.lastPathComponent) chapter \(i) at \(j)") }
                }
                // A round trip through a range lands on the same text.
                if shown.count > 200, let dr = text.domRange(NSRange(location: 100, length: 50)) {
                    let back = text.displayRange(domStart: dr.start, domEnd: dr.end)!
                    XCTAssertEqual(normalizedSelection((text.string.string as NSString).substring(with: back)),
                                   normalizedSelection((text.string.string as NSString).substring(with: NSRange(location: 100, length: 50))))
                }
            }
        }
    }

    func testTxtAndPdfOpen() throws {
        let files = try FileManager.default.contentsOfDirectory(at: books, includingPropertiesForKeys: nil)
        for url in files {
            guard let format = Format(fileName: url.lastPathComponent) else { continue }
            let doc = try BookDocument.open(url, format: format, fileName: url.lastPathComponent)
            XCTAssertFalse(doc.metadata.title.isEmpty, url.lastPathComponent)
            print("opened", url.lastPathComponent, "title:", doc.metadata.title, "author:", doc.metadata.author, "toc:", doc.toc.count, "cover:", doc.cover()?.count ?? 0)
        }
    }
}
