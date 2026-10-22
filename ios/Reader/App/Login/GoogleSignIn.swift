import AuthenticationServices
import UIKit

/// Google sign-in the way the desktop app does it: the server talks to Google, the app shows
/// Google's page and polls the server until it has the result.
@MainActor
final class GoogleSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private static let pollInterval: Duration = .milliseconds(1500)
    private static let timeout: TimeInterval = 10 * 60

    private var closed = false

    /// The new session, or nil when the person closed Google's page without signing in.
    func run() async throws -> Session? {
        let server = Session.defaultServer
        let start = try await API.googleStart(server: server, device: .current)

        // The server finishes the sign-in, so the callback scheme is never used. The page
        // only says it's done, and closing it is how the person gives up.
        let page = ASWebAuthenticationSession(url: start.url, callback: .customScheme("reader")) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.closed = true }
        }
        page.presentationContextProvider = self
        guard page.start() else { throw APIError(message: "Couldn't open Google sign-in", status: 0) }
        defer { page.cancel() }

        let deadline = Date().addingTimeInterval(Self.timeout)
        while Date() < deadline {
            try await Task.sleep(for: Self.pollInterval)
            if let (token, user) = try await API.googlePoll(server: server, state: start.state, secret: start.secret) {
                return Session(serverUrl: server, token: token, email: user.email)
            }
            // One more poll after the page closes, in case it closed right after finishing.
            if closed { return nil }
        }
        throw APIError(message: "Google sign-in timed out. Try again.", status: 0)
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? UIWindow(windowScene: scenes[0])
        }
    }
}
