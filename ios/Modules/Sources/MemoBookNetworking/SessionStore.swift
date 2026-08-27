import Foundation

/// Ce que l'app retient d'une session entre deux lancements.
///
/// Deux choses, et elles ne vivent pas au même endroit :
///
///   - le **jeton de session** est un secret : trousseau, comme le jeton
///     d'appareil ;
///   - le flag **`has_seen_onboarding`** n'en est pas un : `UserDefaults`
///     suffit. Il est de toute façon restauré depuis le serveur à la
///     connexion, ce qui le rend robuste à une désinstallation.
public protocol SessionStore: Sendable {
    var sessionToken: String? { get }
    func saveSession(token: String)
    func clearSession()

    var hasSeenOnboarding: Bool { get }
    func markOnboardingSeen()
}

public struct KeychainSessionStore: SessionStore {
    private let tokens: any TokenStore
    private let defaults: UserDefaults

    private static let onboardingKey = "com.memobook.has_seen_onboarding"

    public init(
        tokens: any TokenStore = KeychainTokenStore(account: "session-token"),
        defaults: UserDefaults = .standard
    ) {
        self.tokens = tokens
        self.defaults = defaults
    }

    public var sessionToken: String? { tokens.read() }

    public func saveSession(token: String) {
        tokens.write(token)
    }

    public func clearSession() {
        tokens.clear()
    }

    public var hasSeenOnboarding: Bool {
        defaults.bool(forKey: Self.onboardingKey)
    }

    public func markOnboardingSeen() {
        defaults.set(true, forKey: Self.onboardingKey)
    }
}

/// Stockage en mémoire, pour les tests et les aperçus SwiftUI.
public final class InMemorySessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    private var seenOnboarding: Bool

    public init(token: String? = nil, hasSeenOnboarding: Bool = false) {
        self.token = token
        self.seenOnboarding = hasSeenOnboarding
    }

    public var sessionToken: String? { lock.withLock { token } }

    public func saveSession(token: String) {
        lock.withLock { self.token = token }
    }

    public func clearSession() {
        lock.withLock { token = nil }
    }

    public var hasSeenOnboarding: Bool { lock.withLock { seenOnboarding } }

    public func markOnboardingSeen() {
        lock.withLock { seenOnboarding = true }
    }
}
