import Foundation
import MemoBookCore
import MemoBookRecording
import Observation
import UIKit

/// Où en est le tour de parole en cours.
///
/// **Un seul état, porté par l'identifiant de la bulle concernée.** La vue ne
/// tient pas de second état parallèle : c'est ce qui garantit qu'un échec ne
/// puisse pas laisser l'indicateur d'attente allumé pendant que le composeur se
/// croit disponible.
public enum ChatTurnState: Sendable, Hashable {
    /// Rien en vol. Le composeur est ouvert, les suggestions sont là.
    case idle

    /// La bulle du voyageur est posée, l'envoi n'est pas confirmé.
    case sending(messageId: String)

    /// MEMO réfléchit. Trois points qui respirent à gauche, à la place de la
    /// bulle qui vient — jamais un `ProgressView` centré, qui ferait sauter le
    /// fil.
    case thinking

    /// Échec. La bulle du voyageur reste, marquée « Non envoyé », et le tour est
    /// rejouable tel quel.
    case failed(messageId: String, message: String)
}

/// Ce que la barre d'envoi propose.
///
/// Trois modes et pas quatre : « en train d'enregistrer » se lit sur
/// ``AudioRecorder/isRecording`` et n'a pas à être dupliqué ici — deux sources
/// pour le même fait finissent toujours par se contredire.
public enum ChatComposerMode: Sendable, Hashable {
    /// Les trois commandes de la maquette : photo, clavier, micro.
    case tools

    /// Le champ de saisie est ouvert.
    case writing

    /// Le micro est armé : le bouton « Record » occupe la barre.
    case speaking
}

/// Ce que l'écran de chat sait faire : charger sa conversation, envoyer ce que
/// le voyageur raconte, et laisser MEMO répondre — `docs/conversation.md`.
///
/// **Même construction que ``HomeModel``, ``TripHomeModel`` et
/// ``ProfileModel``** : le modèle ne connaît pas l'API, il reçoit un
/// ``ChatTransport`` — cinq fonctions-sources — et ne sait pas si derrière il
/// y a le serveur ou le moteur local des aperçus. Un seul chemin de code, deux
/// transports.
///
/// **Tout le déroulé d'un tour est ici, jamais dans la vue.** La bulle du
/// voyageur se pose avant le réseau et passe « envoyée » dès le reçu du
/// serveur ; MEMO répond dans un job, que le modèle **sonde** toutes les deux
/// secondes tant qu'un tour est en vol ou qu'une fiche n'est pas prête ; ses
/// bulles arrivent une par une, chacune après le silence que le serveur a
/// décidé pour elle, avec l'indicateur qui se rallume entre deux ; un échec
/// garde le message pour qu'on puisse le renvoyer, sous le **même**
/// identifiant. Une vue qui aurait à orchestrer ça se remettrait à clignoter
/// au premier refactoring.
@MainActor
@Observable
public final class ChatModel {
    public private(set) var thread: ChatThread?
    public private(set) var errorMessage: String?
    public private(set) var turn: ChatTurnState = .idle

    /// L'enregistrement a été refusé par iOS. La demande ne se présente qu'une
    /// fois : le seul recours est l'app Réglages, et l'écran doit le dire au
    /// lieu de redemander en boucle.
    public private(set) var microphoneIsDenied = RecordingPermission.current == .denied

    /// Le message dont le texte vient d'être copié. Il porte la coche verte
    /// pendant une seconde — voir ``copy(_:)``.
    public private(set) var copiedMessageId: String?

    public var composer: ChatComposerMode = .tools
    public var draft: String = ""

    /// Le brouillon est une retranscription qu'on corrige, et non un message
    /// qu'on écrit. Le champ s'y étire plus haut — corriger un texte de
    /// cinquante mots demande de le **lire**, et six lignes en cachent la
    /// moitié. Retombe à faux dès que le brouillon part ou se jette.
    public private(set) var isEditingTranscript = false

    /// Le souvenir que le brouillon corrige — « à la main ». Envoyer le
    /// brouillon passe alors par ``ChatTransport/editTranscript`` et non par
    /// un nouveau message : la fiche change, le fil n'en gagne pas une copie.
    private var editingEntryId: String?

    public let recorder = AudioRecorder()
    public let player = AudioNotePlayer()
    public let reader = SpeechReader()

    private let transport: ChatTransport

    /// Le curseur du sondage : le `now` de la dernière lecture, en temps
    /// **serveur** — jamais l'horloge du téléphone, qui peut être fausse.
    private var cursor: Date?

    /// Les niveaux du micro, accumulés pendant qu'on parle.
    ///
    /// ``AudioRecorder`` ne publie qu'un niveau **instantané** : sans cette
    /// collecte, la forme d'onde d'un vocal terminé n'aurait aucune donnée et
    /// il faudrait en dessiner une fausse. C'est la seule raison de cette
    /// boucle.
    public private(set) var capturedLevels: [Double] = []
    private var levelSampler: Task<Void, Never>?

