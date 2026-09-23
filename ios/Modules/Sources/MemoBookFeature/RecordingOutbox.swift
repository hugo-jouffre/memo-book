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
/// Elle tient trois choses, et rien d'autre :
///
/// 1. **l'état du réseau** (``Connectivity``), pour savoir s'il faut essayer ;
/// 2. **la file sur le disque** (``PendingRecordingStore``), pour que ce qui
///    n'est pas parti survive à la fermeture de l'app ;
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
        case queued
        /// Le serveur a dit non, et le redire ne changerait rien.
        case rejected(String)
    }

    /// Le réseau est disponible. Il part de `true` : tant que le moniteur n'a
    /// pas parlé, on n'affiche pas « hors ligne » à quelqu'un qui ne l'est pas.
    public private(set) var isOnline = true

    /// Combien de tours attendent sur le disque.
    public private(set) var pending = 0

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
    /// déjà écrit pour l'utilisateur.
    public struct Rejection: LocalizedError, Sendable, Hashable {
        public let message: String
        public var errorDescription: String? { message }
    }

    private let store: PendingRecordingStore
    private let connectivity: Connectivity
    private let send: @Sendable (OutgoingTurn, String) async throws -> ChatTurnReceipt

    /// Les conversations à l'écoute — voir ``turnDeliveries()``.
    private var listeners: [UUID: AsyncStream<ChatTurnDelivery>.Continuation] = [:]

    private var monitor: Task<Void, Never>?
    private var flushing: Task<Void, Never>?
    private var confirmation: Task<Void, Never>?

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
        connectivity: Connectivity = .online,
        send: @escaping @Sendable (OutgoingTurn, String) async throws -> ChatTurnReceipt = { _, _ in
            ChatTurnReceipt(messages: [], turn: .idle, now: .now)
        }
    ) {
        self.store = store
        self.connectivity = connectivity
        self.send = send
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
            pending = await store.count()

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
    public func turnDeliveries() -> AsyncStream<ChatTurnDelivery> {
        AsyncStream { continuation in
            let key = UUID()
            if let lastDelivery { continuation.yield(lastDelivery) }
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
        guard isOnline else { return await queue(turn, for: tripId) }

        sending += 1
        let outcome = await deliver(turn, to: tripId)
        sending -= 1

        switch outcome {
        case .sent(let receipt):
            noteDelivery(of: 1)
            return .delivered(receipt)
        case .deferred:
            return await queue(turn, for: tripId)
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
        if let flushing { return await flushing.value }

        let task = Task { await drain() }
        flushing = task
        await task.value
        flushing = nil
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

        let waiting = await store.all()
        pending = waiting.count
        guard !waiting.isEmpty else { return }

        sending += waiting.count
        defer { sending -= waiting.count }

        var delivered = 0

        for record in waiting {
            guard isOnline else { break }

            guard let files = try? await store.files(for: record),
                let turn = Self.turn(from: record, files: files)
            else {
                // Le fichier a disparu sous la fiche : elle ne sert plus à rien.
                await store.remove(record)
                continue
            }

            switch await deliver(turn, to: record.tripId) {
            case .sent(let receipt):
                await store.remove(record)
                delivered += 1
                note(.delivered(receipt), of: record.id, to: record.tripId)
            case .rejected(let reason):
                await store.remove(record)
                let message = Self.message(for: turn, reason: reason)
                rejection = message
                note(.rejected(message), of: record.id, to: record.tripId)
            case .deferred:
                // Rien n'est passé : le réseau est reparti. Inutile de faire
                // subir la même attente aux suivants.
                pending = await store.count()
                return
            }
        }

        pending = await store.count()
        if delivered > 0 { noteDelivery(of: delivered) }
    }

    private func deliver(_ turn: OutgoingTurn, to tripId: String) async -> Outcome {
        do {
            return .sent(try await send(turn, tripId))
        } catch {
            return Self.outcome(for: error)
        }
    }

    private func queue(_ turn: OutgoingTurn, for tripId: String) async -> Delivery {
        do {
            try await store.enqueue(Self.record(for: turn, tripId: tripId), files: Self.files(of: turn))
            pending = await store.count()
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
    nonisolated private static func turn(from record: PendingTurn, files: [Data]) -> OutgoingTurn? {
        switch record.kind {
        case .text:
            guard let text = record.text else { return nil }
            return OutgoingTurn(
                id: record.id,
                stepId: record.stepId,
                body: .text(text, suggestionId: record.suggestionId, entryId: record.entryId)
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
                )
            )
        case .photos:
            guard files.count == record.filenames.count, files.count == record.mimeTypes.count, !files.isEmpty
            else { return nil }
            let photos = zip(files, zip(record.filenames, record.mimeTypes)).map { data, names in
                ChatPhotoUpload(data: data, filename: names.0, mimeType: names.1)
            }
            return OutgoingTurn(id: record.id, stepId: record.stepId, body: .photos(photos, capturedAt: record.recordedAt))
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
        case rejected(String)
    }

    /// **La** décision de la file : retenter, ou renoncer.
    ///
    /// Elle tient en une question — est-ce que réessayer a une chance ? Une
    /// panne de transport, oui, c'est même exactement ce pour quoi la file
    /// existe. Un 4xx, non : le carnet n'existe plus, le quota est atteint, le
    /// fichier est trop gros. Garder un tour que le serveur refusera à chaque
    /// fois, c'est promettre une arrivée qui n'aura jamais lieu.
    ///
    /// Le cas tordu est le décodage : l'appel **a abouti**, c'est la réponse
    /// qu'on n'a pas su lire. Le tour est donc bien arrivé, et le renvoyer
    /// le mettrait deux fois dans le carnet. On le compte comme parti — sans
    /// reçu.
    nonisolated private static func outcome(for error: any Error) -> Outcome {
        switch error {
        case let error as APIError:
            switch error {
            case .transport, .notAuthenticated:
                .deferred
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
            refreshOnline()
            confirmation?.cancel()
            justDelivered = nil
            rejection = nil
            sending = 0
            await store.removeAll()
            pending = 0
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
