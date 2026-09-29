import Foundation
import MemoBookCore
import MemoBookNetworking

/// Ce que le lancement fait d'une session gardée au trousseau.
///
/// **Seul un refus du serveur ferme une session, et il le dit par un 401.** Le
/// client efface alors le jeton qu'il avait présenté : tant que le jeton est au
/// trousseau, la session n'a pas été refusée, quoi qu'il soit arrivé à l'appel.
///
/// Tout le reste est une panne : un 500, un délai dépassé, un réseau coupé. Le
/// lancement renvoyait pourtant ces pannes-là, elles aussi, vers l'écran
/// d'entrée. Du 27 au 29/09/2026, `GET /v1/auth/me` a rendu 500 (une migration
/// jamais appliquée en production) : chaque lancement à froid sortait les
/// testeurs de leur compte, et comme l'entrée par Apple ou Google tombait sur la
/// même colonne, ils ne pouvaient plus y revenir. « L'app n'est plus connectée
/// au serveur après un certain temps » : le temps que iOS la décharge.
///
/// Sur une panne, on rentre donc avec **le compte d'hier** (``ContentCache``,
/// ``ContentCache/Slot/account``). Chaque écran fait ensuite ses propres appels
/// et montre sa propre erreur, ou son cache hors ligne, comme n'importe quel
/// autre jour.
public enum SessionRestore: Equatable, Sendable {
    /// Le serveur a relu le compte.
    case verified(Account)
    /// Le serveur n'a pas répondu, ou mal, mais n'a pas refusé la session : on
    /// rentre avec le compte gardé la dernière fois.
    case remembered(Account)
    /// Plus de session : le serveur l'a refusée, ou il n'y en avait pas.
    case closed
    /// La session tient peut-être, mais le serveur ne répond pas et aucun
    /// compte n'est gardé : rien pour entrer. Le jeton reste au trousseau, le
    /// prochain lancement réessaiera.
    case unreachable

    /// Décide, à partir des trois questions à poser.
    ///
    /// Une fonction et non une méthode du client : ce qu'elle décide ne dépend
    /// que de ces trois réponses, et c'est ce qui la rend vérifiable sans
    /// serveur.
    ///
    /// - Parameters:
    ///   - verify: relit le compte auprès du serveur.
    ///   - isStillStored: le jeton est-il encore au trousseau, **après**
    ///     l'appel ? Le client l'efface sur un 401, et sur un 401 seulement.
    ///   - remembered: le compte gardé la dernière fois, s'il y en a un.
    ///   - retryDelays: les attentes entre deux essais, quand aucun compte
    ///     n'est gardé et que la panne vaut qu'on réessaie. Avec un compte
    ///     gardé, on n'attend pas : l'accueil est plus utile qu'un tracé du M
    ///     qui dure.
    @MainActor
    static func resolve(
        verify: () async throws -> Account,
        isStillStored: () async -> Bool,
        remembered: () async -> Account?,
        retryDelays: [Duration] = [.seconds(1), .seconds(3)]
    ) async -> SessionRestore {
        var delays = retryDelays[...]

        while true {
            let failure: any Error
            do {
                return .verified(try await verify())
            } catch {
                failure = error
            }

            guard await isStillStored() else { return .closed }
            if let account = await remembered() { return .remembered(account) }

            guard (failure as? APIError)?.isRetryable == true, let delay = delays.popFirst() else {
                return .unreachable
            }
            try? await Task.sleep(for: delay)
        }
    }
}
