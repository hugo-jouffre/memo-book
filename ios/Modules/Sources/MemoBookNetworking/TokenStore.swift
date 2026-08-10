import Foundation
import Security

/// Conservation du token d'appareil entre deux lancements.
public protocol TokenStore: Sendable {
    func read() -> String?
    func write(_ token: String)
    func clear()
}

/// Trousseau iOS. Le token identifie l'appareil auprès de l'API : il n'a rien à
/// faire dans `UserDefaults`, qui est lisible depuis une sauvegarde non chiffrée.
public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    public init(service: String = "com.memobook.app", account: String = "device-token") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else { return nil }

        return String(data: data, encoding: .utf8)
    }

    public func write(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }

        // Un `SecItemUpdate` échoue si l'entrée n'existe pas encore : on
        // supprime puis on insère, ce qui couvre les deux cas.
        SecItemDelete(baseQuery as CFDictionary)

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// Stockage en mémoire, pour les tests et les aperçus SwiftUI.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    public init(token: String? = nil) {
        self.token = token
    }

    public func read() -> String? {
        lock.withLock { token }
    }

    public func write(_ token: String) {
        lock.withLock { self.token = token }
    }

    public func clear() {
        lock.withLock { token = nil }
    }
}