    private var exchange: Task<Void, Never>?
    private var poller: Task<Void, Never>?

    /// Le tour dont l'envoi a échoué. ``retry()`` le renvoie **tel quel**, sous
    /// le même identifiant : le serveur reconnaît un renvoi et ne crée pas un
    /// second souvenir.
    private var pending: OutgoingTurn?

    /// L'écoute de la file — voir ``markDelivery(_:)``. Une tâche, qui meurt
    /// avec l'écran.
    private var deliveryWatcher: Task<Void, Never>?

    /// Le dernier mot de la file, gardé au cas où il arrive **avant** le fil —
    /// l'écran s'ouvre pendant que le vocal de l'accueil part. Il est rejoué
    /// dès que le fil est là.
    private var latestDelivery: ChatTurnDelivery?

    /// - Parameters:
    ///   - transport: ce qui relie le modèle au monde — le serveur, ou le
    ///     moteur local des aperçus. Voir ``ChatTransport``.
    ///   - focusStepId: l'étape sur laquelle le fil s'ouvre, quand on vient
    ///     d'une carte d'étape.
    public init(transport: ChatTransport, focusStepId: String? = nil) {
        self.transport = transport
        self.focusStepId = focusStepId
    }

    /// L'étape sur laquelle le fil s'est ouvert, quand on vient d'une carte
    /// d'étape.
    public private(set) var focusStepId: String?

    /// L'étape à laquelle rattacher un nouveau message : celle qu'on est venu
    /// voir, ou à défaut celle où le voyage en est.
    private var activeStepId: String? {
        focusStepId ?? thread?.context.stepId
    }

    /// Le silence minimal avant une bulle de MEMO. Sans lui, une réponse
    /// arriverait dans la même image que le message du voyageur : c'est le
    /// premier signe qu'il n'y a personne en face.
    private static let minimumThinking = Duration.milliseconds(450)

    /// La cadence du sondage, et le moment où il renonce : le motif de la
    /// feuille Statistiques — pas de connexion ouverte, pas de minuterie
    /// globale, une tâche qui meurt avec l'écran.
    private static let pollingInterval = Duration.seconds(2)
    private static let pollingGivesUpAfter = 90  // × 2 s = trois minutes sans changement

    // MARK: - Charger

    /// `true` tant qu'on n'a rien à montrer. L'écran dessine alors son
    /// squelette plutôt qu'une demi-conversation.
    public var isLoading: Bool { thread == nil && errorMessage == nil }

    public func load() async {
        do {
            let loaded = try await transport.load()
            thread = loaded
            cursor = loaded.now
            errorMessage = nil

            // Le serveur dit si un tour est encore en vol — on l'a quitté au
            // milieu d'une réponse, ou un co-voyageur vient de parler.
            turn = loaded.turn.isReplying ? .thinking : .idle
            if needsPolling { startPolling() }

            // Relu à chaque ouverture : l'accès peut avoir été retiré depuis
            // les Réglages pendant que l'app était en arrière-plan.
            microphoneIsDenied = RecordingPermission.current == .denied

            // Le vocal de l'accueil, s'il y en a un, se pose maintenant — il
            // fallait un fil pour l'y poser. Une fois, et une seule.
            if let handoff = pendingHandoff {
                pendingHandoff = nil
                receive(handoff)
            }

            // Ce qui attend le réseau sur le disque pour ce fil se pose en
            // bulles « en cours d'envoi » : on a quitté l'écran sur un texte
            // dit dans le métro, il est encore là quand on revient.
            for turn in await transport.waiting() where !messages.contains(where: { $0.id == turn.id }) {
                keepLocalFiles(of: turn)
                append(optimisticMessage(for: turn))
            }

            // Et si la file a parlé pendant qu'on chargeait, on l'écoute
            // maintenant — puis on l'écoute tout court.
            if let latestDelivery { markDelivery(latestDelivery) }
            watchDeliveries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Suit ce que la file fait des tours partis par elle — le vocal de
    /// l'accueil, un message d'ici qui attendait le réseau. Une seule écoute à
    /// la fois ; elle repart avec le prochain chargement quand l'écran revient.
    private func watchDeliveries() {
        guard deliveryWatcher == nil else { return }
        deliveryWatcher = Task { [weak self] in
            guard let transport = self?.transport else { return }
            for await delivery in await transport.deliveries() {
                guard !Task.isCancelled, let self else { return }
                self.markDelivery(delivery)
            }
        }
    }

    /// Tout arrêter en quittant l'écran : la lecture, la voix de synthèse, le
    /// tour en vol, le sondage, l'écoute de la file et la collecte de niveaux.
    /// Un écran de chat laissé derrière soi ne doit ni parler ni enregistrer.
    public func teardown() {
        exchange?.cancel()
        exchange = nil
        poller?.cancel()
        poller = nil
        deliveryWatcher?.cancel()
        deliveryWatcher = nil
        levelSampler?.cancel()
        player.stop()
        reader.stop()
        recorder.cancel()
    }

    // MARK: - Ce que la vue lit

    public var messages: [ChatMessage] { thread?.messages ?? [] }

    public var suggestions: [ChatSuggestion] { thread?.suggestions ?? [] }

    public var isThinking: Bool { turn == .thinking }

    /// Le composeur reste utilisable en cas d'échec : on ne piège personne
    /// derrière un message qui ne passe pas.
    public var isComposerEnabled: Bool {
        switch turn {
        case .idle, .failed: true
        case .sending, .thinking: false
        }
    }

    /// Les suggestions ne s'affichent qu'au repos. Un rail encore tapable
    /// pendant que MEMO réfléchit invite au double envoi.
    public var visibleSuggestions: [ChatSuggestion] {
        turn == .idle ? suggestions : []
    }

    public var canSendDraft: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isComposerEnabled
    }

    // MARK: - Envoyer

    public func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        isEditingTranscript = false

        // « À la main » : la correction va au souvenir, pas dans le fil.
        if let entryId = editingEntryId {
            editingEntryId = nil
            submitTranscriptEdit(entryId: entryId, text: text)
            return
        }

        send(.text(text))
    }

