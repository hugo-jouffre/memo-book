import Foundation

/// La personne connectée, telle que le serveur la décrit.
///
/// L'adresse est facultative : quelqu'un entré par Apple avec l'adresse masquée
/// et le partage refusé n'en a pas. Ce n'est pas une anomalie à corriger, c'est
/// un choix que l'app doit savoir respecter.
public struct Account: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let email: String?
    public let firstName: String?
    public let lastName: String?
    public let createdAt: Date

    public init(
        id: String,
        email: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.createdAt = createdAt
    }

    /// De quoi accueillir quelqu'un par son prénom, ou rien plutôt qu'un
    /// « Bonjour  » avec un trou dedans.
    public var displayName: String? {
        let parts = [firstName, lastName].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
        let joined = parts.filter { !$0.isEmpty }.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }
}

/// Une session ouverte : le jeton porteur et le compte auquel il donne accès.
///
/// Le jeton n'arrive en clair qu'une fois, dans la réponse qui l'émet. Il part
/// ensuite au trousseau et n'en ressort que pour être posé dans un en-tête.
public struct AuthSession: Codable, Sendable, Hashable {
    public let token: String
    public let expiresAt: Date
    public let account: Account

    public init(token: String, expiresAt: Date, account: Account) {
        self.token = token
        self.expiresAt = expiresAt
        self.account = account
    }
}

/// Les fournisseurs d'identité tiers, côté app.
public enum AuthProvider: String, Codable, Sendable, Hashable {
    case apple
    case google
}
