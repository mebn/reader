import Observation
import SwiftUI

/// Who is signed in. Signing out keeps the email for the sign-in form.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var session: Session?

    private init() {
        session = SessionStore.load()
        SyncEngine.shared.onSignedOut = { [weak self] in self?.signOut() }
        if let session, session.signedIn { SyncEngine.shared.start(session) }
    }

    var signedIn: Bool { session?.signedIn ?? false }

    func signIn(_ session: Session) {
        SessionStore.save(session)
        self.session = session
        SyncEngine.shared.start(session)
    }

    func signOut() {
        SyncEngine.shared.stop()
        let previous = Session(serverUrl: session?.serverUrl ?? Session.defaultServer, token: "", email: session?.email ?? "")
        SessionStore.save(previous)
        session = previous
    }
}

/// Short notices over the app, like the desktop's toasts.
@MainActor @Observable
final class Toasts {
    static let shared = Toasts()

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        var title: String
        var detail: String?
        var progress = false
        var isError = false
        var action: String?
        static func == (a: Toast, b: Toast) -> Bool { a.id == b.id && a.title == b.title && a.detail == b.detail && a.progress == b.progress }
    }

    private(set) var current: Toast?
    @ObservationIgnored private var onAction: (() -> Void)?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    @discardableResult
    func show(_ title: String, detail: String? = nil, progress: Bool = false, error: Bool = false, action: String? = nil, duration: Duration = .seconds(4), onAction: (() -> Void)? = nil) -> UUID {
        let toast = Toast(title: title, detail: detail, progress: progress, isError: error, action: action)
        withAnimation(.spring(duration: 0.35)) { current = toast }
        self.onAction = onAction
        dismissTask?.cancel()
        if !progress {
            dismissTask = Task {
                try? await Task.sleep(for: duration)
                if !Task.isCancelled { dismiss(toast.id) }
            }
        }
        return toast.id
    }

    func dismiss(_ id: UUID? = nil) {
        guard id == nil || current?.id == id else { return }
        withAnimation(.spring(duration: 0.3)) { current = nil }
    }

    func runAction() {
        onAction?()
        dismiss()
    }
}