    /// Referme l'outil ouvert et ramène la barre à ses trois boutons.
    ///
    /// C'est la croix qui remplace le burger. Elle **jette** un enregistrement
    /// en cours : c'est le seul geste de la barre qui puisse perdre quelque
    /// chose, et c'est aussi ce qu'on attend d'une croix — sinon elle
    /// laisserait le micro tourner derrière une barre au repos.
    public func collapseComposer() {
        if recorder.isRecording {
            cancelRecording()
        }
        draft = ""
        isEditingTranscript = false
        editingEntryId = nil
        composer = .tools
    }

    /// iOS ne présente la demande d'accès **qu'une fois** : après un refus, le
    /// seul recours est l'app Réglages. Le bouton micro barré y mène.
    public func openMicrophoneSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Ce qu'une puce de suggestion déclenche.
    ///
    /// Elle **envoie son libellé** comme un message — la maquette la montre bien
    /// posée en bulle bleue dans le fil — et ouvre en plus l'outil qui va avec.
    /// Le serveur reçoit aussi son identifiant : c'est lui qui dit qu'une puce
    /// est une commande, sans modèle et sans souvenir. Seul l'import de photos
    /// n'envoie rien : on ne dit pas « j'importe des photos », on les importe.
    public func choose(_ suggestion: ChatSuggestion, addPhotos: () -> Void) {
        switch suggestion.intent {
        case .importPhotos:
            addPhotos()
        case .send, .unknown:
            composer = .tools
            // « Ça me convient » vise la dernière fiche du fil : c'est elle
            // que le serveur valide, dans la même requête.
            let entryId = suggestion.id == "accept" ? latestTranscriptCard?.entryId : nil
            send(.text(suggestion.label, suggestionId: suggestion.id, entryId: entryId))
        case .sendThenWrite:
            composer = .writing
            send(.text(suggestion.label, suggestionId: suggestion.id))
        case .sendThenEditTranscript:
            // Le texte de la fiche est posé dans le champ **avant** d'envoyer
            // la puce : la bulle bleue part, MEMO répond « je te laisse la
            // main », et le voyageur a déjà le texte sous les doigts. S'il n'y
            // a aucune fiche remplie — la puce vient du serveur sous un tour
            // qui n'en a pas —, le champ s'ouvre simplement vide.
            if let card = latestTranscriptCard, let text = card.text, !text.isEmpty {
                draft = text
                isEditingTranscript = true
                editingEntryId = card.entryId
            }
            composer = .writing
            send(.text(suggestion.label, suggestionId: suggestion.id))
        case .sendThenSpeak:
            composer = .speaking
            send(.text(suggestion.label, suggestionId: suggestion.id))
        }
    }

    /// Pose la bulle du voyageur et lance le tour.
    ///
    /// - Parameter id: l'identifiant de la bulle, quand il vient d'ailleurs —
    ///   le vocal de l'accueil porte le sien. Sinon un UUID, qui sera aussi
    ///   celui du message côté serveur.
    private func send(_ body: OutgoingTurn.Body, id: String = UUID().uuidString.lowercased()) {
        guard thread != nil else { return }

        let outgoing = OutgoingTurn(id: id, stepId: activeStepId, body: body)
        append(optimisticMessage(for: outgoing))
        start(outgoing)
    }

