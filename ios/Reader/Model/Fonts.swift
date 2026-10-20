import CoreText
import UIKit

struct FontOption: Identifiable {
    var id: String
    var label: String
    /// The family name of a bundled font, or nil for the system font.
    var family: String?
    /// Whether the font has a weight axis, so any weight can be drawn.
    var variable: Bool

    static let all: [FontOption] = [
        .init(id: "literata", label: "Literata", family: "Literata", variable: true),
        .init(id: "source-serif", label: "Source Serif", family: "Source Serif 4", variable: true),
        .init(id: "lora", label: "Lora", family: "Lora", variable: true),
        .init(id: "merriweather", label: "Merriweather", family: "Merriweather", variable: true),
        .init(id: "garamond", label: "EB Garamond", family: "EB Garamond", variable: true),
        .init(id: "georgia", label: "Georgia", family: "Georgia", variable: false),
        .init(id: "inter", label: "Inter", family: "Inter", variable: true),
        .init(id: "atkinson", label: "Atkinson", family: "Atkinson Hyperlegible", variable: false),
        .init(id: "system", label: "System", family: nil, variable: false),
    ]

    static func find(_ id: String) -> FontOption { all.first { $0.id == id } ?? all[0] }
}

enum BookFonts {
    /// Registers the bundled fonts once, at launch.
    static func register() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }

    private static let weightAxis = 0x77676874 // 'wght'

    private static let cache = NSCache<NSString, UIFont>()

    /// A font for book text. `weight` is CSS-style (100–900); variable fonts get it exactly.
    static func font(_ id: String, size: CGFloat, weight: Double, italic: Bool = false, monospace: Bool = false) -> UIFont {
        let key = "\(id)|\(size)|\(weight)|\(italic)|\(monospace)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let font = makeFont(id, size: size, weight: weight, italic: italic, monospace: monospace)
        cache.setObject(font, forKey: key)
        return font
    }

    private static func makeFont(_ id: String, size: CGFloat, weight: Double, italic: Bool, monospace: Bool) -> UIFont {
        if monospace {
            return UIFont.monospacedSystemFont(ofSize: size, weight: uiWeight(weight))
        }
        let option = FontOption.find(id)
        guard let family = option.family else {
            var font = UIFont.systemFont(ofSize: size, weight: uiWeight(weight))
            if italic, let d = font.fontDescriptor.withSymbolicTraits(.traitItalic) { font = UIFont(descriptor: d, size: size) }
            return font
        }

        var traits: UIFontDescriptor.SymbolicTraits = []
        if italic { traits.insert(.traitItalic) }
        if !option.variable && weight >= 600 { traits.insert(.traitBold) }
        var descriptor = UIFontDescriptor(fontAttributes: [.family: family])
        if let d = descriptor.withSymbolicTraits(traits) { descriptor = d }
        if option.variable {
            descriptor = descriptor.addingAttributes([kCTFontVariationAttribute as UIFontDescriptor.AttributeName: [weightAxis: weight]])
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func uiWeight(_ weight: Double) -> UIFont.Weight {
        switch weight {
        case ..<250: .thin
        case ..<350: .light
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        case ..<750: .bold
        default: .heavy
        }
    }
}
