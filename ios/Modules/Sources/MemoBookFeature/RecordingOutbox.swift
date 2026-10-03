import Foundation
import MemoBookCore
import MemoBookNetworking
import MemoBookRecording
import Observation

/// La file de départ de ce qu'on raconte : ce qui garantit qu'un souvenir dit
/// hors ligne finit dans le carnet.
///
/// **Elle vit au-dessus des écrans**, dans ``AppDependencies``, et pas dans
/// ``HomeModel`` : un envoi commencé depuis l'accueil doit se terminer même si
/// on file dans son profil pendant ce temps, et un vocal mis de côté dans le
/// métro doit repartir tout seul à la sortie, quel que soit l'écran affiché.
///
/// **Tout ce qu'on dit passe par elle** — le vocal de l'accueil comme un
/// texte, un vocal ou des photos envoyés depuis la conversation (`docs/
/// conversation.md` § 9). Un tour est un ``OutgoingTurn`` : il porte
/// l'identifiant que le serveur reprendra, donc un tour parti deux fois n'est
/// jamais dans le fil deux fois.
///
/// **Et les voyages créés hors ligne** (Hugo, 01/10/2026) : on crée un voyage
/// dans l'avion, on l'ouvre, on y raconte, et tout part à l'atterrissage. Le
/// voyage passe **avant** ce qu'on y a dit — un vocal envoyé à un carnet que
/// le serveur ne connaît pas encore serait refusé (404) et perdu. Voir
/// ``saveTrip(_:)``.
///
/// **Et le crédit du jour** (Hugo, 03/10/2026) : un `429
/// daily_credit_exhausted` n'est pas un refus définitif. Le tour reste sur le
/// disque, marqué « attend le crédit » jusqu'à l'heure où il se recharge
/// (``PendingTurn/waitingForCreditUntil``), puis repart tout seul ; sa bulle
/// dit « Partira demain » (``ChatDelivery/waitingForCredit(until:)``). Un tour
/// qui coûte **plus qu'une journée entière** — ou que le serveur refuse en
/// `daily_credit_too_long` — n'attend pas demain, qui ne changerait rien : il
/// attend l'illimité (``PendingTurn/waitingForUnlimited``). Et tout ce qui est
/// retenu repart dès que le compte passe en illimité
/// (``releaseCreditHolds()``) — ou se supprime, si la personne le demande
/// depuis sa bulle (``discardTurn(id:)``).
///
/// Elle tient trois choses, et rien d'autre :
///
/// 1. **l'état du réseau** (``Connectivity``), pour savoir s'il faut essayer ;
/// 2. **la file sur le disque** (``PendingRecordingStore`` pour les tours,
///    ``PendingTripStore`` pour les voyages), pour que ce qui n'est pas parti
///    survive à la fermeture de l'app ;
/// 3. **l'envoi lui-même**, une fonction qui rend le reçu du serveur — elle ne
///    connaît pas `MemoBookAPI`, comme les modèles d'écran ne connaissent pas
///    leur route.
///
/// ⚠️ **Un envoi ne survit pas à la mise en arrière-plan.** `URLSession` en
/// tâche de fond serait la réponse complète ; elle demande un envoi par
/// fichier et une délégation, donc une autre forme de client d'API. En
/// attendant, ce qui n'a pas eu le temps de partir reste dans la file et
/// repart au retour dans l'app — rien n'est perdu, c'est juste plus tard.
@MainActor
@Observable
public final class RecordingOutbox {
    /// Ce qu'il est advenu d'un tour qu'on vient de confier.
    public enum Delivery: Sendable, Equatable {
        /// Il est arrivé, et voici ce que le serveur a écrit. Sans reçu quand
        /// l'appel a abouti mais que sa réponse n'a pas pu se lire — le tour
        /// est bien là-bas, on ne le renvoie pas.
        case delivered(ChatTurnReceipt?)
        /// Il attend le réseau, sur le disque. Ce n'est **pas** un échec : la
        /// boîte d'information de l'accueil le dit, il n'y a rien à faire.
        ///
        /// C'est aussi ce que rend un tour que le serveur a refusé **faute de
        /// crédit du jour** : il attend sur le disque, comme sous un tunnel,
        /// seulement plus longtemps — jusqu'à minuit, ou jusqu'à l'illimité
        /// s'il est plus long qu'une journée. La différence voyage par
        /// ``turnDeliveries()`` (``ChatDelivery/waitingForCredit(until:)``,
        /// ``ChatDelivery/waitingForUnlimited``) — un cas de plus ici aurait
        /// obligé chaque appelant à le traiter pour faire la même chose.
        case queued
        /// Le serveur a dit non, et le redire ne changerait rien.
        case rejected(String)
    }

    /// Le réseau est disponible. Il part de `true` : tant que le moniteur n'a
    /// pas parlé, on n'affiche pas « hors ligne » à quelqu'un qui ne l'est pas.
    public private(set) var isOnline = true

    /// Combien de tours attendent **le réseau** sur le disque.
    public private(set) var pending = 0

    /// Combien de tours attendent **le crédit de demain** sur le disque — voir
    /// ``PendingTurn/waitingForCreditUntil``. Comptés à part de ``pending`` :
    /// la boîte de l'accueil promet de les envoyer « dès la reconnexion », et
    /// eux partiront à minuit, réseau ou pas.
    public private(set) var waitingForCredit = 0

    /// Combien de tours attendent **l'illimité** sur le disque — voir
    /// ``PendingTurn/waitingForUnlimited``. Ni le réseau ni minuit ne les
    /// feront partir : comptés à part, eux aussi.
    public private(set) var waitingForUnlimited = 0

    /// Combien de tours sont en train de partir. Zéro quand rien n'est en vol.
    public private(set) var sending = 0

    /// Ce que le dernier envoi a fait arriver, le temps de le dire — voir
    /// ``confirmationDelay``. `nil` le reste du temps.
    public private(set) var justDelivered: Int?

    /// Compteur monotone des tours arrivés. Il ne sert qu'à une chose : que
    /// l'accueil sache qu'il doit se recharger, parce que ses compteurs et sa
    /// jauge viennent de vieillir.
    public private(set) var deliveries = 0

