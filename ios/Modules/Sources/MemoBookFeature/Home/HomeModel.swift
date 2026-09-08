import Foundation
import MemoBookCore
import Observation

/// Ce que l'accueil sait faire : charger son contenu, et dire dans quel état
/// il est.
///
/// Le modèle ne connaît pas l'API. Il reçoit **une source**, une fonction qui
/// rend un ``HomeFeed`` : l'app y branche `api.homeFeed()` (voir
/// ``AppDependencies/homeModel()``), les aperçus n'en fournissent aucune et
/// tombent sur le jeu d'essai. C'est ce qui permet de montrer les quatre états
/// de l'écran sans serveur ni protocole simulé.
@MainActor
@Observable
public final class HomeModel {
    public private(set) var feed: HomeFeed?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    /// Les deux listes déjà triées. Elles sont calculées **une fois** à la
    /// réception du contenu, pas à chaque passage dans `body` : trier dans une
    /// vue, c'est trier à chaque image d'animation.
    public private(set) var ongoingTrips: [Trip] = []
    public private(set) var upcomingTrips: [Trip] = []
    public private(set) var pastTrips: [Trip] = []

    private let source: () async throws -> HomeFeed

    /// - Parameter source: d'où vient le contenu. Par défaut, le jeu d'essai —
    ///   voir ``HomeFeed/fixture``.
    public init(source: @escaping () async throws -> HomeFeed = { .fixture }) {
        self.source = source
    }

    /// `true` tant qu'on n'a rien à montrer : le premier chargement, celui que
    /// l'écran de lancement couvre. Un rechargement, lui, garde le contenu
    /// affiché plutôt que de vider l'écran.
    public var isShowingFirstLoad: Bool { feed == nil && errorMessage == nil }

    /// Aucun voyage du tout : l'utilisateur vient d'arriver.
    public var isEmpty: Bool { feed?.trips.isEmpty == true }

    /// Range le contenu reçu. Les trois listes sont triées **une fois**, ici, et
    /// pas à chaque passage dans `body` : trier dans une vue, c'est trier à
    /// chaque image d'animation.
    private func apply(_ loaded: HomeFeed) {
        feed = loaded
        ongoingTrips = loaded.ongoingTrips
        upcomingTrips = loaded.upcomingTrips
        pastTrips = loaded.pastTrips
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loaded = try await source()

            #if DEBUG
                // Le personnage du bac à sable survit à un rechargement : sans
                // ça, tirer sur la liste pour la rafraîchir remettait le palier
                // du serveur et le profil, lui, gardait le sien. Deux écrans qui
                // ne racontaient plus la même histoire. Absent de l'app livrée.
                apply(SandboxPersona.current?.applied(to: loaded) ?? loaded)
            #else
                apply(loaded)
            #endif

            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Ce que l'accueil peut demander à l'app de faire. L'écran ne navigue pas
/// lui-même : il annonce une intention, et `RootView` décide où elle mène.
/// Tant que les voyages ne sont pas branchés, certaines n'ont pas encore de
/// destination — c'est écrit à l'endroit qui route, pas ici.
public enum HomeIntent: Sendable, Hashable {
    case openProfile
    case openTrip(id: String)
    case orderPrint(tripId: String)
    case openShowcase(url: URL?)
    case startRecording
    /// Créer un voyage — l'appel à l'action quand aucun n'est en cours.
    case createTrip
    /// Aller voir les carnets de la communauté, depuis l'invitation à préparer
    /// le prochain voyage.
    case browseCommunity
    case openHelp
}

#if DEBUG

    // MARK: - Bac à sable
    //
    // De quoi voir les états de l'accueil sans back-end : un voyage en cours, un
    // voyage à venir, des carnets passés, ou rien du tout. Ces méthodes
    // n'existent **pas** dans l'app livrée — `#if DEBUG` ne compile pas en
    // release — et le panneau qui les appelle non plus.
    //
    // Elles vivent dans ce fichier et non à côté du panneau parce que les trois
    // listes sont en `private(set)` : Swift n'ouvre cet accès qu'au fichier qui
    // les déclare. C'est exactement ce qu'on veut — le bac à sable peut ranger
    // le contenu, une vue ne le peut pas.

    extension HomeModel {
        /// Repart du jeu d'essai complet, personnage compris.
        public func debugReset() {
            SandboxPersona.current = nil
            errorMessage = nil
            apply(.fixture)
        }

        /// Un compte tout neuf : aucun voyage.
        public func debugRemoveAllTrips() {
            errorMessage = nil
            apply(HomeFeed(traveller: debugTraveller, trips: [], showcase: feed?.showcase))
        }

        /// Ajoute un voyage à l'étape voulue. Rejouable : chaque appel en pose un
        /// nouveau, tiré dans une petite banque de destinations.
        public func debugAddTrip(stage: TripStage) {
            errorMessage = nil
            let existing = feed?.trips ?? []

            apply(
                HomeFeed(
                    traveller: debugTraveller,
                    trips: existing + [.debugRandom(stage: stage, index: existing.count)],
                    showcase: feed?.showcase
                )
            )
        }

        /// Devenir un abonné : plus de quota d'étapes, donc plus de pastille sur
        /// l'avatar ni de lime sur le CTA — et, dans le profil, la carte de
        /// chiffres ouverte et la ligne « Mon abonnement ».
        public func debugBecomeSubscriber() {
            debugPlay(.subscriber)
        }

        /// Première connexion : le quota d'étapes au complet. La pastille
        /// annonce ce qui reste, le CTA passe au lime et au cadenas, et le
        /// profil repropose l'abonnement.
        ///
        /// Les trois étapes sont **le quota d'ouverture d'un compte**, pas un
        /// chiffre d'interface : c'est le serveur qui le pose, et il descend
        /// ensuite d'une unité par étape racontée.
        public func debugFirstConnection() {
            debugPlay(.freeTrial(remainingSteps: 3))
        }

        /// Le mur : plus une seule étape offerte. La pastille passe à
        /// « Abonne-toi », le CTA au lime et au cadenas, et le profil garde son
        /// bouton d'abonnement — c'est le seul état qui bloque quelque chose.
        public func debugReachFreeLimit() {
            debugPlay(.freeTrial(remainingSteps: 0))
        }

        /// Fait jouer un personnage à l'app entière — l'accueil tout de suite,
        /// le profil à la prochaine ouverture. Voir ``SandboxPersona``.
        private func debugPlay(_ persona: SandboxPersona) {
            SandboxPersona.current = persona
            errorMessage = nil

            apply(
                HomeFeed(
                    traveller: persona.applied(to: debugTraveller),
                    trips: feed?.trips ?? [],
                    showcase: feed?.showcase
                )
            )
        }

        /// Montre l'état d'erreur, sans toucher au contenu.
        public func debugShowError() {
            errorMessage = URLError(.notConnectedToInternet).localizedDescription
        }

        private var debugTraveller: Traveller {
            feed?.traveller ?? HomeFeed.fixture.traveller
        }
    }

#endif
