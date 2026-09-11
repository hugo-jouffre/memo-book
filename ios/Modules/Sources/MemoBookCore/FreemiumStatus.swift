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
    /// Les deux nombres, et non le seul solde : la pastille n'écrit que le
    /// solde (voir ``homePillLabel``), mais le total est ce qui permettra d'en
    /// faire une proportion — « 2 sur 3 » — sans repasser par le serveur.
    case freeSteps(remaining: Int, offered: Int)
    /// Les étapes offertes sont épuisées — ou l'abonnement vient d'être
    /// résilié. C'est le seul état qui appelle une offre.
    case limitReached

    /// Ce que la pastille du profil annonce.
    ///
    /// **Le même message que l'accueil, en plus explicite** : là-bas la pastille
    /// est posée sur l'avatar et n'a pas la ligne pour elle, ici elle a la
    /// place de dire « gratuites ». Les deux comptent la même chose, et c'est
    /// ce qui compte : voir deux formulations pour un même solde fait douter
    /// qu'il s'agisse du même.
    public var profilePillLabel: String {
        switch self {
        // La maquette de la feuille écrit « Abonnée ». Ici l'app ne sait pas à
        // qui elle s'adresse : elle s'en tient à la forme non marquée plutôt
        // que de deviner. Signalé (T76).
        case .subscriber: "Abonné"
        case .freeSteps(let remaining, _):
            remaining == 1
                ? "1 étape gratuite restante"
                : "\(remaining) étapes gratuites restantes"
        case .limitReached: "Abonne-toi"
        }
    }

    /// Ce que la pastille de l'accueil annonce, posée sur l'avatar.
    ///
    /// **Rien pour un abonné** : sur l'accueil la pastille est un décompte, et
    /// quelqu'un qui n'a plus rien à décompter n'a pas besoin qu'on le lui
    /// rappelle à chaque ouverture. Son statut se lit dans le profil, là où il a
    /// une raison d'être.
    ///
    /// **Un seul message, un décompte** : « 3 étapes restantes », qui descend à
    /// chaque étape racontée, puis « Abonne-toi » quand il n'en reste plus. La
    /// pastille annonçait un cadeau (« 3 étapes offertes ») tant que rien
    /// n'était consommé ; deux formulations pour un même chiffre faisaient
    /// hésiter sur ce qu'il fallait lire. Arbitrage de Hugo, 07/09/2026.
    ///
    /// Le nombre offert reste dans le cas, même si la pastille ne l'écrit plus :
    /// c'est lui qui dira « 2 sur 3 » le jour où une jauge le montrera.
    public var homePillLabel: String? {
        switch self {
        case .subscriber: nil
        // Plus court qu'au profil : la pastille est posée sur l'avatar, entre
        // la salutation et le bord de l'écran, et n'a pas la ligne pour elle.
        case .freeSteps(let remaining, _):
            remaining == 1 ? "1 étape restante" : "\(remaining) étapes restantes"
        case .limitReached: profilePillLabel
        }
    }

    /// Le lime et le cadenas, sur le CTA de l'accueil comme sur le gros bouton
    /// du profil. **Uniquement quand le quota est épuisé** : la couleur dit
    /// « c'est fini, il faut s'abonner », pas « il te reste des étapes ».
    public var isBlocked: Bool { self == .limitReached }

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
    /// **Le même calcul que celui de l'accueil**, et c'est tout l'intérêt : les
    /// deux écrans montrent le même parcours vu de deux endroits, et ils
    /// doivent donc en être au même point. Le profil disait « Abonne-toi » à
    /// quelqu'un à qui l'accueil annonçait « 2 étapes restantes » — il ne
    /// regardait que l'abonnement, jamais le quota, alors que
    /// `GET /v1/profile` le rend depuis toujours (`offeredSteps`,
    /// `remainingSteps`). C'était T77, et c'est réglé.
    ///
    /// L'abonnement garde le dernier mot **dans un seul sens** : il suffit
    /// d'être abonné pour n'avoir plus de quota à lire. À l'inverse, un ancien
    /// abonné qui a résilié n'a ni abonnement ni étapes offertes, et retombe
    /// donc sur ``FreemiumStatus/limitReached`` — l'offre, pas un crédit
    /// inventé.
    public func freemiumStatus(override: FreemiumStatus?) -> FreemiumStatus {
        if let override { return override }
        if subscription.isActive { return .subscriber }

        guard let offered = offeredSteps else { return .limitReached }
        let remaining = remainingSteps ?? 0
        return remaining > 0 ? .freeSteps(remaining: remaining, offered: offered) : .limitReached
    }
}
