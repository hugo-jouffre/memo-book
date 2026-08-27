import Foundation
import MemoBookCore

/// Ce qui parle aux SDK des fournisseurs et rapporte un jeton d'identité.
///
/// L'app ne parle jamais directement à Apple, Google ou Facebook depuis un
/// écran : elle demande un jeton ici, et l'envoie au back-end qui, lui, le
/// vérifie. Un jeton vérifié côté client ne prouve rien.
public protocol SocialSignInBroker: Sendable {
    /// - Returns: le jeton d'identité à transmettre au back-end.
    /// - Throws: `SocialSignInError.cancelled` si la personne ferme la fenêtre
    ///   du fournisseur ou refuse l'autorisation.
    func credential(for provider: SocialProvider) async throws -> String
}

public enum SocialSignInError: Error, LocalizedError, Sendable {
    /// Fenêtre fermée ou autorisation refusée. **Ce n'est pas une erreur** :
    /// on revient sur l'écran sans un mot, comme le demande le détail
    /// fonctionnel.
    case cancelled
    case unavailable(SocialProvider)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            nil
        case .unavailable(let provider):
            "La connexion \(provider.rawValue.capitalized) n'est pas encore disponible."
        }
    }
}

/// L'implémentation par défaut, tant qu'aucun SDK n'est intégré.
///
/// Elle échoue franchement plutôt que d'envoyer un jeton vide au back-end : un
/// bouton qui ne marche pas doit le dire. Les trois intégrations —
/// `AuthenticationServices` pour Apple, les SDK Google et Facebook — arrivent
/// avec les identifiants de client, qui n'existent pas encore.
///
/// Sign in with Apple est **obligatoire** dès qu'un login social tiers est
/// proposé (App Store 4.8) : les trois arrivent ensemble, ou aucun.
public struct UnwiredSocialSignInBroker: SocialSignInBroker {
    public init() {}

    public func credential(for provider: SocialProvider) async throws -> String {
        throw SocialSignInError.unavailable(provider)
    }
}

/// Double des aperçus et des tests : rend un jeton que `PreviewAPI` et le
/// vérificateur simulé du back-end savent lire.
public struct PreviewSocialSignInBroker: SocialSignInBroker {
    private let cancels: Bool

    public init(cancels: Bool = false) {
        self.cancels = cancels
    }

    public func credential(for provider: SocialProvider) async throws -> String {
        if cancels { throw SocialSignInError.cancelled }
        return "\(provider.rawValue):apercu-001"
    }
}
