import Foundation
import MemoBookCore
import MemoBookRecording
import Observation

/// Ce que l'accueil sait faire : charger son contenu, et dire dans quel état
/// il est.
///
/// Le modèle ne connaît pas l'API. Il reçoit **une source**, une fonction qui
/// rend un ``HomeFeed`` : l'app y branche `api.homeFeed()` (voir
/// ``AppDependencies/homeModel()``), les aperçus n'en fournissent aucune et
/// tombent sur le jeu d'essai. C'est ce qui permet de montrer les quatre états
/// de l'écran sans serveur ni protocole simulé.
///
/// Il reçoit aussi la ``RecordingOutbox``, et celle-là est un **objet** et non
/// une fonction : elle ne rend pas un contenu, elle tient un état — le réseau,
/// la file des vocaux — qui survit à l'écran et que le profil, demain, lira
/// aussi. C'est la même raison qui fait descendre `AppDependencies` par
/// l'environnement plutôt que par un paramètre de vue.
@MainActor
@Observable
public final class HomeModel {
    public private(set) var feed: HomeFeed?
    public private(set) var isLoading = false

    /// Ce qui a raté **au chargement**. Les refus d'envoi, eux, appartiennent à
    /// la file — voir ``errorMessage``.
    private var loadFailure: String?

    /// Les deux listes déjà triées. Elles sont calculées **une fois** à la
    /// réception du contenu, pas à chaque passage dans `body` : trier dans une
    /// vue, c'est trier à chaque image d'animation.
    public private(set) var ongoingTrips: [Trip] = []
    public private(set) var upcomingTrips: [Trip] = []
    public private(set) var pastTrips: [Trip] = []

    /// La file de départ des vocaux. C'est elle qui sait s'il y a du réseau, ce
    /// qui attend sur le disque et ce qui est en train de partir.
    public let outbox: RecordingOutbox

    private let source: () async throws -> HomeFeed

    /// - Parameters:
    ///   - source: d'où vient le contenu. Par défaut, le jeu d'essai — voir
    ///     ``HomeFeed/fixture``.
    ///   - outbox: où partent les vocaux. Par défaut, une file qui n'envoie
    ///     nulle part et se croit toujours en ligne : les aperçus SwiftUI n'ont
    ///     pas de serveur, et un enregistrement y est un geste sans conséquence.
    public init(
        source: @escaping () async throws -> HomeFeed = { .fixture },
        outbox: RecordingOutbox = RecordingOutbox()
    ) {
        self.source = source
        self.outbox = outbox
    }

    /// Le seul message d'erreur de l'écran, d'où qu'il vienne : le chargement
    /// ou un refus définitif du serveur sur un vocal. Un seul bandeau, parce
    /// qu'il n'y a qu'un endroit où on le lit.
    public var errorMessage: String? { loadFailure ?? outbox.rejection }

    /// `true` tant qu'on n'a rien à montrer : le premier chargement, celui que
    /// l'écran de lancement couvre. Un rechargement, lui, garde le contenu
    /// affiché plutôt que de vider l'écran.
    public var isShowingFirstLoad: Bool { feed == nil && errorMessage == nil }

    /// Aucun voyage du tout : l'utilisateur vient d'arriver.
    public var isEmpty: Bool { feed?.trips.isEmpty == true }

    /// Pas de réseau. L'accueil continue de fonctionner — il montre le dernier
    /// contenu reçu et le micro reste ouvert —, il le dit simplement.
    public var isOffline: Bool { !outbox.isOnline }

