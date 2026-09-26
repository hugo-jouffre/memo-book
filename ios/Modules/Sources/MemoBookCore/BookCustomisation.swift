import Foundation

// Les personnalisations du carnet : ce qui décide de sa mise en page.
//
// Elles vivent **sur le carnet** et non dans une table à part — il y en a
// exactement un jeu par voyage, elles se lisent toujours avec lui, et aucune
// requête ne les interroge seules. C'est déjà le parti pris de la base
// (`memos`, migration M4) ; cette structure n'en est que la lecture.
//
// ⚠️ **Règle de survie** (`docs/reglages-utilisateur.md`) : aucun réglage n'est
// exposé dans l'app avant d'exister dans `templates/travel-journal/LAYOUT_KB.md`.
// Une option que le gabarit ignore ferait croire au voyageur qu'il a réglé
// quelque chose.

/// Les personnalisations d'un carnet, d'un seul tenant.
public struct BookCustomisation: Codable, Sendable, Hashable {
    // MARK: Mise en page

    /// Part de photo dans la page, en pourcentage. 50 = l'équilibre de la
    /// maquette. Pilote le choix des gabarits et la fréquence des pages photo.
    public var photoTextRatio: Int

    /// Nombre de pages visé. Pilote le niveau de détail de la rédaction et le
    /// regroupement des étapes.
    public var targetPageCount: Int

    // MARK: Décors

    public var funFactsEnabled: Bool
    /// Les pointillés d'écriture, sur lesquels le récit se pose.
    public var rulesEnabled: Bool
    /// Combien de décorations par paragraphe. Zéro laisse la page nue.
    public var decorationQuota: Int

    // MARK: Typographies

    /// Les quatre familles du carnet. Ce sont des **noms de police**, pas des
    /// identifiants : c'est le gabarit qui les résout, et l'app ne fait que les
    /// afficher.
    public var fontTitle: String
    public var fontDisplay: String
    public var fontHand: String
    public var fontFacts: String

    // MARK: Extras

    public var quizEnabled: Bool
    public var freeZonesEnabled: Bool
    public var crosswordEnabled: Bool

    // MARK: Couvertures

    /// La première et la quatrième de couverture ont-elles été choisies.
    ///
    /// La ligne du haut mène à leur aperçu quoi qu'il arrive : elle dit
    /// « Aperçu et personnalisation », pas « À configurer ».
    public var hasConfiguredCovers: Bool

    public init(
        photoTextRatio: Int = 50,
        targetPageCount: Int = 60,
        funFactsEnabled: Bool = true,
        rulesEnabled: Bool = true,
        decorationQuota: Int = 2,
        fontTitle: String = "Hansley",
        fontDisplay: String = "Playfair Display",
        fontHand: String = "Gloria Hallelujah",
        fontFacts: String = "Playfair Display",
        quizEnabled: Bool = true,
        freeZonesEnabled: Bool = true,
        crosswordEnabled: Bool = true,
        hasConfiguredCovers: Bool = false
    ) {
        self.photoTextRatio = photoTextRatio
        self.targetPageCount = targetPageCount
        self.funFactsEnabled = funFactsEnabled
        self.rulesEnabled = rulesEnabled
        self.decorationQuota = decorationQuota
        self.fontTitle = fontTitle
        self.fontDisplay = fontDisplay
        self.fontHand = fontHand
        self.fontFacts = fontFacts
        self.quizEnabled = quizEnabled
        self.freeZonesEnabled = freeZonesEnabled
        self.crosswordEnabled = crosswordEnabled
        self.hasConfiguredCovers = hasConfiguredCovers
    }

    /// « 50/50 » — la part de photo face à celle du texte.
    public var photoTextLabel: String { "\(photoTextRatio)/\(100 - photoTextRatio)" }

    /// « 60 pages ». Accordé : un carnet d'une page arrive au premier souvenir.
    public var targetPageLabel: String {
        targetPageCount <= 1 ? "\(targetPageCount) page" : "\(targetPageCount) pages"
    }

    /// « 2 / paragraphe », ou « Aucune » quand le quota est nul.
    public var decorationLabel: String {
        decorationQuota == 0 ? "Aucune" : "\(decorationQuota) / paragraphe"
    }
}

