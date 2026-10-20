import XCTest

/// Walks through the app and saves screenshots to SCREENSHOTS_DIR for review.
final class ReaderUITests: XCTestCase {
    private var app: XCUIApplication!
    private var shots = 0

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
    }

    private func shot(_ name: String) {
        shots += 1
        let png = XCUIScreen.main.screenshot().pngRepresentation
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOTS_DIR"] {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "%02d-%@.png", shots, name)))
        }
    }

    @MainActor
    func testTour() throws {
        app.launch()
        let library = app.navigationBars["Library"]
        XCTAssertTrue(library.waitForExistence(timeout: 15))
        sleep(3)
        shot("library")

        app.buttons["Highlights"].firstMatch.tap()
        sleep(1)
        shot("library-highlights")
        app.buttons["All"].firstMatch.tap()

        // Open the book in Continue reading, or the first book.
        let pride = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Pride'")).firstMatch
        XCTAssertTrue(pride.waitForExistence(timeout: 5))
        pride.tap()
        sleep(4)
        shot("reader-chrome")
        // Let the toolbar hide, then turn a few pages.
        sleep(3)
        shot("reader-page")
        let window = app.windows.firstMatch
        for _ in 0..<3 {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            usleep(600_000)
        }
        shot("reader-turned")

        // Jump to the first chapter from the contents.
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)
        app.buttons["reader.contents"].tap()
        sleep(1)
        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'CHAPTER I.' OR label CONTAINS 'Chapter I.'")).firstMatch
        for _ in 0..<12 where !first.isHittable { app.swipeDown(velocity: .slow) }
        if first.exists { first.tap() }
        sleep(2)
        shot("reader-chapter")

        // Select a word and highlight it from the edit menu.
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        sleep(1)
        let text = app.textViews.allElementsBoundByIndex.first { $0.frame.width > 100 } ?? app.textViews.firstMatch
        text.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)).press(forDuration: 1.0)
        sleep(1)
        shot("reader-selection")
        let highlight = app.menuItems["Highlight"].firstMatch
        if highlight.waitForExistence(timeout: 2) {
            highlight.tap()
            sleep(1)
            shot("reader-highlighted")
        }

        // Toolbar, contents and appearance.
        // Pressing an existing highlight opens its editor instead.
        if app.textFields["Note"].exists || app.textViews["Note"].exists {
            shot("highlight-editor")
            app.buttons["editor.done"].tap()
            sleep(1)
        }
        for _ in 0..<3 where !app.buttons["reader.contents"].exists {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap()
            sleep(1)
        }
        shot("reader-toolbar")
        app.buttons["reader.contents"].tap()
        sleep(2)
        shot("contents")
        app.swipeDown(velocity: .fast)
        sleep(1)
        if !app.buttons["reader.appearance"].exists { window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); sleep(1) }
        app.buttons["reader.appearance"].tap()
        sleep(2)
        shot("appearance")
        app.buttons["Page"].firstMatch.tap()
        sleep(1)
        shot("appearance-page")
        app.buttons["Dark"].firstMatch.tap()
        sleep(2)
        shot("appearance-dark")
        app.buttons["Light"].firstMatch.tap()
        app.swipeDown(velocity: .fast)
        sleep(1)

        // The highlight shows up in the library's notes.
        if !app.buttons["reader.close"].exists { window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); sleep(1) }
        app.buttons["reader.close"].tap()
        sleep(2)
        app.buttons["Highlights"].firstMatch.tap()
        sleep(1)
        shot("library-highlights-after")
        app.buttons["All"].firstMatch.tap()

        // A PDF.
        app.staticTexts["attention"].firstMatch.tap()
        sleep(4)
        shot("pdf")
        if !app.buttons["reader.close"].exists { window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); sleep(1) }
        app.buttons["reader.close"].tap()
        sleep(2)

        // Settings.
        app.buttons["library.settings"].tap()
        sleep(2)
        shot("settings")
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Reading'")).firstMatch.tap()
        sleep(2)
        shot("settings-reading")
        app.navigationBars["Reading"].buttons.element(boundBy: 0).tap()
        sleep(1)
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Account'")).firstMatch.tap()
        sleep(2)
        shot("settings-account")
    }
}