    /// Ce que la boîte d'information annonce, ou `nil` quand il n'y a rien à
    /// dire. **Un seul message à la fois**, dans cet ordre :
    ///
    /// 1. ce qui part **maintenant** — c'est ce qui va changer l'écran ;
    /// 2. ce qui **attend** le réseau — la promesse qu'il faut tenir ;
    /// 3. ce qui vient d'**arriver** — le temps de le lire ;
    /// 4. l'absence de réseau, quand il n'y a rien d'autre à raconter.
    ///
    /// L'ordre n'est pas une hiérarchie de gravité : c'est celui de l'utilité.
    /// Quelqu'un qui a trois vocaux en attente sait déjà qu'il est hors ligne —
    /// ce qu'il veut savoir, c'est qu'ils ne sont pas perdus.
    public var notice: HomeNotice? {
        if outbox.sending > 0 { return .sending(count: outbox.sending) }
        if outbox.pending > 0 { return .waitingForConnection(count: outbox.pending) }
        if let count = outbox.justDelivered { return .delivered(count: count) }
        if isOffline { return .offline }
        return nil
    }

    /// Le carnet que la feuille « Nouveau carnet » propose de retrouver plutôt
    /// que d'en ouvrir un de plus : celui qui est en cours, sinon le prochain
    /// voyage prévu. `nil` quand il n'y a ni l'un ni l'autre.
    ///
    /// Les deux listes sont déjà triées — le voyage le plus récemment commencé
    /// d'un côté, le départ le plus proche de l'autre : il n'y a qu'à prendre
    /// le premier.
    public var resumableTrip: Trip? { ongoingTrips.first ?? upcomingTrips.first }

    /// Range le contenu reçu. Les trois listes sont triées **une fois**, ici, et
    /// pas à chaque passage dans `body` : trier dans une vue, c'est trier à
    /// chaque image d'animation.
    private func apply(_ loaded: HomeFeed) {
        feed = loaded
        ongoingTrips = loaded.ongoingTrips
        upcomingTrips = loaded.upcomingTrips
        pastTrips = loaded.pastTrips
    }

    /// Envoie le vocal qu'on vient d'enregistrer.
    ///
    /// **À tous les carnets en cours, en même temps.** C'est la promesse écrite
    /// sur la feuille d'enregistrement — « MemoBook l'attribuera
    /// automatiquement » : on n'a rien choisi avant de parler, donc on ne
    /// choisit rien après. Quelqu'un qui mène deux voyages de front retrouve le
    /// souvenir dans les deux, et c'est au tri de faire le ménage plus tard,
    /// pas à la personne qui vient de raconter quelque chose.
    ///
    /// L'envoi lui-même appartient à la ``RecordingOutbox`` : c'est elle qui
    /// décide d'essayer ou de garder, et elle continue sans cet écran. Ce qui
    /// reste ici, c'est **la suite** — un souvenir arrivé fait vieillir les
    /// compteurs et la jauge du carnet, donc on recharge.
    ///
    /// Sans aucun carnet en cours, il n'y a rien à faire : la feuille ne
    /// s'ouvre pas depuis un accueil sans voyage ouvert.
    public func upload(_ audio: RecordedAudio) async {
        let trips = ongoingTrips.map(\.id)
        guard !trips.isEmpty else { return }

        switch await outbox.submit(audio, to: trips) {
        case .delivered:
            loadFailure = nil
            // Le carnet vient de grossir : ses compteurs et sa jauge sont
            // périmés. On recharge plutôt que de les corriger à la main ici —
            // c'est le serveur qui sait ce que le souvenir a produit.
            await load()
        case .queued:
            // Rien à dire de plus : la boîte d'information le dit déjà, et
            // mieux qu'un bandeau d'erreur — il ne s'est rien passé de mal.
            loadFailure = nil
        case .rejected:
            // Le message est déjà posé par la file, ``errorMessage`` le lit.
            break
        }
    }

