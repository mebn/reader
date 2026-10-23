import SwiftUI

enum ThemeMode: String, Codable, CaseIterable {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum LibraryTab: String, Codable, CaseIterable, Identifiable {
    case all, books, bookmarks, highlights, notes
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .books: "Books"
        case .highlights: "Highlights"
        case .notes: "Notes"
        case .bookmarks: "Bookmarks"
        }
    }
}

enum TextAlign: String, Codable {
    case left, justify
}

/// How a page gives way to the next.
enum PageTurn: String, Codable {
    case instant, fade, slide
}

/// Settings for how books look. Stored as JSON in the "reader" scope (defaults) and in
/// "reader:<bookId>" (only what a book changes), the same shape the desktop app uses.
struct ReaderSettings: Codable, Equatable {
    /// Background ids for the page while the app is light and while it is dark.
    var lightBackground = "paper"
    var darkBackground = "night"
    var font = "literata"
    var fontSize: Double = 19
    var lineHeight: Double = 1.6
    var weight: Double = 400
    var tracking: Double = 0
    var paragraphSpacing: Double = 0.6
    /// Space beside the text on each side, as a percentage of the width; 0 is none.
    var sideMargin: Double = 20
    var align: TextAlign = .justify
    var hyphenate = true
    /// Shows the book in its own CSS instead of the reader's look.
    var originalStyles = false
    var pages = 1
    var pageTurn: PageTurn = .slide
    /// What the header shows.
    var headerTitle = true
    var headerAuthor = false
    var headerChapter = false
    var headerClock = false
    /// What the line under the text shows.
    var footerChapter = false
    var footerChapterPages = true
    var footerBookPages = true
    var footerPercent = false

    static let defaults = ReaderSettings()

    /// Every key this type reads, so foreign keys in a book's override are ignored.
    static let keys: Set<String> = Set(((try? JSONSerialization.jsonObject(with: JSONEncoder().encode(defaults))) as? [String: Any])?.keys.map { $0 } ?? [])

    init() {}

    /// Missing keys keep their defaults, so older and newer clients read each other's settings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReaderSettings.defaults
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        lightBackground = v(.lightBackground, d.lightBackground)
        darkBackground = v(.darkBackground, d.darkBackground)
        font = v(.font, d.font)
        fontSize = v(.fontSize, d.fontSize)
        lineHeight = v(.lineHeight, d.lineHeight)
        weight = v(.weight, d.weight)
        tracking = v(.tracking, d.tracking)
        paragraphSpacing = v(.paragraphSpacing, d.paragraphSpacing)
        sideMargin = v(.sideMargin, d.sideMargin)
        align = v(.align, d.align)
        hyphenate = v(.hyphenate, d.hyphenate)
        originalStyles = v(.originalStyles, d.originalStyles)
        pages = v(.pages, d.pages) == 2 ? 2 : 1
        pageTurn = v(.pageTurn, d.pageTurn)
        headerTitle = v(.headerTitle, d.headerTitle)
        headerAuthor = v(.headerAuthor, d.headerAuthor)
        headerChapter = v(.headerChapter, d.headerChapter)
        headerClock = v(.headerClock, d.headerClock)
        footerChapter = v(.footerChapter, d.footerChapter)
        footerChapterPages = v(.footerChapterPages, d.footerChapterPages)
        footerBookPages = v(.footerBookPages, d.footerBookPages)
        footerPercent = v(.footerPercent, d.footerPercent)
    }

    /// Settings that change the text layout, used to cache page counts.
    func layoutKey(width: CGFloat, height: CGFloat) -> String {
        [font, "\(fontSize)", "\(lineHeight)", "\(weight)", "\(tracking)", "\(paragraphSpacing)", "\(sideMargin)", align.rawValue, "\(hyphenate)", "\(originalStyles)", "\(pages)", "\(Int(width))", "\(Int(height))"]
            .joined(separator: "|")
    }

    func background(dark: Bool) -> PageBackground {
        PageBackground.find(dark ? darkBackground : lightBackground) ?? PageBackground.find(dark ? "night" : "paper")!
    }
}