/// Ce qu'une personnalisation modifiée envoie au serveur.
///
/// Un réglage à la fois, comme ``TripSettingsEdit`` et pour la même raison :
/// l'écran ne renvoie que ce qu'on a touché, ce qui évite d'écraser ce qu'un
/// co-voyageur aurait changé entre-temps.
public enum BookCustomisationEdit: Sendable, Hashable {
    case photoTextRatio(Int)
    case targetPageCount(Int)
    case funFacts(Bool)
    case rules(Bool)
    case decorationQuota(Int)
    /// La typographie des **titres** du carnet, qui vit dans `fontDisplay` :
    /// c'est le token `--mb-font-display` du gabarit. Voir la table de
    /// `templates/travel-journal/LAYOUT_KB.md`, et ``BookFontRole`` pour le
    /// croisement des noms.
    case fontDisplay(String)
    /// Celle des **sous-titres** — `fontTitle`, token `--mb-font-title`.
    case fontTitle(String)
    /// Celle des **textes** — `fontHand`, la manuscrite du récit.
    case fontHand(String)
    /// Celle des **fun facts** — `fontFacts`.
    case fontFacts(String)
    /// **Les quatre d'un coup**, parce qu'on ne les choisit plus séparément.
    ///
    /// Un seul aller-retour et non quatre : un assortiment est une décision, et
    /// quatre `PATCH` successifs laisseraient le carnet dans trois états
    /// intermédiaires qui n'ont jamais été choisis — dont un, si le réseau
    /// coupe au milieu, resterait. Les quatre colonnes voyagent déjà ensemble
    /// dans le corps de la requête, il n'y avait qu'à les y mettre.
    case fontCombo(BookFontCombo)
    case quiz(Bool)
    case freeZones(Bool)
    case crossword(Bool)
}

// MARK: - Les typographies proposées

/// Une police proposée par une feuille de typographie.
///
/// Un **nom de famille**, celui que `memos.font*` porte et que le gabarit
/// d'impression résout (`templates/travel-journal/`) ; un **libellé**, celui
/// que la maquette écrit — « Playfair » pour Playfair Display — ; et une
/// phrase. L'app ne fait que montrer le libellé et renvoyer le nom.
public struct BookFontOption: Sendable, Hashable, Identifiable {
    public let name: String
    public let label: String
    public let detail: String
    /// Le nom de la police **dessiné dans sa police**, quand Clara l'a fourni
    /// en vectoriel (`assets/logos/<Nom>.svg` → `Wordmark<Nom>`). `nil` :
    /// l'écran écrit le libellé en General Sans.
    public let wordmark: String?

    public var id: String { name }

    public init(name: String, label: String? = nil, detail: String, wordmark: String? = nil) {
        self.name = name
        self.label = label ?? name
        self.detail = detail
        self.wordmark = wordmark
    }

    /// Cette option est-elle celle qu'un carnet porte ? Le nom entier d'abord ;
    /// le libellé aussi, parce que la base a longtemps reçu « Playfair » là où
    /// le gabarit dit « Playfair Display ».
    public func matches(_ stored: String) -> Bool {
        stored == name || stored == label
    }

    /// Deux noms désignent-ils la même famille ? Le nom entier, ou le libellé :
    /// la base a longtemps reçu « Playfair » là où le gabarit dit « Playfair
    /// Display », et les deux doivent se reconnaître.
    public static func matching(_ one: String, _ other: String) -> Bool {
        guard one != other else { return true }
        guard let known = catalogue.first(where: { $0.matches(one) }) else { return false }
        return known.matches(other)
    }

    // Les cinq familles que le carnet sait porter.
    //
    // **Quatre d'entre elles se dessinent dans leur propre police**, par un
    // vectoriel du nom (Hugo, 17/09/2026, T118) : on n'embarque pas une
    // famille pour un bout de ligne. Alegreya a reçu le sien le 22/09/2026 ;
    // Montserrat s'écrit encore en General Sans, mais aucun assortiment ne la
    // propose plus.
    public static let playfair = BookFontOption(
        name: "Playfair Display",
        label: "Playfair",
        detail: "L’élégante, celle des titres",
        wordmark: "WordmarkPlayfair"
    )
    public static let alegreya = BookFontOption(
        name: "Alegreya", detail: "La serif chaleureuse du récit", wordmark: "WordmarkAlegreya"
    )
    public static let montserrat = BookFontOption(name: "Montserrat", detail: "La géométrique, nette et moderne")
    public static let hansley = BookFontOption(
        name: "Hansley", detail: "La manuscrite des titres", wordmark: "WordmarkHansley"
    )
    public static let gloria = BookFontOption(
        name: "Gloria Hallelujah",
        label: "Hallelujah",
        detail: "L’écriture à la main du récit",
        wordmark: "WordmarkGloriaHallelujah"
    )

