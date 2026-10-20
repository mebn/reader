import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { AppearanceSettings() } label: { Label("Appearance", systemImage: "paintpalette") }
                    NavigationLink { ReadingSettings() } label: { Label("Reading", systemImage: "book") }
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        NavigationLink { ShortcutSettings() } label: { Label("Keyboard Shortcuts", systemImage: "keyboard") }
                    }
                    NavigationLink { AccountSettings() } label: { Label("Account", systemImage: "person.crop.circle") }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }
}

/// Light, dark or following the system, for the whole app. Applies as soon as it's picked.
private struct AppearanceSettings: View {
    private var app: AppSettings { SyncEngine.shared.library.appSettings }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    ForEach(ThemeMode.allCases, id: \.self) { mode in
                        let selected = app.theme == mode
                        Button {
                            Actions.setApp { $0.theme = mode }
                        } label: {
                            VStack(spacing: 8) {
                                ThemeSwatch(mode: mode)
                                Label(mode.rawValue.capitalized, systemImage: mode == .system ? "circle.lefthalf.filled" : mode == .light ? "sun.max" : "moon")
                                    .font(.footnote)
                                    .labelStyle(.titleAndIcon)
                            }
                            .padding(8)
                            .background(selected ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Theme")
            } footer: {
                Text("Books use the page colors you choose for light and dark under Reading.")
            }

            Section("Library") {
                Picker("Start on", selection: Binding(get: { app.defaultTab }, set: { tab in
                    Actions.setApp { $0.defaultTab = tab }
                    // Show it on the way back to the library, not only after a restart.
                    LibraryFilter.shared.tab = tab
                })) {
                    ForEach(LibraryTab.allCases) { Text($0.label).tag($0) }
                }
            }
        }
        .navigationTitle("Appearance")
    }
}

/// A miniature window in the theme's colors; System is split down the middle.
private struct ThemeSwatch: View {
    var mode: ThemeMode

    var body: some View {
        HStack(spacing: 0) {
            if mode != .dark { half(bg: 0xfbfaf7, bar: 0xebe8e2, line: 0xd9d5ce) }
            if mode != .light { half(bg: 0x1c1c1e, bar: 0x2a2a2d, line: 0x3a3a3e) }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.1)))
    }

    private func half(bg: UInt32, bar: UInt32, line: UInt32) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(Color(uiColor: UIColor(hex: bar))).frame(height: 5)
            ForEach([0.9, 0.7, 0.8], id: \.self) { w in
                GeometryReader { g in
                    RoundedRectangle(cornerRadius: 2).fill(Color(uiColor: UIColor(hex: line))).frame(width: g.size.width * w, height: 3)
                }
                .frame(height: 3)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: UIColor(hex: bg)))
    }
}

/// Reader defaults for every book.
private struct ReadingSettings: View {
    @State private var draft = SyncEngine.shared.library.defaultReaderSettings
    @State private var dark = false
    @State private var saveTask: Task<Void, Never>?
    @Environment(\.colorScheme) private var scheme

    private var library: Library { SyncEngine.shared.library }

    private var settings: Binding<ReaderSettings> {
        Binding(get: { draft }, set: { next in
            draft = next
            // Saves shortly after the last change so dragging sliders doesn't flood sync.
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                if !Task.isCancelled { Actions.saveSettings(Scope.reader, next) }
            }
        })
    }

    var body: some View {
        Form {
            Section {
                SettingsPreview(settings: draft, dark: dark)
                    .frame(maxWidth: 320)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            Section("Page") { PageSettingsSection(settings: settings, dark: $dark) }
            Section("Text") { TextSettingsSection(settings: settings) }
            Section("Layout") { LayoutSettingsSection(settings: settings) }
            Section("Header") { HeaderSettingsSection(settings: settings) }
            Section("Footer") { FooterSettingsSection(settings: settings) }
            if BookOpener.supportsWindows {
                Section("Library") {
                    Toggle("Open books in a new window", isOn: Binding(get: { library.appSettings.openInNewWindow }, set: { value in
                        Actions.setApp { $0.openInNewWindow = value }
                    }))
                }
            }
        }
        .navigationTitle("Reading")
        .onAppear { dark = scheme == .dark }
        // Picks up changes synced from other devices.
        .onChange(of: library.settings[Scope.reader]?.modifiedAt) {
            if saveTask == nil || saveTask?.isCancelled == true { draft = library.defaultReaderSettings }
        }
    }
}

