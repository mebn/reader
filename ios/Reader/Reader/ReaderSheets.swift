import SwiftUI

/// Contents, highlights and bookmarks of the open book. Picking one jumps there.
struct ContentsSheet: View {
    let model: ReaderModel
    @Environment(\.dismiss) private var dismiss
    @State private var tab = Tab.contents

    enum Tab: String, CaseIterable {
        case contents = "Contents"
        case notes = "Notes"
        case bookmarks = "Bookmarks"
    }

    private var notes: [Annotation] { sorted(.highlight) }
    private var bookmarks: [Annotation] { sorted(.bookmark) }

    private func sorted(_ kind: AnnotationKind) -> [Annotation] {
        model.annotations.filter { $0.kind == kind }.sorted { $0.position.sortKey < $1.position.sortKey }
    }

    private var isEmpty: Bool {
        switch tab {
        case .contents: model.toc.isEmpty
        case .notes: notes.isEmpty
        case .bookmarks: bookmarks.isEmpty
        }
    }

    /// One list whose rows change with the tab, as the appearance sheet keeps one form: a
    /// list per tab made the bar lay itself out again, and the tabs jump, on every switch.
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    switch tab {
                    case .contents: contents
                    case .notes: annotationRows(notes)
                    case .bookmarks: annotationRows(bookmarks)
                    }
                }
                .listStyle(.plain)
                .overlay { if isEmpty { empty } }
                // The chapter being read is centered rather than the list starting at the top.
                .onAppear { centerCurrent(proxy) }
                .onChange(of: tab) { if tab == .contents { centerCurrent(proxy) } }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Show", selection: $tab) {
                        ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    // A set width keeps the segments equal; sized to their labels, the bolder
                    // selected one would resize the control and shift the whole bar on every tap.
                    .frame(width: 240)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }

    private func centerCurrent(_ proxy: ScrollViewProxy) {
        if let id = model.currentEntry?.id { proxy.scrollTo(id, anchor: .center) }
    }

    @ViewBuilder private var contents: some View {
        ForEach(model.toc) { entry in
            let current = entry == model.currentEntry
            Button {
                model.go(entry)
                dismiss()
            } label: {
                Text(entry.label)
                    .fontWeight(current ? .semibold : .regular)
                    .foregroundStyle(.primary)
                    .padding(.leading, CGFloat(entry.depth) * 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .listRowBackground(current ? Color.accentColor.opacity(0.12) : Color.clear)
            .id(entry.id)
        }
    }

    private func annotationRows(_ list: [Annotation]) -> some View {
        ForEach(list) { a in
            Button {
                model.go(toAnnotation: a.position)
                dismiss()
            } label: {
                AnnotationRow(annotation: a)
            }
            .buttonStyle(.plain)
            .swipeActions {
                Button("Remove", systemImage: "trash", role: .destructive) { Actions.remove(a) }
            }
        }
    }

    private var empty: some View {
        Text("Nothing yet").foregroundStyle(.secondary)
    }
}

/// A highlight (with its note) or a bookmark, as listed in the reader and the library.
struct AnnotationRow: View {
    var annotation: Annotation

    var body: some View {
        if annotation.kind == .bookmark {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(annotation.label).lineLimit(1)
                    if !annotation.text.isEmpty {
                        Text(annotation.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(annotation.text)
                    .font(.system(size: 15))
                    .lineLimit(4)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color(uiColor: highlightColor(annotation.color))).frame(width: 3)
                    }
                if annotation.hasNote {
                    Text(annotation.note).font(.footnote).foregroundStyle(.secondary).lineLimit(4).padding(.leading, 13)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
    }
}

/// Appearance of the open book, in tabs. Changes apply to this book and show on the page
/// right away; they can be promoted to every book or dropped.
struct AppearanceSheet: View {
    let model: ReaderModel
    var appDark: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab

    init(model: ReaderModel, appDark: Bool) {
        self.model = model
        self.appDark = appDark
        _tab = State(initialValue: model.isFixed ? .page : .text)
    }

    /// Header and footer go under Layout: a fourth tab doesn't fit beside the close button.
    enum Tab: String, CaseIterable {
        case text = "Text"
        case page = "Page"
        case layout = "Layout"
    }

    /// Fixed pages, as in a PDF, have no text to set.
    private var tabs: [Tab] { model.isFixed ? [.page, .layout] : Tab.allCases }

    private var settings: Binding<ReaderSettings> {
        Binding(get: { model.settings }, set: { next in model.change { $0 = next } })
    }

    /// Switching the page between light and dark switches the whole app.
    private var dark: Binding<Bool> {
        Binding(get: { appDark }, set: { dark in Actions.setApp { $0.theme = dark ? .dark : .light } })
    }

    var body: some View {
        NavigationStack {
            Form {
                switch tab {
                case .text:
                    Section { TextSettingsSection(settings: settings) }
                case .page:
                    Section { PageSettingsSection(settings: settings, dark: dark) }
                case .layout:
                    Section {
                        if model.isFixed {
                            PagesPicker(settings: settings)
                            PageTurnPicker(settings: settings)
                        } else {
                            LayoutSettingsSection(settings: settings)
                        }
                    }
                    Section("Header") { HeaderSettingsSection(settings: settings) }
                    Section("Footer") { FooterSettingsSection(settings: settings) }
                }
                // At the end of every tab rather than pinned over the form, so they don't cover it.
                Section {
                    HStack {
                        Button("Use defaults") { model.useDefaults() }
                            .buttonStyle(.glass)
                        Spacer()
                        Button("Use for all books") { model.makeDefault() }
                            .buttonStyle(.glassProminent)
                            // The tint is near white in dark mode, where the default white label vanishes.
                            .foregroundStyle(Color(uiColor: .systemBackground))
                    }
                    .controlSize(.large)
                    .disabled(!model.hasOverride)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text(model.hasOverride ? "This book has settings of its own." : "Changes apply to this book.")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            // Rows on plain glass would show the page through them.
            .scrollContentBackground(.visible)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Section", selection: $tab) {
                        ForEach(tabs, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    // A set width keeps the segments equal; sized to their labels, the bolder
                    // selected one would resize the control and shift the whole bar on every tap.
                    .frame(width: 240)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }
}

/// A highlight's color and note.
struct AnnotationEditor: View {
    let annotation: Annotation
    var focusNote: Bool
    @State private var note = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(annotation.text)
                    .font(.system(size: 15))
                    .lineLimit(3)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color(uiColor: highlightColor(annotation.color))).frame(width: 3)
                    }
                ColorDots(selected: annotation.color) { Actions.update(annotation, color: $0) }
                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(3...8)
                    .focused($focused)
                    .padding(12)
                    .background(.fill.tertiary, in: .rect(cornerRadius: 14))
                Spacer(minLength: 0)
            }
            .padding(20)
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        Actions.remove(annotation)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { dismiss() }
                        .accessibilityIdentifier("editor.done")
                }
            }
        }
        .onAppear {
            note = annotation.note
            focused = focusNote
        }
        .onDisappear {
            if note != annotation.note, SyncEngine.shared.library.annotations[annotation.id] != nil {
                Actions.update(SyncEngine.shared.library.annotations[annotation.id]!, note: note)
            }
        }
    }
}
