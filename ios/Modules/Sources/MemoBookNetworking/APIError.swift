import Foundation

/// Erreur remontée par le client d'API.
///
/// Les messages sont destinés à l'utilisateur : le back-end renvoie déjà des
/// libellés en français dans son champ `message`, on les réutilise plutôt que
/// d'afficher un code HTTP.
public enum APIError: Error, LocalizedError, Sendable {
    case notAuthenticated
    case server(statusCode: Int, code: String?, message: String)
    case transport(any Error)
    case decoding(any Error)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Cet appareil n'est pas encore enregistré."
        case .server(_, _, let message):
            message
        case .transport:
            "Connexion impossible. Vérifie ton réseau et réessaie."
        case .decoding:
            "Réponse inattendue du serveur."
        }
    }

    /// `true` quand réessayer a une chance d'aboutir.
    public var isRetryable: Bool {
        switch self {
        case .transport: true
        case .server(let statusCode, _, _): statusCode >= 500
        case .notAuthenticated, .decoding: false
        }
    }
}

/// Corps d'erreur normalisé du back-end.
struct APIErrorBody: Decodable {
    let error: String?
    let message: String?
}
