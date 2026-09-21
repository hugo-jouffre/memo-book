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
    case everyThreeDays
    case weekly
    /// Le voyageur règle ses propres alertes.
    ///
    /// ⚠️ **L'écran qui les règle n'est pas dessiné.** L'option existe parce que
    /// la maquette la pose (`3443:9874`) et qu'on n'invente pas plus qu'elle ne
    /// dit (R3) ; choisir « Personnalisé » enregistre donc le rythme et ne
    /// demande rien d'autre. Signalé dans la fiche écran.
    case custom
    /// L'ancien rythme « À chaque lieu », remplacé dans la maquette par
    /// « Tous les 3 jours ». Gardé pour **relire** les voyages déjà réglés
    /// dessus : il s'affiche, il ne se propose plus.
    case byPlace
    case unknown(String)

    /// Le nom du rythme, tel qu'on l'écrit au voyageur.
    public var displayName: String {
        switch self {
        case .daily: "Tous les jours"
        case .everyTwoDays: "Tous les 2 jours"
        case .everyThreeDays: "Tous les 3 jours"
        case .weekly: "Une fois par semaine"
        case .custom: "Personnalisé"
        case .byPlace: "À chaque lieu"
        case .unknown(let raw): raw
        }
    }

    /// La ligne sous le nom, dans la feuille « Rythme du récit ». Elle dit ce
    /// que le rythme **fait**, pas ce qu'il est.
    public var detail: String? {
        switch self {
        case .daily: "Une entrée chaque soir"
        case .everyTwoDays: "Le rythme recommandé pour souffler"
        case .everyThreeDays: "Idéal pour les longs séjours"
        case .weekly: "Pour un résumé global"
        case .custom: "Définis tes propres alertes"
        case .byPlace, .unknown: nil
        }
    }

    /// Les cinq rythmes que la feuille propose, dans l'ordre de la maquette.
    public static let selectable: [NarrationPace] = [
        .daily, .everyTwoDays, .everyThreeDays, .weekly, .custom,
    ]
}

extension NarrationPace: Codable {
    public init(from decoder: any Decoder) throws {
        self = NarrationPace(storedValue: try decoder.singleValueContainer().decode(String.self))
    }

    /// Le rythme, depuis ce que la base garde.
    ///
    /// **Les anciens libellés aussi.** Jusqu'au 17/09/2026, la création écrivait
    /// le rythme dans les mots de l'écran — « Tous les jours », « Tous les 2
    /// jours », « Toutes les semaines » — quand la feuille des réglages
    /// écrivait déjà la clé. Dix voyages en portent encore un : la feuille les
    /// lisait comme un rythme inconnu et ne cochait rien (Hugo, 18/09/2026).
    /// Le serveur les réécrit désormais en clés à l'entrée et une migration a
    /// corrigé les rangées existantes, mais une app qui parle à l'API d'avant
    /// doit les relire de la même façon.
    public init(storedValue raw: String) {
        self =
            switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "daily", "tous les jours": .daily
            case "every_two_days", "tous les 2 jours", "tous les deux jours": .everyTwoDays
            case "every_three_days", "tous les 3 jours", "tous les trois jours": .everyThreeDays
            case "weekly", "toutes les semaines", "une fois par semaine": .weekly
            case "custom", "personnalisé": .custom
            case "by_place", "à chaque lieu": .byPlace
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
        case .everyThreeDays: "every_three_days"
        case .weekly: "weekly"
        case .custom: "custom"
        case .byPlace: "by_place"
        case .unknown(let raw): raw
        }
    }
}

/// Les quatre alertes d'un voyage — la feuille « Notifications ».
///
/// **Quatre drapeaux et non un seul.** L'interrupteur « Notifications » des
/// réglages coupe tout d'un coup ; ceux-ci disent *quoi* recevoir quand il est
/// levé. Les confondre revenait à proposer un réglage fin qui n'était pas
/// retenu — exactement ce que `docs/reglages-utilisateur.md` interdit.
///
/// Décodage tolérant : un serveur qui ne les sert pas encore rend quatre
/// alertes actives, ce qui est le défaut de la base.
public struct TripNotificationPreferences: Codable, Sendable, Hashable {
    /// « Rappel d'écriture » — la relance calée sur le rythme du récit.
    public var writingReminder: Bool
    /// « Nouveau récit » — un proche a alimenté le carnet.
    public var newStory: Bool
    /// « Résumé hebdomadaire » — un point sur les souvenirs capturés.
    public var weeklyDigest: Bool
    /// « Rappel de fin de voyage » — l'alerte qui dit qu'il est temps de
    /// valider l'impression.
    public var tripEndReminder: Bool

