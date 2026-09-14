import Foundation
import MemoBookCore
import Observation

/// Les six étapes de « Créer un voyage », dans l'ordre où on les traverse.
///
/// Elles sont **numérotées par la frise** du haut de l'écran : une barre par
/// étape, la verte étant celle qu'on remplit. C'est aussi pour ça qu'elles
/// forment une énumération et non une liste de vues — le compte des barres se
/// dérive du nombre de cas, et ajouter une étape ne demande pas de penser à la
/// frise.
public enum TripCreationStep: Int, CaseIterable, Sendable, Hashable {
    case theme
    case name
    case dates
    case notifications
    case ratio
    case companions

    /// Le titre vert, tel qu'il s'écrit dans la maquette.
    var title: String {
        switch self {
        case .theme: "Contexte de ton voyage"
        case .name: "Nom de ton aventure"
        case .dates: "Dates"
        case .notifications: "Notifications"
        case .ratio: "Ratio Image/Texte"
        case .companions: "Co-voyageur(s)"
        }
    }

    /// L'illustration posée au-dessus du titre. Elles viennent toutes du même
    /// jeu — voir `ios/Tools/import-brand-illustrations.py`.
    var illustration: String {
        switch self {
        case .theme: "IllustrationCarnet"
        case .name: "IllustrationTag"
        case .dates: "IllustrationValise"
        case .notifications: "IllustrationHorloge"
        case .ratio: "IllustrationAppareilPhoto"
        case .companions: "IllustrationDuo"
        }
    }

    /// Le libellé du bouton du bas. La dernière étape ne valide plus rien :
    /// elle ouvre le voyage.
    var callToAction: String {
        self == .companions ? "Commencer !" : "Valider"
    }

    /// L'étape a un « Passer ». Toutes, sauf la dernière : le voyage existe
    /// déjà, et il n'y a rien à éviter sur un écran qui ne fait que montrer son
    /// code d'accès — Hugo, 14/09/2026.
    var canBeSkipped: Bool { self != .companions }

    /// L'étape après laquelle le voyage **existe**.
    ///
    /// La création ne se fait pas au « Commencer ! » de la fin : la dernière
    /// étape ne montre que le code d'accès, et un code d'accès désigne un
    /// voyage. Le carnet part donc à la validation de l'avant-dernière.
    static var lastBeforeSave: TripCreationStep { .ratio }
}

/// Ce que sait faire la création d'un voyage : garder le brouillon des six
/// étapes, aller d'une étape à l'autre, et l'envoyer.
///
/// Même construction que ``HomeModel`` et ``TripHomeModel`` : le modèle ne
/// connaît pas l'API, il reçoit **deux fonctions** — une qui crée, une qui
/// corrige. Les aperçus n'en fournissent aucune et traversent le formulaire
/// sans serveur.
@MainActor
@Observable
public final class TripCreationModel {
    public private(set) var step: TripCreationStep = .theme

    /// Le brouillon, rempli étape par étape. Il ne part **qu'une fois**, à la
    /// fin de l'avant-dernière : six requêtes pour un formulaire qu'on peut
    /// remonter donneraient six façons de le laisser à moitié écrit.
    public var draft = TripDraft()

    /// Les thèmes de la rangée, **tels que le serveur les sert** — « Autre » en
    /// dernier. Vides le temps de la lecture ; la rangée montre alors une barre
    /// d'attente et non sept émojis inventés. Voir ``loadThemes()``.
    public private(set) var themes: [TripTheme] = []

    /// La lecture des thèmes a échoué. L'étape reste traversable : « Passer »
    /// et « Autre » n'ont besoin d'aucune liste.
    public private(set) var themesFailure: String?

    /// Le thème choisi dans la rangée d'émojis. `nil` tant qu'on n'a rien
    /// touché, ce qui n'est pas la même chose qu'« Autre » : passer l'étape
    /// laisse `theme` vide, choisir « Autre » ouvre un champ.
    public var selectedTheme: TripTheme?

    /// « Autre » est choisi : le champ libre est ouvert et c'est lui qui
    /// compte.
    public var isFreeThemeChosen: Bool { selectedTheme?.isOther == true }

    /// Le texte de « Autre ». Gardé à part de ``draft`` pour qu'un aller-retour
    /// sur l'étape ne l'efface pas quand on repasse par un émoji.
    public var freeTheme = ""

    /// Le voyage, une fois créé, et son code d'accès. C'est lui qui distingue
    /// une première validation d'un retour en arrière : tant qu'il est `nil`,
    /// on crée ; ensuite, on corrige.
    public private(set) var created: CreatedTrip?

    public private(set) var isSaving = false
    public private(set) var errorMessage: String?

    private let create: @Sendable (TripDraft) async throws -> CreatedTrip
    private let update: @Sendable (String, TripDraft) async throws -> CreatedTrip
    private let readThemes: @Sendable () async throws -> [TripTheme]

