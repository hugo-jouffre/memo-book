import Foundation

// Les paramètres d'un voyage : tout ce qui se règle sur le carnet sans quitter
// le voyage.
//
// L'écran est fait à 90 % d'intitulés que l'app connaît déjà — « Dates du
// voyage », « Rythme du récit » — et de valeurs qui viennent du serveur. C'est
// exactement le partage que ``BrandSkeleton`` demande : la page se dessine tout
// de suite, et seules les valeurs portent une barre d'attente.
//
// Ce qui se règle vraiment ici est décrit dans `docs/reglages-utilisateur.md` ;
// cette structure n'en est que la lecture.

/// À quel rythme MEMO découpe le récit en étapes.
///
/// Fermée côté app, tolérante au décodage : un rythme ajouté côté serveur
/// s'affiche sous son nom brut plutôt que de vider la ligne.
public enum NarrationPace: Sendable, Hashable {
    case daily
    case everyTwoDays
    case weekly
    case byPlace
    case unknown(String)

    /// Le nom du rythme, tel qu'on l'écrit au voyageur.
    public var displayName: String {
        switch self {
        case .daily: "Tous les jours"
        case .everyTwoDays: "Tous les 2 jours"
        case .weekly: "Toutes les semaines"
        case .byPlace: "À chaque lieu"
        case .unknown(let raw): raw
        }
    }

    public static let selectable: [NarrationPace] = [.daily, .everyTwoDays, .weekly, .byPlace]
}

extension NarrationPace: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self =
            switch raw {
            case "daily": .daily
            case "every_two_days": .everyTwoDays
            case "weekly": .weekly
            case "by_place": .byPlace
            default: .unknown(raw)
            }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .daily: "daily"
        case .everyTwoDays: "every_two_days"
        case .weekly: "weekly"
        case .byPlace: "by_place"
        case .unknown(let raw): raw
        }
    }
}

/// Les paramètres d'un voyage, d'un seul tenant.
public struct TripSettings: Codable, Sendable, Hashable, Identifiable {
    public let tripId: String

    public nonisolated var id: String { tripId }

    // MARK: Gère ton aventure

    /// Le nom du voyage — « Rome 2026 ».
    public var name: String

    /// Le solde de la cagnotte, en euros. **La même somme que dans le
    /// profil** : la cagnotte appartient au compte, pas au voyage (voir
    /// ``Wallet``). Elle apparaît ici parce que c'est là qu'on la remplit.
    public var walletBalance: Decimal

    public var startDate: Date?
    public var endDate: Date?
    public var narrationPace: NarrationPace?

    /// Les notifications de ce voyage. C'est l'interrupteur du voyage, pas
    /// celui du système : couper ici n'enlève pas l'autorisation, ça arrête
    /// seulement les relances de ce carnet-là.
    public var wantsNotifications: Bool

    /// Ceux qui racontent le voyage avec toi.
    public var companions: [Companion]

    // MARK: Le contenu du carnet

    /// Le thème du voyage — « City trip & découvertes ». Il oriente le ton du
    /// récit et les illustrations.
    public var theme: String?

    /// Le carnet est visible dans la galerie de la communauté.
    public var isPublicGallery: Bool

    /// Le style de mise en page — « Pointillés, cadres, etc. ». Un résumé de ce
    /// que `docs/reglages-utilisateur.md` détaille.
    public var styleSummary: String?

    // MARK: Accès rapide

    /// Le Tricount relié, s'il y en a un. Sa présence change le libellé de la
    /// ligne : « Connecte ton Tricount » devient le compte relié.
    public var tricountLabel: String?

    /// L'aperçu du carnet, pour la vignette de la ligne « Prévisulation PDF ».
    /// `nil` quand rien n'a encore été composé.
    public var previewCoverUrl: URL?

    /// Le carnet peut partir à l'impression. Faux, la ligne « Commander le
    /// carnet » reste lisible mais ne mène nulle part — il n'y a rien à
    /// imprimer.
    public var isPrintable: Bool

    public init(
        tripId: String,
        name: String,
        walletBalance: Decimal = 0,
        startDate: Date? = nil,
        endDate: Date? = nil,
        narrationPace: NarrationPace? = nil,
        wantsNotifications: Bool = true,
        companions: [Companion] = [],
        theme: String? = nil,
        isPublicGallery: Bool = false,
        styleSummary: String? = nil,
        tricountLabel: String? = nil,
        previewCoverUrl: URL? = nil,
        isPrintable: Bool = false
    ) {
        self.tripId = tripId
        self.name = name
        self.walletBalance = walletBalance
        self.startDate = startDate
        self.endDate = endDate
        self.narrationPace = narrationPace
        self.wantsNotifications = wantsNotifications
        self.companions = companions
        self.theme = theme
        self.isPublicGallery = isPublicGallery
        self.styleSummary = styleSummary
        self.tricountLabel = tricountLabel
        self.previewCoverUrl = previewCoverUrl
        self.isPrintable = isPrintable
    }

    /// « @clara_prn, @ana.prn » — les co-voyageurs en bout de ligne.
    ///
    /// `nil` quand on voyage seul : la maquette ne dessine pas ce cas, et une
    /// ligne « Co-voyageur(s) » vide se lirait comme une valeur qui n'a pas
    /// chargé. C'est un écart signalé dans la fiche écran.
    public var companionsLabel: String? {
        guard !companions.isEmpty else { return nil }
        return companions.map(\.name).joined(separator: ", ")
    }
}

/// Ce qu'un réglage modifié envoie au serveur.
///
/// Une seule propriété à la fois, et non la structure entière : l'écran ne
/// renvoie que ce que l'utilisateur a touché, ce qui évite d'écraser un réglage
/// changé ailleurs entre-temps — par un co-voyageur, par exemple.
public enum TripSettingsEdit: Sendable, Hashable {
    case name(String)
    case dates(start: Date?, end: Date?)
    case narrationPace(NarrationPace)
    case notifications(Bool)
    case theme(String)
    case publicGallery(Bool)
}
