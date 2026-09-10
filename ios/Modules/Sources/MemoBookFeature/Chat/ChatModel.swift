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
/// le voyageur raconte, et laisser MEMO répondre.
///
/// **Même construction que ``HomeModel``, ``TripHomeModel`` et
/// ``ProfileModel``** : le modèle ne connaît pas l'API, il reçoit **deux
/// sources** — celle qui rend la conversation, et celle qui répond à sa place
/// (``MemoResponder``). Aujourd'hui le jeu d'essai et le moteur local ; demain
/// `api.chatThread(tripId:)` et `RemoteMemoResponder`, une ligne chacun.
///
/// **Tout le déroulé d'un tour est ici, jamais dans la vue.** La bulle du
/// voyageur se pose avant le réseau, MEMO marque un temps qui dépend de ce
/// qu'il a lu, ses bulles arrivent une par une avec l'indicateur qui se rallume
/// entre deux, et un échec garde le message pour qu'on puisse le renvoyer. Une
/// vue qui aurait à orchestrer ça se remettrait à clignoter au premier
/// refactoring.
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

    public let recorder = AudioRecorder()
    public let player = AudioNotePlayer()
    public let reader = SpeechReader()

    private let source: () async throws -> ChatThread
    private let responder: any MemoResponder

    /// Les niveaux du micro, accumulés pendant qu'on parle.
    ///
    /// ``AudioRecorder`` ne publie qu'un niveau **instantané** : sans cette
    /// collecte, la forme d'onde d'un vocal terminé n'aurait aucune donnée et
    /// il faudrait en dessiner une fausse. C'est la seule raison de cette
    /// boucle.
    public private(set) var capturedLevels: [Double] = []
    private var levelSampler: Task<Void, Never>?

    private var exchange: Task<Void, Never>?

    /// Le message dont la réponse a échoué. ``retry()`` rejoue **ce** tour sans
    /// reposter la bulle : sinon on se retrouverait avec deux fois le même
    /// souvenir dans le carnet.
    private var pending: ChatMessage?

    /// - Parameters:
    ///   - source: ce qui rend la conversation. Par défaut le jeu d'essai, ce
    ///     qui laisse les aperçus montrer les quatre états sans serveur.
    ///   - responder: qui répond. Par défaut ``LocalMemoResponder`` — c'est la
    ///     seule ligne à changer le jour où la route existe.
    public init(
        source: @escaping () async throws -> ChatThread,
        focusStepId: String? = nil,
        responder: any MemoResponder = LocalMemoResponder()
    ) {
        self.source = source
        self.focusStepId = focusStepId
        self.responder = responder
    }

    /// La conversation d'un voyage.
    ///
    /// `focusStepId` n'ouvre **pas** un autre fil : il dit sur quelle journée
    /// se poser en arrivant, et à quelle étape rattacher ce qu'on va raconter.
    /// Un seul fil par voyage — voir ``ChatMessage/stepId``.
    public convenience init(
        tripId: String,
        focusStepId: String? = nil,
        responder: any MemoResponder = LocalMemoResponder()
    ) {
        self.init(
            source: { .fixture(tripId: tripId) },
            focusStepId: focusStepId,
            responder: responder
        )
    }

    /// L'étape sur laquelle le fil s'est ouvert, quand on vient d'une carte
    /// d'étape.
    public private(set) var focusStepId: String?

    /// L'étape à laquelle rattacher un nouveau message : celle qu'on est venu
    /// voir, ou à défaut celle où le voyage en est.
    private var activeStepId: String? {
        focusStepId ?? thread?.context.stepId
    }

    /// Le silence minimal avant une bulle de MEMO. Sans lui, une réponse locale
    /// arriverait dans la même image que le message du voyageur : c'est le
    /// premier signe qu'il n'y a personne en face.
    private static let minimumThinking = Duration.milliseconds(450)

    // MARK: - Charger

    /// `true` tant qu'on n'a rien à montrer. L'écran dessine alors son
    /// squelette plutôt qu'une demi-conversation.
    public var isLoading: Bool { thread == nil && errorMessage == nil }

    public func load() async {
        do {
            var loaded = try await source()

            // Les puces d'ouverture viennent du **répondeur** et non du fil :
            // ce sont les premières propositions de MEMO, au même titre que
            // celles de tous les tours suivants. Les écrire dans le jeu d'essai
            // en ferait un décor que la vraie route devrait recopier.
            if loaded.isEmpty, loaded.suggestions.isEmpty {
                loaded.suggestions = responder.opening(for: loaded.context).suggestions
            }

            thread = loaded
            errorMessage = nil
            // Relu à chaque ouverture : l'accès peut avoir été retiré depuis
            // les Réglages pendant que l'app était en arrière-plan.
            microphoneIsDenied = RecordingPermission.current == .denied
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Tout arrêter en quittant l'écran : la lecture, la voix de synthèse, le
    /// tour en vol, et la collecte de niveaux. Un écran de chat laissé derrière
    /// soi ne doit ni parler ni enregistrer.
    public func teardown() {
        exchange?.cancel()
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
    /// Seul l'import de photos n'envoie rien : on ne dit pas « j'importe des
    /// photos », on les importe.
    public func choose(_ suggestion: ChatSuggestion, addPhotos: () -> Void) {
        switch suggestion.intent {
        case .importPhotos:
            addPhotos()
        case .send, .unknown:
            composer = .tools
            send(.text(suggestion.label))
        case .sendThenWrite:
            composer = .writing
            send(.text(suggestion.label))
        case .sendThenSpeak:
            composer = .speaking
            send(.text(suggestion.label))
        }
    }

    private func send(_ body: ChatMessageBody) {
        guard thread != nil else { return }

        ensureOpening()

        let message = ChatMessage(
            id: "traveller-\(messages.count)",
            author: .traveller,
            body: body,
            sentAt: .now,
            stepId: activeStepId,
            delivery: .sending
        )
        append(message)
        start(message)
    }

    /// MEMO parle le premier.
    ///
    /// Son ouverture est posée **d'un coup et sans attente**, juste avant la
    /// première bulle du voyageur : la conversation se lit alors comme si elle
    /// avait déjà commencé, ce qui est l'ordre que la maquette dessine — la
    /// bulle blanche d'ouverture est au-dessus du premier vocal. La faire venir
    /// après aurait donné l'impression que MEMO répond à côté.
    private func ensureOpening() {
        guard var thread, thread.isEmpty else { return }
        let opening = responder.opening(for: thread.context)
        thread.messages = opening.beats.map(stamped)
        self.thread = thread
    }

    public func retry() {
        guard let pending else { return }
        mark(pending.id, as: .sending)
        start(pending)
    }

    // MARK: - Le tour de parole

    private func start(_ message: ChatMessage) {
        pending = message
        exchange?.cancel()
        exchange = Task { await run(message) }
    }

    private func run(_ message: ChatMessage) async {
        guard var thread else { return }

        // Les suggestions du tour précédent ne veulent plus rien dire.
        thread.suggestions = []
        self.thread = thread

        turn = .sending(messageId: message.id)

        do {
            let history = messages.filter { $0.id != message.id }
            let reply = try await responder.reply(
                to: ChatTurn(message: message, history: history, context: thread.context)
            )

            mark(message.id, as: .sent)

            for beat in reply.beats {
                turn = .thinking
                try await Task.sleep(for: max(beat.pause, Self.minimumThinking))
                append(stamped(beat))
                try await fillTranscriptIfNeeded(of: beat.message.id)
            }

            apply(reply)
            pending = nil
            turn = .idle
        } catch is CancellationError {
            // L'écran s'est refermé, ou un nouveau tour a démarré. Rien à dire.
            turn = .idle
        } catch {
            mark(message.id, as: .failed(error.localizedDescription))
            turn = .failed(messageId: message.id, message: error.localizedDescription)
        }
    }

    /// Une fiche arrive avec sa date, son lieu et sa durée, mais sans récit : la
    /// transcription est un travail de fond côté serveur. On l'attend **la fiche
    /// déjà visible** — cacher une information réelle derrière une attente
    /// donnerait l'impression que rien ne se passe.
    private func fillTranscriptIfNeeded(of messageId: String) async throws {
        guard let index = messages.firstIndex(where: { $0.id == messageId }),
            case .transcript(let card) = messages[index].body,
            card.text == nil
        else { return }

        turn = .thinking
        let filled = try await responder.awaitTranscript(of: card)
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        thread?.messages[index].body = .transcript(filled)
    }

    private func apply(_ reply: MemoReply) {
        guard var thread else { return }
        thread.suggestions = reply.suggestions
        self.thread = thread
    }

    // MARK: - Le vocal

    public func startRecording() {
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
            let id = "voice-\(messages.count)"

            // `AudioRecorder.stop()` efface son fichier temporaire et ne rend
            // que des octets : sans cette écriture, le vocal ne serait plus
            // réécoutable une seconde après l'avoir dit.
            let url = try? VoiceNoteFile.save(audio, id: id)

            composer = .tools
            send(
                .voice(
                    VoiceNote(
                        id: id,
                        duration: audio.duration,
                        levels: levels,
                        localUrl: url
                    )
                )
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

    public func togglePlayback(of note: VoiceNote) {
        guard let url = note.playbackUrl else {
            errorMessage = MemoResponderError.transcriptionUnavailable.localizedDescription
            return
        }
        reader.stop()
        do {
            try player.toggle(id: note.id, url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
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

        let attachments = images.enumerated().compactMap { index, data -> PhotoAttachment? in
            let id = "photo-\(messages.count)-\(index)"
            guard let url = try? ChatPhotoFile.save(data, id: id) else { return nil }
            return PhotoAttachment(id: id, localUrl: url)
        }

        guard !attachments.isEmpty else {
            errorMessage = ChatCopy.photosUnreadable
            return
        }

        composer = .tools
        send(.photos(attachments))
    }

    /// « Modifier » : le texte revient dans le champ de saisie, le clavier
    /// s'ouvre. La bulle reste dans le fil — la corriger côté serveur demande
    /// `PATCH /v1/entries/:id`, et l'entrée n'existe pas encore. Voir la fiche
    /// écran.
    public func edit(_ message: ChatMessage) {
        guard let text = message.spokenText else { return }
        draft = text
        composer = .writing
    }

    // MARK: -

    private func append(_ message: ChatMessage) {
        thread?.messages.append(message)
    }

    private func mark(_ id: String, as delivery: ChatDelivery) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        thread?.messages[index].delivery = delivery
    }

    /// Le répondeur est déterministe : il n'a pas le droit de lire l'horloge, et
    /// horodate donc ses bulles à ``Date/distantPast``. C'est le modèle qui les
    /// datent en les posant — le seul endroit de la chaîne qui vive dans le
    /// temps réel.
    private func stamped(_ beat: MemoBeat) -> ChatMessage {
        ChatMessage(
            id: beat.message.id,
            author: beat.message.author,
            body: beat.message.body,
            sentAt: .now,
            // La réponse parle de la même journée que la question : sans ça,
            // rouvrir une étape ne retrouverait que ce qu'on a dit soi-même.
            stepId: activeStepId
        )
    }
}

// MARK: - Débogage

#if DEBUG
    extension ChatModel {
        /// Une conversation déjà remplie, pour les aperçus. Dans une extension
        /// `#if DEBUG` du fichier du modèle, parce que `private(set)` ne s'ouvre
        /// qu'ici.
        static func preview(
            thread: ChatThread,
            turn: ChatTurnState = .idle,
            composer: ChatComposerMode = .tools,
            draft: String = "",
            microphoneIsDenied: Bool = false,
            focusStepId: String? = nil
        ) -> ChatModel {
            let model = ChatModel(source: { thread }, focusStepId: focusStepId)
            model.thread = thread
            model.turn = turn
            model.composer = composer
            model.draft = draft
            model.microphoneIsDenied = microphoneIsDenied
            return model
        }
    }
#endif
