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
        case .ratio: "Ratio image/texte"
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

    /// L'étape a un « Passer ». Toutes, sauf trois : la dernière — le voyage
    /// existe déjà, et il n'y a rien à éviter sur un écran qui ne fait que
    /// montrer son code d'accès (Hugo, 14/09/2026) —, **le nom**, que la base
    /// exige et qu'on ne remplace pas par « Mon voyage » en douce (Hugo,
    /// 29/09/2026), et **les dates**, comme le nom (01/10/2026) : le bouton du
    /// bas reste éteint tant que le départ n'est pas posé.
    var canBeSkipped: Bool { self != .companions && self != .name && self != .dates }

    /// L'étape après laquelle le voyage **existe**.
    ///
    /// La création ne se fait pas au « Commencer ! » de la fin : la dernière
    /// étape montre le code d'accès, et un code d'accès désigne un voyage. Le
    /// carnet est donc enregistré à la validation de l'avant-dernière — de
    /// celles qu'on traverse — **sur le téléphone d'abord** : le serveur
    /// l'apprend quand il peut (Hugo, 01/10/2026).
    static var lastBeforeSave: TripCreationStep {
        let index = active.firstIndex(of: .companions) ?? active.endIndex
        return active[max(0, index - 1)]
    }

    /// Les étapes **qu'on traverse**, dans l'ordre. Le contexte (les thèmes)
    /// et le ratio image / texte sont **retirés du parcours pour le moment**
    /// (Hugo, 17/09/2026) : leur code reste — écran, modèle, brouillon —, et
    /// le brouillon part avec leurs valeurs par défaut. Les remettre, c'est
    /// une ligne ici.
    static let active: [TripCreationStep] = [.name, .dates, .notifications, .companions]

    /// L'étape qui suit celle-ci dans le parcours, `nil` sur la dernière.
    var next: TripCreationStep? {
        guard let index = Self.active.firstIndex(of: self) else { return nil }
        return Self.active.indices.contains(index + 1) ? Self.active[index + 1] : nil
    }

    /// L'étape qui précède celle-ci dans le parcours, `nil` sur la première.
    var previous: TripCreationStep? {
        guard let index = Self.active.firstIndex(of: self), index > 0 else { return nil }
        return Self.active[index - 1]
    }

    /// Le rang de l'étape dans le parcours, pour la frise.
    var position: Int { Self.active.firstIndex(of: self) ?? 0 }
}

/// Ce que sait faire la création d'un voyage : garder le brouillon des six
/// étapes, aller d'une étape à l'autre, et l'enregistrer.
///
/// **Rien n'y attend le réseau, sauf le code d'accès** (Hugo, 01/10/2026). On
/// crée un voyage dans l'avion de bout en bout : la validation garde le
/// brouillon sur le téléphone et passe à l'étape suivante ; « Commencer ! »
/// ouvre le voyage ; le serveur le reçoit au retour du réseau, et c'est lui qui
/// tire le code — la seule chose de l'écran qu'il faut lui demander.
///
/// Même construction que ``HomeModel`` et ``TripHomeModel`` : le modèle ne
/// connaît ni l'API ni la file, il reçoit **deux fonctions** — une qui
/// enregistre, une qui attend le code. Les aperçus n'en fournissent aucune et
/// traversent le formulaire sans serveur.
@MainActor
@Observable
public final class TripCreationModel {
    public private(set) var step: TripCreationStep = TripCreationStep.active[0]

    /// Le brouillon, rempli étape par étape. Il ne s'enregistre **qu'une
    /// fois**, à la fin de l'avant-dernière : six requêtes pour un formulaire
    /// qu'on peut remonter donneraient six façons de le laisser à moitié écrit.
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

    /// Le voyage, une fois enregistré sur le téléphone. C'est ce que
    /// « Commencer ! » ouvre, que le serveur l'ait reçu ou non.
    public private(set) var trip: Trip?

    /// Le code d'accès, quand le serveur a créé le voyage. `nil` jusque-là :
    /// la ligne du code porte une barre d'attente et « Partager » reste gris —
    /// c'est la seule chose de l'écran qui attend le réseau.
    public private(set) var accessCode: String?

