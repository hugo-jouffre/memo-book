import Foundation

/// Une session ouverte sur un compte. C'est ce que le back-end renvoie à
/// l'inscription comme à la connexion.
public struct AuthenticatedSession: Codable, Sendable, Hashable {
    public let userId: String
    public let sessionToken: String
    /// Restauré depuis le serveur : une réinstallation ne repropose pas le
    /// Welcome Screen à quelqu'un qui a déjà un compte.
    public let hasSeenOnboarding: Bool

    public init(userId: String, sessionToken: String, hasSeenOnboarding: Bool) {
        self.userId = userId
        self.sessionToken = sessionToken
        self.hasSeenOnboarding = hasSeenOnboarding
    }
}

/// Le compte de la session, tel que `GET /v1/auth/me` le décrit.
public struct Account: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let email: String
    public let firstName: String
    public let lastName: String
    public let hasSeenOnboarding: Bool

    public init(
        id: String,
        email: String,
        firstName: String,
        lastName: String,
        hasSeenOnboarding: Bool
    ) {
        self.id = id
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.hasSeenOnboarding = hasSeenOnboarding
    }
}

/// Les trois fournisseurs proposés sur *Sign Up* et *Login*.
///
/// Apple est **obligatoire** dès qu'un login social tiers est proposé
/// (App Store 4.8) : les trois vont ensemble ou aucun.
public enum SocialProvider: String, Codable, Sendable, CaseIterable {
    case apple
    case google
    case facebook

    /// Ce que VoiceOver annonce sur le bouton.
    public var label: String {
        switch self {
        case .apple: "Continuer avec Apple"
        case .google: "Continuer avec Google"
        case .facebook: "Continuer avec Facebook"
        }
    }
}

/// L'issue d'une connexion tierce : soit le compte existait, soit il faut
/// passer par *Complète tes informations*.
public enum SocialSignInOutcome: Sendable, Hashable {
    case signedIn(AuthenticatedSession)
    case profileRequired(SocialProfileDraft)
}

/// Ce que le fournisseur a transmis, à confirmer ou corriger par l'utilisateur.
public struct SocialProfileDraft: Codable, Sendable, Hashable {
    public let socialToken: String
    public let provider: SocialProvider
    public let firstName: String?
    public let lastName: String?
    public let email: String?

    public init(
        socialToken: String,
        provider: SocialProvider,
        firstName: String?,
        lastName: String?,
        email: String?
    ) {
        self.socialToken = socialToken
        self.provider = provider
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
    }

    /// Apple peut renvoyer une adresse relais plutôt qu'une adresse
    /// personnelle. Elle est acceptée telle quelle : Apple fait suivre le
    /// courrier tant que l'accès n'est pas révoqué, et on ne va pas demander
    /// une « vraie » adresse à quelqu'un qui a justement choisi de la masquer.
    public var usesAppleRelayEmail: Bool {
        email?.lowercased().hasSuffix("@privaterelay.appleid.com") ?? false
    }
}

/// Ce qu'on envoie pour créer un compte.
public struct NewAccount: Codable, Sendable, Hashable {
    public let firstName: String
    public let lastName: String
    public let email: String
    public let password: String

    public init(firstName: String, lastName: String, email: String, password: String) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.password = password
    }
}

/// Le profil confirmé sur *Complète tes informations*.
public struct CompletedSocialProfile: Codable, Sendable, Hashable {
    public let socialToken: String
    public let firstName: String
    public let lastName: String
    public let email: String

    public init(socialToken: String, firstName: String, lastName: String, email: String) {
        self.socialToken = socialToken
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
    }
}
