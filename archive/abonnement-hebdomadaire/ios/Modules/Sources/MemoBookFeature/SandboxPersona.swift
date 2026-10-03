#if DEBUG

    import MemoBookCore

    /// Le personnage que le bac à sable de l'accueil fait jouer à l'app.
    ///
    /// **Il n'existe pas dans l'app livrée.** Le fichier entier est sous
    /// `#if DEBUG`, comme le panneau qui l'actionne.
    ///
    /// Il existe parce que le parcours freemium se lit sur **deux écrans** :
    /// la pastille et le CTA de l'accueil d'un côté, la carte de chiffres et le
    /// bouton d'abonnement du profil de l'autre. Chacun a son modèle et sa
    /// source, et le profil n'est construit qu'au moment où on l'ouvre — une
    /// seconde après avoir appuyé sur le bouton de l'accueil. Il faut donc un
    /// endroit qui survive aux deux, et c'est celui-ci.
    ///
    /// Ce n'est pas une seconde source de vérité : le personnage **retouche**
    /// ce que la source a rendu, jeu d'essai ou serveur, au lieu de le
    /// remplacer. Le reste du profil — nom, adresse, cagnotte, commandes —
    /// continue de venir d'où il venait.
    @MainActor
    public enum SandboxPersona {
        /// Quelqu'un qui paie : plus de quota d'étapes, la carte de chiffres
        /// ouverte, la ligne « Mon abonnement » dans les services.
        case subscriber
        /// Quelqu'un qui vient d'arriver : un solde d'étapes offertes qui
        /// s'épuise, et l'abonnement encore à découvrir. À zéro, c'est le mur —
        /// voir ``FreemiumStatus/limitReached``.
        case freeTrial(remainingSteps: Int)

        /// Celui qu'on joue en ce moment. `nil` — le cas normal — laisse les
        /// données telles qu'elles arrivent.
        public static var current: SandboxPersona?

        /// Le solde d'étapes que le personnage impose, `nil` pour « aucun
        /// quota ». C'est la seule chose que l'accueil ait besoin de savoir.
        private var steps: (offered: Int, remaining: Int)? {
            switch self {
            case .subscriber: nil
            // Le nombre offert est celui qu'on annonce à l'ouverture d'un
            // compte ; le solde, lui, descend jusqu'à zéro. Les deux se
            // rejoignent au premier jour, et c'est normal — c'est même ce que
            // « Première connexion » rejoue.
            case .freeTrial(let remaining): (offered: 3, remaining: remaining)
            }
        }

        /// Retouche le contenu de l'accueil : seul le voyageur change.
        public func applied(to feed: HomeFeed) -> HomeFeed {
            HomeFeed(
                traveller: applied(to: feed.traveller),
                trips: feed.trips,
                showcase: feed.showcase
            )
        }

        public func applied(to traveller: Traveller) -> Traveller {
            Traveller(
                id: traveller.id,
                firstName: traveller.firstName,
                avatarUrl: traveller.avatarUrl,
                offeredSteps: steps?.offered,
                remainingSteps: steps?.remaining
            )
        }

        public func applied(to profile: TravellerProfile) -> TravellerProfile {
            var profile = profile
            profile.subscription.isActive = steps == nil
            profile.offeredSteps = steps?.offered
            profile.remainingSteps = steps?.remaining
            return profile
        }
    }

#endif
