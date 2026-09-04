import Foundation
import MemoBookCore
import Observation

/// Ce que l'accueil sait faire : charger son contenu, et dire dans quel état
/// il est.
///
/// Le modèle ne connaît pas l'API. Il reçoit **une source**, une fonction qui
/// rend un ``HomeFeed`` — aujourd'hui le jeu d'essai, demain
/// `api.homeFeed()`. C'est la seule ligne à changer le jour où le back-end
/// existe, et c'est ce qui permet aux aperçus de montrer les quatre états sans
/// serveur ni protocole simulé.
@MainActor
@Observable
public final class HomeModel {
    public private(set) var feed: HomeFeed?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    /// Les deux listes déjà triées. Elles sont calculées **une fois** à la
    /// réception du contenu, pas à chaque passage dans `body` : trier dans une
    /// vue, c'est trier à chaque image d'animation.
    public private(set) var ongoingTrips: [Trip] = []
    public private(set) var pastTrips: [Trip] = []

    private let source: () async throws -> HomeFeed

    /// - Parameter source: d'où vient le contenu. Par défaut, le jeu d'essai —
    ///   voir ``HomeFeed/fixture``.
    public init(source: @escaping () async throws -> HomeFeed = { .fixture }) {
        self.source = source
    }

    /// `true` tant qu'on n'a rien à montrer : le premier chargement, celui que
    /// l'écran de lancement couvre. Un rechargement, lui, garde le contenu
    /// affiché plutôt que de vider l'écran.
    public var isShowingFirstLoad: Bool { feed == nil && errorMessage == nil }

    /// Aucun voyage du tout : l'utilisateur vient d'arriver.
    public var isEmpty: Bool { feed?.trips.isEmpty == true }

    public func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loaded = try await source()
            feed = loaded
            ongoingTrips = loaded.ongoingTrips
            pastTrips = loaded.pastTrips
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Ce que l'accueil peut demander à l'app de faire. L'écran ne navigue pas
/// lui-même : il annonce une intention, et `RootView` décide où elle mène.
/// Tant que les voyages ne sont pas branchés, certaines n'ont pas encore de
/// destination — c'est écrit à l'endroit qui route, pas ici.
public enum HomeIntent: Sendable, Hashable {
    case openProfile
    case openTrip(id: String)
    case orderPrint(tripId: String)
    case openShowcase(url: URL?)
    case startRecording
}
