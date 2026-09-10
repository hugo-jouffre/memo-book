import MemoBookCore
import Observation
import SwiftUI

/// Ce que la session sait du palier du compte, en attendant qu'un serveur le
/// sache.
///
/// **Résilier depuis le profil doit changer l'accueil** : la pastille de
/// l'avatar cesse de décompter des étapes et propose de s'abonner. Or les deux
/// écrans ont chacun leur modèle, alimenté par un appel distinct, et rien n'est
/// encore persisté — l'accueil ne peut donc pas l'apprendre du serveur.
///
/// L'information circule à l'envers de l'environnement, du profil vers
/// l'accueil : elle passe par un objet partagé, exactement comme
/// ``BrandSheetPresentation`` porte le recul des feuilles. `nil` tant que rien
/// n'a été touché de la session — c'est alors la parole du serveur qui vaut.
///
/// Elle ne porte que les gestes **vrais** — souscrire, résilier. Le bac à sable,
/// lui, passe par ``SandboxPersona``, qui retouche les données au lieu de les
/// contredire : les deux se rejoignent dans
/// ``Traveller/freemiumStatus(override:)``, où la session a le dernier mot. Le
/// panneau de débogage efface donc l'override avant de faire jouer un
/// personnage.
///
/// ⚠️ **Provisoire.** Le jour où la souscription et la résiliation sont des
/// routes, `GET /v1/profile` et `GET /v1/home` s'accorderont d'eux-mêmes et cet
/// objet disparaît.
@MainActor
@Observable
final class SubscriptionSession {
    /// Le palier que la session impose, ou `nil` pour laisser parler les
    /// données reçues.
    private(set) var override: FreemiumStatus?

    init() {}

    /// Souscrire ou résilier depuis la feuille d'abonnement.
    ///
    /// Résilier donne ``FreemiumStatus/limitReached`` et non un solde : le
    /// serveur croit encore le compte abonné et lui a laissé son ancien quota ;
    /// le lui rendre ferait repartir un décompte au lieu de proposer l'offre.
    func record(isSubscribed: Bool) {
        override = isSubscribed ? .subscriber : .limitReached
    }

    #if DEBUG
        /// Le bac à sable fait jouer un palier à l'app entière — l'accueil tout
        /// de suite, le profil à sa prochaine ouverture. `nil` rend la main aux
        /// données.
        func play(_ status: FreemiumStatus?) {
            override = status
        }
    #endif
}

extension EnvironmentValues {
    /// Le palier tel que la session le connaît. `nil` dans un aperçu isolé, où
    /// personne ne résilie et où ce n'est pas un problème.
    @Entry var subscriptionSession: SubscriptionSession?
}
