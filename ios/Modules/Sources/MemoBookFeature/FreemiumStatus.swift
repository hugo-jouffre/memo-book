import MemoBookCore

/// Où en est le compte vis-à-vis de l'abonnement.
///
/// **Un seul vocabulaire pour les deux écrans.** L'accueil et le profil
/// montrent le même parcours vu de deux endroits — une pastille et un bouton
/// d'un côté, une pastille et un gros bouton de l'autre — et chacun le
/// déduisait de son propre modèle. Deux calculs, donc deux occasions de
/// diverger : l'accueil a longtemps mis du lime sur son bouton dès qu'un quota
/// existait, alors que le profil, lui, attendait que le quota soit épuisé.
///
/// Le lime ne dit qu'une chose et ne la dit qu'ici : **c'est fini, il faut
/// s'abonner**. Tant qu'il reste des étapes offertes, le parcours est normal et
/// se peint en vert ; une fois abonné, il n'y a plus rien à vendre et le lime
/// disparaît de l'app, sauf la pastille qui dit « Abonné ».
enum FreemiumStatus: Equatable {
    /// Le compte paie. Aucune limite à annoncer, aucune offre à faire.
    case subscriber
    /// Il reste des étapes offertes. Le parcours est celui de tout le monde.
    case freeSteps(remaining: Int)
    /// Les étapes offertes sont épuisées. C'est le seul état qui bloque.
    case limitReached

    /// Ce que la pastille du profil annonce — toujours quelque chose : un
    /// statut pour un abonné, un solde ou une invitation pour les autres.
    var pillLabel: String {
        switch self {
        case .subscriber:
            // La maquette écrit « ABONNÉE ». L'app ne sait pas à qui elle
            // s'adresse : elle s'en tient à la forme non marquée plutôt que de
            // deviner. Signalé à Clara.
            "Abonné"
        case .freeSteps(let remaining):
            // « gratuites » n'est pas un mot de trop : sur le profil, la
            // pastille voisine du bouton d'abonnement, et « 3 étapes
            // restantes » se lisait comme un quota du produit plutôt que comme
            // ce qu'on perd en ne s'abonnant pas.
            "\(remaining) étapes gratuites restantes"
        case .limitReached:
            "Abonne-toi"
        }
    }

    /// Ce que la pastille de l'accueil annonce, posée sur l'avatar.
    ///
    /// Rien pour un abonné : sur l'accueil, la pastille est un **décompte**, et
    /// quelqu'un qui n'a plus rien à décompter n'a pas besoin qu'on le lui
    /// rappelle à chaque ouverture de l'app. Son statut se lit dans le profil,
    /// là où il a une raison d'être.
    var homePillLabel: String? {
        switch self {
        case .subscriber: nil
        // Plus court qu'au profil : la pastille est posée sur l'avatar, entre
        // la salutation et le bord de l'écran, et n'a pas la ligne entière pour
        // elle. Le mot qui manque est celui que le profil ajoute à côté du
        // bouton d'abonnement, là où il a une raison d'être.
        case .freeSteps(let remaining): "\(remaining) étapes restantes"
        case .limitReached: pillLabel
        }
    }

    /// Le lime et le cadenas, sur le CTA de l'accueil comme sur le gros bouton
    /// du profil. **Uniquement quand le quota est épuisé.**
    var isBlocked: Bool { self == .limitReached }

    /// Il y a encore quelque chose à vendre : le profil pose alors son bouton
    /// « Découvrir l'abonnement », et garde pour lui la ligne « Mon abonnement ».
    var wantsSubscription: Bool { self != .subscriber }
}

extension Traveller {
    /// Le palier du compte, tel que l'accueil peut le lire.
    ///
    /// L'accueil ne connaît pas l'abonnement : c'est **l'absence de quota** qui
    /// le lui dit, parce que le serveur met `offeredSteps` à `nil` le jour d'une
    /// souscription. Une seule donnée à tenir d'accord, et non deux — voir
    /// ``Traveller/offeredSteps``.
    var freemiumStatus: FreemiumStatus {
        guard offeredSteps != nil else { return .subscriber }
        let remaining = remainingSteps ?? 0
        return remaining > 0 ? .freeSteps(remaining: remaining) : .limitReached
    }
}

extension TravellerProfile {
    /// Le palier du compte, tel que le profil peut le lire.
    ///
    /// Le profil, lui, a l'abonnement sous la main : il s'y fie plutôt qu'au
    /// quota. Un ancien abonné qui a résilié n'a ni abonnement ni étapes
    /// offertes — il faut lui reproposer l'offre, pas lui inventer un crédit.
    var freemiumStatus: FreemiumStatus {
        guard !subscription.isActive else { return .subscriber }
        let remaining = remainingSteps ?? 0
        return remaining > 0 ? .freeSteps(remaining: remaining) : .limitReached
    }
}
