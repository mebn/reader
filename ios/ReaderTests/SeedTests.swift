import XCTest
@testable import Reader

/// Signs the app in and imports the sample books through the app's own import, for
/// trying the app against a local server. Runs only with TEST_RUNNER_SEED=1.
@MainActor
final class SeedTests: XCTestCase {
    func testSeedLibrary() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SEED"] == "1", let dir = env["BOOKS_DIR"] else { throw XCTSkip("Seeding is opt-in") }
        let server = Session.defaultServer
        let email = "reader@example.com", password = "correct horse"
        let auth: (token: String, user: User)
        if let registered = try? await API.register(server: server, email: email, password: password, device: DeviceInfo.current) {
            auth = registered
        } else {
            auth = try await API.login(server: server, email: email, password: password, device: DeviceInfo.current)
        }
        AppModel.shared.signIn(Session(serverUrl: server, token: auth.token, email: auth.user.email))
        await SyncEngine.shared.pull()

        let library = SyncEngine.shared.library
        if library.books.isEmpty {
            let urls = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil)
            await Actions.importFiles(urls.sorted { $0.lastPathComponent > $1.lastPathComponent }, into: nil)
            let folder = Actions.createFolder("Classics", in: nil)
            if let alice = library.books.values.first(where: { $0.title.contains("Alice") }) { Actions.move(alice, to: folder.id) }
        }
        XCTAssertGreaterThanOrEqual(library.books.count, 3)
        // Let the outbox reach the server.
        try await Task.sleep(for: .seconds(2))
    }
}