    /// La bulle bleue telle qu'elle se dessine avant le reçu du serveur. Le
    /// serveur la remplacera par la sienne, sous le même identifiant — sans
    /// perdre le fichier local d'un vocal ou d'une photo.
    private func optimisticMessage(for outgoing: OutgoingTurn) -> ChatMessage {
        let body: ChatMessageBody
        switch outgoing.body {
        case .text(let text, _, _):
            body = .text(text)
        case .voice(let audio):
            body = .voice(
                VoiceNote(
                    id: outgoing.id,
                    duration: audio.durationSeconds,
                    levels: audio.levels,
                    localUrl: localVoiceUrls[outgoing.id]
                )
            )
        case .photos(let photos, _):
            body = .photos(
                photos.indices.map { index in
                    let id = "\(outgoing.id)-\(index)"
                    return PhotoAttachment(id: id, localUrl: localPhotoUrls[id])
                }
            )
        }
        return ChatMessage(
            id: outgoing.id,
            author: .traveller,
            body: body,
            sentAt: .now,
            stepId: outgoing.stepId,
            delivery: .sending
        )
    }

    /// Les fichiers écrits dans les caches pour ce qu'on vient d'envoyer, par
    /// identifiant — ce que le serveur ne rend jamais et qu'on ne veut pas
    /// perdre en fusionnant sa réponse.
    private var localVoiceUrls: [String: URL] = [:]
    private var localPhotoUrls: [String: URL] = [:]

    /// « Réessayer » sous la bulle : le tour repart **tel quel**, sous le même
    /// identifiant. Celui dont l'envoi vient d'échouer ici ; sinon celui que
    /// la file a vu refuser — rebâti depuis la bulle et ses fichiers locaux,
    /// puisque la file l'a déjà oublié.
    public func retry() {
        guard let turn = pending ?? refusedTurn() else { return }
        mark(turn.id, as: .sending)
        start(turn)
    }

    private func refusedTurn() -> OutgoingTurn? {
        guard let message = messages.last(where: { $0.author.isTraveller && $0.delivery.hasFailed }) else { return nil }
        return outgoingTurn(from: message)
    }

    /// Le tour qu'une bulle du voyageur représente, avec ses octets relus des
    /// caches. `nil` quand ils n'y sont plus : il n'y a alors rien à renvoyer.
    private func outgoingTurn(from message: ChatMessage) -> OutgoingTurn? {
        switch message.body {
        case .text(let text):
            return OutgoingTurn(id: message.id, stepId: message.stepId, body: .text(text))
        case .voice(let note):
            guard let url = note.localUrl, let data = try? Data(contentsOf: url) else { return nil }
            return OutgoingTurn(
                id: message.id,
                stepId: message.stepId,
                body: .voice(
                    RecordedTurnAudio(
                        data: data,
                        filename: "\(message.id).m4a",
                        mimeType: "audio/mp4",
                        capturedAt: message.sentAt,
                        durationSeconds: note.duration,
                        levels: note.levels,
                        placeLabel: thread?.context.placeName
                    )
                )
            )
        case .photos(let attachments):
            let photos = attachments.compactMap { attachment -> ChatPhotoUpload? in
                guard let url = attachment.localUrl, let data = try? Data(contentsOf: url) else { return nil }
                return ChatPhotoUpload(data: data, filename: "\(attachment.id).jpg", mimeType: "image/jpeg")
            }
            guard !photos.isEmpty, photos.count == attachments.count else { return nil }
            return OutgoingTurn(id: message.id, stepId: message.stepId, body: .photos(photos, capturedAt: message.sentAt))
        case .transcript:
            return nil
        }
    }

    // MARK: - Le tour de parole

    private func start(_ outgoing: OutgoingTurn) {
        pending = outgoing
        exchange?.cancel()
        exchange = Task { await run(outgoing) }
    }

    private func run(_ outgoing: OutgoingTurn) async {
        guard var thread else { return }

        // Les suggestions du tour précédent ne veulent plus rien dire.
        thread.suggestions = []
        self.thread = thread

        turn = .sending(messageId: outgoing.id)

        do {
            let outcome = try await transport.send(outgoing)
            try Task.checkCancellation()
            pending = nil

            switch outcome {
            case .received(let receipt):
                accept(receipt, for: outgoing.id)
            case .queued:
                // Le tour attend le réseau sur le disque. Ce n'est pas un
                // échec : la bulle reste « en cours d'envoi », le composeur se
                // rouvre, et c'est la file qui la terminera — par son
                // identifiant, voir ``markDelivery(_:)``.
                turn = .idle
            }
        } catch is CancellationError {
            // L'écran s'est refermé, ou un nouveau tour a démarré. Rien à dire.
            turn = .idle
        } catch {
            mark(outgoing.id, as: .failed(error.localizedDescription))
            turn = .failed(messageId: outgoing.id, message: error.localizedDescription)
        }
        exchange = nil
    }