    /// Le code attend **le retour du réseau**, pas seulement le serveur : le
    /// voyage est gardé, rien n'est revenu, et le téléphone est hors ligne.
    /// L'étape le dit sous la barre d'attente — « Ton code arrivera dès ta
    /// reconnexion » (T240, Hugo, 06/10/2026). En ligne, le code arrive en une
    /// fraction de seconde : la phrase n'y aurait que le temps de clignoter.
    public var awaitsReconnection: Bool {
        trip != nil && accessCode == nil && !wasRejected && isOffline()
    }

    /// L'enregistrement local est en cours — l'affaire d'un instant.
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?

    /// Le serveur a refusé le voyage : il n'y a plus rien à ouvrir.
    public private(set) var wasRejected = false

    private let save: @Sendable (TripDraft) async throws -> Trip
    private let sync: @Sendable (String) async -> TripSync?
    private let readThemes: @Sendable () async throws -> [TripTheme]
    private let isOffline: @MainActor () -> Bool
    private let notificationsStepPassed: @MainActor () -> Void

    /// - Parameters:
    ///   - save: garde le brouillon — l'app y branche la file de départ
    ///     (``RecordingOutbox/saveTrip(_:)``), qui l'envoie quand elle peut.
    ///     Le brouillon porte déjà son identifiant ; la même fonction sert la
    ///     création et la correction qui suit un retour en arrière.
    ///   - sync: attend ce que le serveur a fait du voyage — son code d'accès,
    ///     ou son refus (``RecordingOutbox/tripSync(for:)``).
    ///   - themes: d'où viennent les thèmes de la première étape. Par défaut la
    ///     liste du jeu d'essai, pour les aperçus ; l'app y branche
    ///     `GET /v1/trip-themes`.
    ///   - isOffline: le téléphone est-il sans réseau ? L'app y branche
    ///     ``RecordingOutbox/isOnline`` — lue pendant le dessin, elle redessine
    ///     l'étape au retour du réseau. Par défaut, toujours en ligne.
    ///   - notificationsStepPassed: l'étape « Notifications » vient d'être
    ///     traversée — choisie ou passée. L'app le retient sur l'appareil : la
    ///     conversation proposera d'activer les notifications à qui l'a passée
    ///     sans les autoriser (``NotificationsNudge``, T246).
    public init(
        save: @escaping @Sendable (TripDraft) async throws -> Trip = { draft in
            .local(draft, id: draft.id ?? UUID().uuidString.lowercased())
        },
        sync: @escaping @Sendable (String) async -> TripSync? = { id in
            .created(CreatedTrip(trip: Trip(id: id, title: TripDraft.untitled, stage: .ongoing), accessCode: "JHKFDA"))
        },
        themes: @escaping @Sendable () async throws -> [TripTheme] = { TripTheme.fixtures },
        isOffline: @escaping @MainActor () -> Bool = { false },
        notificationsStepPassed: @escaping @MainActor () -> Void = {}
    ) {
        self.save = save
        self.sync = sync
        self.readThemes = themes
        self.isOffline = isOffline
        self.notificationsStepPassed = notificationsStepPassed
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
    /// Deux étapes l'éteignent, celles qui n'ont pas de « Passer » : le nom,
    /// que la base exige, et les dates, **tant que le départ n'est pas posé**
    /// (01/10/2026) — le retour, lui, reste facultatif. Partout ailleurs
    /// « Valider » vaut « Passer », et un bouton grisé n'apprendrait rien.
    public var canValidate: Bool {
        switch step {
        case .name: !draft.title.trimmed.isEmpty
        case .dates: draft.startDate != nil
        case .theme: !isFreeThemeChosen || !freeTheme.trimmed.isEmpty
        default: true
        }
    }

    /// La frise : une barre par étape traversée, la verte étant celle-ci.
    public var progress: Int { step.position }

    /// Combien d'étapes le parcours compte — pour la frise et VoiceOver.
    public var stepCount: Int { TripCreationStep.active.count }

    /// Le glissé vers l'avant vaut « Valider » : il n'avance que si l'étape
    /// le permet, comme le bouton.
    public var canAdvance: Bool { canValidate && step != .companions }

    /// Le glissé vers l'arrière n'a d'effet que s'il y a une étape avant.
    public var canGoBack: Bool { step.previous != nil }

    // MARK: - Aller et venir

    /// Valide l'étape courante et passe à la suivante.
    ///
    /// **Le modèle refuse lui-même une étape incomplète** (T238, Hugo,
    /// 06/10/2026 : « c'est impossible de créer un voyage sans dates »). Le
    /// bouton gris et le glissé le vérifiaient déjà, chacun de son côté ; le
    /// dire ici ferme aussi les chemins à venir — la touche « Terminé » d'un
    /// clavier, un raccourci — sans qu'aucun ait à s'en souvenir. Un voyage a
    /// toujours un départ : c'est lui qui le range dans « à venir », « en
    /// cours » ou « précédents ».
    public func validate() async {
        guard canValidate else { return }
        if step == .theme {
            draft.theme = isFreeThemeChosen ? freeTheme.trimmed : selectedTheme?.label
        }
        await advance()
    }

    /// Passe l'étape sans rien en retenir — le « Passer » du coin haut droit.
    ///
    /// Passer, c'est `nil`, jamais une valeur inventée. Une étape sans
    /// « Passer » (``TripCreationStep/canBeSkipped``) ne se passe pas non plus
    /// d'ici : le nom et les dates s'obtiennent par « Valider », une fois
    /// remplis.
    public func skip() async {
        guard step.canBeSkipped else { return }
        switch step {
        case .theme:
            selectedTheme = nil
            freeTheme = ""
            draft.theme = nil
        case .notifications:
            draft.narrationPace = nil
        case .ratio:
            draft.photoTextRatio = 50
        case .name, .dates, .companions:
            break
        }
        await advance()
    }

    /// Revient à l'étape précédente. `false` quand il n'y en a pas : c'est
    /// alors à l'écran de se refermer, pas au modèle.
    @discardableResult
    public func goBack() -> Bool {
        guard let previous = step.previous else { return false }
        errorMessage = nil
        step = previous
        return true
    }

    // MARK: - L'enregistrement

    /// Enregistre le brouillon puis avance, ou avance seulement.
    ///
    /// Le voyage s'enregistre **une fois** — à la fin de l'avant-dernière
    /// étape. Y revenir et revalider ne crée pas un second voyage : le
    /// brouillon garde son identifiant, on corrige celui qui existe, et son
    /// code d'accès ne bouge pas, parce qu'il a peut-être déjà été envoyé à
    /// quelqu'un.
    private func advance() async {
        errorMessage = nil

        if step == .name, draft.title.trimmed.isEmpty { draft.title = TripDraft.untitled }
        if step == .name { draft.title = draft.title.trimmed }

        if step == .notifications { notificationsStepPassed() }

        if step == .lastBeforeSave {
            guard await persist() else { return }
        }

        guard let next = step.next else { return }
        step = next
    }

    private func persist() async -> Bool {
        isSaving = true
        defer { isSaving = false }

        // L'identifiant est tiré **ici**, une fois : c'est celui que le serveur
        // reprendra, et celui sous lequel ce qu'on racontera attendra le réseau.
        if draft.id == nil { draft.id = UUID().uuidString.lowercased() }

        do {
            trip = try await save(draft)
            wasRejected = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Attend ce que le serveur fait du voyage. À lancer **par l'écran**, sur
    /// l'identifiant du voyage (`.task(id:)`) : quitter l'écran annule
    /// l'attente, pas l'envoi — le voyage reste dans la file.
    ///
    /// Le code arrive tout de suite en ligne, au retour du réseau sinon. Un
    /// refus se dit sur l'étape, et « Commencer ! » n'ouvre plus rien.
    public func awaitAccessCode() async {
        guard let id = trip?.id, accessCode == nil else { return }

        switch await sync(id) {
        case .created(let created):
            accessCode = created.accessCode
        case .rejected(let message):
            errorMessage = message
            wasRejected = true
        case nil:
            break
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
