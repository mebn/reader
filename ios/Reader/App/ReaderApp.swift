import SwiftUI

@main
struct ReaderApp: App {
    init() {
        BookFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView { LibraryRoot() }
        }
        // A book in a window of its own, on iPad.
        WindowGroup("Book", id: "reader", for: String.self) { $bookId in
            RootView {
                if let bookId { StandaloneReader(bookId: bookId) }
            }
        }
    }
}

/// Signs in first, follows the app's theme, and shows notices on top.
struct RootView<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var app = AppModel.shared
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if app.signedIn {
                content
            } else {
                LoginView()
            }
        }
        .preferredColorScheme(app.signedIn ? SyncEngine.shared.library.appSettings.theme.colorScheme : nil)
        .overlay(alignment: .top) { ToastView() }
        .onChange(of: phase) { if phase == .active { SyncEngine.shared.wake() } }
    }
}

/// A book opened in its own window, which has nothing to go back to.
private struct StandaloneReader: View {
    let bookId: String
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ReaderView(bookId: bookId) { dismissWindow() }
            .navigationTitle(SyncEngine.shared.library.books[bookId]?.title ?? "Book")
    }
}

private struct ToastView: View {
    @State private var toasts = Toasts.shared

    var body: some View {
        if let toast = toasts.current {
            HStack(spacing: 12) {
                if toast.progress { ProgressView() }
                else if toast.isError { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(toast.title).font(.subheadline.weight(.semibold))
                    if let detail = toast.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
                if let action = toast.action {
                    Button(action) { toasts.runAction() }
                        .buttonStyle(.glassProminent)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: 420)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onTapGesture { if !toast.progress && toast.action == nil { toasts.dismiss() } }
            .gesture(DragGesture(minimumDistance: 10).onEnded { if $0.translation.height < 0 { toasts.dismiss() } })
        }
    }
}
