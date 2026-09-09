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

    /// L'étape après laquelle le voyage **existe**.
    ///
    /// La création ne se fait pas au « Commencer ! » de la fin : la dernière
    /// étape ne montre que le code d'accès, et un code d'accès désigne un
    /// voyage. Le carnet part donc à la validation de l'avant-dernière.
    static var lastBeforeSave: TripCreationStep { .ratio }
}

/// Les thèmes proposés par la première étape.
///
/// ⚠️ **Les libellés ne viennent pas de la maquette**, qui ne montre que les
/// émojis et le seul mot « Autre », affiché sous celui qui est choisi. Ils sont
/// écrits ici parce que `memos.theme` est du texte lu par l'agent de rédaction
/// (`agents/agent-transcription.md`) : un émoji seul ne lui apprendrait rien.
/// À confirmer avec Clara, comme la copie vouvoyée de `NewNotebookSheet`.
public struct TripTheme: Sendable, Hashable, Identifiable {
    public let emoji: String
    public let label: String

    public var id: String { emoji }

    /// Le thème libre : il ne s'enregistre pas tel quel, il ouvre un champ.
    /// C'est celui que la maquette montre sélectionné.
    public static let other = TripTheme(emoji: "💬", label: "Autre")

    /// Le thème du milieu de la rangée. Ce n'est pas un choix, c'est un
    /// **cadrage** : c'est là que le carrousel s'ouvre, pour qu'on voie des
    /// thèmes de part et d'autre.
    public static var middle: TripTheme { all[all.count / 2] }

    /// Dans l'ordre de la maquette, « Autre » au milieu.
    public static let all: [TripTheme] = [
        TripTheme(emoji: "🍷", label: "Gastronomie"),
        TripTheme(emoji: "☀️", label: "Vacances au soleil"),
        TripTheme(emoji: "🎉", label: "Fête"),
        .other,
        TripTheme(emoji: "💼", label: "Voyage d’affaires"),
        TripTheme(emoji: "🌍", label: "Tour du monde"),
        TripTheme(emoji: "🏔️", label: "Montagne"),
    ]
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

    /// Le thème choisi dans la rangée d'émojis. `nil` tant qu'on n'a rien
    /// touché, ce qui n'est pas la même chose qu'« Autre » : passer l'étape
    /// laisse `theme` vide, choisir « Autre » ouvre un champ.
    public var selectedTheme: TripTheme?

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

    public init(
        create: @escaping @Sendable (TripDraft) async throws -> CreatedTrip = { .fixture($0) },
        update: @escaping @Sendable (String, TripDraft) async throws -> CreatedTrip = { id, draft in
            .fixture(draft, id: id)
        }
    ) {
        self.create = create
        self.update = update
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
        case .theme: selectedTheme != .other || !freeTheme.trimmed.isEmpty
        default: true
        }
    }

    /// La frise : une barre par étape, la verte étant celle-ci.
    public var progress: Int { step.rawValue }

    // MARK: - Aller et venir

    /// Valide l'étape courante et passe à la suivante.
    public func validate() async {
        if step == .theme {
            draft.theme = selectedTheme == .other ? freeTheme.trimmed : selectedTheme?.label
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
