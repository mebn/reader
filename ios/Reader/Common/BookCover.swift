import SwiftUI

/// Covers fetched from the server, kept in memory and in the URL cache.
@MainActor
final class Covers {
    static let shared = Covers()
    private let cache = NSCache<NSString, UIImage>()
    private var loading: [String: Task<UIImage?, Never>] = [:]

    func cached(_ book: Book) -> UIImage? {
        cache.object(forKey: key(book))
    }

    func load(_ book: Book) async -> UIImage? {
        guard book.hasCover, let session = SyncEngine.shared.session else { return nil }
        let key = key(book)
        if let image = cache.object(forKey: key) { return image }
        if let task = loading[key as String] { return await task.value }
        let url = API.coverURL(session, book: book)
        let task = Task.detached(priority: .utility) { () -> UIImage? in
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return await UIImage(data: data)?.byPreparingForDisplay()
        }
        loading[key as String] = task
        let image = await task.value
        loading[key as String] = nil
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    private func key(_ book: Book) -> NSString { "\(book.id)|\(book.modifiedAt)" as NSString }
}

private let tints: [Color] = [0x5b6b7a, 0x7a5b5b, 0x5b7a65, 0x6d5b7a, 0x7a6d5b, 0x4f6f78, 0x7a5b6f, 0x62705a].map { Color(uiColor: UIColor(hex: $0)) }

/// The same tint the desktop app picks for a title.
func coverTint(_ seed: String) -> Color {
    var h: UInt32 = 0
    for scalar in seed.unicodeScalars {
        let unit = String(scalar).utf16.first ?? 0
        h = h &* 31 &+ UInt32(unit)
    }
    return tints[Int(h % UInt32(tints.count))]
}

/// A book's cover, or a typographic stand-in when it has none.
struct BookCover: View {
    var book: Book
    var cornerRadius: CGFloat = 6
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                if let image = image ?? Covers.shared.cached(book) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
            .overlay(alignment: .leading) {
                // The spine's shadow.
                GeometryReader { geo in
                    LinearGradient(colors: [.black.opacity(0.15), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.05)
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.primary.opacity(0.06)))
            .task(id: "\(book.id)|\(book.modifiedAt)") {
                if book.hasCover { image = await Covers.shared.load(book) }
            }
    }

    private var placeholder: some View {
        let tint = coverTint(book.title)
        return GeometryReader { geo in
            VStack(alignment: .leading) {
                Text(book.title)
                    .font(.system(size: max(9, geo.size.width * 0.12)).weight(.medium))
                    .lineLimit(5)
                Spacer(minLength: 0)
                Text(book.author)
                    .font(.system(size: max(7, geo.size.width * 0.08)))
                    .opacity(0.75)
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
            .padding(geo.size.width * 0.09)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(LinearGradient(colors: [tint, tint.mix(with: .black, by: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}
