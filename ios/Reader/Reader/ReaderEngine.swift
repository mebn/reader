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
    /// The text a locator covers, as a selection would give it; nil when it can't be read.
    func text(of locator: Locator) -> String?
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
    func engineHighlight(_ selection: TextSelection, withNote: Bool)
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

/// Plays page turns. A turn asked for while one plays ends that one at once, so quick
/// taps land on the newest page rather than queueing up.
@MainActor
final class PageTurner {
    private weak var host: UIViewController?
    /// The page controller showing, for engines that show pages as child controllers.
    private(set) var page: UIViewController?
    private var animator: UIViewPropertyAnimator?
    private var cleanup: (() -> Void)?

    init(host: UIViewController? = nil) {
        self.host = host
    }

    /// Puts a page controller on screen in place of the one showing, turning to it as `style`
    /// says; nil just swaps them, as for a jump.
    func show(_ next: UIViewController, style: PageTurn?, forward: Bool) {
        finish()
        guard next !== page, let host else { return }
        let old = page
        page = next
        if next.parent !== host { host.addChild(next) }
        next.view.frame = host.view.bounds
        next.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if let old { host.view.insertSubview(next.view, aboveSubview: old.view) } else { host.view.insertSubview(next.view, at: 0) }
        next.didMove(toParent: host)
        guard let old else { return }
        let drop = {
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        if let style { turn(from: old.view, to: next.view, style: style, forward: forward, done: drop) } else { drop() }
    }

    /// Turns from one view to another, both on screen; `done` runs once the old one is gone.
    func turn(from old: UIView, to new: UIView, style: PageTurn, forward: Bool, done: @escaping () -> Void) {
        finish()
        // Sliding is motion; with Reduce Motion pages fade instead.
        let style = style == .slide && UIAccessibility.isReduceMotionEnabled ? .fade : style
        let animator: UIViewPropertyAnimator
        switch style {
        case .instant:
            done()
            return
        case .fade:
            old.superview?.bringSubviewToFront(old)
            animator = UIViewPropertyAnimator(duration: 0.2, curve: .easeInOut) { old.alpha = 0 }
        case .slide:
            let width = new.superview?.bounds.width ?? new.bounds.width
            new.transform = CGAffineTransform(translationX: forward ? width : -width, y: 0)
            animator = UIViewPropertyAnimator(duration: 0.25, curve: .easeOut) {
                new.transform = .identity
                old.transform = CGAffineTransform(translationX: forward ? -width : width, y: 0)
            }
        }
        cleanup = {
            old.alpha = 1
            old.transform = .identity
            new.transform = .identity
            done()
        }
        animator.addCompletion { [weak self, weak animator] _ in
            guard let self, let animator, self.animator === animator else { return }
            self.animator = nil
            self.ended()
        }
        self.animator = animator
        animator.startAnimation()
    }

    /// Ends the turn playing, if any, with the new page in place.
    func finish() {
        guard let animator else { return }
        self.animator = nil
        animator.stopAnimation(true)
        ended()
    }

    private func ended() {
        let cleanup = self.cleanup
        self.cleanup = nil
        cleanup?()
    }
}
