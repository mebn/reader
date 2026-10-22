import SwiftUI

/// Flat, book-themed sprites for the sign-in backdrop, drawn like the desktop's SVGs.
/// Each fills the width it is given.

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

extension Animation {
    /// The sign-in screen's easing: quick to start, long to settle.
    static func settle(_ duration: Double) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: duration) }
}

struct BookColors {
    var cover: UInt32
    var spine: UInt32
    var accent: UInt32

    static let clay = BookColors(cover: 0xd9663f, spine: 0xb9502d, accent: 0xf7e3b5)
    static let sage = BookColors(cover: 0x6f9a7e, spine: 0x567d65, accent: 0xf4efe2)
    static let ink = BookColors(cover: 0x46607f, spine: 0x344b67, accent: 0xf2c46d)
    static let mustard = BookColors(cover: 0xe0a93c, spine: 0xbf8a24, accent: 0x2f2a25)
    static let plum = BookColors(cover: 0x7d6590, spine: 0x624d75, accent: 0xf4efe2)
}

/// Draws in a fixed view box, scaled to the width it is given.
private struct Sprite: View {
    var width: CGFloat
    var height: CGFloat
    var draw: (inout GraphicsContext) -> Void

    var body: some View {
        Canvas { ctx, size in
            ctx.scaleBy(x: size.width / width, y: size.height / height)
            draw(&ctx)
        }
        .aspectRatio(width / height, contentMode: .fit)
        .shadow(color: Color(red: 40 / 255, green: 30 / 255, blue: 20 / 255).opacity(0.28), radius: 7, y: 10)
    }
}

private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, r: CGFloat = 0) -> Path {
    Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
}

private func poly(_ points: (CGFloat, CGFloat)...) -> Path {
    Path { p in
        p.addLines(points.map { CGPoint(x: $0.0, y: $0.1) })
        p.closeSubpath()
    }
}

private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

private extension GraphicsContext {
    func fill(_ path: Path, _ hex: UInt32, _ opacity: Double = 1) {
        fill(path, with: .color(Color(hex: hex).opacity(opacity)))
    }
}

struct ClosedBook: View {
    var colors: BookColors

    var body: some View {
        Sprite(width: 100, height: 140) { ctx in
            ctx.fill(rect(4, 4, 92, 132, r: 9), colors.cover)
            ctx.fill(UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 9).path(in: CGRect(x: 4, y: 4, width: 18, height: 132)), colors.spine)
            ctx.fill(rect(26, 4, 2, 132), 0xffffff, 0.28)
            ctx.fill(rect(40, 46, 42, 7, r: 3.5), colors.accent, 0.95)
            ctx.fill(rect(40, 60, 28, 7, r: 3.5), colors.accent, 0.55)
            ctx.fill(poly((70, 4), (82, 4), (82, 34), (76, 29), (70, 34)), colors.accent, 0.9)
        }
    }
}

struct BookStack: View {
    var body: some View {
        Sprite(width: 150, height: 106) { ctx in
            let rows: [(y: CGFloat, w: CGFloat, x: CGFloat, c: BookColors)] = [(74, 150, 0, .ink), (44, 128, 12, .clay), (14, 138, 4, .sage)]
            for (y, w, x, c) in rows {
                ctx.fill(rect(x, y, w, 28, r: 5), c.cover)
                ctx.fill(rect(x + w - 12, y, 12, 28, r: 4), 0xf4ecde, 0.92)
                ctx.fill(rect(x + 14, y + 8, 34, 5, r: 2.5), c.accent, 0.85)
                ctx.fill(rect(x + 14, y + 17, 20, 4, r: 2), c.accent, 0.5)
            }
        }
    }
}

