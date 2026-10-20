import Foundation
import Security
import UIKit

struct Session: Codable, Equatable {
    var serverUrl: String
    var token: String
    var email: String

    var signedIn: Bool { !token.isEmpty }

    /// The sync server, fixed at build time (READER_SERVER_URL); never shown to people.
    static let defaultServer: String = {
        let value = Bundle.main.object(forInfoDictionaryKey: "ReaderServerURL") as? String ?? ""
        return value.isEmpty || value.contains("$(") ? "http://localhost:8080" : value
    }()

    func url(_ path: String) -> URL {
        let base = serverUrl.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        return URL(string: "\(base)/api\(path)")!
    }
}

struct DeviceInfo: Codable {
    var name: String
    var platform: String

    /// How this device is listed among the account's devices.
    @MainActor static var current: DeviceInfo {
        let device = UIDevice.current
        return DeviceInfo(name: device.name, platform: device.userInterfaceIdiom == .pad ? "iPadOS" : "iOS")
    }
}

/// Keeps the session in the keychain. Signing out keeps the email for the next sign-in.
enum SessionStore {
    private static let service = "reader.session"

    static func load() -> Session? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    static func save(_ session: Session) {
        let data = (try? JSONEncoder().encode(session)) ?? Data()
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }
}
