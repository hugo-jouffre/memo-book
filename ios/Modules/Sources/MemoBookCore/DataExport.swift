import Foundation

/// Ce que le serveur répond à « Exporter mes données » —
/// `POST /v1/accounts/me/export`.
///
/// **La demande ne fabrique rien** : elle envoie par e-mail le lien d'une page
/// où télécharger l'archive, valable sept jours, et c'est en l'ouvrant que
/// l'archive se compose. L'app n'a donc qu'à dire **où** le lien est parti, et
/// **jusqu'à quand** il vaut.
public struct DataExportReceipt: Codable, Sendable, Hashable {
    /// L'adresse du compte — la seule où le lien peut partir : la requête n'en
    /// porte aucune.
    public let email: String
    public let requestedAt: Date
    public let expiresAt: Date

    /// Un e-mail était déjà parti il y a moins de cinq minutes : le serveur
    /// n'en a pas envoyé d'autre. L'écran le dit autrement — l'e-mail est en
    /// route, ou dans les indésirables.
    public let alreadyRequested: Bool

    public init(email: String, requestedAt: Date, expiresAt: Date, alreadyRequested: Bool = false) {
        self.email = email
        self.requestedAt = requestedAt
        self.expiresAt = expiresAt
        self.alreadyRequested = alreadyRequested
    }

    /// Ce que l'aperçu et le bac à sable font répondre : un lien parti à
    /// l'instant, valable sept jours.
    public static func fixture(email: String, now: Date = .now) -> DataExportReceipt {
        DataExportReceipt(
            email: email,
            requestedAt: now,
            expiresAt: now.addingTimeInterval(7 * 24 * 60 * 60)
        )
    }
}
