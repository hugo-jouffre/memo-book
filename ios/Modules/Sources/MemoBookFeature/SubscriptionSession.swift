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
/// C'est aussi **le seul levier du bac à sable** sur le palier : un personnage
/// joué et une résiliation vraie passent par le même objet, donc les deux
/// écrans ne peuvent pas se contredire.
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

#if DEBUG

    /// Le réseau, vu du bac à sable.
    ///
    /// ⚠️ **Ce n'est pas le hors-ligne complet de la branche `proprietaire-unique-et-secrets`** :
    /// celui-là coupait vraiment le réseau et faisait partir les vocaux sur le
    /// disque, via une file d'envoi (`outbox`) qui n'existe pas encore ici.
    /// Faute d'elle, ce drapeau fait ce qu'il peut faire honnêtement : les
    /// écrans échouent au chargement comme sous un tunnel, et on voit leur état
    /// d'erreur. Rien n'est mis en file — voir T51.
    @MainActor
    enum SandboxNetwork {
        static var isOffline = false

        /// L'erreur que les modèles rendent quand le bac à sable a coupé le
        /// réseau. La même que celle d'une vraie coupure.
        static var failure: String {
            URLError(.notConnectedToInternet).localizedDescription
        }
    }

#endif
