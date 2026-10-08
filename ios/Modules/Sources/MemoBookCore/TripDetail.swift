import Foundation

// Ce qu'on voit en entrant dans un voyage : sa couverture, la relance de
// MemoBook, et les étapes déjà racontées.
//
// Même principe que ``HomeFeed`` : l'écran ne sait rien du contenu, il ne sait
// que le dessiner. Le jour où l'API existe, seule la source change.

/// Comment on est allé d'une étape à la suivante.
///
/// La liste est fermée côté app mais **tolérante au décodage** : un mode ajouté
/// par le serveur ne fait pas disparaître l'étape, il la laisse simplement sans
/// pictogramme — même parti pris que ``TripStage``.
public enum TripTransport: Sendable, Hashable, CaseIterable {
    case walk
    case bike
    case car
    case bus
    case train
    case boat
    case plane

    /// Le nom du mode, tel qu'on l'écrit à l'utilisateur.
    public var displayName: String {
        switch self {
        case .walk: "À pied"
        case .bike: "Vélo"
        case .car: "Voiture"
        case .bus: "Bus"
        case .train: "Train"
        case .boat: "Bateau"
        case .plane: "Avion"
        }
    }
}

extension TripTransport: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let match = Self.allCases.first(where: { $0.rawValue == raw }) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "mode de transport inconnu : \(raw)")
            )
        }
        self = match
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .walk: "walk"
        case .bike: "bike"
        case .car: "car"
        case .bus: "bus"
        case .train: "train"
        case .boat: "boat"
        case .plane: "plane"
        }
    }
}

/// Une étape du voyage : un lieu, des dates, ceux qui y étaient.
public struct TripStep: Codable, Sendable, Hashable, Identifiable {
    public let id: String

    /// Son rang dans le voyage. C'est lui qui nomme l'étape tant qu'elle n'a
    /// pas de titre — le carnet, lui, en trouvera un.
    public let number: Int

    /// Le lieu, tel qu'on le dirait : « Trastevere ».
    public let placeName: String?

    /// Le pays, qui porte le drapeau de la vignette et le filtre « Pays ».
    public let destination: Destination?

    public let startDate: Date?
    public let endDate: Date?
    public let companions: [Companion]
    public let photoUrl: URL?
    public let transport: TripTransport?

    /// « Valider cette étape » : le voyageur l'a confirmée. `nil` tant que ce
    /// n'est pas fait.
    public let validatedAt: Date?

    /// **Les souvenirs rattachés à cette étape** — ce que la croix de son
    /// tiroir efface (T235, Hugo, 06/10/2026), un `DELETE /v1/entries/:id`
    /// chacun.
    ///
    /// Une étape est un **lieu** ; elle peut porter plusieurs souvenirs — un
    /// vocal, un texte, des photos (`entries.stepId`, plusieurs lignes pour
    /// une étape). « Le souvenir de l'étape », c'est donc tout ce qu'on y a
    /// raconté. `nil` d'un serveur qui ne le sert pas encore : la croix ne
    /// paraît pas, faute de savoir quoi effacer.
    public let entryIds: [String]?

    public init(
        id: String,
        number: Int,
        placeName: String? = nil,
        destination: Destination? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        companions: [Companion] = [],
        photoUrl: URL? = nil,
        transport: TripTransport? = nil,
        validatedAt: Date? = nil,
        entryIds: [String]? = nil
    ) {
        self.id = id
        self.number = number
        self.placeName = placeName
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.companions = companions
        self.photoUrl = photoUrl
        self.transport = transport
        self.validatedAt = validatedAt
        self.entryIds = entryIds
    }

    /// La croix du tiroir s'offre : on sait quels souvenirs effacer.
    public var hasDeletableMemories: Bool { !(entryIds ?? []).isEmpty }

    /// Cette étape, validée. Sert la mise à jour optimiste de « Valider cette
    /// étape » côté app, et les jeux d'essai qui simulent la même réponse.
    public func validated(at date: Date = .now) -> TripStep {
        TripStep(
            id: id,
            number: number,
            placeName: placeName,
            destination: destination,
            startDate: startDate,
            endDate: endDate,
            companions: companions,
            photoUrl: photoUrl,
            transport: transport,
            validatedAt: date,
            entryIds: entryIds
        )
    }
}

/// Un voyage ouvert : tout ce qu'il faut pour dessiner son accueil.
public struct TripDetail: Codable, Sendable, Hashable, Identifiable {
    public let trip: Trip

    /// La relance de MemoBook — « Comment ça se passe à Trastevere ? ».
    ///
    /// Elle vient du serveur et non de l'app : c'est une question posée à
    /// partir de ce qui a déjà été raconté, pas un libellé d'interface. `nil`
    /// quand il n'y a encore rien à relancer.
    public let prompt: String?

    public let steps: [TripStep]

    public var id: String { trip.id }

    public init(trip: Trip, prompt: String? = nil, steps: [TripStep] = []) {
        self.trip = trip
        self.prompt = prompt
        self.steps = steps
    }

    /// Les pays traversés, sans doublon, dans l'ordre des étapes. C'est la
    /// liste du filtre « Pays ».
    public var countries: [Destination] {
        var seen = Set<String>()
        return steps.compactMap(\.destination).filter { seen.insert($0.name).inserted }
    }

    /// Les modes de transport employés, sans doublon.
    public var transports: [TripTransport] {
        var seen = Set<TripTransport>()
        return steps.compactMap(\.transport).filter { seen.insert($0).inserted }
    }
}
