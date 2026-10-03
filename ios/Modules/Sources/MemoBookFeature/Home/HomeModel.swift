import Foundation
import MemoBookCore
import MemoBookNetworking
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

    /// Ce qu'on avait sur le disque — voir ``ContentCache``. `nil` en aperçu.
    private let cached: CachedValue<HomeFeed>?

    /// Supprime un voyage — `DELETE /v1/memos/:id`. `nil` en aperçu, où la
    /// carte disparaît comme si c'était fait.
    private let remove: ((String) async throws -> Void)?

    /// Rejoint un voyage par son code — `POST /v1/trips/join`. `nil` en
    /// aperçu, où le code de la maquette ouvre le premier voyage du jeu
    /// d'essai et tout autre se dit introuvable.
    private let joinByCode: ((String) async throws -> CreatedTrip)?

    /// Le voyage dont la suppression est partie, le temps qu'elle aboutisse.
    public private(set) var deletingTripId: String?

    /// Ce que le serveur a répondu à une suppression refusée — un co-voyageur
    /// qui essaie, par exemple. Se lit dans la feuille de confirmation.
    public private(set) var deletionError: String?

    /// Ce que le dernier chargement a appris : rien, une reprise du disque, une
    /// confirmation, ou un vrai changement. C'est lui que la vue anime.
    public private(set) var freshness: ContentFreshness = .unknown

    /// - Parameters:
    ///   - source: d'où vient le contenu. Par défaut, le jeu d'essai — voir
    ///     ``HomeFeed/fixture``.
    ///   - outbox: où partent les vocaux. Par défaut, une file qui n'envoie
    ///     nulle part et se croit toujours en ligne : les aperçus SwiftUI n'ont
    ///     pas de serveur, et un enregistrement y est un geste sans conséquence.
    ///   - cached: ce que l'appareil a gardé du dernier passage. Sert à
    ///     **ouvrir tout de suite** plutôt qu'à attendre le réseau ; la lecture
    ///     continue derrière, et remplace. `nil` en aperçu.
    ///   - remove: supprime un voyage, depuis le tiroir d'une carte. `nil` en
    ///     aperçu.
    ///   - join: rejoint un voyage par son code d'accès. `nil` en aperçu.
    public init(
        source: @escaping () async throws -> HomeFeed = { .fixture },
        cached: CachedValue<HomeFeed>? = nil,
        outbox: RecordingOutbox = RecordingOutbox(),
        remove: ((String) async throws -> Void)? = nil,
        join: ((String) async throws -> CreatedTrip)? = nil
    ) {
        self.source = source
        self.cached = cached
        self.outbox = outbox
        self.remove = remove
        self.joinByCode = join
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

    /// **Le crédit du jour du voyage que vise le vocal de l'accueil** — le
    /// premier voyage en cours, celui où ``upload(_:levels:handoffId:)``
    /// envoie (Hugo, 03/10/2026). La feuille d'enregistrement s'en sert pour
    /// prévenir à 4:30 et couper à 5:00, comme la barre de la conversation.
    /// `nil` sans voyage en cours, ou d'un serveur qui ne le sert pas encore.
    ///
    /// **Passé minuit, le crédit d'hier se recharge** (03/10/2026) —
    /// `DailyCredit.refreshed(now:)`, la règle de la conversation. Le flux
    /// gardé sur le disque, ou laissé en mémoire la nuit, portait le crédit
    /// épuisé de la veille : le micro de l'accueil refusait de s'ouvrir le
    /// lendemain, toute la journée hors ligne, alors que la file aurait gardé
    /// le vocal.
    ///
    /// **Moins ce qui attend encore dans la file** (``unreceivedCosts``) : le
    /// crédit servi — le serveur, ou hors ligne le cache que la lecture rend —
    /// ne compte pas un vocal que le serveur n'a pas reçu. C'est la règle de
    /// la conversation (``ChatModel/dailyCredit``).
    public var ongoingTripCredit: DailyCredit? { ongoingTripCredit(at: .now) }

    /// Le même, à une heure donnée — pour les tests.
    func ongoingTripCredit(at now: Date) -> DailyCredit? {
        guard let trip = ongoingTrips.first else { return nil }
        return trip.dailyCredit?.refreshed(now: now).consuming(unreceivedCosts[trip.id] ?? 0)
    }

    /// Ce que coûtent, par voyage en cours, les tours que la file garde sur le
    /// disque et que le serveur n'a **pas encore reçus** — relu de la file
    /// après chaque lecture de l'accueil (``countWaitingTurns(now:)``), jamais
    /// mêlé au crédit servi.
    ///
    /// À part, et recalculé en entier plutôt qu'additionné (03/10/2026) : le
    /// décompte d'un vocal en file vivait dans le crédit du voyage, en
    /// mémoire seulement. La relecture suivante — au retour de la
    /// conversation que l'accueil ouvre après chaque vocal —, hors ligne,
    /// rendait le cache et l'effaçait : un second vocal repartait de 5:00, ni
    /// prévenu ni coupé, et le serveur le refusait au retour du réseau.
    /// Relire la file, c'est aussi ne jamais compter deux fois le même vocal.
    private var unreceivedCosts: [String: Int] = [:]

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
    /// **Au carnet en cours** — le premier, celui dont la conversation s'ouvre
    /// juste après avec la bulle déjà posée. C'est la promesse écrite sur la
    /// feuille d'enregistrement — « MemoBook l'attribuera automatiquement » :
    /// on n'a rien choisi avant de parler, donc on ne choisit rien après. Un
    /// vocal est un tour de **une** conversation (`docs/conversation.md` § 2) ;
    /// il ne se recopie plus dans un second voyage mené de front
    /// (22/09/2026).
    ///
    /// L'envoi lui-même appartient à la ``RecordingOutbox`` : c'est elle qui
    /// décide d'essayer ou de garder, et elle continue sans cet écran. Ce qui
    /// reste ici, c'est **la suite** — un souvenir arrivé fait vieillir les
    /// compteurs et la jauge du carnet, donc on recharge.
    ///
    /// Sans aucun carnet en cours, il n'y a rien à faire : la feuille ne
    /// s'ouvre pas depuis un accueil sans voyage ouvert.
    ///
    /// `handoffId` est l'identifiant de la bulle qui va s'afficher dans la
    /// conversation — et celui du message côté serveur : la file s'en sert
    /// pour dire **où en est cet envoi-là**, et c'est ce qui permet à la bulle
    /// de ne pas se déclarer arrivée avant de l'être. Voir
    /// ``RecordingOutbox/lastDelivery``. `levels` est la forme d'onde relevée
    /// pendant l'enregistrement : elle part avec le vocal, pour sa bulle.
    public func upload(_ audio: RecordedAudio, levels: [Double] = [], handoffId: String? = nil) async {
        guard let tripId = ongoingTrips.first?.id else { return }

        let turn = OutgoingTurn.voice(audio, levels: levels, id: handoffId ?? UUID().uuidString.lowercased())
        switch await outbox.submit(turn, to: tripId) {
        case .delivered(let receipt):
            loadFailure = nil
            // Le reçu porte le crédit **après** ce tour ; sans lui, on le
            // décompte ici. La feuille suivante part du bon reste même si la
            // relecture qui suit échoue.
            settleCredit(of: tripId, served: receipt?.dailyCredit, spentMs: audio.creditMs)
            // Le carnet vient de grossir : ses compteurs et sa jauge sont
            // périmés. On recharge plutôt que de les corriger à la main ici —
            // c'est le serveur qui sait ce que le souvenir a produit.
            await load()
        case .queued:
            // Rien à dire de plus : la boîte d'information le dit déjà, et
            // mieux qu'un bandeau d'erreur — il ne s'est rien passé de mal.
            loadFailure = nil
            // **Le vocal en file compte déjà** (03/10/2026) : sans ce décompte,
            // un second vocal de l'accueil, hors ligne, partait d'un reste
            // trop haut — ni prévenu à 4:30, ni coupé à 5:00 — et le serveur le
            // refusait au retour du réseau. Il est sur le disque de la file :
            // on la relit, comme après chaque lecture de l'accueil.
            await countWaitingTurns()
        case .rejected:
            // Le message est déjà posé par la file, ``errorMessage`` le lit.
            break
        }
    }

    /// Le crédit du voyage après un vocal **arrivé** : celui du reçu quand le
    /// serveur l'a rendu, sinon le reste d'avant **rechargé** (un vocal du
    /// matin ne se retire pas du crédit d'hier) moins ce vocal. Un abonné ne
    /// décompte rien — ``DailyCredit/consuming(_:)`` le sait.
    private func settleCredit(of tripId: String, served: DailyCredit?, spentMs: Int) {
        guard let index = ongoingTrips.firstIndex(where: { $0.id == tripId }) else { return }
        if let served {
            ongoingTrips[index].dailyCredit = served
        } else if let credit = ongoingTrips[index].dailyCredit?.refreshed(now: .now) {
            ongoingTrips[index].dailyCredit = credit.consuming(spentMs)
        }
    }

    /// Relit ce que la file garde pour chaque voyage en cours, et ce que ça
    /// coûtera au crédit d'aujourd'hui — ``unreceivedCosts``.
    ///
    /// Après une lecture **seulement** : le crédit qu'elle vient de poser ne
    /// connaît pas ces tours. Si la lecture a échoué, l'ancien décompte reste
    /// juste — un tour parti entre-temps compterait sinon pour rien.
    ///
    /// Le total est posé d'un coup, après les lectures du disque : deux
    /// relectures qui se croisent ne s'additionnent pas.
    private func countWaitingTurns(now: Date = .now) async {
        var costs: [String: Int] = [:]
        for trip in ongoingTrips {
            guard let credit = trip.dailyCredit?.refreshed(now: now), !credit.isUnlimited else { continue }
            // Ce qui attend l'illimité, ou une recharge encore à venir, prendra
            // un autre crédit que celui d'aujourd'hui (``OutgoingTurn/isOnHold``).
            let waiting = await outbox.waiting(for: trip.id).filter {
                !$0.waitingForUnlimited && !$0.isWaitingForCredit(at: now)
            }
            costs[trip.id] = waiting.reduce(0) { $0 + $1.creditCost(in: credit) }
        }
        unreceivedCosts = costs
    }

    /// Supprime un voyage depuis le tiroir de sa carte (Hugo, 17/09/2026).
    ///
    /// La carte disparaît **sur la réponse du serveur**, pas avant : c'est le
    /// récit de tout le monde qui part, et un co-voyageur se voit refuser le
    /// geste — la feuille lit alors le refus. Renvoie `true` quand c'est fait,
    /// et recharge l'accueil : les compteurs et la section « en cours » ont
    /// changé.
    public func deleteTrip(id: String) async -> Bool {
        deletingTripId = id
        deletionError = nil
        defer { deletingTripId = nil }

        do {
            if let remove {
                try await remove(id)
                await load()
            } else if let feed {
                apply(HomeFeed(traveller: feed.traveller, trips: feed.trips.filter { $0.id != id }, showcase: feed.showcase))
            }
            return true
        } catch {
            deletionError = error.localizedDescription
            return false
        }
    }

    /// Oublie le refus d'une suppression : à la fermeture de la feuille.
    public func dismissDeletionError() {
        deletionError = nil
    }

    /// Rejoint le voyage de quelqu'un par son code d'accès — « Rejoins une
    /// aventure ».
    ///
    /// **Trois issues, et la feuille n'en montre que deux.** Le voyage ouvert,
    /// et l'accueil rechargé pour qu'il y soit ; un code qui ne mène nulle
    /// part, dit par l'alerte « Oups, voyage introuvable » (Clara, 26/09/2026)
    /// — une faute de frappe se corrige dans le champ, sans rien refermer ;
    /// tout le reste, un réseau absent ou un retrait par le propriétaire, avec
    /// la phrase du serveur.
    public func join(code: String) async -> JoinOutcome {
        guard let joinByCode else {
            // En aperçu, le code de la maquette ouvre le premier voyage du jeu
            // d'essai ; tout autre est introuvable, pour voir l'alerte.
            guard code == "JHKFDA", let trip = ongoingTrips.first ?? feed?.trips.first else { return .notFound }
            return .joined(tripId: trip.id)
        }

        do {
            let joined = try await joinByCode(code)
            await load()
            return .joined(tripId: joined.trip.id)
        } catch let error as APIError {
            if case .server(let status, let reason, _) = error, status == 404 || reason == "trip_not_found" {
                return .notFound
            }
            return .failed(error.localizedDescription)
        } catch {
            return .failed(error.localizedDescription)
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

        // **Ce qu'on avait, tout de suite.** Seulement au premier chargement :
        // un « tirer pour rafraîchir » ne doit pas remplacer ce qui est à
        // l'écran par une copie plus ancienne le temps d'un aller-retour.
        if feed == nil, let stored = await cached?() {
            apply(stored)
            freshness = .restored
            await countWaitingTurns()
        }

        do {
            let loaded = try await source()
            // **Avant** de poser la valeur : la comparaison porte sur ce qui
            // est encore à l'écran.
            freshness = contentFreshness(of: loaded, replacing: feed)

            #if DEBUG
                // Le personnage et le crédit du bac à sable survivent à un
                // rechargement : sans ça, tirer sur la liste pour la rafraîchir
                // remettait l'abonnement du serveur et le profil, lui, gardait
                // le sien. Deux écrans qui ne racontaient plus la même
                // histoire. Absent de l'app livrée.
                apply(debugSandboxed(loaded))
            #else
                apply(loaded)
            #endif

            loadFailure = nil
            // Hors ligne, la lecture rend le cache sans lever : son crédit ne
            // compte pas plus que celui du serveur ce qui attend dans la file.
            await countWaitingTurns()
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

extension RecordedAudio {
    /// Ce que ce vocal consomme du crédit du jour, en millisecondes — sa
    /// durée, comme le serveur la mesure.
    var creditMs: Int { Int((max(0, duration) * 1000).rounded()) }
}

/// Ce qu'a donné un code d'accès — voir ``HomeModel/join(code:)``.
public enum JoinOutcome: Sendable, Hashable {
    case joined(tripId: String)
    /// Le code ne mène à aucun voyage : l'alerte « Oups, voyage introuvable ».
    case notFound
    case failed(String)
}

/// Ce que l'accueil peut demander à l'app de faire. L'écran ne navigue pas
/// lui-même : il annonce une intention, et `RootView` décide où elle mène.
/// Tant que les voyages ne sont pas branchés, certaines n'ont pas encore de
/// destination — c'est écrit à l'endroit qui route, pas ici.
public enum HomeIntent: Sendable, Hashable {
    case openProfile
    case openTrip(id: String)
    case orderPrint(tripId: String)
    /// Partager un voyage, depuis le tiroir de sa carte : l'aperçu du carnet,
    /// ouvert directement sur sa feuille de partage — c'est là que vivent le
    /// PDF et le lien, et un second chemin de partage aurait dit la même chose.
    case shareTrip(id: String)
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
    /// Reprendre un voyage déjà enregistré dans Polarsteps, avec ses étapes.
    case importFromPolarsteps
    case openHelp
    /// Le vocal qu'on vient d'enregistrer depuis l'accueil, à retrouver **dans
    /// la conversation** du voyage en cours. L'envoi au serveur ne passe pas
    /// par là — il est déjà parti par la file —, seul l'affichage voyage.
    case openConversation(tripId: String, handoff: RecordingHandoff)
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
        /// Repart du jeu d'essai complet, personnage et crédit compris — et
        /// remet le réseau, la file et les messages à zéro.
        public func debugReset() {
            SandboxPersona.current = nil
            SandboxCredit.reset()
            loadFailure = nil
            unreceivedCosts = [:]
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

        /// Devenir un abonné : il raconte sans limite — plus de crédit compté
        /// dans la conversation ni dans les réglages — et, dans le profil, la
        /// pastille « Abonné(e) » et la ligne « Mon abonnement ».
        public func debugBecomeSubscriber() {
            debugPlay(.subscriber)
        }

        /// Sans abonnement : le crédit du jour compte, et le profil propose
        /// « Découvrir l'abonnement ».
        public func debugBecomeFree() {
            debugPlay(.free)
        }

        /// Quelqu'un qui n'a **jamais** été abonné : le paywall s'ouvre sur la
        /// découverte en trois écrans. Le profil du jeu d'essai démarre abonné,
        /// et « Sans abonnement » en fait un ancien abonné : sans ce
        /// personnage, la découverte était inatteignable dans le bac à sable
        /// (recette du 03/10/2026). Le panneau remet aussi la session à zéro.
        public func debugBecomeNeverSubscribed() {
            debugPlay(.neverSubscribed)
        }

        /// Fait servir ce crédit du jour à chaque voyage — « Crédit neuf »,
        /// « Plus que 30 s », « Crédit épuisé » —, par le double d'API (fil de
        /// la conversation, ses mises à jour, le reçu d'un tour, réglages du
        /// voyage) et sur l'accueil tout de suite. Le crédit ne compte que pour
        /// qui n'est pas abonné : le personnage passe donc sans abonnement.
        ///
        /// Avec un vrai serveur, seul l'accueil se retouche : la conversation
        /// et les réglages lisent le crédit du serveur.
        public func debugPlayCredit(_ preset: SandboxCredit.Preset) {
            SandboxCredit.play(preset)
            debugPlay(.free)
        }

        /// Fait jouer un personnage à l'app entière — l'accueil tout de suite,
        /// le profil à la prochaine ouverture. Voir ``SandboxPersona``.
        private func debugPlay(_ persona: SandboxPersona) {
            SandboxPersona.current = persona
            loadFailure = nil

            apply(
                debugSandboxed(
                    HomeFeed(
                        traveller: debugTraveller,
                        trips: feed?.trips ?? [],
                        showcase: feed?.showcase
                    )
                )
            )
        }

        /// Ce que le bac à sable retouche sur un accueil reçu : le crédit des
        /// voyages en cours d'abord — seulement si un réglage est joué, pour ne
        /// jamais maquiller celui d'un vrai serveur —, puis le personnage.
        fileprivate func debugSandboxed(_ loaded: HomeFeed) -> HomeFeed {
            let credited = SandboxCredit.isPlaying ? SandboxCredit.applied(to: loaded) : loaded
            return SandboxPersona.current?.applied(to: credited) ?? credited
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
        /// Il vise **le carnet en cours**, comme un vrai. Sur un voyage du
        /// jeu d'essai, le serveur le refusera à la reconnexion et la file le
        /// dira — c'est le comportement attendu, pas un bug du bac à sable.
        public func debugQueueRecording() async {
            guard let tripId = ongoingTrips.first?.id else {
                loadFailure = "Aucun voyage en cours : il n’y a pas de carnet où envoyer un vocal."
                return
            }

            await outbox.debugQueue(.debugSilence, for: tripId)
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
