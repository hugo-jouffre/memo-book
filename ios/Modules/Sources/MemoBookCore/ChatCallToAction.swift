import Foundation

/// **L'appel à l'action d'une bulle de MEMO** (03/10/2026) — le bouton posé
/// sous le texte, séparé par un filet, avec « Ignorer » en dessous (maquettes
/// Figma `3653:17090` et, une fois touché, `3653:17213`).
///
/// **C'est le serveur qui le pose**, et le plus souvent l'IA de conversation
/// qui le choisit — dans un catalogue fermé (`services/callsToAction.ts`) : elle
/// propose un identifiant, le code écrit le libellé et l'action. L'app ne
/// décide que de ce qu'elle fait au toucher, d'après ``Kind``.
///
/// Distinct d'une ``ChatSuggestion`` : une puce **dit** quelque chose à MEMO,
/// elle part comme message ; un appel à l'action **ouvre** un écran et
/// n'envoie rien. Et il appartient à une bulle, là où les puces appartiennent
/// au fil.
public struct ChatCallToAction: Codable, Sendable, Hashable, Identifiable {
    /// Ce que l'app fait au toucher.
    public enum Kind: Sendable, Hashable {
        /// Ouvrir le paywall.
        case subscribe
        /// Ouvrir les réglages du voyage.
        case openTripSettings
        /// Ouvrir l'aperçu du carnet.
        case openPreview
        /// Ouvrir le sélecteur de photos.
        case importPhotos
        /// Ouvrir la page de MemoBook dans les Réglages d'iOS.
        case openPhotoSettings
        /// Une action que le serveur connaît et pas cette version de l'app :
        /// **le bouton ne s'affiche pas**, le texte de la bulle reste. Même
        /// parti pris que ``ChatSuggestion/Intent/unknown(_:)``, mais à
        /// l'inverse : une puce inconnue peut encore s'envoyer, un bouton
        /// inconnu ne mènerait nulle part.
        case unknown(String)

        public var rawValue: String {
            switch self {
            case .subscribe: "subscribe"
            case .openTripSettings: "open_trip_settings"
            case .openPreview: "open_preview"
            case .importPhotos: "import_photos"
            case .openPhotoSettings: "open_photo_settings"
            case .unknown(let raw): raw
            }
        }

        public init(rawValue: String) {
            self =
                switch rawValue {
                case "subscribe": .subscribe
                case "open_trip_settings": .openTripSettings
                case "open_preview": .openPreview
                case "import_photos": .importPhotos
                case "open_photo_settings": .openPhotoSettings
                default: .unknown(rawValue)
                }
        }

        /// L'app sait-elle faire quelque chose de ce bouton ?
        public var isSupported: Bool {
            if case .unknown = self { return false }
            return true
        }
    }

    /// L'identifiant du catalogue — `daily_credit_subscribe`, `subscribe`…
    public let id: String
    public let kind: Kind
    /// Le libellé du bouton, au caractère près.
    public let label: String
    /// L'en-tête manuscrit de la carte, précédé d'une étoile.
    public let eyebrow: String?
    /// « Ignorer » sous le bouton.
    public let dismissible: Bool

    public init(
        id: String,
        kind: Kind,
        label: String,
        eyebrow: String? = nil,
        dismissible: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.eyebrow = eyebrow
        self.dismissible = dismissible
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, label, eyebrow, dismissible
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = Kind(rawValue: try container.decode(String.self, forKey: .kind))
        label = try container.decode(String.self, forKey: .label)
        eyebrow = try container.decodeIfPresent(String.self, forKey: .eyebrow)
        dismissible = try container.decodeIfPresent(Bool.self, forKey: .dismissible) ?? true
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind.rawValue, forKey: .kind)
        try container.encode(label, forKey: .label)
        try container.encodeIfPresent(eyebrow, forKey: .eyebrow)
        try container.encode(dismissible, forKey: .dismissible)
    }

    /// Celui que l'app pose elle-même sous la bulle « reviens demain » quand
    /// elle coupe le micro hors ligne — le même que le serveur
    /// (`daily_credit_subscribe`).
    public static let dailyCreditSubscribe = ChatCallToAction(
        id: "daily_credit_subscribe",
        kind: .subscribe,
        label: "Raconter sans limite",
        eyebrow: "Crédit du jour épuisé"
    )
}

/// Ce qu'on a fait d'un appel à l'action : rien encore, touché, ou ignoré.
///
/// **Retenu sur l'appareil**, par identifiant de bulle : c'est l'état d'un
/// geste, pas un fait du récit. Touché, le bouton passe au bleu et « Ignorer »
/// s'en va ; ignoré, les deux s'en vont et la bulle redevient une bulle.
public enum ChatCallToActionState: String, Codable, Sendable, Hashable {
    case pending
    case followed
    case dismissed
}