    /// Un refus **définitif** du serveur, à montrer à l'utilisateur. Ce qui
    /// tient au réseau n'arrive jamais ici : ça retourne dans la file.
    public private(set) var rejection: String?

    /// Où en est le dernier tour dont le sort a changé — et le reçu du
    /// serveur, quand il est arrivé.
    ///
    /// La bulle s'affiche **dans la conversation**, sur un écran que la file ne
    /// connaît pas — et le tour peut très bien attendre le réseau sur le
    /// disque. La bulle suit donc la file au lieu de décider elle-même : une
    /// bulle qui se déclarerait envoyée parce que MEMO a répondu mentirait à
    /// chaque fois qu'on raconte dans le métro. La conversation écoute
    /// ``turnDeliveries()`` ; cette valeur-ci est le dernier mot, pour qui arrive
    /// après. Voir ``ChatModel/markDelivery(_:)``.
    public private(set) var lastDelivery: ChatTurnDelivery?

    /// Un refus définitif, tel que la conversation le reçoit : le libellé est
    /// déjà écrit pour l'utilisateur, le code du serveur suit quand il y en a
    /// un — l'écran peut ainsi distinguer un refus d'un autre sans relire la
    /// phrase.
    public struct Rejection: LocalizedError, Sendable, Hashable {
        public let message: String
        public var code: String? = nil
        public var errorDescription: String? { message }

        public init(message: String, code: String? = nil) {
            self.message = message
            self.code = code
        }
    }

    private let store: PendingRecordingStore
    private let connectivity: Connectivity
    private let send: @Sendable (OutgoingTurn, String) async throws -> ChatTurnReceipt

    /// Les voyages créés sur le téléphone que le serveur n'a pas encore vus,
    /// **tous comptes confondus** — voir ``localTrips``.
    private var storedTrips: [PendingTrip] = []
    private let trips: PendingTripStore
    private let createTrip: @Sendable (TripDraft) async throws -> CreatedTrip

    /// Les voyages arrivés pendant cette session, avec leur code d'accès :
    /// revenir sur la création ne fait pas attendre un code déjà reçu.
    private var createdTrips: [String: CreatedTrip] = [:]
    private var tripListeners: [UUID: AsyncStream<TripSyncEvent>.Continuation] = [:]

    /// Le compte ouvert : ses voyages en attente sont les seuls qu'on montre
    /// et qu'on envoie. `nil` avant l'ouverture de la session, et dans le bac à
    /// sable.
    private var accountId: String?

    /// Un vidage a été demandé pendant qu'un autre tournait : il repassera,
    /// pour prendre ce qui est arrivé entre-temps.
    private var drainsAgain = false

    /// Les conversations à l'écoute — voir ``turnDeliveries()``.
    private var listeners: [UUID: AsyncStream<ChatTurnDelivery>.Continuation] = [:]

    private var monitor: Task<Void, Never>?
    private var flushing: Task<Void, Never>?
    private var confirmation: Task<Void, Never>?

    /// Le réveil des tours qui attendent le crédit du jour : une tâche qui
    /// dort jusqu'à la plus proche recharge, puis vide la file. Une seule à la
    /// fois — voir ``scheduleCreditWake()``.
    private var creditWake: Task<Void, Never>?

    /// Ce que dit le moniteur, avant que le bac à sable ne s'en mêle.
    private var networkIsUp = true

    #if DEBUG
        /// Le « Passer hors ligne » du bac à sable. Il **prime** sur le
        /// moniteur, et le reste — file, envois, reprise — se comporte
        /// exactement comme sous un vrai tunnel. Absent de l'app livrée.
        private var forcedOffline = false
    #endif

    /// Combien de temps la confirmation d'arrivée reste à l'écran. Assez pour
    /// être lue, assez peu pour ne pas devenir un meuble.
    private static let confirmationDelay = Duration.seconds(4)

    public init(
        store: PendingRecordingStore = .temporary(),
        trips: PendingTripStore = .temporary(),
        connectivity: Connectivity = .online,
        send: @escaping @Sendable (OutgoingTurn, String) async throws -> ChatTurnReceipt = { _, _ in
            ChatTurnReceipt(messages: [], turn: .idle, now: .now)
        },
        createTrip: @escaping @Sendable (TripDraft) async throws -> CreatedTrip = { draft in
            .fixture(draft, id: draft.id)
        }
    ) {
        self.store = store
        self.trips = trips
        self.connectivity = connectivity
        self.send = send
        self.createTrip = createTrip
    }

    /// Ouvre la file et se met à l'écoute du réseau. Idempotent : l'appeler
    /// deux fois ne pose pas deux moniteurs.
    ///
    /// À appeler **au démarrage** et non à l'ouverture d'un écran : c'est ce
    /// qui permet de savoir qu'on est hors ligne avant de dessiner l'accueil,
    /// et de repartir avec ce qu'un lancement précédent avait laissé en file.
    public func start() {
        guard monitor == nil else { return }

        // `self` est retenu volontairement : cette boucle ne s'arrête pas, et
        // l'objet vit aussi longtemps que l'app.
        monitor = Task {
            await refreshCounts()
            storedTrips = await trips.all()
            // Un tour mis de côté hier soir faute de crédit repart à l'heure
            // dite, même si l'app a été relancée entre-temps.
            await scheduleCreditWake()

            var isFirstPath = true
            for await isUp in connectivity.updates() {
                // La reconnexion, c'est aussi le tout premier état connu : une
                // app relancée en ligne avec une file pleine doit la vider sans
                // attendre une coupure suivie d'un retour.
                let reconnected = isUp && (isFirstPath || !networkIsUp)
                networkIsUp = isUp
                isFirstPath = false
                refreshOnline()

                if reconnected, isOnline { await flush() }
            }
        }
    }