    /// Ce que le serveur a écrit en recevant un tour : la bulle du voyageur
    /// avec son rang, l'ouverture de MEMO si elle vient d'être posée, la fiche
    /// d'un vocal. On fusionne ; on ne remplace pas le fil.
    ///
    /// Le curseur ne recule jamais : un reçu arrivé en retard — un tour parti
    /// de la file après une lecture plus récente — ne fait pas relire ce qu'on
    /// a déjà.
    private func accept(_ receipt: ChatTurnReceipt, for id: String) {
        merge(receipt.messages)
        mark(id, as: .sent)
        cursor = max(cursor ?? .distantPast, receipt.now)

        if receipt.turn.isReplying {
            turn = .thinking
        } else if owns(id) {
            turn = .idle
        }
        if needsPolling { startPolling() }
    }

    /// Le tour en cours est celui de cette bulle. Un reçu venu de la file pour
    /// un tour d'hier ne doit pas rouvrir le composeur pendant qu'un autre part.
    private func owns(_ id: String) -> Bool {
        switch turn {
        case .sending(let messageId), .failed(let messageId, _): messageId == id
        case .idle, .thinking: false
        }
    }

    // MARK: - Le sondage

    /// Tant qu'un tour est en vol, ou qu'une fiche attend sa transcription ou
    /// sa rédaction.
    private var needsPolling: Bool {
        if turn == .thinking { return true }
        return messages.contains { message in
            if case .transcript(let card) = message.body { return card.isSettling || card.text == nil }
            return false
        }
    }

