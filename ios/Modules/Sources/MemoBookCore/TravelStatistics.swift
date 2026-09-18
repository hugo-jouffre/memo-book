import Foundation

// Ce que la feuille « Statistiques » du profil affiche, modélisé comme
// `GET /v1/profile/statistics` le rend.
//
// **Rien ici n'est calculé par l'app.** Chaque souvenir rédigé porte le relevé
// de l'agent de rédaction — pays, régions, villes, rencontres, kilomètres,
// transports, et l'endroit où le voyageur se trouve — et c'est le serveur qui
// les additionne à la lecture (`services/travelStatistics.ts`). L'app dessine
// ces chiffres, les accorde, et les relit tant que le serveur dit qu'un
// souvenir attend encore son relevé.

/// Les cinq chiffres qui se lisent au global comme sur le voyage en cours.
public struct TravelFigures: Codable, Sendable, Hashable {
    public var countries: Int
    public var regions: Int
    public var cities: Int
    /// Combien de personnes rencontrées — les compagnons de voyage n'y sont pas.
    public var encounters: Int
    /// Arrondis au kilomètre par le serveur ; l'app choisit seulement comment
    /// les écrire.
    public var distanceKilometres: Int

    public init(
        countries: Int = 0,
        regions: Int = 0,
        cities: Int = 0,
        encounters: Int = 0,
        distanceKilometres: Int = 0
    ) {
        self.countries = countries
        self.regions = regions
        self.cities = cities
        self.encounters = encounters
        self.distanceKilometres = distanceKilometres
    }

    public static let empty = TravelFigures()
}

/// Un moyen de transport employé sur le voyage en cours.
///
/// **Le nombre est facultatif, et c'est le sens de la ligne** : « 2 trains »
/// se compte, « scooter » se constate — la maquette écrit les deux sur la même
/// ligne. Le relevé ne pose un nombre que quand le récit l'a donné.
public struct TransportUsage: Codable, Sendable, Hashable, Identifiable {
    /// Les moyens que l'agent sait nommer. Fermée : c'est l'app qui en écrit
    /// le libellé et l'accord, et un moyen inconnu ne se lirait pas.
    public enum Kind: String, Codable, Sendable, Hashable, CaseIterable {
        case plane, train, bus, car, boat, bike, walk, scooter, motorbike, metro, taxi

        /// Le mot au singulier et son pluriel — « avion », « avions ». Les deux
        /// écrits, plutôt qu'un « s » collé : « bateau » fait « bateaux », et
        /// « à pied » ne se compte pas.
        public var words: (singular: String, plural: String) {
            switch self {
            case .plane: ("avion", "avions")
            case .train: ("train", "trains")
            case .bus: ("bus", "bus")
            case .car: ("voiture", "voitures")
            case .boat: ("bateau", "bateaux")
            case .bike: ("vélo", "vélos")
            case .walk: ("à pied", "à pied")
            case .scooter: ("scooter", "scooters")
            case .motorbike: ("moto", "motos")
            case .metro: ("métro", "métros")
            case .taxi: ("taxi", "taxis")
            }
        }
    }

    public let kind: Kind
    public var count: Int?

    public var id: Kind { kind }

    public init(kind: Kind, count: Int? = nil) {
        self.kind = kind
        self.count = count
    }

    /// « 1 avion », « 2 trains », « scooter ». Le nombre ne s'écrit que s'il a
    /// été relevé ; la marche ne se compte jamais.
    public var label: String {
        let (singular, plural) = kind.words
        guard let count, kind != .walk else { return singular }
        return count == 1 ? "\(count) \(singular)" : "\(count) \(plural)"
    }
}

