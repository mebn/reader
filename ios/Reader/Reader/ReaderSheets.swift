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

    var body: some View {
        NavigationStack {
            Group {
                switch tab {
                case .contents: contents
                case .notes: annotationList(model.annotations.filter { $0.kind == .highlight })
                case .bookmarks: annotationList(model.annotations.filter { $0.kind == .bookmark })
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Show", selection: $tab) {
                        ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }

    private var contents: some View {
        ScrollViewReader { proxy in
            List(model.toc) { entry in
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
            .listStyle(.plain)
            .overlay { if model.toc.isEmpty { empty } }
            // The chapter being read is centered rather than the list starting at the top.
            .onAppear {
                if let id = model.currentEntry?.id { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func annotationList(_ list: [Annotation]) -> some View {
        List {
            ForEach(list.sorted { $0.position.sortKey < $1.position.sortKey }) { a in
                Button {
                    model.go(a.position)
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
        .listStyle(.plain)
        .overlay { if list.isEmpty { empty } }
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
                    .font(.custom("Literata", size: 15))
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
    @State private var tab = Tab.text

    enum Tab: String, CaseIterable {
        case text = "Text"
        case page = "Page"
        case layout = "Layout"
        case headerFooter = "Header & Footer"
    }

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
                    Section { LayoutSettingsSection(settings: settings) }
                case .headerFooter:
                    Section("Header") { HeaderSettingsSection(settings: settings) }
                    Section("Footer") { FooterSettingsSection(settings: settings) }
                }
            }
            .scrollContentBackground(.hidden)
            .safeAreaBar(edge: .top) {
                Picker("Section", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 6)
            }
            .safeAreaBar(edge: .bottom) {
                HStack {
                    if model.hasOverride {
                        Button("Use defaults") { model.useDefaults() }
                            .buttonStyle(.glass)
                        Spacer()
                        Button("Use for all books") { model.makeDefault() }
                            .buttonStyle(.glassProminent)
                    } else {
                        Text("Changes apply to this book.").font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
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
                    .font(.custom("Literata", size: 15))
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
