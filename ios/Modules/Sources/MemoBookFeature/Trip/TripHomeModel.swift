import Foundation
import MemoBookCore
import Observation

/// Ce que l'accueil d'un voyage sait faire : charger son contenu, et filtrer
/// ses étapes.
///
/// Même construction que ``HomeModel`` et ``ProfileModel`` : le modèle ne
/// connaît pas l'API, il reçoit **une source**. Aujourd'hui le jeu d'essai,
/// demain `api.trip(id:)` — une seule ligne à changer, et les aperçus
/// continuent de montrer les quatre états sans serveur.
@MainActor
@Observable
public final class TripHomeModel {
    public private(set) var detail: TripDetail?
    public private(set) var errorMessage: String?

    // Les trois filtres. `nil` veut dire « tous » : c'est l'état d'ouverture de
    // l'écran, et celui vers lequel « Tout afficher » ramène.
    public var country: String?
    public var stepId: String?
    public var transport: TripTransport?

    private let tripId: String
    private let source: (String) async throws -> TripDetail

    public init(
        tripId: String,
        source: @escaping (String) async throws -> TripDetail = { .fixture(id: $0) }
    ) {
        self.tripId = tripId
        self.source = source
    }

    /// `true` tant qu'on n'a rien à montrer. L'écran ne dessine alors rien
    /// plutôt qu'un demi-voyage.
    public var isLoading: Bool { detail == nil && errorMessage == nil }

    public func load() async {
        do {
            detail = try await source(tripId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Filtres

    /// Les étapes qui restent une fois les filtres posés.
    ///
    /// Les trois se combinent : choisir un pays **et** un transport ne garde
    /// que ce qui satisfait les deux. C'est ce qu'on attend d'une barre de
    /// filtres, et ça évite d'avoir à expliquer une règle de priorité.
    public var visibleSteps: [TripStep] {
        guard let steps = detail?.steps else { return [] }

        return steps.filter { step in
            if let country, step.destination?.name != country { return false }
            if let stepId, step.id != stepId { return false }
            if let transport, step.transport != transport { return false }
            return true
        }
    }

    public var hasActiveFilter: Bool {
        country != nil || stepId != nil || transport != nil
    }

    public func clearFilters() {
        country = nil
        stepId = nil
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
}
