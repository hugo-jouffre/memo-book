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
