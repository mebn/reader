import SwiftUI

/// Page color for light and dark. `dark` picks which one is being edited.
struct PageSettingsSection: View {
    @Binding var settings: ReaderSettings
    @Binding var dark: Bool

    var body: some View {
        Picker("Mode", selection: $dark) {
            Text("Light").tag(false)
            Text("Dark").tag(true)
        }
        .pickerStyle(.segmented)

        LabeledContent("Background") {
            HStack(spacing: 10) {
                ForEach(PageBackground.all.filter { $0.dark == dark }) { bg in
                    let selected = (dark ? settings.darkBackground : settings.lightBackground) == bg.id
                    Button {
                        if dark { settings.darkBackground = bg.id } else { settings.lightBackground = bg.id }
                    } label: {
                        Circle()
                            .fill(bg.color)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(.primary.opacity(0.15)))
                            .padding(3)
                            .overlay(Circle().strokeBorder(selected ? Color.primary : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(bg.id.capitalized)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}

struct TextSettingsSection: View {
    @Binding var settings: ReaderSettings

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(FontOption.all) { font in
                let selected = settings.font == font.id
                Button {
                    settings.font = font.id
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Aa").font(Font(BookFonts.font(font.id, size: 20, weight: 400)))
                        Text(font.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(selected ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor : .primary.opacity(0.12), lineWidth: selected ? 1.5 : 1))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)

        StepperRow(label: "Size", value: $settings.fontSize, range: 12...34, step: 1) { "\(Int($0))" }
        StepperRow(label: "Line height", value: $settings.lineHeight, range: 1.1...2.4, step: 0.05) { String(format: "%.2f", $0) }
        StepperRow(label: "Weight", value: $settings.weight, range: 300...700, step: 50) { "\(Int($0))" }
        StepperRow(label: "Spacing", value: $settings.tracking, range: -0.03...0.12, step: 0.005) { String(format: "%.1f", $0 * 100) }
    }
}

struct LayoutSettingsSection: View {
    @Binding var settings: ReaderSettings

    var body: some View {
        StepperRow(label: "Margins", value: $settings.sideMargin, range: 0...40, step: 1) { $0 == 0 ? "None" : "\(Int($0))%" }
        StepperRow(label: "Paragraphs", value: $settings.paragraphSpacing, range: 0...2, step: 0.1) { String(format: "%.1f", $0) }
        Picker("Align", selection: $settings.align) {
            Text("Left").tag(TextAlign.left)
            Text("Justify").tag(TextAlign.justify)
        }
        PagesPicker(settings: $settings)
        PageTurnPicker(settings: $settings)
        Toggle("Hyphenation", isOn: $settings.hyphenate)
        Toggle("Original styles", isOn: $settings.originalStyles)
    }
}

/// One page at a time, or two facing pages on a wide screen.
struct PagesPicker: View {
    @Binding var settings: ReaderSettings

    var body: some View {
        Picker("Pages", selection: $settings.pages) {
            Text("One").tag(1)
            Text("Two").tag(2)
        }
    }
}

/// Whether a page changes at once, fades or slides in.
struct PageTurnPicker: View {
    @Binding var settings: ReaderSettings

    var body: some View {
        Picker("Page turn", selection: $settings.pageTurn) {
            Text("Instant").tag(PageTurn.instant)
            Text("Fade").tag(PageTurn.fade)
            Text("Slide").tag(PageTurn.slide)
        }
    }
}

struct HeaderSettingsSection: View {
    @Binding var settings: ReaderSettings

    var body: some View {
        Toggle("Book title", isOn: $settings.headerTitle)
        Toggle("Author", isOn: $settings.headerAuthor)
        Toggle("Chapter title", isOn: $settings.headerChapter)
        Toggle("Clock", isOn: $settings.headerClock)
    }
}

struct FooterSettingsSection: View {
    @Binding var settings: ReaderSettings

    var body: some View {
        Toggle("Chapter title", isOn: $settings.footerChapter)
        Toggle("Page in chapter", isOn: $settings.footerChapterPages)
        Toggle("Page in book", isOn: $settings.footerBookPages)
        Toggle("Percent read", isOn: $settings.footerPercent)
    }
}

/// A setting stepped a notch at a time: [−] value [+]. Holding a button keeps stepping.
struct StepperRow: View {
    var label: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var format: (Double) -> String

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                button(-1, "minus", "Decrease")
                Text(format(value))
                    .font(.body.monospacedDigit())
                    .frame(minWidth: 52)
                    .contentTransition(.numericText(value: value))
                button(1, "plus", "Increase")
            }
            .background(.fill.tertiary, in: .capsule)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: change(1)
            case .decrement: change(-1)
            @unknown default: break
            }
        }
    }

    private func button(_ direction: Double, _ symbol: String, _ name: String) -> some View {
        let limit = direction < 0 ? range.lowerBound : range.upperBound
        return Button { change(direction) } label: {
            Image(systemName: symbol)
                .frame(width: 44, height: 34)
                .contentShape(.rect)
        }
        // Borderless, or a tap anywhere in the form row presses both buttons.
        .buttonStyle(.borderless)
        .buttonRepeatBehavior(.enabled)
        .disabled(abs(value - limit) < step / 2)
        .accessibilityLabel(name)
    }

    private func change(_ direction: Double) {
        let next = ((value + direction * step) / step).rounded() * step
        withAnimation(.snappy(duration: 0.15)) { value = min(max(next, range.lowerBound), range.upperBound) }
    }
}

/// A small page that shows how the settings will read.
struct SettingsPreview: UIViewRepresentable {
    var settings: ReaderSettings
    var dark: Bool

    private static let sample = Node.element("body", [:], [
        .element("h3", [:], [.text("One")]),
        .element("p", [:], [.text("It was a bright cold day in April, and the clocks were striking thirteen. The hallway smelt of boiled cabbage and old rag mats.")]),
        .element("p", [:], [.text("At one end of it a coloured poster, too large for indoor display, had been tacked to the wall.")]),
    ])

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = false
        view.textContainer.lineFragmentPadding = 0
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let bg = settings.background(dark: dark)
        var scaled = settings
        scaled.fontSize = settings.fontSize * 0.8
        let width: CGFloat = 300
        let margin = width * settings.sideMargin / 100 * 0.6
        let style = TextStyle(settings: scaled, text: bg.uiText, columnWidth: width - margin * 2, pageHeight: 400, language: "en")
        view.backgroundColor = bg.uiColor
        view.textContainerInset = UIEdgeInsets(top: 20, left: margin, bottom: 20, right: margin)
        view.attributedText = ChapterTextBuilder(style: style, image: { _ in nil }).build(Self.sample).string
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        return CGSize(width: width, height: width * 4 / 3)
    }
}