    /// - Parameter themes: d'où viennent les thèmes de la première étape. Par
    ///   défaut la liste du jeu d'essai, pour les aperçus ; l'app y branche
    ///   `GET /v1/trip-themes`.
    public init(
        create: @escaping @Sendable (TripDraft) async throws -> CreatedTrip = { .fixture($0) },
        update: @escaping @Sendable (String, TripDraft) async throws -> CreatedTrip = { id, draft in
            .fixture(draft, id: id)
        },
        themes: @escaping @Sendable () async throws -> [TripTheme] = { TripTheme.fixtures }
    ) {
        self.create = create
        self.update = update
        self.readThemes = themes
    }

    /// Lit les thèmes. À appeler à l'ouverture de l'écran ; relire ne fait pas
    /// de mal, la rangée garde son choix tant que le thème existe encore.
    public func loadThemes() async {
        do {
            themes = try await readThemes()
            themesFailure = nil
            if let chosen = selectedTheme, !themes.contains(chosen) {
                selectedTheme = nil
            }
        } catch {
            themesFailure = error.localizedDescription
        }
    }

    // MARK: - Ce que l'étape courante autorise

    /// Le bouton du bas est-il allumé ?
    ///
    /// Une seule étape peut l'éteindre : le nom, parce que c'est le seul champ
    /// dont la base ne sait pas se passer. Partout ailleurs « Valider » vaut
    /// « Passer », et un bouton grisé n'apprendrait rien.
    public var canValidate: Bool {
        switch step {
        case .name: !draft.title.trimmed.isEmpty
        case .theme: !isFreeThemeChosen || !freeTheme.trimmed.isEmpty
        default: true
        }
    }

    /// La frise : une barre par étape, la verte étant celle-ci.
    public var progress: Int { step.rawValue }

    // MARK: - Aller et venir

    /// Valide l'étape courante et passe à la suivante.
    public func validate() async {
        if step == .theme {
            draft.theme = isFreeThemeChosen ? freeTheme.trimmed : selectedTheme?.label
        }
        await advance()
    }

    /// Passe l'étape sans rien en retenir — le « Passer » du coin haut droit.
    ///
    /// Passer, c'est `nil`, jamais une valeur inventée. La seule exception est
    /// le nom, que la base exige : il tombe alors sur ``TripDraft/untitled``,
    /// qui se corrige ensuite dans les réglages du voyage.
    public func skip() async {
        switch step {
        case .theme:
            selectedTheme = nil
            freeTheme = ""
            draft.theme = nil
        case .name:
            if draft.title.trimmed.isEmpty { draft.title = TripDraft.untitled }
        case .dates:
            draft.startDate = nil
            draft.endDate = nil
        case .notifications:
            draft.narrationPace = nil
        case .ratio:
            draft.photoTextRatio = 50
        case .companions:
            break
        }
        await advance()
    }

    /// Revient à l'étape précédente. `false` quand il n'y en a pas : c'est
    /// alors à l'écran de se refermer, pas au modèle.
    @discardableResult
    public func goBack() -> Bool {
        guard let previous = TripCreationStep(rawValue: step.rawValue - 1) else { return false }
        errorMessage = nil
        step = previous
        return true
    }

    // MARK: - L'envoi

    /// Enregistre le brouillon puis avance, ou avance seulement.
    ///
    /// Le voyage part **une fois** — à la fin de l'avant-dernière étape. Y
    /// revenir et revalider ne crée pas un second voyage : on corrige celui
    /// qui existe, et son code d'accès ne bouge pas, parce qu'il a peut-être
    /// déjà été envoyé à quelqu'un.
    private func advance() async {
        errorMessage = nil

        if step == .name, draft.title.trimmed.isEmpty { draft.title = TripDraft.untitled }
        if step == .name { draft.title = draft.title.trimmed }

        if step == .lastBeforeSave {
            guard await save() else { return }
        }

        guard let next = TripCreationStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    private func save() async -> Bool {
        isSaving = true
        defer { isSaving = false }

        do {
            if let existing = created {
                created = try await update(existing.trip.id, draft)
            } else {
                created = try await create(draft)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

private extension String {
    /// Un champ rempli d'espaces est un champ vide. Utilisé partout où le
    /// formulaire décide si quelque chose a été saisi.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}


/// Le jeu d'essai de la création.
///
/// Il rend un voyage qui ressemble au brouillon, sans serveur — c'est ce qui
/// permet de traverser les six étapes dans un aperçu. Le code d'accès est celui
/// de la maquette. Même rôle que ``TripDetail/fixture(id:)`` et
/// ``HomeFeed/fixture``, et pour la même raison : un écran doit pouvoir se
/// regarder sans back-end.
extension CreatedTrip {
    /// - Parameter id: l'identifiant à garder, quand le brouillon corrige un
    ///   voyage déjà créé. `nil` en tire un nouveau.
    public static func fixture(_ draft: TripDraft, id: String? = nil) -> CreatedTrip {
        CreatedTrip(
            trip: Trip(
                id: id ?? UUID().uuidString,
                title: draft.title.isEmpty ? TripDraft.untitled : draft.title,
                stage: draft.startDate.map { $0 > .now ? .upcoming : .ongoing } ?? .ongoing,
                startDate: draft.startDate,
                endDate: draft.endDate
            ),
            accessCode: "JHKFDA"
        )
    }
}
