import XCTest
@testable import Reader

/// The CSS engine behind original styles, and that it never changes DOM offsets.
@MainActor
final class CSSTests: XCTestCase {
    private func chapter(_ html: String, css: String) -> Node {
        let doc = Markup.parse(html)
        let body = doc.first("body")!
        body.stylesheet = Stylesheet(css)
        body.sanitize()
        return body
    }

    private func element(_ root: Node, id: String) -> Node {
        var found: Node?
        func walk(_ node: Node) {
            if node.attributes["id"] == id { found = node }
            node.children.forEach(walk)
        }
        walk(root)
        return found!
    }

    func testSelectorsAndCascade() {
        let root = chapter("""
        <html><body><div class="main"><p id="a" class="x y">One</p><blockquote><p id="b">Two</p></blockquote>
        <p id="c" style="text-align: left">Three</p></div></body></html>
        """, css: """
        p { text-align: justify }
        .main > p { text-indent: 2em }
        p.x.y { text-align: right }
        div p { font-style: italic }
        #a { text-align: center }
        blockquote p, h9 { font-weight: bold }
        p { text-align: justify }
        html body .main p:first-child { text-transform: uppercase }
        p + blockquote { margin-left: 10px }
        p::first-letter { font-size: 3em }
        .main p { text-decoration: underline !important }
        """)
        let cascade = CSSCascade(book: root.stylesheet)
        let a = cascade.declarations(for: element(root, id: "a"))
        XCTAssertEqual(a["text-align"], "center", "an id beats classes and types")
        XCTAssertEqual(a["text-indent"], "2em")
        XCTAssertEqual(a["font-style"], "italic")
        XCTAssertEqual(a["text-transform"], "uppercase")
        XCTAssertNil(a["font-size"], "pseudo-elements are skipped")

        let b = cascade.declarations(for: element(root, id: "b"))
        XCTAssertEqual(b["text-align"], "justify", "the later of equal rules wins")
        XCTAssertEqual(b["font-weight"], "bold")
        XCTAssertNil(b["text-indent"], "a child combinator needs the direct parent")

        let c = cascade.declarations(for: element(root, id: "c"))
        XCTAssertEqual(c["text-align"], "left", "a style attribute beats rules")
        XCTAssertEqual(c["text-decoration-line"], "underline")

        let quote = element(root, id: "b").parent!
        XCTAssertEqual(cascade.declarations(for: quote)["margin-left"], "10px")
    }

    func testValuesAndShorthands() {
        let sheet = Stylesheet("""
        @import url("other.css");
        @media print { p { display: none } }
        @media screen and (min-width: 10px) { p { margin: 1em 2em } }
        @font-face { font-family: X; src: url(x.ttf) }
        h1 { font: italic bold 1.5em/1.2 Georgia, serif; color: red; font-family: X }
        """)
        XCTAssertEqual(sheet.imports, ["other.css"])
        let props = sheet.rules.flatMap { $0.declarations.map(\.property) }
        XCTAssertFalse(props.contains("display"), "print rules don't apply")
        XCTAssertTrue(props.contains("margin-left"))
        XCTAssertFalse(props.contains("color"))
        XCTAssertFalse(props.contains("font-family"))

        let context = CSSStyle.Context(fontSize: 20, width: 300)
        let base = CSSStyle(weight: 400)
        let h1 = CSSStyle.resolve(["font-size": "1.5em", "font-weight": "bold", "font-style": "italic", "margin-top": "1em", "margin-left": "10%", "text-indent": "16px"], parent: base, context: context)
        XCTAssertEqual(h1.size, 1.5)
        XCTAssertEqual(h1.weight, 700)
        XCTAssertTrue(h1.italic)
        XCTAssertEqual(h1.top, 30, "em margins count in the element's own size")
        XCTAssertEqual(h1.left, 30)
        XCTAssertEqual(h1.indent, 20, "16px is 1em of the user's size")
        XCTAssertEqual(CSSStyle.fontSize("smaller", parent: 1.2, context: context), 1)
        XCTAssertEqual(CSSStyle.fontSize("80%", parent: 1, context: context), 0.8)
        XCTAssertEqual(CSSStyle.fontSize("large", parent: 1, context: context), 1.2)
        XCTAssertNil(CSSStyle.fontSize("bogus", parent: 1, context: context))
        XCTAssertEqual(CSSStyle.weight("bolder", parent: 700), 900)
    }