/// Every keyboard shortcut, for iPad with a keyboard.
private struct ShortcutSettings: View {
    private static let groups: [(String, [(String, String)])] = [
        ("Everywhere", [("⌘1", "Library"), ("⌘,", "Settings")]),
        ("Reading", [("→  Space", "Next page"), ("←  ⇧Space", "Previous page"), ("B  ⌘D", "Bookmark this page"), ("C", "Contents, notes and bookmarks"),
                     ("A", "Appearance"), ("⌘=", "Larger text"), ("⌘−", "Smaller text"), ("⌘0", "Default text size"), ("Esc", "Close book")]),
        ("With text selected", [("H", "Highlight selection"), ("N", "Highlight selection with a note")]),
    ]

    var body: some View {
        Form {
            ForEach(Self.groups, id: \.0) { title, items in
                Section(title) {
                    ForEach(items, id: \.1) { keys, label in
                        LabeledContent(label) { Text(keys).font(.callout.monospaced()).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .navigationTitle("Keyboard Shortcuts")
    }
}

/// Who is signed in, and the devices on the account.
private struct AccountSettings: View {
    @State private var devices: [Device]?
    @State private var error = ""
    @State private var removing: Device?

    private var session: Session? { SyncEngine.shared.session }

    var body: some View {
        Form {
            Section {
                LabeledContent("Signed in as", value: session?.email ?? "")
                Button("Sign Out", role: .destructive) { AppModel.shared.signOut() }
            } footer: {
                Text("Your library, reading positions, highlights and settings stay in sync on every device you sign in on.")
            }

            Section("Devices") {
                if let devices {
                    ForEach(devices) { device in
                        DeviceRow(device: device)
                            .swipeActions {
                                if !device.current {
                                    Button("Sign Out", role: .destructive) { removing = device }
                                }
                            }
                            .contextMenu {
                                if !device.current {
                                    Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { removing = device }
                                }
                            }
                    }
                } else {
                    Text(error.isEmpty ? "Loading…" : error).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Account")
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .refreshable { await load() }
        .alert("Sign out \(removing?.name ?? "device")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) { if let removing { Task { await remove(removing) } } }
        } message: {
            Text("It will stop syncing until someone signs in on it again.")
        }
    }

    private func load() async {
        guard let session else { return }
        do {
            devices = try await API.devices(session)
            error = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove(_ device: Device) async {
        guard let session else { return }
        devices?.removeAll { $0.id == device.id }
        do {
            try await API.removeDevice(session, id: device.id)
        } catch {
            Toasts.shared.show("Couldn't sign out \(device.name)", detail: error.localizedDescription, error: true)
        }
        await load()
    }
}

private struct DeviceRow: View {
    var device: Device

    private var symbol: String {
        switch device.platform {
        case "macOS": "laptopcomputer"
        case "Windows", "Linux": "desktopcomputer"
        case "Web": "globe"
        case "iPadOS": "ipad"
        case "iOS", "Android": "iphone"
        default: "desktopcomputer"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 34, height: 34)
                .background(.fill.tertiary, in: .rect(cornerRadius: 9))
                .overlay(alignment: .bottomTrailing) {
                    if device.online {
                        Circle().fill(.green).frame(width: 10, height: 10).overlay(Circle().stroke(.background, lineWidth: 2)).offset(x: 3, y: 3)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.name).lineLimit(1)
                    if device.current {
                        Text("This device").font(.caption2.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 1).background(.fill.tertiary, in: .capsule)
                    }
                }
                Text((device.platform.isEmpty ? "" : "\(device.platform) · ") + (device.current || device.online ? "Active now" : "Last active \(formatWhen(Int64(device.lastSeenAt.timeIntervalSince1970 * 1000)))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
