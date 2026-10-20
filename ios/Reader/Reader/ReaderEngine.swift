import UIKit

struct Position: Equatable {
    /// 0-based chapter, or nil when the book has no chapters.
    var chapter: Int?
    var chapterCount: Int
    /// 1-based page; nil while page numbers are still being computed.
    var page: Int?
    var pageCount: Int?
    /// 1-based page within the current chapter, or nil when the book has no chapters.
    var chapterPage: Int?
    var chapterPageCount: Int?
    /// 0–1 through the whole book.
    var percent: Double
    var locator: Locator
}

struct Appearance: Equatable {
    var settings: ReaderSettings
    var background: PageBackground
}

struct TextSelection: Equatable {
    var locator: Locator
    var text: String
}

/// What the reader screen asks of the view that shows the pages.
@MainActor
protocol ReaderEngine: AnyObject {
    var position: Position? { get }
    func setAppearance(_ appearance: Appearance)
    func setAnnotations(_ annotations: [Annotation])
    func goTo(_ locator: Locator)
    func goTo(_ entry: TocEntry)
    func turn(forward: Bool)
    /// Whether a locator is on the page(s) showing.
    func isVisible(_ locator: Locator) -> Bool
    /// The 1-based book page a locator falls on, or nil while pages are still being counted.
    func pageOf(_ locator: Locator) -> Int?
    func clearSelection()
    /// Whether the reader is at or past a contents entry.
    func hasReached(_ entry: TocEntry) -> Bool
}

/// What the page views tell the reader screen.
@MainActor
protocol ReaderEngineDelegate: AnyObject {
    func engineChanged(_ position: Position)
    /// A tap that hit nothing in particular, at this fraction of the width.
    func engineTapped(atFraction x: CGFloat)
    func engineTappedAnnotation(_ id: String)
    func engineSelected(_ selection: TextSelection?)
    func engineHighlight(_ selection: TextSelection, color: String, withNote: Bool)
    func engineOpen(_ url: URL)
}

/// Selected text the way it's stored: whitespace collapsed, no object placeholders.
func normalizedSelection(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{FFFC}", with: "")
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
}

/// Turns pages from a hardware keyboard.
final class PageKeys {
    static func commands(_ target: Selector, _ back: Selector) -> [UIKeyCommand] {
        let forward = [UIKeyCommand.inputRightArrow, " ", UIKeyCommand.inputPageDown].map {
            UIKeyCommand(input: $0, modifierFlags: [], action: target)
        }
        let backward = [UIKeyCommand.inputLeftArrow, UIKeyCommand.inputPageUp].map {
            UIKeyCommand(input: $0, modifierFlags: [], action: back)
        } + [UIKeyCommand(input: " ", modifierFlags: .shift, action: back)]
        let all = forward + backward
        all.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return all
    }
}