struct OpenBook: View {
    var body: some View {
        Sprite(width: 170, height: 116) { ctx in
            // A page from its outer top corner, curving into the spine and back out along the bottom.
            func page(x: CGFloat, top: CGFloat, bottom: CGFloat, spine: ClosedRange<CGFloat>, controlX: CGFloat, controlY: ClosedRange<CGFloat>) -> Path {
                Path { p in
                    p.move(to: pt(x, top))
                    p.addQuadCurve(to: pt(85, spine.lowerBound), control: pt(controlX, controlY.lowerBound))
                    p.addLine(to: pt(85, spine.upperBound))
                    p.addQuadCurve(to: pt(x, bottom), control: pt(controlX, controlY.upperBound))
                    p.closeSubpath()
                }
            }
            ctx.fill(page(x: 6, top: 14, bottom: 104, spine: 20...110, controlX: 46, controlY: 2...92), 0xe8dcc6)
            ctx.fill(page(x: 164, top: 14, bottom: 104, spine: 20...110, controlX: 124, controlY: 2...92), 0xe8dcc6)
            ctx.fill(page(x: 10, top: 10, bottom: 98, spine: 16...104, controlX: 48, controlY: -1...88), 0xfbf6ec)
            ctx.fill(page(x: 160, top: 10, bottom: 98, spine: 16...104, controlX: 122, controlY: -1...88), 0xf6efe1)
            for (i, y) in [28, 42, 56, 70].map({ CGFloat($0) }).enumerated() {
                ctx.fill(rect(24, y, i == 3 ? 30 : 48, 4, r: 2), 0x46607f, 0.22)
                ctx.fill(rect(104, y - 2, i == 0 ? 34 : 42, 4, r: 2), 0x46607f, 0.22)
            }
            ctx.fill(rect(104, 80, 38, 4, r: 2), 0x46607f, 0.22)
            ctx.fill(rect(83, 16, 4, 92), 0x000000, 0.08)
        }
    }
}

struct Bookmark: View {
    var color: UInt32 = 0xd9663f

    var body: some View {
        Sprite(width: 40, height: 100) { ctx in
            ctx.fill(poly((4, 0), (36, 0), (36, 100), (20, 82), (4, 100)), color)
            ctx.fill(poly((10, 0), (14, 0), (14, 84), (10, 88)), 0xffffff, 0.22)
        }
    }
}

