import Foundation

/// Où en est le compte vis-à-vis de l'abonnement.
///
/// **Un seul vocabulaire pour les deux écrans.** L'accueil et le profil montrent
/// le même parcours vu de deux endroits — une pastille sur l'avatar d'un côté,
/// une pastille et un gros bouton de l'autre — et chacun le déduisait de son
/// propre modèle. Deux calculs, donc deux occasions de diverger.
///
/// Le lime ne dit qu'une chose : **il reste quelque chose à vendre**. Une fois
/// abonné il disparaît de l'app, sauf la pastille qui annonce le statut.
public enum FreemiumStatus: Equatable {
    /// Le compte paie. Aucune limite à annoncer, aucune offre à faire.
    case subscriber
    /// Il reste des étapes offertes. Le parcours est celui de tout le monde.
    ///
    /// Les deux nombres, et non le seul solde : c'est leur **écart** qui change
    /// le message. Rien de consommé, on annonce un cadeau ; une fois entamé, un
    /// solde. C'est le même chiffre, mais pas la même nouvelle.
    case freeSteps(remaining: Int, offered: Int)
    /// Les étapes offertes sont épuisées — ou l'abonnement vient d'être
    /// résilié. C'est le seul état qui appelle une offre.
    case limitReached

    /// Ce que la pastille du profil annonce.
    public var profilePillLabel: String {
        switch self {
        // La maquette de la feuille écrit « Abonnée ». Ici l'app ne sait pas à
        // qui elle s'adresse : elle s'en tient à la forme non marquée plutôt
        // que de deviner. Signalé (T49).
        case .subscriber: "Abonné"
        case .freeSteps(let remaining, _): "\(remaining) étapes gratuites restantes"
        case .limitReached: "Abonne-toi"
        }
    }

    /// Ce que la pastille de l'accueil annonce, posée sur l'avatar.
    ///
    /// **Rien pour un abonné** : sur l'accueil la pastille est un décompte, et
    /// quelqu'un qui n'a plus rien à décompter n'a pas besoin qu'on le lui
    /// rappelle à chaque ouverture. Son statut se lit dans le profil, là où il a
    /// une raison d'être.
    public var homePillLabel: String? {
        switch self {
        case .subscriber: nil
        // Plus court qu'au profil : la pastille est posée sur l'avatar, entre
        // la salutation et le bord de l'écran, et n'a pas la ligne pour elle.
        case .freeSteps(let remaining, let offered):
            remaining == offered
                ? "\(offered) étapes offertes"
                : "\(remaining) étapes restantes"
        case .limitReached: profilePillLabel
        }
    }

    /// Il y a encore quelque chose à vendre : le profil pose alors son gros
    /// bouton lime, et garde pour lui la ligne « Mon abonnement ».
    public var wantsSubscription: Bool { self != .subscriber }
}

extension Traveller {
    /// Le palier du compte, tel que l'accueil peut le lire.
    ///
    /// L'accueil ne connaît pas l'abonnement : c'est **l'absence de quota** qui
    /// le lui dit, parce que le serveur met `offeredSteps` à `nil` le jour d'une
    /// souscription. Tant que ni la souscription ni la résiliation ne sont des
    /// routes, la session a le dernier mot sur cette déduction.
    public func freemiumStatus(override: FreemiumStatus?) -> FreemiumStatus {
        // La session a vu quelque chose que le serveur ignore encore — une
        // résiliation, une souscription, un personnage du bac à sable. Elle
        // prime, et **elle prime en entier** : résilier ne rend pas le vieux
        // quota, sans quoi l'écran repartirait à décompter des étapes que
        // personne n'a offertes.
        if let override { return override }

        guard let offered = offeredSteps else { return .subscriber }
        let remaining = remainingSteps ?? 0
        return remaining > 0 ? .freeSteps(remaining: remaining, offered: offered) : .limitReached
    }
}

extension TravellerProfile {
    /// Le palier du compte, tel que le profil peut le lire.
    ///
    /// Le profil, lui, a l'abonnement sous la main : il s'y fie plutôt qu'au
    /// quota. Un ancien abonné qui a résilié n'a ni abonnement ni étapes
    /// offertes — il faut lui reproposer l'offre, pas lui inventer un crédit.
    ///
    /// ⚠️ Il ne sait pas distinguer ``FreemiumStatus/freeSteps(remaining:)`` de
    /// ``FreemiumStatus/limitReached`` : `GET /v1/profile` ne rend pas le quota
    /// d'étapes, que seul l'accueil reçoit. Un compte neuf voit donc la même
    /// invitation qu'un compte épuisé — signalé (T50).
    public func freemiumStatus(override: FreemiumStatus?) -> FreemiumStatus {
        override ?? (subscription.isActive ? .subscriber : .limitReached)
    }
}