    /// Ce que fait « Réessayer » du bandeau d'erreur : oublier le refus, et
    /// redemander le contenu. Les deux, parce qu'un seul bouton ne peut pas
    /// laisser un message à l'écran après qu'on a appuyé dessus.
    public func retry() async {
        outbox.dismissRejection()
        await load()
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

            loadFailure = nil
        } catch {
            // Hors ligne **avec** du contenu déjà à l'écran, on se tait : la
            // boîte d'information dit déjà pourquoi rien ne bouge, et un
            // bandeau rouge par-dessus ferait croire à une panne de l'app. Sans
            // rien à montrer, en revanche, l'erreur est la seule chose qui
            // explique l'écran vide.
            loadFailure = isOffline && feed != nil ? nil : error.localizedDescription
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
    /// La carte de découverte, en bas de l'accueil : elle ouvre la galerie des
    /// carnets de la communauté.
    ///
    /// Sans destination : elle en portait une (`Showcase.destinationUrl`, une
    /// page web), mais la carte mène désormais à un écran de l'app. Le champ
    /// reste au contrat d'API pour une campagne qui pointerait ailleurs ; le
    /// jour où l'une le fera, c'est ici que le choix se dira.
    case openGallery
    /// Créer un carnet à partir de zéro — la première porte de la feuille
    /// « Nouveau carnet ».
    case createTrip
    /// Rejoindre le voyage de quelqu'un d'autre, code d'accès en main.
    case joinTrip(code: String)
    /// Reprendre un voyage déjà enregistré dans Polarsteps, avec ses étapes.
    case importFromPolarsteps
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
        /// Repart du jeu d'essai complet, personnage compris — et remet le
        /// réseau, la file et les messages à zéro.
        public func debugReset() {
            SandboxPersona.current = nil
            loadFailure = nil
            apply(.fixture)
            Task { await outbox.debugReset() }
        }

        /// Un compte tout neuf : aucun voyage.
        public func debugRemoveAllTrips() {
            loadFailure = nil
            apply(HomeFeed(traveller: debugTraveller, trips: [], showcase: feed?.showcase))
        }

        /// Ajoute un voyage à l'étape voulue. Rejouable : chaque appel en pose un
        /// nouveau, tiré dans une petite banque de destinations.
        public func debugAddTrip(stage: TripStage) {
            loadFailure = nil
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
            loadFailure = nil

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
            loadFailure = URLError(.notConnectedToInternet).localizedDescription
        }

        // MARK: Hors ligne
        //
        // Le hors-ligne du bac à sable n'est **pas** un faux affichage : il
        // coupe vraiment le réseau pour l'app, et tout ce qui suit — le vocal
        // qui part sur le disque, la file qui se vide au retour — emprunte le
        // même chemin que sous un tunnel. C'est la seule façon de vérifier que
        // la promesse écrite dans la boîte est tenue.

        /// Coupe le réseau, ou le rétablit. Le rétablissement déclenche
        /// l'envoi de ce qui attendait, exactement comme une vraie reconnexion.
        public func debugToggleOffline() {
            outbox.debugSetOffline(!isOffline)
        }

        /// Met un vocal en file sans passer par le micro : de quoi voir la
        /// boîte « tes vocaux sont conservés » sans avoir à parler.
        ///
        /// Il vise **les carnets en cours**, comme un vrai. Sur des voyages du
        /// jeu d'essai, le serveur le refusera à la reconnexion et la file le
        /// dira — c'est le comportement attendu, pas un bug du bac à sable.
        public func debugQueueRecording() async {
            let trips = ongoingTrips.map(\.id)
            guard !trips.isEmpty else {
                loadFailure = "Aucun voyage en cours : il n’y a pas de carnet où envoyer un vocal."
                return
            }

            await outbox.debugQueue(.debugSilence, for: trips)
        }

        /// Montre l'envoi en cours, quelques secondes.
        public func debugShowSending() {
            outbox.debugShowSending(1)
        }

        /// Montre la confirmation d'arrivée.
        public func debugShowDelivered() {
            outbox.debugShowDelivered(1)
        }

        private var debugTraveller: Traveller {
            feed?.traveller ?? HomeFeed.fixture.traveller
        }
    }

    extension RecordedAudio {
        /// Un vocal de bac à sable : la durée et le nom d'un vrai, et zéro
        /// octet de son. Il ne sert qu'à remplir la file.
        static var debugSilence: RecordedAudio {
            RecordedAudio(
                data: Data(),
                filename: "sandbox-\(UUID().uuidString).m4a",
                mimeType: "audio/m4a",
                duration: 12,
                recordedAt: .now
            )
        }
    }

#endif