    func testMalformedCssDoesNotCrash() {
        let junk = [
            "}}}{{ p { color: ; } @media { ; ;; p[ { a",
            "p { margin: 1em 2em 3em 4em 5em } a::{ } :not( { } [x=\"unclosed] { }",
            "@media screen { p { text-align: center }",
            "/* unterminated", "p { font-size: -3em; text-indent: 1e999px; font: ; }",
            "\\\\ { } #{ } .{ } * > > p { } p ~ { }", "",
        ]
        for css in junk {
            let sheet = Stylesheet(css)
            let root = chapter("<body><p class=\"a\">x</p></body>", css: css)
            _ = CSSCascade(book: sheet).declarations(for: root.children[0])
            var settings = ReaderSettings.defaults
            settings.originalStyles = true
            _ = ChapterTextBuilder(style: TextStyle(settings: settings, text: .black, columnWidth: 300, pageHeight: 500, language: "en"), image: { _ in nil }).build(root)
        }
    }

    /// Original styles may hide, recase and restyle text, but every DOM offset stays the same.
    func testOriginalStylesKeepDomOffsets() {
        let html = """
        <html><head><style>.gone { display: none }</style></head><body>
        <h1 class="t">Stra\u{DF}e  title</h1>
        <p class="up">Gro\u{DF}e \u{1F600} letters <span class="gone">hidden <b>text</b></span> after</p>
        <ul class="gone"><li>one</li><li>two</li></ul>
        <ol><li>first</li><li class="inline">second</li></ol>
        <p>Some <sup>1</sup> and <span class="sc">Small Caps</span> <a href="x.html">link</a>.</p>
        <div class="block"><span style="display: block">block span</span> and <p style="display:inline">inline p</p></div>
        </body></html>
        """
        let css = """
        .t { text-transform: capitalize; font-size: 3em; text-align: center }
        .up { text-transform: uppercase; text-indent: -1em; margin: 2em 3em }
        .gone { display: none }
        .sc { font-variant: small-caps; text-decoration: line-through }
        li.inline { display: inline }
        a { text-decoration: none }
        """
        let root = chapter(html, css: css)
        let dom = Array(root.textContent.utf16)
        var on = ReaderSettings.defaults
        on.originalStyles = true
        func build(_ settings: ReaderSettings) -> ChapterText {
            ChapterTextBuilder(style: TextStyle(settings: settings, text: .black, columnWidth: 320, pageHeight: 600, language: "en"), image: { _ in nil }).build(root)
        }
        let plain = build(.defaults)
        let styled = build(on)
        XCTAssertEqual(plain.domLength, dom.count)
        XCTAssertEqual(styled.domLength, plain.domLength)
        XCTAssertEqual(styled.string.length, styled.domOffsets.count)
        XCTAssertFalse(styled.string.string.contains("hidden"))
        XCTAssertTrue(styled.string.string.contains("GRO\u{DF}E"), "letters that would change length keep their case")
        XCTAssertTrue(styled.string.string.contains("Stra\u{DF}e  Title") || styled.string.string.contains("Stra\u{DF}e Title"))
        var last: Int32 = -1
        for (j, unit) in Array(styled.string.string.utf16).enumerated() {
            let offset = styled.domOffsets[j]
            XCTAssertGreaterThanOrEqual(offset, last)
            last = offset
            if styled.synthetic[j] || unit == 0x20 { continue }
            let source = String(utf16CodeUnits: [dom[Int(offset)]], count: 1)
            let shown = String(utf16CodeUnits: [unit], count: 1)
            XCTAssertEqual(shown.lowercased(), source.lowercased(), "at \(j)")
        }
        // Text shown both ways maps to the same DOM range.
        for word in ["after", "link", "second"] {
            let a = (plain.string.string as NSString).range(of: word), b = (styled.string.string as NSString).range(of: word, options: .caseInsensitive)
            XCTAssertEqual(plain.domRange(a)?.start, styled.domRange(b)?.start, word)
            XCTAssertEqual(plain.domRange(a)?.end, styled.domRange(b)?.end, word)
        }
    }

    /// The same, for every chapter of the sample books when they are available.
    func testSampleBooksKeepDomLength() throws {
        guard let dir = ProcessInfo.processInfo.environment["BOOKS_DIR"] else { throw XCTSkip("Set TEST_RUNNER_BOOKS_DIR to a folder of sample books") }
        BookFonts.register()
        var on = ReaderSettings.defaults
        on.originalStyles = true
        let urls = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil).filter { $0.pathExtension == "epub" }
        for url in urls {
            let doc = try EpubDocument(url: url)
            for i in 0..<doc.chapterCount {
                let root = try doc.chapter(i)
                let plain = ChapterTextBuilder(style: TextStyle(settings: .defaults, text: .black, columnWidth: 320, pageHeight: 600, language: "en"), image: doc.image).build(root)
                let styled = ChapterTextBuilder(style: TextStyle(settings: on, text: .black, columnWidth: 320, pageHeight: 600, language: "en"), image: doc.image).build(root)
                XCTAssertEqual(styled.domLength, plain.domLength, "\(url.lastPathComponent) chapter \(i)")
                XCTAssertEqual(styled.domLength, root.textContent.utf16.count)
            }
        }
    }
}
