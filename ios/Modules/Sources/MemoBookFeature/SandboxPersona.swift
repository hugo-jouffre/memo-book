#if DEBUG

    import MemoBookCore

    /// Le personnage que le bac à sable de l'accueil fait jouer à l'app.
    ///
    /// **Il n'existe pas dans l'app livrée.** Le fichier entier est sous
    /// `#if DEBUG`, comme le panneau qui l'actionne.
    ///
    /// Il existe parce que l'abonnement se lit sur **plusieurs écrans** :
    /// l'accueil, le profil (pastille « Abonné(e) », bouton « Découvrir
    /// l'abonnement », ligne « Mon abonnement »), et le crédit du jour que
    /// servent la conversation et les réglages du voyage. Chacun a son modèle
    /// et sa source, et le profil n'est construit qu'au moment où on l'ouvre —
    /// une seconde après avoir appuyé sur le bouton de l'accueil. Il faut donc
    /// un endroit qui survive à tous, et c'est celui-ci.
    ///
    /// Ce n'est pas une seconde source de vérité : le personnage **retouche**
    /// ce que la source a rendu, jeu d'essai ou serveur, au lieu de le
    /// remplacer. Le reste — nom, adresse, cagnotte, commandes, les deux
    /// alertes de l'accueil — continue de venir d'où il venait. Et il prévient
    /// le double d'API (``SandboxCredit``), pour que le crédit du jour qu'il
    /// sert dise « illimité » à un abonné.
    @MainActor
    public enum SandboxPersona {
        /// Quelqu'un qui paie : il raconte sans limite, le profil porte la
        /// pastille « Abonné(e) » et la ligne « Mon abonnement ».
        case subscriber
        /// Quelqu'un qui n'a pas d'abonnement : il raconte dans le crédit du
        /// jour, et le profil lui propose « Découvrir l'abonnement ». Son
        /// passé d'abonné, lui, reste celui des données : le jeu d'essai en a
        /// un, et le paywall s'ouvre donc sur la version « retour ».
        case free
        /// Quelqu'un qui n'a **jamais** été abonné (03/10/2026) : sans
        /// abonnement, et sans passé d'abonné — le paywall s'ouvre sur la
        /// découverte en trois écrans, inatteignable sinon dans le bac à sable
        /// (le profil du jeu d'essai démarre abonné).
        case neverSubscribed

        /// Celui qu'on joue en ce moment. `nil` — le cas normal — laisse les
        /// données telles qu'elles arrivent.
        public static var current: SandboxPersona? {
            didSet { SandboxCredit.setUnlimited(current.map { $0.isUnlimited }) }
        }

        fileprivate var isUnlimited: Bool {
            switch self {
            case .subscriber: true
            case .free, .neverSubscribed: false
            }
        }

        /// Retouche le contenu de l'accueil : le voyageur, et le crédit des
        /// voyages en cours — illimité pour un abonné, compté sinon.
        public func applied(to feed: HomeFeed) -> HomeFeed {
            let trips = feed.trips.map { trip in
                guard var credit = trip.dailyCredit else { return trip }
                var trip = trip
                credit.isUnlimited = isUnlimited
                trip.dailyCredit = credit
                return trip
            }
            return HomeFeed(
                traveller: applied(to: feed.traveller),
                trips: trips,
                showcase: feed.showcase
            )
        }

        /// Le voyageur, abonné ou non — **tout le reste gardé**. La version
        /// d'avant reconstruisait le voyageur sans ses deux alertes
        /// (`subscriptionEndedOn`, `subscriptionOutlivesTrip`), qui ne se
        /// rejouaient donc plus avec un personnage actif.
        public func applied(to traveller: Traveller) -> Traveller {
            let hasSubscribedBefore =
                switch self {
                case .subscriber: true
                case .free: traveller.hasSubscribedBefore
                case .neverSubscribed: false
                }
            return traveller.replacing(isUnlimited: isUnlimited, hasSubscribedBefore: hasSubscribedBefore)
        }

        /// Le profil : un abonné actif, ou un compte sans abonnement ni mois
        /// payé devant lui — sans quoi le sursis le ferait encore passer pour
        /// abonné.
        public func applied(to profile: TravellerProfile) -> TravellerProfile {
            var profile = profile
            switch self {
            case .subscriber:
                profile.subscription.isActive = true
                profile.subscription.cancelledAt = nil
            case .free:
                profile.subscription.isActive = false
                profile.subscription.paidThrough = nil
            case .neverSubscribed:
                // Ni abonnement, ni mois payé, ni résiliation, ni passé : un
                // compte qui n'a rien souscrit.
                profile.subscription.isActive = false
                profile.subscription.paidThrough = nil
                profile.subscription.cancelledAt = nil
                profile.subscription.hasEndedBefore = false
                profile.subscription.managedByAppStore = false
            }
            return profile
        }
    }

#endif
