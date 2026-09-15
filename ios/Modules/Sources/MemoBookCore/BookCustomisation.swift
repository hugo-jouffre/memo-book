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

    public var id: String { name }

    public init(name: String, label: String? = nil, detail: String) {
        self.name = name
        self.label = label ?? name
        self.detail = detail
    }

    /// Cette option est-elle celle qu'un carnet porte ? Le nom entier d'abord ;
    /// le libellé aussi, parce que la base a longtemps reçu « Playfair » là où
    /// le gabarit dit « Playfair Display ».
    public func matches(_ stored: String) -> Bool {
        stored == name || stored == label
    }

    // Les trois familles de la maquette (`3443:10073`), dans son ordre.
    //
    // ⚠️ **Elles ne sont pas rendues dans leur propre dessin.** Figma écrit
    // chaque nom dans sa police ; les embarquer demanderait trois familles de
    // plus dans le binaire pour trois bouts de ligne, et le dépôt n'a que
    // Playfair Display, en woff2 — un format que CoreText ne lit pas. Écart
    // signalé dans la fiche écran.
    static let playfairRecommended = BookFontOption(
        name: "Playfair Display", label: "Playfair", detail: "La recommandations de nos équipes"
    )
    static let playfair = BookFontOption(
        name: "Playfair Display", label: "Playfair", detail: "L’élégante, celle des titres"
    )
    static let alegreya = BookFontOption(name: "Alegreya", detail: "Pour des livres plus fun")
    static let montserrat = BookFontOption(name: "Montserrat", detail: "La plus classique")
    static let hansley = BookFontOption(name: "Hansley", detail: "Le choix de nos équipes")
    static let gloria = BookFontOption(name: "Gloria Hallelujah", detail: "Le choix de nos équipes")
}

/// Les quatre typographies du carnet, dans l'ordre de l'écran.
///
/// **Une feuille pour les quatre, qui se comporte pareil** (Hugo, 16/09/2026) :
/// la maquette n'en dessine qu'une — « Titres du carnet » —, et l'écran
/// laissait les trois autres lignes inertes (T78, désormais T136). Chaque rôle
/// sait quelle colonne il écrit, quelle édition il envoie, et quelles familles
/// il propose : son défaut d'abord, puis les trois de la maquette.
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

    /// Les familles proposées, la première étant le défaut du carnet.
    public var options: [BookFontOption] {
        switch self {
        case .titles: [.playfairRecommended, .alegreya, .montserrat]
        case .subtitles: [.hansley, .playfair, .alegreya, .montserrat]
        case .texts: [.gloria, .playfair, .alegreya, .montserrat]
        case .funFacts: [.playfairRecommended, .alegreya, .montserrat]
        }
    }

    /// Ce que la ligne de l'écran affiche : le libellé de la maquette quand le
    /// nom est une des options, le nom tel quel sinon — une famille posée par
    /// un autre client ne doit pas disparaître de l'écran.
    public func label(in customisation: BookCustomisation) -> String {
        let name = customisation[keyPath: keyPath]
        return options.first { $0.matches(name) }?.label ?? name
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
