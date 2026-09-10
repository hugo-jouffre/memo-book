import Foundation
import MemoBookNetworking
import MemoBookRecording
import Observation

/// La file de départ des vocaux : ce qui garantit qu'un souvenir raconté hors
/// ligne finit dans le carnet.
///
/// **Elle vit au-dessus des écrans**, dans ``AppDependencies``, et pas dans
/// ``HomeModel`` : un envoi commencé depuis l'accueil doit se terminer même si
/// on file dans son profil pendant ce temps, et un vocal mis de côté dans le
/// métro doit repartir tout seul à la sortie, quel que soit l'écran affiché.
///
/// Elle tient trois choses, et rien d'autre :
///
/// 1. **l'état du réseau** (``Connectivity``), pour savoir s'il faut essayer ;
/// 2. **la file sur le disque** (``PendingRecordingStore``), pour que ce qui
///    n'est pas parti survive à la fermeture de l'app ;
/// 3. **l'envoi lui-même**, une fonction — elle ne connaît pas `MemoBookAPI`,
///    comme les modèles d'écran ne connaissent pas leur route.
///
/// ⚠️ **Un envoi ne survit pas à la mise en arrière-plan.** `URLSession` en
/// tâche de fond serait la réponse complète ; elle demande un envoi par
/// fichier et une délégation, donc une autre forme de client d'API. En
/// attendant, ce qui n'a pas eu le temps de partir reste dans la file et
/// repart au retour dans l'app — rien n'est perdu, c'est juste plus tard.
@MainActor
@Observable
public final class RecordingOutbox {
    /// Ce qu'il est advenu d'un vocal qu'on vient de confier.
    public enum Delivery: Sendable, Equatable {
        /// Il est arrivé dans tous les carnets visés.
        case delivered
        /// Il attend le réseau, sur le disque. Ce n'est **pas** un échec : la
        /// boîte d'information de l'accueil le dit, il n'y a rien à faire.
        case queued
        /// Le serveur a dit non, et le redire ne changerait rien.
        case rejected(String)
    }

    /// Le réseau est disponible. Il part de `true` : tant que le moniteur n'a
    /// pas parlé, on n'affiche pas « hors ligne » à quelqu'un qui ne l'est pas.
    public private(set) var isOnline = true

    /// Combien de vocaux attendent sur le disque.
    public private(set) var pending = 0

    /// Combien de vocaux sont en train de partir. Zéro quand rien n'est en vol.
    public private(set) var sending = 0

    /// Ce que le dernier envoi a fait arriver, le temps de le dire — voir
    /// ``confirmationDelay``. `nil` le reste du temps.
    public private(set) var justDelivered: Int?

    /// Compteur monotone des vocaux arrivés. Il ne sert qu'à une chose : que
    /// l'accueil sache qu'il doit se recharger, parce que ses compteurs et sa
    /// jauge viennent de vieillir.
    public private(set) var deliveries = 0

    /// Un refus **définitif** du serveur, à montrer à l'utilisateur. Ce qui
    /// tient au réseau n'arrive jamais ici : ça retourne dans la file.
    public private(set) var rejection: String?

    private let store: PendingRecordingStore
    private let connectivity: Connectivity
    private let send: @Sendable (RecordedAudio, String) async throws -> Void

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
        send: @escaping @Sendable (RecordedAudio, String) async throws -> Void = { _, _ in }
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

    /// Confie un vocal à un ou plusieurs carnets.
    ///
    /// Hors ligne, il part directement dans la file — on n'essaie même pas, et
    /// on ne fait donc pas attendre quelqu'un devant un échec annoncé. En
    /// ligne, on essaie, et **ce qui échoue au transport retourne dans la
    /// file** : le moniteur dit qu'une interface est montée, pas que l'API
    /// répond.
    @discardableResult
    public func submit(_ audio: RecordedAudio, to tripIds: [String]) async -> Delivery {
        guard !tripIds.isEmpty else { return .delivered }
        rejection = nil

        guard isOnline else { return await queue(audio, for: tripIds) }

        sending += 1
        let attempt = await deliver(audio, to: tripIds)
        sending -= 1

        if !attempt.rejected.isEmpty {
            rejection = message(for: attempt, of: tripIds.count)
        }

        guard attempt.deferred.isEmpty else {
            return await queue(audio, for: attempt.deferred, keepingRejection: true)
        }

        if let message = rejection, attempt.rejected.count == tripIds.count {
            return .rejected(message)
        }

        noteDelivery(of: 1)
        return .delivered
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

            guard let audio = try? await store.audio(for: record) else {
                // Le fichier a disparu sous la fiche : elle ne sert plus à rien.
                await store.remove(record)
                continue
            }

            let attempt = await deliver(audio, to: record.tripIds)

            if !attempt.rejected.isEmpty {
                rejection = message(for: attempt, of: record.tripIds.count)
            }

            if attempt.deferred.isEmpty {
                await store.remove(record)
                if attempt.rejected.count < record.tripIds.count { delivered += 1 }
            } else if attempt.deferred.count == record.tripIds.count {
                // Rien n'est passé : le réseau est reparti. Inutile de faire
                // subir la même attente aux suivants.
                break
            } else {
                var remaining = record
                remaining.tripIds = attempt.deferred
                try? await store.update(remaining)
            }
        }

