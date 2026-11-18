import Foundation
import MemoBookCore

/// **Revenir deux fois sur un voyage en 24 h ouvre l'app dessus** (T268, Hugo,
/// 05/11/2026).
///
/// Quand on raconte un voyage en cours, on y revient plusieurs fois par jour —
/// et on repasse à chaque fois par l'accueil, qui ne sert alors à rien. Au
/// bout de deux visites dans la journée, l'app l'admet et ouvre directement
/// sur le voyage.
///
/// **La règle vit dans ``TripVisits`` (`MemoBookCore`)**, sans dépendance et
/// donc testée ; ce fichier-ci ne fait que la garder sur le disque.
///
/// ## Trois règles, et la deuxième est la seule qui ne va pas de soi
///
/// 1. **Deux visites en 24 h**, pas une. Une seule visite ne dit rien : on
///    ouvre un voyage pour le regarder. Deux disent qu'on y travaille.
///
/// 2. ⚠️ **Une ouverture automatique ne compte pas comme une visite.** Sans
///    ça la règle s'auto-entretient : l'app ouvre le voyage, l'ouverture
///    compte, la condition reste vraie, et l'accueil devient inatteignable au
///    lancement — pour toujours. Seul un geste délibéré depuis l'accueil
///    compte, et c'est ce que `noter(_:)` enregistre, appelé là et nulle part
///    ailleurs.
///
/// 3. **Ça s'oublie tout seul.** Les visites de plus de 24 h sont jetées à
///    chaque lecture : qui cesse de revenir retrouve son accueil le
///    lendemain, sans rien avoir à désactiver.
///
/// Et il y a toujours une sortie : le voyage s'ouvre **au-dessus de
/// l'accueil** dans la pile de navigation (`RootView`), donc la flèche de
/// retour y ramène. L'app ne piège jamais personne sur un écran.
///
/// Les visites vivent dans `UserDefaults` : c'est une commodité locale, pas un
/// souvenir. Perdue, on repasse par l'accueil, et c'est tout — rien à voir
/// avec les deux files du disque, qui gardent ce que le serveur n'a jamais vu.
///
/// Pas `Sendable` : `UserDefaults` ne l'est pas, et cette trace se lit et
/// s'écrit depuis `RootView`, c'est-à-dire sur l'acteur principal. Rien ici
/// n'a à traverser un fil.
@MainActor
public struct RecentTripVisits {
    /// La clé sous laquelle les visites sont rangées.
    static let defaultsKey = "recentTripVisits"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Une visite **délibérée** : le voyageur a touché son voyage sur
    /// l'accueil, ou l'a ouvert depuis un code d'accès. Jamais appelée par
    /// l'ouverture automatique — voir la règle 2.
    public func noter(_ tripId: String, maintenant: Date = .now) {
        ecrire(TripVisits.enNotant(tripId, dans: lire(), maintenant: maintenant))
    }

    /// Le voyage sur lequel ouvrir, ou `nil` pour l'accueil.
    ///
    /// Le plus récemment visité parmi ceux qui ont assez de visites : revenir
    /// sur deux voyages dans la même journée est rare, mais c'est le dernier
    /// qu'on avait en tête.
    public func voyageAReprendre(maintenant: Date = .now) -> String? {
        TripVisits.voyageAReprendre(lire(), maintenant: maintenant)
    }

    /// Oublie un voyage — il a été supprimé, ou le compte a changé.
    public func oublier(_ tripId: String) {
        var toutes = lire()
        toutes.removeValue(forKey: tripId)
        ecrire(toutes)
    }

    /// Tout oublier : à la déconnexion, comme le reste du contenu du compte.
    public func toutOublier() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    // MARK: - Le disque

    private func lire() -> [String: [Date]] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let lues = try? JSONDecoder().decode([String: [Date]].self, from: data)
        else { return [:] }
        return lues
    }

    private func ecrire(_ toutes: [String: [Date]]) {
        guard let data = try? JSONEncoder().encode(toutes) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