    /// Le catalogue entier, pour résoudre un nom stocké en libellé.
    public static let catalogue: [BookFontOption] = [playfair, alegreya, montserrat, hansley, gloria]
}

/// Les quatre typographies du carnet, dans l'ordre de l'écran.
///
/// **On n'en choisit plus une par une** (Hugo, 16/09/2026) : l'écran ne propose
/// que des ``BookFontCombo``, trois assortiments dont on sait qu'ils tiennent
/// ensemble. Ce type reste, parce qu'il porte ce qu'un combo ne dit pas —
/// quelle colonne chaque rôle écrit, quelle édition il envoie, et sous quel nom
/// il se lit. C'est lui qui traduit un combo en quatre valeurs.
///
/// ⚠️ **Le croisement des noms est volontaire.** « Typographie des titres »
/// écrit `fontDisplay` — le token `--mb-font-display` du gabarit —, et « des
/// sous-titres » écrit `fontTitle` (`--mb-font-title`). Voir la table de
/// `templates/travel-journal/LAYOUT_KB.md`.
public enum BookFontRole: String, Sendable, Hashable, CaseIterable, Identifiable {
    case titles
    case subtitles
    case texts
    case funFacts

    public var id: String { rawValue }

    /// La colonne du carnet que ce rôle lit et écrit.
    public var keyPath: WritableKeyPath<BookCustomisation, String> {
        switch self {
        case .titles: \.fontDisplay
        case .subtitles: \.fontTitle
        case .texts: \.fontHand
        case .funFacts: \.fontFacts
        }
    }

    /// L'édition qui porte ce nom au serveur.
    public func edit(_ name: String) -> BookCustomisationEdit {
        switch self {
        case .titles: .fontDisplay(name)
        case .subtitles: .fontTitle(name)
        case .texts: .fontHand(name)
        case .funFacts: .fontFacts(name)
        }
    }

    /// Ce que ce rôle habille, tel que la feuille des combos l'écrit en face du
    /// nom de la police. C'est **la** chose qu'un assortiment doit rendre
    /// évidente : on choisit une ligne, et on doit voir ce qu'elle décide.
    public var label: String {
        switch self {
        case .titles: "Titres"
        case .subtitles: "Sous-titres"
        case .texts: "Textes"
        case .funFacts: "Fun facts & autres"
        }
    }

    /// Le nom de la police que ce rôle porte dans ce carnet, écrit comme la
    /// marque l'écrit — « Playfair » là où le gabarit dit « Playfair Display ».
    /// Une famille inconnue s'affiche telle quelle : une valeur posée par un
    /// autre client ne doit pas disparaître de l'écran.
    public func fontLabel(in customisation: BookCustomisation) -> String {
        BookFontOption.catalogue
            .first { $0.matches(customisation[keyPath: keyPath]) }?
            .label ?? customisation[keyPath: keyPath]
    }
}

// MARK: - Les trois assortiments

/// Un assortiment de quatre typographies qui vont ensemble.
///
/// **On ne choisit plus police par police** (Hugo, 16/09/2026). L'écran posait
/// quatre lignes — titres, sous-titres, textes, fun facts — et laissait
/// composer librement : trois familles au choix sur chacune, soit des dizaines
/// de combinaisons dont la plupart sont laides. Un carnet imprimé ne se
/// rattrape pas, et personne ne veut découvrir à la livraison qu'il a marié une
/// géométrique et une manuscrite.
///
/// Quatre assortiments, donc, chacun cohérent de bout en bout, et l'écran dit
/// **ce que chaque police habille** : c'est la seule façon de choisir en
/// connaissance de cause sans avoir à connaître la typographie.
///
/// ⚠️ **Deux des cinq familles ne sont pas encore dans le gabarit.** `fonts.css`
/// n'inline que Playfair Display et Gloria Hallelujah ; Hansley est versionné
/// sans être inliné, Alegreya et Montserrat ne sont pas là du tout — voir
/// `templates/travel-journal/LAYOUT_KB.md` § Polices. Rien n'échoue : la page
/// retombe sur une police système. C'était déjà vrai des quatre lignes que ces
/// combos remplacent ; ce n'est donc pas une régression, c'est une dette
/// nommée.
public struct BookFontCombo: Sendable, Hashable, Identifiable {
    public let id: String
    /// Le nom de l'assortiment — ce qu'on retient. « Carnet de voyage ».
    public let name: String
    /// Ce qu'il donne au carnet, en une phrase.
    public let detail: String

