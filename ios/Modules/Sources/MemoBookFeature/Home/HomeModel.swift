import Foundation
import MemoBookCore
import Observation

/// Ce que l'accueil sait faire : charger son contenu, et dire dans quel état
/// il est.
///
/// Le modèle ne connaît pas l'API. Il reçoit **une source**, une fonction qui
/// rend un ``HomeFeed`` — aujourd'hui le jeu d'essai, demain
/// `api.homeFeed()`. C'est la seule ligne à changer le jour où le back-end
/// existe, et c'est ce qui permet aux aperçus de montrer les quatre états sans
/// serveur ni protocole simulé.
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

        #if DEBUG
            // Le bac à sable a coupé le réseau : l'écran échoue comme sous un
            // tunnel, avant même de demander sa source.
            if SandboxNetwork.isOffline {
                errorMessage = SandboxNetwork.failure
                return
            }
        #endif

        do {
            apply(try await source())
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
    /// Raconter la suite d'un voyage en cours. L'identifiant est porté par
    /// l'intention parce que c'est **l'écran** qui sait quel voyage il montre :
    /// `RootView` n'a pas de `HomeModel` à interroger.
    case startRecording(tripId: String)
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
        /// Repart du jeu d'essai complet : contenu, palier et réseau.
        public func debugReset() {
            SandboxNetwork.isOffline = false
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

        /// Retire le quota d'étapes offertes, ou le remet.
        public func debugToggleFreeSteps() {
            let isStripped = debugTraveller.offeredSteps == nil
            debugSetQuota(isStripped ? (offered: 3, remaining: 2) : nil)
        }

        /// Devenir un abonné : plus de quota d'étapes, donc plus de pastille sur
        /// l'avatar — et, dans le profil, la ligne « Mon abonnement » à la place
        /// du gros bouton lime.
        public func debugBecomeSubscriber() {
            debugSetQuota(nil)
        }

        /// Première connexion : le quota d'ouverture au complet.
        ///
        /// Les trois étapes sont **le quota d'ouverture d'un compte**, pas un
        /// chiffre d'interface : c'est le serveur qui le pose, et il descend
        /// ensuite d'une unité par étape racontée. Rien n'étant consommé, la
        /// pastille annonce un cadeau et non un solde.
        public func debugFirstConnection() {
            debugSetQuota((offered: 3, remaining: 3))
        }

        /// Le mur : plus une seule étape offerte. La pastille passe à
        /// « Abonne-toi » — c'est le seul état qui bloque quelque chose.
        public func debugReachFreeLimit() {
            debugSetQuota((offered: 3, remaining: 0))
        }

        /// Le palier que ce quota décrit, pour que la session le fasse suivre au
        /// profil. `nil` veut dire « abonné ».
        public func debugStatus(for quota: (offered: Int, remaining: Int)?) -> FreemiumStatus {
            guard let quota else { return .subscriber }
            return quota.remaining > 0
                ? .freeSteps(remaining: quota.remaining, offered: quota.offered)
                : .limitReached
        }

        private func debugSetQuota(_ quota: (offered: Int, remaining: Int)?) {
            let current = debugTraveller
            errorMessage = nil

            apply(
                HomeFeed(
                    traveller: Traveller(
                        id: current.id,
                        firstName: current.firstName,
                        avatarUrl: current.avatarUrl,
                        offeredSteps: quota?.offered,
                        remainingSteps: quota?.remaining
                    ),
                    trips: feed?.trips ?? [],
                    showcase: feed?.showcase
                )
            )
        }

        /// `true` quand le bac à sable a coupé le réseau.
        public var isOffline: Bool { SandboxNetwork.isOffline }

        /// Coupe le réseau, ou le rétablit — et recharge, pour que l'écran
        /// tombe (ou se relève) tout de suite.
        public func debugToggleOffline() async {
            SandboxNetwork.isOffline.toggle()
            await load()
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
