import Foundation
import MemoBookCore

/// Ce que l'app retient d'une conversation qu'on a supprimée.
///
/// **Il n'y a pas encore de conversation côté serveur** : ni
/// `GET /v1/trips/:id/chat` pour la lire, ni `DELETE` pour l'effacer — le fil
/// vient du jeu d'essai, et ce qu'on y dit ne survit pas à la fermeture de
/// l'écran (voir ``AppDependencies/chatModel(tripId:stepId:)``). « Supprimer
/// la conversation » a pourtant un sens dès aujourd'hui : le fil s'ouvre
/// ensuite **sur le mot d'accueil de MEMO** et rien d'autre, et il y reste. Ce
/// petit objet est ce qui le retient, en attendant que la route existe — le
/// jour où elle existera, ``clear(tripId:)`` l'appellera et le reste ne
/// bougera pas.
///
/// Un seul pour la session, tenu par ``AppDependencies`` : les réglages du
/// voyage y écrivent, la conversation y lit, et la conversation **recharge**
/// quand ``version`` bouge — l'écran du chat est en dessous de celui des
/// réglages dans la pile, il ne se refabrique pas au retour.
///
/// Les identifiants de voyages sont des UUID : ceux d'un autre compte sur le
/// même appareil ne peuvent pas les croiser, et une conversation supprimée ne
/// revient pas parce qu'on s'est déconnecté puis reconnecté.
@MainActor
@Observable
public final class ConversationArchive {
    /// Les voyages dont la conversation a été supprimée.
    public private(set) var clearedTripIds: Set<String>

    /// Monte à chaque suppression. C'est ce que la conversation observe pour
    /// se recharger — un ensemble qui change ne dit pas *lequel*.
    public private(set) var version = 0

    private let defaults: UserDefaults?
    private static let key = "clearedConversations"

    /// - Parameter defaults: où retenir la liste d'un lancement à l'autre.
    ///   `nil` ne retient rien au-delà de la session — c'est le cas des
    ///   aperçus et du bac à sable, qui ne doivent pas écrire dans les
    ///   réglages du simulateur.
    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        clearedTripIds = Set(defaults?.stringArray(forKey: Self.key) ?? [])
    }

    public func isCleared(tripId: String) -> Bool {
        clearedTripIds.contains(tripId)
    }

    /// Supprime la conversation d'un voyage. Idempotent : supprimer deux fois
    /// ne change rien, et ne fait pas recharger deux fois.
    public func clear(tripId: String) {
        guard clearedTripIds.insert(tripId).inserted else { return }
        persist()
        version += 1
    }

    /// Oublie la suppression : le fil revient. **Bac à sable seulement** — le
    /// jeu d'essai est le seul fil qu'une suppression puisse faire revenir, et
    /// c'est ce qui permet de rejouer la scène sans réinstaller l'app.
    public func restore(tripId: String) {
        guard clearedTripIds.remove(tripId) != nil else { return }
        persist()
        version += 1
    }

    private func persist() {
        defaults?.set(Array(clearedTripIds).sorted(), forKey: Self.key)
    }
}
