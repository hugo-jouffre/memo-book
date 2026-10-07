import Foundation

/// Un message à l'équipe — `POST /v1/support/messages` (contrat du 06/10/2026,
/// point 4, T226).
///
/// « Envoyer » du support attendait 600 ms puis disait « envoyé », et rien ne
/// partait (Hugo, 06/10/2026). Le formulaire de « Nous contacter » et
/// « Partager mes retours » du mot des fondateurs passent désormais par ici ;
/// ``source`` dit lequel des deux.
public struct SupportMessage: Encodable, Sendable, Hashable {
    /// D'où part le message.
    public enum Source: String, Encodable, Sendable, Hashable {
        /// « Écris à notre équipe », et les deux questions de « Nous contacter ».
        case support
        /// « Partager mes retours », dans le mot des fondateurs.
        case foundersNote = "founders_note"
    }

    public var source: Source
    /// La question de « Nous contacter » qui a ouvert le formulaire
    /// (`FaqEntry.id`), `nil` pour le formulaire seul.
    public var topicId: String?
    public var message: String
    /// Le voyage d'où l'on écrit, s'il y en a un. Le serveur ignore un voyage
    /// qu'il ne voit pas.
    public var tripId: String?
    /// « 0.1.0 (21) ».
    public var appVersion: String?
    /// L'appareil, sans rien des souvenirs — ce que la mention sous le champ
    /// promet.
    public var diagnostics: SupportDiagnostics?

    public init(
        source: Source,
        topicId: String? = nil,
        message: String,
        tripId: String? = nil,
        appVersion: String? = nil,
        diagnostics: SupportDiagnostics? = nil
    ) {
        self.source = source
        self.topicId = topicId
        self.message = message
        self.tripId = tripId
        self.appVersion = appVersion
        self.diagnostics = diagnostics
    }
}

/// Le diagnostic technique joint à un message : le système, le modèle et la
/// langue de l'appareil. Rien d'autre.
public struct SupportDiagnostics: Encodable, Sendable, Hashable {
    public var osVersion: String
    public var deviceModel: String
    public var locale: String

    public init(osVersion: String, deviceModel: String, locale: String) {
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.locale = locale
    }
}

/// Un vote « Est-ce utile ? » — `PUT /v1/support/faq-votes/:questionId` et
/// `GET /v1/support/faq-votes`. Un par compte et par question : revoter
/// remplace.
public struct FaqVote: Codable, Sendable, Hashable {
    public let questionId: String
    public let isHelpful: Bool
    public let updatedAt: Date?

    public init(questionId: String, isHelpful: Bool, updatedAt: Date? = nil) {
        self.questionId = questionId
        self.isHelpful = isHelpful
        self.updatedAt = updatedAt
    }
}