    /// Les quatre familles, **par rôle**. Une table et non quatre champs : c'est
    /// elle qui se parcourt pour écrire les quatre colonnes comme pour dessiner
    /// les quatre lignes de la feuille, sans que personne ait à réénumérer les
    /// rôles.
    public let fonts: [BookFontRole: String]

    public init(id: String, name: String, detail: String, fonts: [BookFontRole: String]) {
        self.id = id
        self.name = name
        self.detail = detail
        self.fonts = fonts
    }

    /// La police de ce rôle dans cet assortiment, sous son nom de famille — ce
    /// que la base stocke et que le gabarit résout.
    public func font(_ role: BookFontRole) -> String {
        fonts[role] ?? BookFontCombo.travelJournal.fonts[role] ?? "Playfair Display"
    }

    /// Le même, sous le nom qu'on écrit : « Playfair » et non « Playfair Display ».
    public func fontLabel(_ role: BookFontRole) -> String {
        let name = font(role)
        return BookFontOption.catalogue.first { $0.matches(name) }?.label ?? name
    }

    /// Le vectoriel du nom de la police de ce rôle, s'il existe.
    public func fontWordmark(_ role: BookFontRole) -> String? {
        BookFontOption.catalogue.first { $0.matches(font(role)) }?.wordmark
    }

    /// Ce carnet porte-t-il cet assortiment ? **Les quatre rôles, ou aucun** :
    /// un carnet composé à la main avant cette feuille peut très bien avoir
    /// trois polices sur quatre en commun avec un combo, et le cocher serait
    /// mentir sur ce qui s'imprimera.
    public func matches(_ customisation: BookCustomisation) -> Bool {
        BookFontRole.allCases.allSatisfy { role in
            BookFontOption.matching(font(role), customisation[keyPath: role.keyPath])
        }
    }

    // MARK: Les trois

    /// Le défaut, et celui que portent déjà les carnets existants : Playfair,
    /// Hansley, Gloria Hallelujah, Playfair. C'est **exactement** le jeu que la
    /// base pose par défaut (voir `BookCustomisation.init`), ce qui fait qu'un
    /// carnet d'avant cette feuille s'y reconnaît sans rien changer.
    public static let travelJournal = BookFontCombo(
        id: "travel-journal",
        name: "Carnet de voyage",
        detail: "Le choix de nos équipes : une serif de caractère, et le récit écrit à la main.",
        fonts: [
            .titles: "Playfair Display",
            .subtitles: "Hansley",
            .texts: "Gloria Hallelujah",
            .funFacts: "Playfair Display",
        ]
    )

    /// Tout en serif : un vrai livre, celui qu'on range dans une bibliothèque.
    public static let editorial = BookFontCombo(
        id: "editorial",
        name: "Éditorial",
        detail: "Tout en serif, comme un roman. Le plus sobre des trois.",
        fonts: [
            .titles: "Playfair Display",
            .subtitles: "Playfair Display",
            .texts: "Alegreya",
            .funFacts: "Alegreya",
        ]
    )

    /// Tout à la main : le carnet qu'on aurait écrit soi-même.
    public static let handwritten = BookFontCombo(
        id: "handwritten",
        name: "Manuscrit",
        detail: "Entièrement écrit à la main, comme un carnet qu'on aurait tenu soi-même.",
        fonts: [
            .titles: "Hansley",
            .subtitles: "Hansley",
            .texts: "Gloria Hallelujah",
            .funFacts: "Gloria Hallelujah",
        ]
    )

