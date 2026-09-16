import Foundation
import MemoBookCore
import Observation

/// Ce que l'accueil d'un voyage sait faire : charger son contenu, et filtrer
/// ses étapes.
///
/// Même construction que ``HomeModel`` et ``ProfileModel`` : le modèle ne
/// connaît pas l'API, il reçoit **une source**. L'app y branche
/// `api.tripDetail(id:)` (voir ``AppDependencies/tripModel(id:)``), les aperçus
/// n'en fournissent aucune et montrent les quatre états sur le jeu d'essai.
@MainActor
@Observable
public final class TripHomeModel {
    public private(set) var detail: TripDetail?
    public private(set) var errorMessage: String?

    // Les deux filtres. `nil` veut dire « tous » : c'est l'état d'ouverture de
    // l'écran, et celui vers lequel « Tout afficher » ramène. Il y en a eu un
    // troisième, sur une étape — retiré, voir ``TripStepsSection`` (T30).
    public var country: String?
    public var transport: TripTransport?

    private let tripId: String
    private let source: (String) async throws -> TripDetail

    /// Ce qu'on avait sur le disque — voir ``ContentCache``. `nil` en aperçu.
    private let cached: CachedValue<TripDetail>?

    /// Ce que le dernier chargement a appris. C'est lui que la vue anime —
    /// voir ``SwiftUI/View/brandRefreshFlash(_:)``.
    public private(set) var freshness: ContentFreshness = .unknown

    public init(
        tripId: String,
        source: @escaping (String) async throws -> TripDetail = { .fixture(id: $0) },
        cached: CachedValue<TripDetail>? = nil
    ) {
        self.tripId = tripId
        self.source = source
        self.cached = cached
    }

    /// `true` tant qu'on n'a rien à montrer. L'écran ne dessine alors rien
    /// plutôt qu'un demi-voyage.
    public var isLoading: Bool { detail == nil && errorMessage == nil }

    public func load() async {
        // Ce qu'on avait, tout de suite, et seulement au premier chargement :
        // un « tirer pour rafraîchir » ne doit pas repasser par une copie.
        if detail == nil, let stored = await cached?() {
            detail = stored
            freshness = .restored
        }

        do {
            let loaded = try await source(tripId)
            freshness = contentFreshness(of: loaded, replacing: detail)
            detail = loaded
            errorMessage = nil
        } catch {
            // Un échec **ne vide pas** ce qui vient du disque : on garde la
            // page et on pose le bandeau. C'est la même règle que l'accueil
            // hors ligne.
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Filtres

    /// Les étapes qui restent une fois les filtres posés.
    ///
    /// Les deux se combinent : choisir un pays **et** un transport ne garde
    /// que ce qui satisfait les deux. C'est ce qu'on attend d'une barre de
    /// filtres, et ça évite d'avoir à expliquer une règle de priorité.
    public var visibleSteps: [TripStep] {
        guard let steps = detail?.steps else { return [] }

        return steps.filter { step in
            if let country, step.destination?.name != country { return false }
            if let transport, step.transport != transport { return false }
            return true
        }
    }

    public var hasActiveFilter: Bool {
        country != nil || transport != nil
    }

    public func clearFilters() {
        country = nil
        transport = nil
    }
}

/// Ce que l'accueil d'un voyage peut demander à l'app de faire.
///
/// L'écran ne navigue pas lui-même : il annonce une intention, et `RootView`
/// décide où elle mène. Même contrat que ``HomeIntent`` — c'est sa deuxième
/// occurrence, et le motif se tient donc désormais sur deux écrans.
public enum TripIntent: Sendable, Hashable {
    /// Raconter la suite du voyage. C'est le CTA « Continuer à enregistrer »,
    /// et il ouvre la conversation avec MEMO.
    case tellMore(tripId: String)

    /// Ouvrir une étape. Elle ouvre la **même** conversation, mais posée sur
    /// cette étape-là : c'est ce qui permet à MEMO de savoir de quelle journée
    /// on parle sans avoir à le demander.
    case openStep(tripId: String, stepId: String)

    /// « Besoin d'aide ? » depuis le paywall qu'ouvre un micro verrouillé :
    /// le support, la même destination que depuis l'accueil et le profil.
    case openHelp

    /// La roue crantée de l'en-tête : les réglages du voyage.
    ///
    /// Elle est posée au **même endroit** que sur la conversation, et elle mène
    /// au même écran : les réglages appartiennent au voyage, pas à l'écran
    /// depuis lequel on les ouvre.
    case openSettings(tripId: String)

    /// L'imprimante de l'en-tête : l'aperçu du carnet.
    ///
    /// Elle ouvre l'**aperçu** et non un tunnel de commande, pour la même
    /// raison que celle des cartes de l'accueil : on ne commande pas un carnet
    /// qu'on n'a pas vu. « Commander ce carnet » attend en bas de l'aperçu.
    case openBookPreview(tripId: String)
}