struct AppSettings: Codable, Equatable {
    /// Light or dark for the whole app, the reader included.
    var theme: ThemeMode = .system
    var openInNewWindow = false
    /// The library tab shown when the app starts.
    var defaultTab: LibraryTab = .all

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        theme = (try? c.decodeIfPresent(ThemeMode.self, forKey: .theme)) ?? .system
        openInNewWindow = (try? c.decodeIfPresent(Bool.self, forKey: .openInNewWindow)) ?? false
        defaultTab = (try? c.decodeIfPresent(LibraryTab.self, forKey: .defaultTab)) ?? .all
    }
}

enum Scope {
    static let app = "app"
    static let reader = "reader"
    static func book(_ id: String) -> String { "reader:\(id)" }
}

struct PageBackground: Identifiable, Equatable {
    var id: String
    var color: Color
    var text: Color
    var uiColor: UIColor
    var uiText: UIColor
    var dark: Bool

    init(_ id: String, _ color: UInt32, _ text: UInt32, dark: Bool) {
        self.id = id
        self.uiColor = UIColor(hex: color)
        self.uiText = UIColor(hex: text)
        self.color = Color(uiColor: uiColor)
        self.text = Color(uiColor: uiText)
        self.dark = dark
    }

    static let all: [PageBackground] = [
        .init("paper", 0xfbfaf7, 0x26231f, dark: false),
        .init("white", 0xffffff, 0x151515, dark: false),
        .init("cream", 0xf5eedf, 0x2e2820, dark: false),
        .init("sepia", 0xebdcc0, 0x3a2e20, dark: false),
        .init("sage", 0xe1e8dc, 0x1f2a20, dark: false),
        .init("slate", 0x2a2d33, 0xd6d7d9, dark: true),
        .init("night", 0x18181a, 0xcfccc6, dark: true),
        .init("black", 0x000000, 0xb3b1ad, dark: true),
    ]

    static func find(_ id: String) -> PageBackground? { all.first { $0.id == id } }
}

let highlightColors: [(name: String, color: UIColor)] = [
    ("yellow", UIColor(hex: 0xf5c84c)),
    ("green", UIColor(hex: 0x7fcf8a)),
    ("blue", UIColor(hex: 0x6fb3f0)),
    ("pink", UIColor(hex: 0xf08fb8)),
]

func highlightColor(_ name: String) -> UIColor {
    highlightColors.first { $0.name == name }?.color ?? highlightColors[0].color
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

// MARK: - Parsing

/// Older saved settings: one background for both modes, and a header that showed one
/// thing ("title", "chapter" or "none") rather than a set of switches.
private func migrate(_ object: inout [String: Any]) {
    if let header = object["header"] as? String, object["headerTitle"] == nil {
        object["headerTitle"] = header == "title"
        object["headerChapter"] = header == "chapter"
    }
    if let id = object["background"] as? String, let old = PageBackground.find(id),
       object["lightBackground"] == nil, object["darkBackground"] == nil {
        object[old.dark ? "darkBackground" : "lightBackground"] = old.id
    }
}

/// The keys a settings record sets, after migrating older shapes.
func settingsObject(_ data: String?) -> [String: Any] {
    guard let data, let parsed = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any] else { return [:] }
    var object = parsed
    migrate(&object)
    return object
}

/// Decodes settings over a base, keeping the base for anything not set.
func decodeSettings<T: Codable>(_ object: [String: Any], over base: T) -> T {
    guard var merged = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(base))) as? [String: Any] else { return base }
    for (k, v) in object where merged[k] != nil { merged[k] = v }
    guard let data = try? JSONSerialization.data(withJSONObject: merged) else { return base }
    return (try? JSONDecoder().decode(T.self, from: data)) ?? base
}

/// The keys where `settings` differs from `base`, as a JSON object.
func settingsDiff<T: Codable>(_ settings: T, from base: T) -> [String: Any] {
    guard let a = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(settings))) as? [String: Any],
          let b = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(base))) as? [String: Any] else { return [:] }
    return a.filter { k, v in !(b[k].map { NSDictionary(dictionary: ["v": $0]).isEqual(to: ["v": v]) } ?? false) }
}

func encodeSettings<T: Encodable>(_ settings: T) -> String {
    String(decoding: (try? JSONEncoder().encode(settings)) ?? Data("{}".utf8), as: UTF8.self)
}