    /// Confie un tour à un carnet.
    ///
    /// Hors ligne, il part directement dans la file — on n'essaie même pas, et
    /// on ne fait donc pas attendre quelqu'un devant un échec annoncé. En
    /// ligne, on essaie, et **ce qui échoue au transport retourne dans la
    /// file** : le moniteur dit qu'une interface est montée, pas que l'API
    /// répond.
    @discardableResult
    public func submit(_ turn: OutgoingTurn, to tripId: String) async -> Delivery {
        rejection = nil
        publish(ChatTurnDelivery(id: turn.id, tripId: tripId, state: .sending))

        let outcome = await deliverOrQueue(turn, to: tripId)
        note(outcome, of: turn.id, to: tripId)
        return outcome
    }

    /// Le sort des tours, au fil de l'eau — ce que la conversation écoute.
    ///
    /// Un flux et non une valeur observée : deux tours qui partent dans la
    /// même seconde font deux événements, et une bulle ne doit rater ni l'un
    /// ni l'autre. Il commence par le dernier connu : un écran ouvert après
    /// l'arrivée du vocal de l'accueil ne l'attend pas pour rien. Le flux
    /// s'arrête quand la tâche qui le lit s'arrête.
    ///
    /// Ce premier mot est **marqué rejoué** (``ChatTurnDelivery/isReplay``) :
    /// il vit autant que l'app, et son reçu peut dater du matin — le fil qui
    /// vient de lire un crédit plus frais ne doit pas le reprendre.
    public func turnDeliveries() -> AsyncStream<ChatTurnDelivery> {
        AsyncStream { continuation in
            let key = UUID()
            if let lastDelivery { continuation.yield(lastDelivery.replayed) }
            listeners[key] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in self?.listeners[key] = nil }
            }
        }
    }

    private func publish(_ delivery: ChatTurnDelivery) {
        lastDelivery = delivery
        for listener in listeners.values { listener.yield(delivery) }
    }

    /// Les tours qui attendent le réseau pour un carnet, le plus ancien
    /// d'abord — ce que la conversation pose en bulles « en cours d'envoi »
    /// quand on l'ouvre. Relus du disque, fichiers compris : la bulle d'un
    /// vocal doit se réécouter.
    public func waiting(for tripId: String) async -> [OutgoingTurn] {
        var turns: [OutgoingTurn] = []
        for record in await store.all() where record.tripId == tripId {
            guard let files = try? await store.files(for: record), let turn = Self.turn(from: record, files: files)
            else { continue }
            turns.append(turn)
        }
        return turns
    }

    private func deliverOrQueue(_ turn: OutgoingTurn, to tripId: String) async -> Delivery {
        // Un carnet que le serveur ne connaît pas encore : le tour attend son
        // voyage, qui partira avant lui.
        guard isOnline, !isWaitingForServer(tripId) else { return await queue(turn, for: tripId) }

        sending += 1
        let outcome = await deliver(turn, to: tripId)
        sending -= 1

        switch outcome {
        case .sent(let receipt):
            noteDelivery(of: 1)
            return .delivered(receipt)
        case .deferred:
            return await queue(turn, for: tripId)
        case .waitingForCredit(let until, let credit):
            // Pas un refus : le tour attend sur le disque, marqué, et sa bulle
            // dit « Partira demain ». Le disque qui refuse, lui, reste le seul
            // cas où il se perdrait — et ``queue`` le dit.
            let delivery = await queue(turn, for: tripId, waitingForCreditUntil: until)
            if delivery == .queued {
                publish(ChatTurnDelivery(id: turn.id, tripId: tripId, state: .waitingForCredit(until: until), credit: credit))
            }
            return delivery
        case .waitingForUnlimited(let credit):
            // Plus long qu'une journée : gardé, marqué, et sa bulle propose
            // l'illimité au lieu de promettre demain.
            let delivery = await queue(turn, for: tripId, waitingForUnlimited: true)
            if delivery == .queued {
                publish(ChatTurnDelivery(id: turn.id, tripId: tripId, state: .waitingForUnlimited, credit: credit))
            }
            return delivery
        case .rejected(let reason):
            let message = Self.message(for: turn, reason: reason)
            rejection = message
            return .rejected(message)
        }
    }

    /// Ce que la bulle de la conversation doit montrer.
    ///
    /// ⚠️ `.queued` **n'est pas un échec, et n'est pas une arrivée** : le tour
    /// attend le réseau sur le disque, et la bulle reste donc sur « envoi en
    /// cours ». C'est ``drain()`` qui la terminera, au retour de la connexion,
    /// **par son identifiant**.
    private func note(_ outcome: Delivery, of id: String, to tripId: String) {
        switch outcome {
        case .delivered(let receipt):
            publish(ChatTurnDelivery(id: id, tripId: tripId, state: .sent, receipt: receipt))
        case .queued:
            break
        case .rejected(let message):
            publish(ChatTurnDelivery(id: id, tripId: tripId, state: .failed(message)))
        }
    }

    /// Vide la file. Sans effet hors ligne, et un seul vidage à la fois : deux
    /// déclencheurs simultanés — le retour du réseau et le retour dans l'app —
    /// ne doivent pas envoyer deux fois le même souvenir.
    public func flush() async {
        // Un vidage déjà en cours repassera pour ce qui vient d'arriver — et
        // celui qui attend attend **tous** les passages : rendre la main avant
        // le dernier, ce serait dire « parti » d'un voyage encore sur le disque.
        if let flushing {
            drainsAgain = true
            return await flushing.value
        }

        let task = Task {
            repeat {
                drainsAgain = false
                await drain()
            } while drainsAgain && isOnline
            // **Ici**, dans la même foulée que le dernier passage : levé après
            // coup par l'appelant, il laissait un instant où un vidage tout
            // juste demandé attendait une tâche déjà finie — et ne repassait
            // pas.
            flushing = nil
        }
        flushing = task
        await task.value
    }

    /// Oublie le dernier refus. C'est ce que demande « Réessayer » du bandeau
    /// d'erreur : un message qui survit au geste censé le traiter fait douter
    /// du geste.
    public func dismissRejection() {
        rejection = nil
    }

    // MARK: - L'envoi

    private func drain() async {
        guard isOnline else { return }

        // Les voyages d'abord : ce qu'on y a raconté ne peut partir qu'après.
        // Un voyage qui n'est pas passé ne retient que ses propres tours — ceux
        // des carnets que le serveur connaît partent quand même.
        await drainTrips()
        guard isOnline else { return }

        // Ce qui attend le crédit de demain reste de côté jusqu'à l'heure dite,
        // ce qui attend l'illimité jusqu'à l'abonnement : le renvoyer
        // maintenant, c'est le même refus — et une requête de plus à chaque
        // retour dans l'app.
        let now = Date.now
        let waiting = await store.all().filter { !$0.isOnHold(at: now) }
        await refreshCounts()
        guard !waiting.isEmpty else { return }

        sending += waiting.count
        defer { sending -= waiting.count }

        var delivered = 0

        /// Les voyages refusés faute de crédit pendant ce vidage, avec l'heure
        /// de la recharge et le solde que le serveur a rendu. Leurs tours
        /// suivants ne partent que s'ils tiennent dans ce reste — une puce, des
        /// photos, un texte assez court ; les autres sont marqués « Partira
        /// demain » tout de suite, sans un aller-retour pour le même refus.
        var heldTrips: [String: (until: Date, credit: DailyCredit?)] = [:]

        for record in waiting {
            guard isOnline else { break }

            // Son voyage attend encore : il partira au prochain vidage, après lui.
            if isWaitingForServer(record.tripId) { continue }

            guard let files = try? await store.files(for: record),
                let turn = Self.turn(from: record, files: files)
            else {
                // Le fichier a disparu sous la fiche : elle ne sert plus à rien.
                await store.remove(record)
                continue
            }

            // Le voyage vient d'être refusé, et ce tour-ci coûte plus qu'une
            // journée entière : demain ne le ferait pas passer non plus. Il
            // attend l'illimité tout de suite, comme si le serveur l'avait dit
            // — annoncé « Partira demain », il l'aurait été toute la journée
            // avant d'être reconnu trop long au renvoi de minuit (03/10/2026).
            if let held = heldTrips[record.tripId], turn.exceedsAWholeDay(in: held.credit ?? DailyCredit()) {
                var marked = record
                marked.waitingForCreditUntil = nil
                marked.waitingForUnlimited = true
                try? await store.update(marked)
                publish(
                    ChatTurnDelivery(id: record.id, tripId: record.tripId, state: .waitingForUnlimited, credit: held.credit)
                )
                continue
            }

            // Le voyage vient d'être refusé : ce tour-ci tient-il encore dans
            // ce qui reste ? Sinon il attend demain, marqué et dit comme tel —
            // laissé sans marque, il resterait compté « hors ligne » et sa
            // bulle « en cours d'envoi », alors qu'on est en ligne.
            if let held = heldTrips[record.tripId], !Self.fits(turn, in: held.credit) {
                var marked = record
                marked.waitingForCreditUntil = held.until
                try? await store.update(marked)
                publish(
                    ChatTurnDelivery(
                        id: record.id,
                        tripId: record.tripId,
                        state: .waitingForCredit(until: held.until),
                        credit: held.credit
                    )
                )
                continue
            }

            switch await deliver(turn, to: record.tripId) {
            case .sent(let receipt):
                await store.remove(record)
                delivered += 1
                note(.delivered(receipt), of: record.id, to: record.tripId)
            case .waitingForCredit(let until, let credit):
                // Gardé, marqué, et sa bulle passe à « Partira demain ».
                var marked = record
                marked.waitingForCreditUntil = until
                try? await store.update(marked)
                heldTrips[record.tripId] = (until, credit)
                publish(
                    ChatTurnDelivery(
                        id: record.id,
                        tripId: record.tripId,
                        state: .waitingForCredit(until: until),
                        credit: credit
                    )
                )
            case .waitingForUnlimited(let credit):
                // Plus long qu'une journée : il attend l'illimité. Le voyage,
                // lui, n'est pas retenu — le reste du jour sert aux suivants.
                var marked = record
                marked.waitingForCreditUntil = nil
                marked.waitingForUnlimited = true
                try? await store.update(marked)
                publish(ChatTurnDelivery(id: record.id, tripId: record.tripId, state: .waitingForUnlimited, credit: credit))
            case .rejected(let reason):
                await store.remove(record)
                let message = Self.message(for: turn, reason: reason)
                rejection = message
                note(.rejected(message), of: record.id, to: record.tripId)
            case .deferred:
                // Rien n'est passé : le réseau est reparti. Inutile de faire
                // subir la même attente aux suivants.
                await refreshCounts()
                await scheduleCreditWake()
                return
            }
        }

        await refreshCounts()
        await scheduleCreditWake()
        if delivered > 0 { noteDelivery(of: delivered) }
    }

    /// Recompte la file : ce qui attend le réseau, ce qui attend le crédit,
    /// ce qui attend l'illimité.
    private func refreshCounts() async {
        let now = Date.now
        let all = await store.all()
        waitingForUnlimited = all.filter(\.waitingForUnlimited).count
        waitingForCredit = all.filter { !$0.waitingForUnlimited && $0.isWaitingForCredit(at: now) }.count
        pending = all.count - waitingForCredit - waitingForUnlimited
    }

    /// **Le compte vient de passer en illimité** (03/10/2026) : ce qui
    /// attendait le crédit de demain ou l'illimité repart tout de suite. On
    /// vient de payer pour raconter sans limite — le vocal refusé à 15 h ne
    /// doit pas attendre minuit pour autant.
    ///
    /// Les bulles quittent « Partira demain » et « Trop long pour une
    /// journée » pour « en cours d'envoi », puis la file se vide — hors ligne,
    /// elles partiront au retour du réseau. Tout est relâché, sans trier par
    /// compte : un tour d'un autre compte resté sans abonnement reprendra son
    /// refus, et sa marque, au premier envoi.
    public func releaseCreditHolds() async {
        var released: [PendingTurn] = []
        for record in await store.all() where record.waitingForCreditUntil != nil || record.waitingForUnlimited {
            var freed = record
            freed.waitingForCreditUntil = nil
            freed.waitingForUnlimited = false
            try? await store.update(freed)
            released.append(freed)
        }
        guard !released.isEmpty else { return }

        await refreshCounts()
        await scheduleCreditWake()
        for record in released {
            publish(ChatTurnDelivery(id: record.id, tripId: record.tripId, state: .sending))
        }
        if isOnline { await flush() }
    }

    /// Pose le réveil des tours qui attendent le crédit du jour : à la plus
    /// proche recharge, la file se vide d'elle-même — pas besoin de rouvrir
    /// l'app ni de toucher « Réessayer ». Quelques secondes de marge : le
    /// serveur tranche le jour à son horloge, et arriver une seconde trop tôt
    /// ferait reposer le tour pour une nuit de plus.
    ///
    /// Une app suspendue ne se réveille pas pour autant : la tâche repart au
    /// retour au premier plan, et ``RootView`` vide la file à ce moment-là de
    /// toute façon.
    private func scheduleCreditWake() async {
        creditWake?.cancel()
        creditWake = nil

        let now = Date.now
        let next = await store.all().compactMap(\.waitingForCreditUntil).filter { $0 > now }.min()
        guard let next else { return }

        creditWake = Task { [weak self] in
            let delay = max(0, next.timeIntervalSinceNow) + Self.creditWakeMargin
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            await self.refreshCounts()
            if self.isOnline { await self.flush() }
        }
    }

    /// La marge du réveil, après l'heure de recharge annoncée par le serveur.
    private static let creditWakeMargin: TimeInterval = 5

    private func deliver(_ turn: OutgoingTurn, to tripId: String) async -> Outcome {
        do {
            return .sent(try await send(turn, tripId))
        } catch {
            let outcome = Self.outcome(for: error)
            // Un refus faute de crédit pour un tour qu'aucune journée ne
            // laissera passer : demain donnerait le même refus.
            if case .waitingForCredit(_, let credit) = outcome, Self.neverFitsADay(turn, refusal: credit) {
                return .waitingForUnlimited(credit: credit)
            }
            return outcome
        }
    }

    private func queue(
        _ turn: OutgoingTurn,
        for tripId: String,
        waitingForCreditUntil: Date? = nil,
        waitingForUnlimited: Bool = false
    ) async -> Delivery {
        do {
            var record = Self.record(for: turn, tripId: tripId)
            record.waitingForCreditUntil = waitingForCreditUntil
            record.waitingForUnlimited = waitingForUnlimited
            try await store.enqueue(record, files: Self.files(of: turn))
            await refreshCounts()
            if waitingForCreditUntil != nil { await scheduleCreditWake() }
            return .queued
        } catch {
            // Le disque a refusé : c'est le seul cas où un tour se perd, et il
            // faut le dire tout de suite — la personne peut encore recommencer.
            let message = "\(Self.subject(of: turn)) n’a pas pu être gardé sur ton téléphone. Réessaie."
            rejection = message
            return .rejected(message)
        }
    }

    private func noteDelivery(of count: Int) {
        deliveries += count
        justDelivered = count

        confirmation?.cancel()
        confirmation = Task {
            try? await Task.sleep(for: Self.confirmationDelay)
            guard !Task.isCancelled else { return }
            justDelivered = nil
        }
    }

    private func refreshOnline() {
        #if DEBUG
            isOnline = networkIsUp && !forcedOffline
        #else
            isOnline = networkIsUp
        #endif
    }

    // MARK: - Les voyages créés hors ligne

    /// Les voyages du compte ouvert que le serveur n'a pas encore vus. C'est ce
    /// que l'accueil, l'écran du voyage et la conversation montrent à leur
    /// place, en attendant — voir ``mergingLocalTrips(into:)``.
    public var localTrips: [PendingTrip] {
        storedTrips.filter { $0.accountId == accountId }
    }

    /// Le voyage en attente qui porte cet identifiant, s'il y en a un.
    public func localTrip(_ id: String) -> PendingTrip? {
        localTrips.first { $0.id == id }
    }

    /// Le serveur ne connaît pas encore ce carnet : rien de ce qu'on y dit ne
    /// doit partir avant lui. Tous comptes confondus — le vocal d'un voyage
    /// qu'un autre compte a créé attend que ce compte revienne.
    private func isWaitingForServer(_ tripId: String) -> Bool {
        storedTrips.contains { $0.id == tripId }
    }

    /// Le compte de la session ouverte — ``nil`` à la déconnexion. Ses voyages
    /// en attente partent alors, s'il y a du réseau.
    public func setAccount(_ id: String?) {
        guard id != accountId else { return }
        accountId = id
        if id != nil, isOnline { Task { await flush() } }
    }

    /// Confie un voyage à la file — la création, et chaque correction qui la
    /// suit.
    ///
    /// Le voyage est **gardé sur le disque d'abord**, et la fonction rend dès
    /// que c'est fait : la création passe à l'étape du code d'accès sans
    /// attendre personne, réseau ou pas. L'envoi part derrière ; son issue —
    /// le code d'accès, ou un refus — arrive par ``tripSync(for:)``.
    ///
    /// Corriger un voyage déjà parti le remet dans la file : `POST /v1/trips`
    /// se rejoue sur son identifiant, et pose le dernier brouillon.
    ///
    /// - Throws: ``Rejection`` quand le disque refuse — le seul cas où le
    ///   voyage se perdrait, et il faut le dire tant qu'on est sur l'écran.
    @discardableResult
    public func saveTrip(_ draft: TripDraft) async throws -> Trip {
        var draft = draft
        let id = draft.id ?? UUID().uuidString.lowercased()
        draft.id = id

        do {
            try await trips.save(PendingTrip(id: id, draft: draft, accountId: accountId))
        } catch {
            throw Rejection(message: "Ton voyage n’a pas pu être gardé sur ton téléphone. Réessaie.")
        }
        storedTrips = await trips.all()

        if isOnline { Task { await flush() } }
        return .local(draft, id: id)
    }

    /// Ce que le serveur a fait du voyage : son code d'accès, ou son refus.
    ///
    /// **Attend** tant que le voyage n'est pas parti — hors ligne, jusqu'au
    /// retour du réseau. Rend `nil` quand la tâche qui attend est annulée :
    /// l'écran a été quitté, le voyage, lui, reste dans la file.
    public func tripSync(for id: String) async -> TripSync? {
        if let created = createdTrips[id] { return .created(created) }

        for await event in tripEvents() where event.tripId == id {
            return event.sync
        }
        return nil
    }

    /// Oublie un voyage que le serveur n'a jamais vu, et ce qu'on y a raconté
    /// en attendant. `false` quand il n'est pas en attente : c'est alors au
    /// serveur de le supprimer.
    public func discardLocalTrip(_ id: String) async -> Bool {
        guard localTrip(id) != nil else { return false }

        await trips.remove(id: id)
        for record in await store.all() where record.tripId == id {
            await store.remove(record)
        }
        storedTrips = await trips.all()
        await refreshCounts()
        return true
    }

    /// **Oublie un tour retenu** (03/10/2026) — « Supprimer », sous une bulle
    /// qui attend l'illimité : sans abonnement, rien ne le ferait jamais
    /// partir, et il resterait sur le disque, compté, sa bulle reposée à
    /// chaque ouverture du fil. La personne l'a demandé, et confirmé.
    ///
    /// Seulement un tour **retenu** — par l'illimité ou par le crédit de
    /// demain : un tour qui n'attend que le réseau peut être en train de
    /// partir, et l'effacer sous un envoi ne le rattraperait pas. `false`
    /// quand il n'y est pas, ou ne l'est plus.
    @discardableResult
    public func discardTurn(id: String) async -> Bool {
        guard let record = await store.all().first(where: { $0.id == id }), record.isOnHold(at: .now) else {
            return false
        }
        await store.remove(record)
        await refreshCounts()
        await scheduleCreditWake()
        return true
    }

    /// L'accueil du serveur, et les voyages qu'il ne connaît pas encore
    /// devant : ils viennent d'être créés — avec leur crédit du jour, plein
    /// (``withFreshCredit(_:isUnlimited:now:)``) : la feuille d'enregistrement
    /// de l'accueil compte et coupe à la limite sur un voyage créé hors ligne
    /// comme sur les autres.
    public func mergingLocalTrips(into feed: HomeFeed) -> HomeFeed {
        let known = Set(feed.trips.map(\.id))
        let waiting = localTrips.filter { !known.contains($0.id) }.map {
            Self.withFreshCredit($0.trip, isUnlimited: feed.traveller.isUnlimited)
        }
        guard !waiting.isEmpty else { return feed }
        return HomeFeed(traveller: feed.traveller, trips: waiting + feed.trips, showcase: feed.showcase)
    }

    /// Un voyage que le serveur n'a jamais vu, avec **son crédit du jour**
    /// (03/10/2026) : plein — rien de ce qu'on y a dit n'est encore arrivé,
    /// et ce qui attend dans la file se décompte à part —, rechargé au minuit
    /// local suivant, illimité si le compte l'est. Un voyage qui porte déjà
    /// un crédit le garde.
    ///
    /// Sans lui, le carnet créé à l'aéroport s'ouvrait sans rien compter : ni
    /// bandeau à 4:30, ni arrêt à 5:00, et un vocal de 6 minutes ne se savait
    /// trop long qu'au retour du réseau. L'objection « un abonné verrait le
    /// bandeau » ne tient pas : l'accueil gardé dit s'il l'est.
    nonisolated static func withFreshCredit(_ trip: Trip, isUnlimited: Bool, now: Date = .now) -> Trip {
        guard trip.dailyCredit == nil else { return trip }
        var trip = trip
        trip.dailyCredit = DailyCredit(isUnlimited: isUnlimited, resetsAt: creditReturns(nil, now: now))
        return trip
    }

    /// Envoie les voyages qui attendent, le plus ancien d'abord. S'arrête au
    /// premier qui ne passe pas : le suivant n'aurait pas plus de chance.
    private func drainTrips() async {
        for waiting in localTrips {
            guard isOnline else { break }

            switch await deliver(waiting.draft) {
            case .created(let created):
                // Retiré **seulement** s'il n'a pas changé pendant l'envoi : une
                // correction faite entre-temps doit partir à son tour.
                await trips.remove(id: waiting.id, ifDraftIs: waiting.draft)
                createdTrips[waiting.id] = created
                // Un serveur d'avant le 01/10 ignore l'identifiant de l'app et
                // en tire un autre : ce qu'on a raconté le suit, au lieu de
                // partir vers un carnet qui n'existe pas — et d'y être perdu.
                if created.trip.id != waiting.id {
                    for var record in await store.all() where record.tripId == waiting.id {
                        record.tripId = created.trip.id
                        try? await store.update(record)
                    }
                }
                publish(TripSyncEvent(tripId: waiting.id, sync: .created(created)))
            case .deferred:
                storedTrips = await trips.all()
                return
            case .rejected(let reason):
                await trips.remove(id: waiting.id)
                let message = "Ton voyage « \(waiting.draft.title) » n’a pas pu être créé. \(reason)"
                rejection = message
                publish(TripSyncEvent(tripId: waiting.id, sync: .rejected(message)))
            }
        }

        storedTrips = await trips.all()
    }

    private func deliver(_ draft: TripDraft) async -> TripOutcome {
        do {
            return .created(try await createTrip(draft))
        } catch {
            switch Self.outcome(for: error) {
            // Une création de voyage ne consomme aucun crédit : un refus de
            // crédit ici ne peut venir que d'un serveur confus — on retentera.
            case .deferred, .waitingForCredit, .waitingForUnlimited: return .deferred
            case .rejected(let reason): return .rejected(reason)
            // L'appel a abouti, la réponse ne s'est pas lue : le voyage existe,
            // mais sans code à montrer. Il se rejoue sans risque — la création
            // reconnaît son identifiant — donc on retentera.
            case .sent: return .deferred
            }
        }
    }

    private enum TripOutcome {
        case created(CreatedTrip)
        case deferred
        case rejected(String)
    }

    private func tripEvents() -> AsyncStream<TripSyncEvent> {
        AsyncStream { continuation in
            let key = UUID()
            tripListeners[key] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in self?.tripListeners[key] = nil }
            }
        }
    }

    private func publish(_ event: TripSyncEvent) {
        for listener in tripListeners.values { listener.yield(event) }
    }

    // MARK: - Entre la file et le disque

    /// La fiche d'un tour, telle qu'elle attend sur le disque.
    nonisolated private static func record(for turn: OutgoingTurn, tripId: String) -> PendingTurn {
        switch turn.body {
        case .text(let text, let suggestionId, let entryId):
            return PendingTurn(
                id: turn.id,
                tripId: tripId,
                kind: .text,
                text: text,
                suggestionId: suggestionId,
                entryId: entryId,
                stepId: turn.stepId,
                recordedAt: .now
            )
        case .voice(let audio):
            return PendingTurn(
                id: turn.id,
                tripId: tripId,
                kind: .voice,
                stepId: turn.stepId,
                filenames: [audio.filename],
                mimeTypes: [audio.mimeType],
                duration: audio.durationSeconds,
                levels: audio.levels,
                placeLabel: audio.placeLabel,
                recordedAt: audio.capturedAt
            )
        case .photos(let photos, let capturedAt):
            return PendingTurn(
                id: turn.id,
                tripId: tripId,
                kind: .photos,
                stepId: turn.stepId,
                filenames: photos.map(\.filename),
                mimeTypes: photos.map(\.mimeType),
                recordedAt: capturedAt
            )
        }
    }

    nonisolated private static func files(of turn: OutgoingTurn) -> [Data] {
        switch turn.body {
        case .text: []
        case .voice(let audio): [audio.data]
        case .photos(let photos, _): photos.map(\.data)
        }
    }

    /// Le tour relu du disque. `nil` quand la fiche ne dit plus ce qu'elle
    /// promettait — une version d'avant sans fichier, par exemple.
    ///
    /// Une attente du crédit **échue** ne se recopie pas : la fiche garde sa
    /// date jusqu'au prochain envoi, mais le tour, lui, n'attend plus rien —
    /// la conversation le rouvre « en cours d'envoi » et le décompte du jour
    /// où il partira, au lieu de « Partira demain » (03/10/2026).
    nonisolated private static func turn(from record: PendingTurn, files: [Data], now: Date = .now) -> OutgoingTurn? {
        let waitingForCreditUntil = record.isWaitingForCredit(at: now) ? record.waitingForCreditUntil : nil
        switch record.kind {
        case .text:
            guard let text = record.text else { return nil }
            return OutgoingTurn(
                id: record.id,
                stepId: record.stepId,
                body: .text(text, suggestionId: record.suggestionId, entryId: record.entryId),
                waitingForCreditUntil: waitingForCreditUntil,
                waitingForUnlimited: record.waitingForUnlimited
            )
        case .voice:
            guard let data = files.first, let filename = record.filenames.first,
                let mimeType = record.mimeTypes.first
            else { return nil }
            return OutgoingTurn(
                id: record.id,
                stepId: record.stepId,
                body: .voice(
                    RecordedTurnAudio(
                        data: data,
                        filename: filename,
                        mimeType: mimeType,
                        capturedAt: record.recordedAt,
                        durationSeconds: record.duration ?? 0,
                        levels: record.levels,
                        placeLabel: record.placeLabel
                    )
                ),
                waitingForCreditUntil: waitingForCreditUntil,
                waitingForUnlimited: record.waitingForUnlimited
            )
        case .photos:
            guard files.count == record.filenames.count, files.count == record.mimeTypes.count, !files.isEmpty
            else { return nil }
            let photos = zip(files, zip(record.filenames, record.mimeTypes)).map { data, names in
                ChatPhotoUpload(data: data, filename: names.0, mimeType: names.1)
            }
            return OutgoingTurn(
                id: record.id,
                stepId: record.stepId,
                body: .photos(photos, capturedAt: record.recordedAt),
                waitingForCreditUntil: waitingForCreditUntil,
                waitingForUnlimited: record.waitingForUnlimited
            )
        }
    }

    /// Ce qu'on écrit quand le serveur a refusé. Le libellé du serveur est
    /// déjà destiné à l'utilisateur — on le reprend plutôt que d'en inventer un.
    nonisolated private static func message(for turn: OutgoingTurn, reason: String) -> String {
        "\(subject(of: turn)) n’a pas pu être envoyé. \(reason)"
    }

    nonisolated private static func subject(of turn: OutgoingTurn) -> String {
        switch turn.body {
        case .text: "Ton message"
        case .voice: "Ton vocal"
        case .photos: "Tes photos"
        }
    }

    private enum Outcome: Sendable {
        case sent(ChatTurnReceipt?)
        case deferred
        /// Refusé faute de crédit du jour : on retentera à `until`.
        case waitingForCredit(until: Date, credit: DailyCredit?)
        /// Plus long qu'une journée de crédit : on attendra l'illimité.
        case waitingForUnlimited(credit: DailyCredit?)
        case rejected(String)
    }

    /// **La** décision de la file : retenter, ou renoncer.
    ///
    /// Elle tient en une question — est-ce que réessayer a une chance ? Une
    /// panne de transport, oui, c'est même exactement ce pour quoi la file
    /// existe. Un 4xx, non : le carnet n'existe plus, le fichier est trop
    /// gros. Garder un tour que le serveur refusera à chaque fois, c'est
    /// promettre une arrivée qui n'aura jamais lieu.
    ///
    /// **Sauf le crédit du jour** (03/10/2026) : réessayer a une chance —
    /// demain. Le tour attend l'heure que le serveur donne (`resetsAt`), et à
    /// défaut le minuit local suivant. Et un tour plus long qu'une journée
    /// (`daily_credit_too_long`) a une chance aussi : l'illimité. Il reste sur
    /// le disque — le jeter, ce serait perdre ce qu'on a raconté.
    ///
    /// Le cas tordu est le décodage : l'appel **a abouti**, c'est la réponse
    /// qu'on n'a pas su lire. Le tour est donc bien arrivé, et le renvoyer
    /// le mettrait deux fois dans le carnet. On le compte comme parti — sans
    /// reçu.
    nonisolated private static func outcome(for error: any Error, now: Date = .now) -> Outcome {
        switch error {
        case let error as APIError:
            switch error {
            case .transport, .notAuthenticated:
                .deferred
            case .dailyCreditExhausted(_, let credit):
                .waitingForCredit(until: creditReturns(credit?.resetsAt, now: now), credit: credit)
            case .server(_, APIError.dailyCreditTooLongCode, _):
                .waitingForUnlimited(credit: nil)
            case .server(let statusCode, _, let message):
                statusCode >= 500 ? .deferred : .rejected(message)
            case .decoding:
                .sent(nil)
            }
        case is URLError, is CancellationError:
            .deferred
        default:
            .rejected(error.localizedDescription)
        }
    }

    /// L'heure à laquelle le crédit revient : celle du serveur quand elle est
    /// à venir, sinon le minuit local qui suit — un `resetsAt` absent ou déjà
    /// passé (horloge du téléphone en avance, serveur d'avant) ne doit ni
    /// bloquer le tour pour toujours, ni le renvoyer en boucle.
    /// Un refus faute de crédit pour ce tour se répétera-t-il **chaque
    /// jour** ? Oui quand il coûte plus qu'une journée entière
    /// (``OutgoingTurn/exceedsAWholeDay(in:)``), ou quand le serveur l'a
    /// refusé pot plein — sa mesure du vocal fait foi, pas la nôtre. Sans
    /// solde rendu, le barème du catalogue.
    nonisolated static func neverFitsADay(_ turn: OutgoingTurn, refusal credit: DailyCredit?) -> Bool {
        if let credit, !credit.isUnlimited, credit.limitMs > 0, credit.remainingMs >= credit.limitMs {
            return turn.creditCost(in: credit) > 0
        }
        return turn.exceedsAWholeDay(in: credit ?? DailyCredit())
    }

    /// Ce tour tient-il dans le reste d'un voyage qui vient d'être refusé ?
    /// Ce qui ne coûte rien — une puce, des photos — part toujours ; le reste
    /// seulement s'il tient dans le solde rendu, le serveur tranchant de
    /// nouveau. Sans solde, rien ne passe qui coûte.
    nonisolated static func fits(_ turn: OutgoingTurn, in credit: DailyCredit?) -> Bool {
        let cost = turn.creditCost(in: credit ?? DailyCredit())
        guard cost > 0 else { return true }
        guard let credit else { return false }
        return cost <= credit.remainingMs
    }

    nonisolated static func creditReturns(
        _ resetsAt: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date {
        if let resetsAt, resetsAt > now { return resetsAt }
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(86_400)
    }
}

