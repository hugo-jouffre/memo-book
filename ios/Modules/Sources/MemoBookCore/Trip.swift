import Foundation

// Ce que la page d'accueil affiche, modélisé comme le back-end le renverra.
//
// Rien n'est en dur dans les vues : l'écran ne sait rien du contenu, il ne sait
// que le dessiner. Le jour où l'API existe, seule la source du ``HomeFeed``
// change — voir `HomeModel`.

/// La personne qui voyage. Le prénom porte la salutation de l'accueil.
public struct Traveller: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let firstName: String
    public let avatarUrl: URL?

    public init(id: String, firstName: String, avatarUrl: URL? = nil) {
        self.id = id
        self.firstName = firstName
        self.avatarUrl = avatarUrl
    }
}

/// Où se passe le voyage. Le drapeau n'est **pas** une donnée : il se dérive du
/// code pays, pour qu'aucun back-end n'ait à stocker un emoji.
public struct Destination: Codable, Sendable, Hashable {
    /// Nom affiché, dans la langue de l'utilisateur. Ex. « Italie ».
    public let name: String

    /// Code ISO 3166-1 alpha-2. Ex. « IT ».
    public let countryCode: String?

    public init(name: String, countryCode: String? = nil) {
        self.name = name
        self.countryCode = countryCode
    }

    /// Le drapeau du pays, composé des deux indicateurs régionaux Unicode.
    /// `nil` si le code est absent ou hors A–Z : mieux vaut pas de drapeau
    /// qu'un carré blanc.
    public var flag: String? {
        guard let countryCode, countryCode.count == 2 else { return nil }

        var scalars = String.UnicodeScalarView()
        for scalar in countryCode.uppercased().unicodeScalars {
            guard ("A"..."Z").contains(scalar),
                let indicator = Unicode.Scalar(scalar.value + 0x1F1E6 - 0x41)
            else { return nil }
            scalars.append(indicator)
        }
        return String(scalars)
    }
}

/// Un compagnon de voyage, tel qu'il apparaît en pastille sur la couverture.
public struct Companion: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let avatarUrl: URL?

    public init(id: String, name: String, avatarUrl: URL? = nil) {
        self.id = id
        self.name = name
        self.avatarUrl = avatarUrl
    }

    /// Repli quand la photo manque : une ou deux initiales, jamais plus.
    public var initials: String {
        let words = name.split(separator: " ").prefix(2)
        return words.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

/// Les compteurs affichés sous le titre d'un voyage. Chacun est optionnel :
/// un voyage tout juste commencé n'a ni distance ni photo, et la ligne se
/// contente alors de ce qu'elle a.
public struct TripStats: Codable, Sendable, Hashable {
    public let dayCount: Int?
    /// En kilomètres. L'unité affichée suit les réglages de l'utilisateur.
    public let distanceKilometres: Double?
    public let photoCount: Int?

    public init(dayCount: Int? = nil, distanceKilometres: Double? = nil, photoCount: Int? = nil) {
        self.dayCount = dayCount
        self.distanceKilometres = distanceKilometres
        self.photoCount = photoCount
    }

    public var isEmpty: Bool {
        dayCount == nil && distanceKilometres == nil && photoCount == nil
    }
}

/// Où en est le voyage. C'est cette valeur, et non l'ordre de la liste, qui
/// range un voyage dans « en cours » ou dans « précédents ».
///
/// Comme ``Status``, le cas `unknown` existe pour qu'un état ajouté côté
/// serveur ne fasse pas planter une app déjà installée. Un état inconnu est
/// traité comme « en cours » : mieux vaut un voyage visible en haut de l'écran
/// qu'un voyage qui disparaît.
public enum TripStage: Sendable, Hashable {
    case ongoing
    case past
    case unknown(String)

    public var isOngoing: Bool { self != .past }
}

extension TripStage: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self =
            switch raw {
            case "ongoing": .ongoing
            case "past": .past
            default: .unknown(raw)
            }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .ongoing: "ongoing"
        case .past: "past"
        case .unknown(let raw): raw
        }
    }
}

/// Un voyage : le carnet vu du dessus, avant d'entrer dedans.
public struct Trip: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let destination: Destination?
    public let stage: TripStage

    /// Bornes du séjour. Ouvertes des deux côtés : un voyage en cours n'a pas
    /// encore de fin, un carnet importé peut n'avoir aucune date.
    public let startDate: Date?
    public let endDate: Date?

    public let coverPhotoUrl: URL?
    public let stats: TripStats
    public let companions: [Companion]

    /// Le carnet est généré et peut partir à l'impression — c'est ce qui
    /// allume le bouton imprimante sur les voyages passés.
    public let isPrintable: Bool

    public init(
        id: String,
        title: String,
        destination: Destination? = nil,
        stage: TripStage,
        startDate: Date? = nil,
        endDate: Date? = nil,
        coverPhotoUrl: URL? = nil,
        stats: TripStats = TripStats(),
        companions: [Companion] = [],
        isPrintable: Bool = false
    ) {
        self.id = id
        self.title = title
        self.destination = destination
        self.stage = stage
        self.startDate = startDate
        self.endDate = endDate
        self.coverPhotoUrl = coverPhotoUrl
        self.stats = stats
        self.companions = companions
        self.isPrintable = isPrintable
    }
}

/// La carte de découverte en bas de l'accueil. Son contenu vient du serveur
/// pour qu'une campagne se change sans mise à jour de l'app.
public struct Showcase: Codable, Sendable, Hashable {
    public let title: String
    public let subtitle: String
    public let imageUrl: URL?
    public let destinationUrl: URL?

    public init(
        title: String,
        subtitle: String,
        imageUrl: URL? = nil,
        destinationUrl: URL? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.imageUrl = imageUrl
        self.destinationUrl = destinationUrl
    }
}

/// Tout ce qu'il faut pour dessiner l'accueil, en une seule réponse.
///
/// Les voyages arrivent dans **une** liste : c'est ``TripStage`` qui les range,
/// pas deux tableaux que le serveur devrait tenir cohérents.
public struct HomeFeed: Codable, Sendable, Hashable {
    public let traveller: Traveller
    public let trips: [Trip]
    public let showcase: Showcase?

    public init(traveller: Traveller, trips: [Trip], showcase: Showcase? = nil) {
        self.traveller = traveller
        self.trips = trips
        self.showcase = showcase
    }

    /// Les voyages en cours, les plus récemment commencés d'abord.
    public var ongoingTrips: [Trip] {
        trips.filter(\.stage.isOngoing).sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    /// Les voyages terminés, du plus récent au plus ancien.
    public var pastTrips: [Trip] {
        trips.filter { !$0.stage.isOngoing }
            .sorted { ($0.endDate ?? $0.startDate ?? .distantPast) > ($1.endDate ?? $1.startDate ?? .distantPast) }
    }
}