/// Le voyage en cours, tel que la moitié basse de la feuille le montre.
public struct CurrentTripStatistics: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public var startDate: Date?
    public var endDate: Date?
    /// « Rome » — la dernière ville où un souvenir situe le voyageur.
    public var currentPlace: String?
    /// Le nombre de jours du voyage, pour « 2 jours validés sur 21 ».
    public var dayCount: Int
    /// Les journées qui ont au moins un souvenir rédigé.
    public var validatedDays: Int
    public var figures: TravelFigures
    /// Les vocaux enregistrés sur ce voyage.
    public var recordings: Int
    public var transports: [TransportUsage]

    public init(
        id: String,
        startDate: Date? = nil,
        endDate: Date? = nil,
        currentPlace: String? = nil,
        dayCount: Int = 0,
        validatedDays: Int = 0,
        figures: TravelFigures = .empty,
        recordings: Int = 0,
        transports: [TransportUsage] = []
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.currentPlace = currentPlace
        self.dayCount = dayCount
        self.validatedDays = validatedDays
        self.figures = figures
        self.recordings = recordings
        self.transports = transports
    }

    /// Décodage tolérant : un transport que cette version de l'app ne connaît
    /// pas est **sauté**, pas fatal. L'agent peut apprendre un mot avant que
    /// l'app ne soit mise à jour, et une ligne de moins vaut mieux qu'une
    /// feuille qui ne s'ouvre plus.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        currentPlace = try container.decodeIfPresent(String.self, forKey: .currentPlace)
        dayCount = try container.decodeIfPresent(Int.self, forKey: .dayCount) ?? 0
        validatedDays = try container.decodeIfPresent(Int.self, forKey: .validatedDays) ?? 0
        figures = try container.decodeIfPresent(TravelFigures.self, forKey: .figures) ?? .empty
        recordings = try container.decodeIfPresent(Int.self, forKey: .recordings) ?? 0
        transports =
            try container.decodeIfPresent([Lenient<TransportUsage>].self, forKey: .transports)?
            .compactMap(\.value) ?? []
    }

    /// La part du voyage déjà racontée, entre 0 et 1 : les jours validés sur
    /// les jours du voyage. Zéro tant qu'on ne sait pas combien il dure — un
    /// pourcentage d'une durée inconnue ne veut rien dire.
    public var writtenFraction: Double {
        guard dayCount > 0 else { return 0 }
        return min(1, max(0, Double(validatedDays) / Double(dayCount)))
    }
}

/// Tout ce que la feuille « Statistiques » montre, d'un seul tenant.
public struct TravelStatistics: Codable, Sendable, Hashable {
    public var tripCount: Int
    /// Tous les voyages du compte, additionnés.
    public var overall: TravelFigures
    public var currentTrip: CurrentTripStatistics?
    /// Combien de souvenirs attendent encore leur relevé. Tant qu'il y en a,
    /// la feuille se relit à intervalle court : c'est ce qui fait bouger un
    /// chiffre sous les yeux, sans connexion ouverte avec le serveur.
    public var pendingDetections: Int
    public var updatedAt: Date?

    public init(
        tripCount: Int = 0,
        overall: TravelFigures = .empty,
        currentTrip: CurrentTripStatistics? = nil,
        pendingDetections: Int = 0,
        updatedAt: Date? = nil
    ) {
        self.tripCount = tripCount
        self.overall = overall
        self.currentTrip = currentTrip
        self.pendingDetections = pendingDetections
        self.updatedAt = updatedAt
    }

    /// Même raison que ``TravellerProfile`` : un serveur plus ancien, ou un
    /// champ ajouté plus tard, ne doit pas vider la feuille.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tripCount = try container.decodeIfPresent(Int.self, forKey: .tripCount) ?? 0
        overall = try container.decodeIfPresent(TravelFigures.self, forKey: .overall) ?? .empty
        currentTrip = try container.decodeIfPresent(CurrentTripStatistics.self, forKey: .currentTrip)
        pendingDetections = try container.decodeIfPresent(Int.self, forKey: .pendingDetections) ?? 0
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    /// `true` tant que l'agent a encore des souvenirs à relire — la feuille
    /// le dit, et se relit.
    public var isDetecting: Bool { pendingDetections > 0 }

    /// Ce qui **compte** pour dire que la feuille a changé : les chiffres, pas
    /// l'horodatage. Deux lectures à trois secondes d'écart sur un voyage
    /// immobile ne doivent pas faire clignoter l'écran.
    public func hasSameFigures(as other: TravelStatistics) -> Bool {
        tripCount == other.tripCount
            && overall == other.overall
            && currentTrip == other.currentTrip
            && pendingDetections == other.pendingDetections
    }
}

/// Décode une valeur **ou rien**, au lieu de faire échouer le tableau qui la
/// porte. C'est ce qui permet à une liste de transports de survivre à un mot
/// que l'app ne connaît pas encore.
private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