    public init(
        writingReminder: Bool = true,
        newStory: Bool = true,
        weeklyDigest: Bool = true,
        tripEndReminder: Bool = true
    ) {
        self.writingReminder = writingReminder
        self.newStory = newStory
        self.weeklyDigest = weeklyDigest
        self.tripEndReminder = tripEndReminder
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        writingReminder = try container.decodeIfPresent(Bool.self, forKey: .writingReminder) ?? true
        newStory = try container.decodeIfPresent(Bool.self, forKey: .newStory) ?? true
        weeklyDigest = try container.decodeIfPresent(Bool.self, forKey: .weeklyDigest) ?? true
        tripEndReminder = try container.decodeIfPresent(Bool.self, forKey: .tripEndReminder) ?? true
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

    /// Les **limites de souvenirs** du compte — voir ``MemoryAllowance``.
    ///
    /// Elles appartiennent au compte comme la cagnotte, et elles voyagent ici
    /// pour la même raison : c'est **le seul écran qui les montre** (Hugo,
    /// 16/09/2026). Elles n'ont rien à faire sur l'accueil, où elles feraient
    /// du bruit pour une limite que personne n'atteint.
    ///
    /// Optionnelle le temps qu'un serveur plus ancien la serve : la ligne
    /// disparaît alors, au lieu d'annoncer un budget inventé.
    public var memory: MemoryAllowance?

    public var startDate: Date?
    public var endDate: Date?
    public var narrationPace: NarrationPace?

    /// Les notifications de ce voyage. C'est l'interrupteur du voyage, pas
    /// celui du système : couper ici n'enlève pas l'autorisation, ça arrête
    /// seulement les relances de ce carnet-là.
    public var wantsNotifications: Bool

    /// Le détail des quatre alertes, réglé par « Gérer mes notifications ».
    public var notifications: TripNotificationPreferences

    /// Ceux qui racontent le voyage avec toi — **le propriétaire compris**, en
    /// tête de liste.
    ///
    /// Il y figure parce que la feuille « Inviter un proche » le montre : sa
    /// ligne dit « Moi » et « Propriétaire du voyage », et c'est elle qui fait
    /// comprendre que la liste est celle du voyage entier. Il en est retiré
    /// **là où on compte les autres** — voir ``guests``.
    public var companions: [Companion]

    /// Le code d'accès du voyage — « JHKFDA ». C'est lui qu'on colle dans un
    /// message pour faire entrer quelqu'un. Nul tant que les réglages
    /// viennent d'un jeu d'essai sans code.
    public var accessCode: String?

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

    /// L'aperçu du carnet, pour la vignette de la ligne « Prévisualisation PDF ».
    /// `nil` quand rien n'a encore été composé.
    public var previewCoverUrl: URL?

    /// Le PDF du dernier carnet composé.
    ///
    /// Il voyage **avec les réglages** parce qu'il s'y trouvait déjà : la route
    /// lit le dernier rendu prêt pour en tirer la vignette de couverture, et le
    /// document est dans la même ligne. C'est lui que les feuilles de
    /// personnalisation feuillettent au-dessus d'elles — voir `BookPagesPeek`.
    ///
    /// `nil` tant qu'aucun carnet n'a été composé : les feuilles s'ouvrent
    /// alors seules, sans pages au-dessus. Montrer deux rectangles vides
    /// donnerait l'impression d'un rendu qui a échoué.
    public var bookPdfUrl: URL?

    /// Le carnet peut partir à l'impression. Faux, la ligne « Commander le
    /// carnet » reste lisible mais ne mène nulle part — il n'y a rien à
    /// imprimer.
    public var isPrintable: Bool

    /// Les personnalisations de la mise en page — l'écran « Style du carnet ».
    ///
    /// Elles voyagent **avec** les réglages et non sur une requête à elles : il
    /// y en a un jeu par voyage, elles se lisent toujours avec lui, et
    /// `styleSummary` en est le résumé d'une ligne. Optionnel le temps que la
    /// route les serve à tous les carnets.
    public var customisation: BookCustomisation?

    public init(
        tripId: String,
        name: String,
        walletBalance: Decimal = 0,
        memory: MemoryAllowance? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        narrationPace: NarrationPace? = nil,
        wantsNotifications: Bool = true,
        notifications: TripNotificationPreferences = TripNotificationPreferences(),
        companions: [Companion] = [],
        accessCode: String? = nil,
        theme: String? = nil,
        isPublicGallery: Bool = false,
        styleSummary: String? = nil,
        tricountLabel: String? = nil,
        previewCoverUrl: URL? = nil,
        bookPdfUrl: URL? = nil,
        isPrintable: Bool = false,
        customisation: BookCustomisation? = nil
    ) {
        self.tripId = tripId
        self.name = name
        self.walletBalance = walletBalance
        self.memory = memory
        self.startDate = startDate
        self.endDate = endDate
        self.narrationPace = narrationPace
        self.wantsNotifications = wantsNotifications
        self.notifications = notifications
        self.companions = companions
        self.accessCode = accessCode
        self.theme = theme
        self.isPublicGallery = isPublicGallery
        self.styleSummary = styleSummary
        self.tricountLabel = tricountLabel
        self.previewCoverUrl = previewCoverUrl
        self.bookPdfUrl = bookPdfUrl
        self.isPrintable = isPrintable
        self.customisation = customisation
    }

    /// « @clara_prn, @ana.prn » — les co-voyageurs en bout de ligne.
    ///
    /// `nil` quand on voyage seul : la maquette ne dessine pas ce cas, et une
    /// ligne « Co-voyageur(s) » vide se lirait comme une valeur qui n'a pas
    /// chargé. C'est un écart signalé dans la fiche écran.
    public var companionsLabel: String? {
        guard !guests.isEmpty else { return nil }
        return guests.map(\.name).joined(separator: ", ")
    }

    /// Les co-voyageurs **sans le propriétaire**.
    ///
    /// C'est ce que compte la ligne « Co-voyageur(s) » des réglages : le
    /// titulaire de l'écran n'est pas quelqu'un qu'il a invité, et se voir dans
    /// sa propre liste ferait douter du nombre.
    public var guests: [Companion] {
        companions.filter { !$0.isOwner }
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
    /// Les quatre alertes, d'un bloc. **Une exception à la règle du réglage
    /// unique**, et elle se justifie : les quatre vivent sur la même feuille,
    /// personne d'autre ne les touche, et les envoyer une par une ferait quatre
    /// requêtes pour quatre bascules qu'on enchaîne au doigt.
    case notificationPreferences(TripNotificationPreferences)
    case theme(String)
    case publicGallery(Bool)
}
