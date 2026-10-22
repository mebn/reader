import SwiftUI

/// A closed book that opens, turns its pages and closes, like the desktop's CSS 3D one.
struct HeroBook: View {
    /// The book's width when closed.
    var width: CGFloat

    /// One loop, in seconds: the book opens, turns three pages, and closes again.
    private static let loop = 12.0
    /// Opens by .24, stays open until .78, closed again by .94.
    private static let coverTimes = [0, 0.08, 0.24, 0.78, 0.94, 1]
    private static let flipped = -168.0
    private static let rightRows: [CGFloat] = [100, 94, 100, 88, 100, 62]
    private static let leftRows: [CGFloat] = [96, 100, 84, 100, 92, 48]

    private static func leafTimes(_ i: Int) -> [Double] {
        let start = 0.3 + Double(i) * 0.12
        return [0, start, start + 0.11, 0.78, 0.94, 1]
    }

    @Environment(\.accessibilityReduceMotion) private var calm
    @Environment(\.colorScheme) private var scheme
    @State private var start = Date()
    @State private var shown = false

    private var height: CGFloat { width * 1.46 }

    var body: some View {
        TimelineView(.animation(paused: calm)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            let t = calm ? 0 : elapsed.truncatingRemainder(dividingBy: Self.loop) / Self.loop
            // Rests on the page: floats gently as a whole.
            let float = calm ? 0 : -3 * (1 - cos(elapsed * 2 * .pi / 5))
            book(at: t)
                .offset(y: float)
        }
        .frame(width: width * 2.2, height: height)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 24)
        .scaleEffect(shown ? 1 : 0.9)
        .onAppear { withAnimation(.settle(0.9).delay(0.1)) { shown = true } }
        .accessibilityHidden(true)
    }

    private func book(at t: Double) -> some View {
        let shift = key(t, Self.coverTimes, [0, 0, 0.5, 0.5, 0, 0])
        return ZStack(alignment: .topLeading) {
            tableShadow(at: t)
            pageBlock.zIndex(1)
            ForEach(0..<3) { i in leaf(i, at: t) }
            cover(at: t)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .offset(x: shift * width)
        .rotation3DEffect(.degrees(-16), axis: (0, 1, 0), perspective: 0.4)
        .rotation3DEffect(.degrees(8), axis: (1, 0, 0), perspective: 0.4)
    }

    private func tableShadow(at t: Double) -> some View {
        Ellipse()
            .fill(.black.opacity(scheme == .dark ? 0.6 : 0.3))
            .frame(width: width, height: height * 0.09)
            .blur(radius: 6)
            .scaleEffect(x: key(t, Self.coverTimes, [1, 1, 1.9, 1.9, 1, 1]), y: 1, anchor: .leading)
            .offset(x: key(t, Self.coverTimes, [0, 0, -0.48, -0.48, 0, 0]) * width, y: height)
    }

    /// The pages under the leaves, always at rest on the right.
    private var pageBlock: some View {
        let shape = UnevenRoundedRectangle(bottomTrailingRadius: width * 0.06, topTrailingRadius: width * 0.06)
        return ZStack(alignment: .topLeading) {
            shape.fill(Color(hex: 0xc9bda6)).offset(x: 4, y: 6)
            shape.fill(Color(hex: 0xd8cdb9)).offset(x: 2, y: 3)
            shape.fill(Color(hex: 0xf6efe1))
            PageLines(rows: Self.rightRows, heading: true, width: width)
        }
        .frame(width: width, height: height)
    }

    /// A sheet that turns about the spine: its front faces right, its back faces left once turned.
    private func leaf(_ i: Int, at t: Double) -> some View {
        let times = Self.leafTimes(i)
        let turned = Self.flipped + Double(i) * 2
        let angle = key(t, times, [0, 0, turned, turned, 0, 0])
        let rest = Double(4 - i), onLeft = Double(i + 1)
        return Group {
            if angle > -90 {
                ZStack(alignment: .topLeading) {
                    UnevenRoundedRectangle(bottomTrailingRadius: width * 0.06, topTrailingRadius: width * 0.06).fill(Color(hex: 0xfbf6ec))
                    PageLines(rows: Self.rightRows.map { $0 - CGFloat(i) * 3 }, heading: i == 1, width: width)
                }
            } else {
                ZStack(alignment: .topLeading) {
                    UnevenRoundedRectangle(topLeadingRadius: width * 0.06, bottomLeadingRadius: width * 0.06).fill(Color(hex: 0xf6efe1))
                    PageLines(rows: Self.leftRows.map { $0 - CGFloat(i) * 4 }, width: width)
                }
                .scaleEffect(x: -1)
            }
        }
        .frame(width: width, height: height)
        .rotation3DEffect(.degrees(angle), axis: (0, 1, 0), anchor: .leading, perspective: 0.5)
        .zIndex(key(t, times, [rest, rest, onLeft, onLeft, rest, rest]))
    }

    /// The cover, with the bookmark ribbon, and the endpaper inside it.
    private func cover(at t: Double) -> some View {
        let angle = key(t, Self.coverTimes, [0, 0, Self.flipped - 4, Self.flipped - 4, 0, 0])
        return Group {
            if angle > -90 {
                coverFront
            } else {
                coverInside.scaleEffect(x: -1)
            }
        }
        .frame(width: width, height: height)
        .rotation3DEffect(.degrees(angle), axis: (0, 1, 0), anchor: .leading, perspective: 0.5)
        .zIndex(key(t, Self.coverTimes, [6, 6, 0, 0, 6, 6]))
    }

    private var coverFront: some View {
        let bar = width * 0.055
        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(hex: 0xf7f1e6), Color(hex: 0xe8decc)], startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [Color(hex: 0xcfc3ae), Color(hex: 0xe0d6c3)], startPoint: .leading, endPoint: .trailing)
                .frame(width: width * 0.15)
            Rectangle().fill(.white.opacity(0.7)).frame(width: 1).offset(x: width * 0.15)
            Capsule().fill(Color(hex: 0x3d3630).opacity(0.85))
                .frame(width: width * 0.56, height: bar)
                .offset(x: width * 0.3, y: height * 0.34)
            Capsule().fill(Color(hex: 0x3d3630).opacity(0.35))
                .frame(width: width * 0.36, height: bar)
                .offset(x: width * 0.3, y: height * 0.34 + width * 0.11)
            LinearGradient(colors: [Color(hex: 0xe2744a), Color(hex: 0xc9532c)], startPoint: .top, endPoint: .bottom)
                .frame(width: width * 0.12, height: height * 0.3)
                .clipShape(Ribbon())
                .offset(x: width * 0.76)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: width * 0.06, bottomLeadingRadius: width * 0.06, bottomTrailingRadius: width * 0.08, topTrailingRadius: width * 0.08))
    }

    private var coverInside: some View {
        ZStack {
            UnevenRoundedRectangle(topLeadingRadius: width * 0.06, bottomLeadingRadius: width * 0.06).fill(Color(hex: 0x3d3630))
            RoundedRectangle(cornerRadius: width * 0.03)
                .strokeBorder(Color(hex: 0xf4ecde).opacity(0.2))
                .padding(width * 0.12)
            RoundedRectangle(cornerRadius: width * 0.04)
                .fill(Color(hex: 0xf4ecde).opacity(0.9))
                .frame(width: width * 0.46, height: height * 0.26)
        }
    }
}

