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
    case quiz(Bool)
    case freeZones(Bool)
    case crossword(Bool)
}