    /// Les trois, dans l'ordre de la feuille — le défaut en tête.
    ///
    /// Il y en avait quatre : « Moderne » (titres Montserrat, récit Alegreya)
    /// est retiré le 18/09/2026 (Hugo). Un carnet réglé dessus reste tel quel —
    /// ses quatre polices sont en base, le gabarit les résout — et la feuille
    /// l'écrit « Personnalisé », comme tout carnet composé hors de ces trois.
    public static let all: [BookFontCombo] = [travelJournal, editorial, handwritten]

    /// L'assortiment d'un carnet, ou `nil` s'il n'en porte aucun.
    ///
    /// `nil` est un état réel et non un défaut manquant : un carnet composé
    /// police par police avant cette feuille, ou par un autre client, peut
    /// n'entrer dans aucune des trois cases. L'écran l'écrit alors
    /// « Personnalisé » plutôt que de cocher de force.
    public static func matching(_ customisation: BookCustomisation) -> BookFontCombo? {
        all.first { $0.matches(customisation) }
    }
}

// MARK: - Le nombre de pages

/// Le niveau de détail du carnet, tel que la feuille « Nombre de page » le
/// propose.
///
/// **Les nombres ne sont pas écrits dans l'app.** La maquette annonce 30 / 60 /
/// 90 en précisant « Estimations pour un voyage de 2 mois » : ce sont des
/// projections, pas des valeurs. Elles se recalculent donc sur la durée du
/// voyage qu'on regarde — c'est la note « Logique » du nœud (`3443:10070`).
public enum BookPageTarget: String, Sendable, Hashable, CaseIterable, Identifiable {
    case compact
    case standard
    case detailed
    /// Le voyageur pose lui-même son nombre de pages.
    case custom

    public var id: String { rawValue }

    /// Le nom du palier, sans son nombre — celui-ci dépend du voyage.
    public var title: String {
        switch self {
        case .compact: "Compact"
        case .standard: "Par défaut"
        case .detailed: "Détaillé"
        case .custom: "Personnalisé"
        }
    }

    public var detail: String {
        switch self {
        case .compact: "Très condensé, peu impliquer des pertes de détails"
        case .standard: "Parfait pour une aventure comme la tienne"
        case .detailed: "Les moindre détails de tes récits seront conservés"
        case .custom: "Définissez un nombre de pages cible"
        }
    }

    /// « Compact (≈ 30 pages) » — le titre, et sa projection pour ce voyage-ci.
    public func label(forTripDays days: Int?) -> String {
        guard let pages = pageCount(forTripDays: days) else { return title }
        return "\(title) (≈ \(pages) pages)"
    }

    /// Combien de pages ce palier vise pour un voyage de `days` jours.
    ///
    /// Une page par jour au palier courant, arrondie à la dizaine, bornée entre
    /// un carnet minimal et ce qu'une reliure accepte : c'est la règle qui rend
    /// 30 / 60 / 90 sur les deux mois de la maquette. `nil` pour
    /// ``BookPageTarget/custom``, qui ne projette rien — c'est le voyageur qui
    /// pose le nombre.
    public func pageCount(forTripDays days: Int?) -> Int? {
        guard self != .custom else { return nil }
        let standard = Self.standardPageCount(forTripDays: days)
        return switch self {
        case .compact: Self.roundedToTen(Double(standard) * 0.5)
        case .standard: standard
        case .detailed: Self.roundedToTen(Double(standard) * 1.5)
        case .custom: nil
        }
    }

    /// Le palier auquel un nombre de pages correspond, ou ``custom`` s'il ne
    /// tombe sur aucun.
    public static func matching(pageCount: Int, tripDays: Int?) -> BookPageTarget {
        [.compact, .standard, .detailed]
            .first { $0.pageCount(forTripDays: tripDays) == pageCount } ?? .custom
    }

    /// Un carnet de moins de 30 pages ne vaut pas une reliure, et au-delà de 180
    /// le dos ne tient plus. Sans durée connue, on rend le défaut de la base.
    private static func standardPageCount(forTripDays days: Int?) -> Int {
        guard let days, days > 0 else { return 60 }
        return min(max(roundedToTen(Double(days)), 30), 180)
    }

    private static func roundedToTen(_ value: Double) -> Int {
        Int((value / 10).rounded()) * 10
    }
}