/// Ruled lines standing in for text, as widths in percent of the line.
private struct PageLines: View {
    var rows: [CGFloat]
    var heading = false
    var width: CGFloat

    var body: some View {
        let line = width * 0.68
        VStack(alignment: .leading, spacing: width * 0.085) {
            if heading {
                Capsule().fill(Color(hex: 0xd9663f).opacity(0.7)).frame(width: line * 0.46, height: width * 0.05)
            }
            ForEach(rows.indices, id: \.self) { i in
                Capsule().fill(Color(hex: 0x46607f).opacity(0.2)).frame(width: line * rows[i] / 100, height: width * 0.032)
            }
        }
        .padding(.leading, width * 0.16)
        .padding(.top, width * 1.46 * 0.14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A bookmark ribbon's notched end.
private struct Ribbon: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.addLines([CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY),
                        CGPoint(x: r.midX, y: r.minY + r.height * 0.82), CGPoint(x: r.minX, y: r.maxY)])
            p.closeSubpath()
        }
    }
}

/// The value at `t` (0–1) of a keyframed track, eased in and out between keyframes.
private func key(_ t: Double, _ times: [Double], _ values: [Double]) -> Double {
    for k in 1..<times.count where t <= times[k] {
        let span = times[k] - times[k - 1]
        let p = span > 0 ? (t - times[k - 1]) / span : 1
        return values[k - 1] + (values[k] - values[k - 1]) * p * p * (3 - 2 * p)
    }
    return values[values.count - 1]
}
