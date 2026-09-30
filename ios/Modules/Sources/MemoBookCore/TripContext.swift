import Foundation

/// Le contexte du voyage, tel que la conversation le montre : la pastille
/// « Contexte du voyage 3/5 » et la fiche qu'elle ouvre.
///
/// Avant la première étape, MEMO demande d'où l'on part, à combien, le prénom
/// de chaque compagnon, les dates et le genre de voyage. **Le serveur tient
/// tout** — la liste des lignes, leurs libellés, ce qui compte comme rempli
/// (`backend/src/services/tripContext.ts`, `serializeTripContext`) : une ligne
/// ajoutée là-bas s'affiche ici sans livrer une version.
///
/// `nil` sur ``ChatThread/tripContext`` tant que le voyageur n'a pas commencé
/// à le raconter.
public struct ChatTripContext: Codable, Sendable, Hashable {
    public enum Status: Sendable, Hashable {
        /// MEMO recueille : chaque tour du voyageur y va.
        case gathering
        case complete
        /// « Je compléterai plus tard ».
        case skipped
        case unknown(String)
    }

    public struct Item: Codable, Sendable, Hashable, Identifiable {
        public let key: String
        public let label: String
        /// Ce que MEMO a compris, en clair. `nil` tant que la ligne est vide.
        public let value: String?
        public let isRequired: Bool
        public let isFilled: Bool

        public var id: String { key }

        public init(key: String, label: String, value: String?, isRequired: Bool = true, isFilled: Bool? = nil) {
            self.key = key
            self.label = label
            self.value = value
            self.isRequired = isRequired
            self.isFilled = isFilled ?? (value != nil)
        }
    }

    public let status: Status
    public let filledCount: Int
    public let requiredCount: Int
    public let items: [Item]

    public init(status: Status, filledCount: Int, requiredCount: Int, items: [Item]) {
        self.status = status
        self.filledCount = filledCount
        self.requiredCount = requiredCount
        self.items = items
    }

    /// La pastille ne se montre que pendant le recueil : une fois posé, le
    /// contexte n'a plus rien à réclamer.
    public var isGathering: Bool { status == .gathering }

    /// De 0 à 1, pour la jauge de la pastille.
    public var progress: Double {
        requiredCount > 0 ? min(1, Double(filledCount) / Double(requiredCount)) : 0
    }
}

extension ChatTripContext.Status: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self =
            switch raw {
            case "gathering": .gathering
            case "complete": .complete
            case "skipped": .skipped
            default: .unknown(raw)
            }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .gathering: try container.encode("gathering")
        case .complete: try container.encode("complete")
        case .skipped: try container.encode("skipped")
        case .unknown(let raw): try container.encode(raw)
        }
    }
}

public extension ChatTripContext {
    /// À mi-chemin : deux lignes sur cinq, pour les aperçus.
    static let fixture = ChatTripContext(
        status: .gathering,
        filledCount: 2,
        requiredCount: 5,
        items: [
            Item(key: "departureCountry", label: "Pays de départ", value: "France"),
            Item(key: "travellerCount", label: "Voyageurs", value: "3, toi compris"),
            Item(key: "companions", label: "Compagnons de route", value: nil),
            Item(key: "dates", label: "Dates", value: nil),
            Item(key: "tripType", label: "Genre de voyage", value: nil),
            Item(key: "itinerary", label: "Itinéraire", value: "Kuala Lumpur, Penang, Langkawi", isRequired: false),
        ]
    )
}