/// Ce que le serveur a fait d'un voyage créé sur le téléphone.
public enum TripSync: Sendable, Equatable {
    /// Il existe, et voici son code d'accès.
    case created(CreatedTrip)
    /// Il a été refusé, et le redire ne changerait rien. Le libellé est écrit
    /// pour l'utilisateur.
    case rejected(String)
}

struct TripSyncEvent: Sendable {
    let tripId: String
    let sync: TripSync
}

#if DEBUG

    // MARK: - Bac à sable
    //
    // De quoi jouer le hors-ligne sans couper le wifi du Mac. Ces méthodes
    // n'existent **pas** dans l'app livrée, et le panneau qui les appelle non
    // plus — voir `HomeDebugPanel`.
    //
    // Elles sont dans ce fichier et pas ailleurs parce que l'état de la file
    // est en `private(set)` : Swift n'ouvre cet accès qu'ici. Le bac à sable
    // peut donc poser un état, une vue ne le peut pas.

    extension RecordingOutbox {
        /// Coupe (ou rétablit) le réseau pour l'app entière.
        ///
        /// Ce n'est **pas** un faux affichage : hors ligne, un vocal
        /// enregistré part vraiment sur le disque, et le rétablissement le fait
        /// vraiment repartir. C'est le même chemin que sous un tunnel.
        public func debugSetOffline(_ offline: Bool) {
            forcedOffline = offline
            SandboxNetwork.isOffline.withLock { $0 = offline }
            refreshOnline()
            if isOnline { Task { await flush() } }
        }

        /// Met un vocal en file sans passer par le micro.
        public func debugQueue(_ audio: RecordedAudio, for tripId: String) async {
            _ = await queue(OutgoingTurn.voice(audio, levels: []), for: tripId)
        }

        /// Montre l'envoi en cours, sans rien envoyer.
        public func debugShowSending(_ count: Int) {
            sending += count
            Task {
                try? await Task.sleep(for: .seconds(3))
                sending = max(0, sending - count)
            }
        }

        /// Montre la confirmation d'arrivée, sans rien avoir livré.
        public func debugShowDelivered(_ count: Int) {
            noteDelivery(of: count)
        }

        /// Repart d'une file vide, en ligne, sans message.
        public func debugReset() async {
            forcedOffline = false
            SandboxNetwork.isOffline.withLock { $0 = false }
            refreshOnline()
            confirmation?.cancel()
            justDelivered = nil
            rejection = nil
            sending = 0
            creditWake?.cancel()
            creditWake = nil
            await store.removeAll()
            pending = 0
            waitingForCredit = 0
            waitingForUnlimited = 0
            await trips.removeAll()
            storedTrips = []
        }
    }

#endif

extension OutgoingTurn {
    /// Un tour vocal depuis un enregistrement du micro — l'accueil et la
    /// conversation en font le même.
    public static func voice(
        _ audio: RecordedAudio,
        levels: [Double],
        id: String = UUID().uuidString.lowercased(),
        stepId: String? = nil,
        placeLabel: String? = nil
    ) -> OutgoingTurn {
        OutgoingTurn(
            id: id,
            stepId: stepId,
            body: .voice(
                RecordedTurnAudio(
                    data: audio.data,
                    filename: audio.filename,
                    mimeType: audio.mimeType,
                    capturedAt: audio.recordedAt,
                    durationSeconds: audio.duration,
                    levels: levels,
                    placeLabel: placeLabel
                )
            )
        )
    }
}