struct Glasses: View {
    var body: some View {
        Sprite(width: 130, height: 52) { ctx in
            let lenses = Path(ellipseIn: CGRect(x: 12, y: 8, width: 40, height: 40)).union(Path(ellipseIn: CGRect(x: 78, y: 8, width: 40, height: 40)))
            ctx.fill(lenses, 0xbfe0e8, 0.45)
            var frame = lenses
            frame.move(to: pt(52, 26))
            frame.addQuadCurve(to: pt(78, 26), control: pt(65, 18))
            frame.move(to: pt(12, 24))
            frame.addLine(to: pt(3, 14))
            frame.move(to: pt(118, 24))
            frame.addLine(to: pt(127, 14))
            ctx.stroke(frame, with: .color(Color(hex: 0x3a322b)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
    }
}

struct Cup: View {
    var body: some View {
        Sprite(width: 100, height: 100) { ctx in
            let steam = Path { p in
                for (x, top) in [(26.0, 6.0), (46, 2), (66, 6)] {
                    p.move(to: pt(x, top))
                    p.addQuadCurve(to: pt(x, 24), control: pt(x - 8, (top + 24) / 2 + 1))
                }
            }
            ctx.stroke(steam, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 4, lineCap: .round))

            let body = Path { p in
                p.move(to: pt(14, 34))
                p.addLine(to: pt(76, 34))
                p.addLine(to: pt(76, 56))
                p.addArc(tangent1End: pt(76, 82), tangent2End: pt(50, 82), radius: 26)
                p.addLine(to: pt(40, 82))
                p.addArc(tangent1End: pt(14, 82), tangent2End: pt(14, 56), radius: 26)
                p.closeSubpath()
            }
            ctx.fill(body, 0xf4ecde)
            let handle = Path { p in
                p.move(to: pt(76, 42))
                p.addLine(to: pt(82, 42))
                p.addArc(tangent1End: pt(92, 42), tangent2End: pt(92, 52), radius: 10)
                p.addArc(tangent1End: pt(92, 62), tangent2End: pt(82, 62), radius: 10)
                p.addLine(to: pt(74, 62))
            }
            ctx.stroke(handle, with: .color(Color(hex: 0xf4ecde)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
            ctx.fill(rect(14, 34, 62, 9, r: 4), 0x6b4a36)
            ctx.fill(Path(ellipseIn: CGRect(x: 7, y: 87, width: 76, height: 10)), 0xd9cdb8)
        }
    }
}

struct Pencil: View {
    var body: some View {
        Sprite(width: 36, height: 130) { ctx in
            ctx.fill(rect(4, 12, 28, 80, r: 4), 0xe0a93c)
            ctx.fill(rect(14, 12, 8, 80), 0xbf8a24, 0.5)
            ctx.fill(poly((4, 92), (32, 92), (18, 122)), 0xf4ecde)
            ctx.fill(poly((13, 111), (23, 111), (18, 122)), 0x3a322b)
            ctx.fill(rect(4, 2, 28, 12, r: 4), 0xd9663f)
            ctx.fill(rect(4, 12, 28, 5), 0xcfd4d9)
        }
    }
}

struct LoosePage: View {
    var body: some View {
        Sprite(width: 100, height: 130) { ctx in
            ctx.fill(poly((6, 4), (78, 4), (94, 20), (94, 126), (6, 126)), 0xfbf6ec)
            ctx.fill(poly((78, 4), (78, 20), (94, 20)), 0xe8dcc6)
            for (i, y) in [38, 52, 66, 80, 94].map({ CGFloat($0) }).enumerated() {
                ctx.fill(rect(18, y, i == 4 ? 30 : 62, 4, r: 2), 0x46607f, 0.2)
            }
            ctx.fill(rect(18, 20, 36, 6, r: 3), 0xd9663f, 0.7)
        }
    }
}

/// Books and bookish things that pop into place one after another, then stay put.
struct FloatingObjects: View {
    private struct Item {
        var art: AnyView
        /// Distance from the leading or trailing edge, and from the top, as fractions of the screen.
        var leading: CGFloat?
        var trailing: CGFloat?
        var top: CGFloat
        var width: CGFloat
        var rotate: Double
        /// Sits behind the text, so it drops out on narrow screens.
        var middle = false
        /// Where it goes on narrow screens instead, to keep clear of the form's links.
        var narrowTop: CGFloat?
    }

    private static let items: [Item] = [
        Item(art: AnyView(ClosedBook(colors: .clay)), leading: 0.05, top: 0.13, width: 84, rotate: -14),
        Item(art: AnyView(BookStack()), leading: 0.02, top: 0.46, width: 124, rotate: 6),
        Item(art: AnyView(Glasses()), leading: 0.09, top: 0.78, width: 96, rotate: -8, narrowTop: 0.9),
        Item(art: AnyView(Pencil()), leading: 0.24, top: 0.26, width: 26, rotate: 28, middle: true),
        Item(art: AnyView(ClosedBook(colors: .mustard)), leading: 0.19, top: 0.88, width: 54, rotate: 12, middle: true),

        Item(art: AnyView(OpenBook()), trailing: 0.05, top: 0.09, width: 142, rotate: 9),
        Item(art: AnyView(Cup()), trailing: 0.03, top: 0.44, width: 84, rotate: -6),
        Item(art: AnyView(ClosedBook(colors: .ink)), trailing: 0.09, top: 0.70, width: 78, rotate: 16, narrowTop: 0.86),
        Item(art: AnyView(ClosedBook(colors: .sage)), trailing: 0.26, top: 0.24, width: 46, rotate: -18, middle: true),
        Item(art: AnyView(LoosePage()), trailing: 0.20, top: 0.88, width: 58, rotate: 10, middle: true),
        Item(art: AnyView(Bookmark()), leading: 0.42, top: -0.02, width: 22, rotate: 0, middle: true),
        Item(art: AnyView(ClosedBook(colors: .plum)), leading: 0.14, top: 0.34, width: 40, rotate: -26, middle: true),
    ]

    @Environment(\.accessibilityReduceMotion) private var calm
    @State private var shown = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                ForEach(Self.items.indices, id: \.self) { i in
                    let item = Self.items[i]
                    if !(item.middle && size.width < 760) {
                        let x = item.leading.map { $0 * size.width } ?? size.width * (1 - item.trailing!) - item.width
                        let top = size.width < 560 ? item.narrowTop ?? item.top : item.top
                        item.art
                            .frame(width: item.width)
                            .scaleEffect(shown ? 1 : 0.4)
                            .rotationEffect(.degrees(shown ? item.rotate : item.rotate - 30))
                            .opacity(shown ? 1 : 0)
                            .animation(calm ? nil : .interpolatingSpring(stiffness: 120, damping: 14).delay(0.15 + Double(i) * 0.07), value: shown)
                            .opacity(size.width < 560 ? 0.4 : 1)
                            .offset(x: x, y: top * size.height)
                    }
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { shown = true }
    }
}