    /// Une tâche, et une seule : relire la suite du fil toutes les deux
    /// secondes, jouer ce qui arrive, s'arrêter dès qu'il n'y a plus rien à
    /// attendre ou après trois minutes sans changement.
    private func startPolling() {
        guard poller == nil else { return }
        poller = Task { [weak self] in
            var quietTicks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollingInterval)
                guard !Task.isCancelled, let self else { return }
                guard self.needsPolling else { break }

                do {
                    let update = try await self.transport.poll(self.cursor ?? .distantPast)
                    try Task.checkCancellation()
                    let changed = await self.apply(update)
                    quietTicks = changed ? 0 : quietTicks + 1
                } catch is CancellationError {
                    return
                } catch {
                    // Un sondage qui rate n'est pas une erreur d'écran : on
                    // réessaie au tour suivant, et on renonce comme un fil
                    // silencieux.
                    quietTicks += 1
                }

                if quietTicks >= Self.pollingGivesUpAfter { break }
            }
            guard let self else { return }
            self.poller = nil
            // On renonce sans réponse : le composeur se rouvre, le fil ne
            // ment pas — MEMO n'a simplement pas répondu à temps.
            if self.turn == .thinking { self.turn = .idle }
        }
    }

    /// Fusionne la suite du fil. Les bulles d'un co-voyageur et les fiches
    /// mises à jour entrent tout de suite ; les bulles de MEMO **une par une,
    /// rythmées** par le silence que le serveur a décidé — c'est ce qui les
    /// fait arriver comme une réponse et non comme un chargement.
    ///
    /// - Returns: `true` si quelque chose a changé.
    private func apply(_ update: ChatThreadUpdate) async -> Bool {
        cursor = update.now

        var arrivals: [ChatMessage] = []
        var changed = false

        for message in update.messages.sorted(by: Self.byRank) {
            if messages.contains(where: { $0.id == message.id }) {
                replace(message)
                changed = true
            } else if message.author.isTraveller {
                insert(message)
                changed = true
            } else {
                arrivals.append(message)
            }
        }

        for bubble in arrivals {
            turn = .thinking
            let pause = Duration.milliseconds(bubble.pauseMilliseconds ?? 700)
            try? await Task.sleep(for: max(pause, Self.minimumThinking))
            if Task.isCancelled { return changed }
            insert(bubble)
            changed = true
        }

        if let preview = update.preview { thread?.preview = preview }

        if update.turn.isReplying {
            turn = .thinking
        } else if turn == .thinking {
            thread?.suggestions = update.suggestions
            turn = .idle
        } else if turn == .idle, !update.suggestions.isEmpty {
            thread?.suggestions = update.suggestions
        }

        return changed
    }

    // MARK: - Le fil

    /// L'ordre du serveur d'abord ; ce qui n'en a pas encore — une bulle
    /// optimiste — reste en bas, où il est.
    private static func byRank(_ a: ChatMessage, _ b: ChatMessage) -> Bool {
        (a.seq ?? Int.max) < (b.seq ?? Int.max)
    }

    private func merge(_ received: [ChatMessage]) {
        for message in received.sorted(by: Self.byRank) {
            if messages.contains(where: { $0.id == message.id }) {
                replace(message)
            } else {
                insert(message)
            }
        }
    }

    private func insert(_ message: ChatMessage) {
        guard var thread else { return }
        thread.messages.append(message)
        thread.messages.sort(by: Self.byRank)
        self.thread = thread
    }

    /// Remplace par identifiant, en gardant ce que l'app seule sait : le
    /// fichier local. L'état d'envoi, lui, est celui du serveur — un message
    /// qu'il rend est un message qu'il a : une bulle restée « en cours
    /// d'envoi » parce qu'on a raté le mot de la file se répare au sondage
    /// suivant.
    private func replace(_ message: ChatMessage) {
        guard var thread, let index = thread.messages.firstIndex(where: { $0.id == message.id }) else { return }
        thread.messages[index] = message.keepingLocalFiles(of: thread.messages[index])
        thread.messages.sort(by: Self.byRank)
        self.thread = thread
    }

    // MARK: - « À la main »

    /// La correction part au souvenir ; la fiche se redessine avec elle ; puis
    /// une commande silencieuse fait accuser réception à MEMO — sans modèle,
    /// sans souvenir de plus.
    private func submitTranscriptEdit(entryId: String, text: String) {
        exchange?.cancel()
        turn = .sending(messageId: entryId)
        exchange = Task {
            do {
                let entry = try await transport.editTranscript(entryId, text)
                try Task.checkCancellation()
                refreshCard(for: entry)
                turn = .idle
                send(.text(ChatCopy.editedByHand, suggestionId: "transcript_edited", entryId: entryId))
            } catch is CancellationError {
                turn = .idle
            } catch {
                errorMessage = error.localizedDescription
                turn = .idle
            }
        }
    }

    /// La fiche d'un souvenir, une fois le serveur repassé dessus.
    private func refreshCard(for entry: Entry) {
        guard var thread else { return }
        for index in thread.messages.indices {
            guard case .transcript(let card) = thread.messages[index].body, card.entryId == entry.id else { continue }
            thread.messages[index].body = .transcript(
                TranscriptCard(
                    title: card.title,
                    capturedAt: entry.capturedAt,
                    placeLabel: entry.placeLabel ?? card.placeLabel,
                    duration: card.duration,
                    text: entry.displayText ?? card.text,
                    isSimulated: false,
                    entryId: entry.id,
                    footnote: card.footnote,
                    phase: .ready,
                    isValidated: entry.validatedAt != nil || card.isValidated
                )
            )
        }
        self.thread = thread
    }

    // MARK: - Le vocal

    /// Le vocal enregistré depuis l'accueil, en attendant que le fil soit là
    /// pour le recevoir. Voir ``RecordingHandoff``.
    private var pendingHandoff: RecordingHandoff?

    /// Annonce un vocal venu de l'accueil. Il sera posé dans le fil au
    /// chargement, exactement comme s'il avait été dit ici : même bulle, même
    /// forme d'onde.
    public func expect(_ handoff: RecordingHandoff) {
        pendingHandoff = handoff
    }

    /// Pose un vocal déjà enregistré, **sans l'envoyer** : il est parti avant
    /// que cet écran n'existe, par la file de l'accueil, et c'est elle qui
    /// dira où il en est — par ``markDelivery(_:)``. Le fichier est gardé pour
    /// la réécoute.
    ///
    /// S'il est déjà dans le fil — le serveur l'a reçu avant qu'on ait fini de
    /// charger —, la bulle du serveur reste, et ne gagne que le fichier local.
    private func receive(_ handoff: RecordingHandoff) {
        let url = try? VoiceNoteFile.save(handoff.audio, id: handoff.id)
        localVoiceUrls[handoff.id] = url

        if messages.contains(where: { $0.id == handoff.id }) {
            if let url { rememberLocalUrl(url, forVoice: handoff.id) }
            return
        }

        append(
            ChatMessage(
                id: handoff.id,
                author: .traveller,
                body: .voice(
                    VoiceNote(
                        id: handoff.id,
                        duration: handoff.audio.duration,
                        levels: handoff.levels,
                        localUrl: url
                    )
                ),
                sentAt: .now,
                stepId: activeStepId,
                delivery: .sending
            )
        )
    }

    /// Ce que la file dit d'un tour — le vocal de l'accueil, ou un message
    /// d'ici qui attendait le réseau. La bulle suit **la file**, pas l'écran :
    /// hors ligne elle reste sur « envoi en cours », et c'est la reconnexion
    /// qui la termine, par son identifiant.
    ///
    /// Arrivé, le tour a un reçu : les bulles que le serveur a écrites — la
    /// sienne avec son rang, sa fiche — entrent dans le fil, et le sondage
    /// prend la suite si MEMO répond. Un tour d'un autre voyage ne touche à
    /// rien ici.
    public func markDelivery(_ delivery: ChatTurnDelivery) {
        latestDelivery = delivery
        guard let thread, delivery.tripId == thread.context.tripId else { return }

        switch delivery.state {
        case .sending:
            mark(delivery.id, as: .sending)
        case .failed(let message):
            mark(delivery.id, as: .failed(message))
        case .sent:
            if let receipt = delivery.receipt {
                accept(receipt, for: delivery.id)
            } else {
                mark(delivery.id, as: .sent)
            }
        }
    }

    /// Écrit dans les caches les fichiers d'un tour relu du disque de la
    /// file, pour que sa bulle se réécoute et se regarde comme celle d'un tour
    /// dit ici.
    private func keepLocalFiles(of turn: OutgoingTurn) {
        switch turn.body {
        case .text:
            break
        case .voice(let audio):
            guard localVoiceUrls[turn.id] == nil else { return }
            let recorded = RecordedAudio(
                data: audio.data,
                filename: audio.filename,
                mimeType: audio.mimeType,
                duration: audio.durationSeconds,
                recordedAt: audio.capturedAt
            )
            localVoiceUrls[turn.id] = try? VoiceNoteFile.save(recorded, id: turn.id)
        case .photos(let photos, _):
            for (index, photo) in photos.enumerated() {
                let id = "\(turn.id)-\(index)"
                guard localPhotoUrls[id] == nil else { continue }
                localPhotoUrls[id] = try? ChatPhotoFile.save(photo.data, id: id)
            }
        }
    }

    /// Les étapes offertes sont épuisées : le micro ne s'ouvre plus, il mène au
    /// paywall — voir ``SubscriptionSession/isBlocked``. Posé par l'écran, qui
    /// seul connaît la session.
    public var isRecordingLocked = false

    /// Ce que fait le micro quand il est verrouillé : l'écran y ouvre le
    /// paywall.
    public var onRecordingLocked: (() -> Void)?

    public func startRecording() {
        // Le verrou passe avant tout : ni micro, ni niveaux, ni permission
        // demandée pour rien.
        if isRecordingLocked {
            onRecordingLocked?()
            return
        }
        guard !recorder.isRecording else { return }

        Task {
            do {
                try await recorder.start()
                microphoneIsDenied = false
                startSamplingLevels()
            } catch RecordingError.permissionDenied {
                microphoneIsDenied = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func finishRecording() {
        levelSampler?.cancel()
        let levels = capturedLevels

        do {
            guard let audio = try recorder.stop() else { return }
            let id = UUID().uuidString.lowercased()

            // `AudioRecorder.stop()` efface son fichier temporaire et ne rend
            // que des octets : sans cette écriture, le vocal ne serait plus
            // réécoutable une seconde après l'avoir dit.
            if let url = try? VoiceNoteFile.save(audio, id: id) {
                localVoiceUrls[id] = url
            }

            composer = .tools
            send(
                .voice(
                    RecordedTurnAudio(
                        data: audio.data,
                        filename: audio.filename,
                        mimeType: audio.mimeType,
                        capturedAt: audio.recordedAt,
                        durationSeconds: audio.duration,
                        levels: levels,
                        placeLabel: thread?.context.placeName
                    )
                ),
                id: id
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func pauseRecording() {
        recorder.pause()
        levelSampler?.cancel()
    }

    public func resumeRecording() {
        recorder.resume()
        startSamplingLevels(resetting: false)
    }

    public func cancelRecording() {
        levelSampler?.cancel()
        capturedLevels = []
        recorder.cancel()
        composer = .tools
    }

    /// Onze relevés par seconde : assez pour dessiner le grain d'une voix,
    /// assez peu pour qu'un vocal de trois minutes reste un tableau de deux
    /// mille valeurs.
    private func startSamplingLevels(resetting: Bool = true) {
        if resetting { capturedLevels = [] }
        levelSampler = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(90))
                guard let self, self.recorder.isRecording, !self.recorder.isPaused else { return }
                self.capturedLevels.append(self.recorder.level)
            }
        }
    }

    // MARK: - Les commandes d'un message

    /// Joue un vocal. Le fichier local d'abord ; sinon le serveur le sert
    /// **avec la session** — une URL nue ne suffirait pas —, et on le garde
    /// dans les caches pour la fois suivante.
    public func togglePlayback(of note: VoiceNote) {
        reader.stop()

        if let url = note.localUrl {
            play(note.id, at: url)
            return
        }

        guard let remote = note.remoteUrl else {
            errorMessage = MemoResponderError.transcriptionUnavailable.localizedDescription
            return
        }

        Task {
            do {
                let data = try await transport.media(remote)
                let audio = RecordedAudio(
                    data: data,
                    filename: "\(note.id).m4a",
                    mimeType: "audio/mp4",
                    duration: note.duration,
                    recordedAt: .now
                )
                let url = try VoiceNoteFile.save(audio, id: note.id)
                localVoiceUrls[note.id] = url
                rememberLocalUrl(url, forVoice: note.id)
                play(note.id, at: url)
            } catch {
                errorMessage = MemoResponderError.transcriptionUnavailable.localizedDescription
            }
        }
    }

    private func play(_ id: String, at url: URL) {
        do {
            try player.toggle(id: id, url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rememberLocalUrl(_ url: URL, forVoice id: String) {
        guard var thread else { return }
        for index in thread.messages.indices {
            guard case .voice(var note) = thread.messages[index].body, note.id == id else { continue }
            note.localUrl = url
            thread.messages[index].body = .voice(note)
        }
        self.thread = thread
    }

    public func toggleReading(of message: ChatMessage) {
        guard let text = message.spokenText else { return }
        player.stop()
        reader.toggle(id: message.id, text: text)
    }

    /// Copie le message. Le retour est un `UINotificationFeedbackGenerator` et
    /// non une alerte : on ne pose pas une fenêtre pour dire qu'un texte est
    /// dans le presse-papiers.
    public func copy(_ message: ChatMessage) {
        guard let text = message.spokenText else { return }
        UIPasteboard.general.string = text
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // La coche verte prend la place de l'icône pendant une seconde. Une
        // seconde parce que c'est le temps qu'il faut pour la voir sans qu'elle
        // devienne un état : au-delà, on se demande si elle attend un second
        // geste.
        copiedMessageId = message.id
        Task { [id = message.id] in
            try? await Task.sleep(for: .seconds(1))
            guard copiedMessageId == id else { return }
            copiedMessageId = nil
        }
    }

    /// Poste les photos choisies.
    ///
    /// Les images sont écrites dans les caches avant d'entrer dans le fil : une
    /// bulle qui garderait ses octets en mémoire ferait grossir la conversation
    /// à chaque photo, et les perdrait au premier retour d'arrière-plan.
    public func sendPhotos(_ images: [Data]) {
        guard !images.isEmpty else { return }
        let id = UUID().uuidString.lowercased()

        var uploads: [ChatPhotoUpload] = []
        for (index, data) in images.prefix(4).enumerated() {
            let photoId = "\(id)-\(index)"
            guard let url = try? ChatPhotoFile.save(data, id: photoId) else { continue }
            localPhotoUrls[photoId] = url
            uploads.append(ChatPhotoUpload(data: data, filename: "\(photoId).jpg", mimeType: "image/jpeg"))
        }

        guard !uploads.isEmpty else {
            errorMessage = ChatCopy.photosUnreadable
            return
        }

        composer = .tools
        send(.photos(uploads, capturedAt: .now), id: id)
    }

    /// « Modifier » : le texte revient dans le champ de saisie, le clavier
    /// s'ouvre. Sur une fiche, c'est « à la main » sans la puce : envoyer
    /// corrige le souvenir. Sur une bulle de texte, c'est un nouveau message.
    public func edit(_ message: ChatMessage) {
        guard let text = message.spokenText else { return }
        draft = text
        if case .transcript(let card) = message.body {
            isEditingTranscript = true
            editingEntryId = card.entryId
        }
        composer = .writing
    }

    /// La dernière fiche remplie du fil — celle que le trio « Ça me convient /
    /// à la main / à l'oral » suit. La dernière et non la première : on
    /// corrige ce qu'on vient d'entendre, pas la fiche d'hier.
    private var latestTranscriptCard: TranscriptCard? {
        for message in messages.reversed() {
            if case .transcript(let card) = message.body, let text = card.text, !text.isEmpty {
                return card
            }
        }
        return nil
    }

    // MARK: -

    private func append(_ message: ChatMessage) {
        thread?.messages.append(message)
    }

    private func mark(_ id: String, as delivery: ChatDelivery) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        thread?.messages[index].delivery = delivery
    }
}

// MARK: - Aperçus

extension ChatModel {
    /// Une conversation déjà remplie, pour les aperçus. Dans une extension du
    /// fichier du modèle, parce que `private(set)` ne s'ouvre qu'ici.
    ///
    /// Pas de `#if DEBUG` : un `#Preview` se compile **aussi** en release, donc
    /// ce que l'aperçu appelle doit exister en release. Sinon l'archive casse,
    /// alors que la compilation de debug passait. C'est la règle du paquet —
    /// les jeux d'essai des aperçus (`ChatThread.fixture`, `HomeFeed.emptyFixture`)
    /// se compilent partout ; seuls les panneaux du bac à sable sont en `#if DEBUG`.
    static func preview(
        thread: ChatThread,
        turn: ChatTurnState = .idle,
        composer: ChatComposerMode = .tools,
        draft: String = "",
        microphoneIsDenied: Bool = false,
        focusStepId: String? = nil
    ) -> ChatModel {
        let model = ChatModel(transport: .local(tripId: thread.id), focusStepId: focusStepId)
        model.thread = thread
        model.turn = turn
        model.composer = composer
        model.draft = draft
        model.microphoneIsDenied = microphoneIsDenied
        return model
    }
}