        pending = await store.count()
        if delivered > 0 { noteDelivery(of: delivered) }
    }

    /// Un vocal, plusieurs carnets, **en même temps** : deux carnets ne font
    /// pas deux fois l'attente. Chaque envoi est indépendant — ce qui passe
    /// passe, et on ne retient que ce qui a manqué.
    private func deliver(_ audio: RecordedAudio, to tripIds: [String]) async -> Attempt {
        let send = send

        let outcomes = await withTaskGroup(of: (String, Outcome).self) { group in
            for tripId in tripIds {
                group.addTask {
                    do {
                        try await send(audio, tripId)
                        return (tripId, .sent)
                    } catch {
                        return (tripId, Self.outcome(for: error))
                    }
                }
            }

            var collected: [(String, Outcome)] = []
            for await outcome in group { collected.append(outcome) }
            return collected
        }

        var attempt = Attempt()
        for (tripId, outcome) in outcomes {
            switch outcome {
            case .sent: break
            case .deferred: attempt.deferred.append(tripId)
            case .rejected(let reason):
                attempt.rejected.append(tripId)
                attempt.reason = attempt.reason ?? reason
            }
        }
        return attempt
    }

    private func queue(
        _ audio: RecordedAudio,
        for tripIds: [String],
        keepingRejection: Bool = false
    ) async -> Delivery {
        do {
            try await store.enqueue(audio, for: tripIds)
            pending = await store.count()
            return .queued
        } catch {
            // Le disque a refusé : c'est le seul cas où un vocal se perd, et il
            // faut le dire tout de suite — la personne peut encore recommencer.
            let message = "Ton vocal n’a pas pu être gardé sur ton téléphone. Réessaie."
            if !keepingRejection { rejection = message }
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

    /// Ce qu'on écrit quand le serveur a refusé. Le libellé du serveur est
    /// déjà destiné à l'utilisateur — on le reprend plutôt que d'en inventer un.
    private func message(for attempt: Attempt, of total: Int) -> String {
        let reason = attempt.reason.map { " \($0)" } ?? ""

        return attempt.rejected.count == total
            ? "Ton vocal n’a pas pu être envoyé.\(reason)"
            : "Ton vocal n’a pas pu être ajouté à \(attempt.rejected.count) de tes carnets.\(reason)"
    }

    /// Ce qu'un envoi a laissé derrière lui.
    private struct Attempt {
        /// À retenter : le réseau a manqué.
        var deferred: [String] = []
        /// À oublier : le serveur a dit non.
        var rejected: [String] = []
        var reason: String?
    }

    private enum Outcome: Sendable {
        case sent
        case deferred
        case rejected(String)
    }

    /// **La** décision de la file : retenter, ou renoncer.
    ///
    /// Elle tient en une question — est-ce que réessayer a une chance ? Une
    /// panne de transport, oui, c'est même exactement ce pour quoi la file
    /// existe. Un 4xx, non : le carnet n'existe plus, le quota est atteint, le
    /// fichier est trop gros. Garder un vocal que le serveur refusera à chaque
    /// fois, c'est promettre une arrivée qui n'aura jamais lieu.
    ///
    /// Le cas tordu est le décodage : l'appel **a abouti**, c'est la réponse
    /// qu'on n'a pas su lire. Le souvenir est donc bien arrivé, et le renvoyer
    /// le mettrait deux fois dans le carnet. On le compte comme parti.
    nonisolated private static func outcome(for error: any Error) -> Outcome {
        switch error {
        case let error as APIError:
            switch error {
            case .transport, .notAuthenticated:
                .deferred
            case .server(let statusCode, _, let message):
                statusCode >= 500 ? .deferred : .rejected(message)
            case .decoding:
                .sent
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
        public func debugQueue(_ audio: RecordedAudio, for tripIds: [String]) async {
            _ = await queue(audio, for: tripIds)
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
