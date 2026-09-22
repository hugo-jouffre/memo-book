import Foundation
import MemoBookCore
import MemoBookNetworking

/// Un tour que le voyageur envoie — ce que ``ChatTransport/send`` reçoit.
///
/// L'identifiant est **fabriqué par l'app** et devient celui du message côté
/// serveur : la bulle optimiste et la bulle servie sont la même, et un renvoi
/// après une panne de transport tombe sur l'existant au lieu d'un doublon.
public struct OutgoingTurn: Sendable, Hashable, Identifiable {
    public enum Body: Sendable, Hashable {
        /// Un texte libre, ou une puce (`suggestionId`), ou une commande
        /// silencieuse. `entryId` vise le souvenir de « Ça me convient ».
        case text(String, suggestionId: String? = nil, entryId: String? = nil)
        case voice(RecordedTurnAudio)
        case photos([ChatPhotoUpload], capturedAt: Date)
    }

    public let id: String
    public let stepId: String?
    public let body: Body

    public init(id: String = UUID().uuidString.lowercased(), stepId: String? = nil, body: Body) {
        self.id = id
        self.stepId = stepId
        self.body = body
    }
}

/// Le vocal d'un tour : les octets, et ce qu'il faut pour les décompter et
/// les dessiner.
public struct RecordedTurnAudio: Sendable, Hashable {
    public let data: Data
    public let filename: String
    public let mimeType: String
    public let capturedAt: Date
    public let durationSeconds: TimeInterval
    public let levels: [Double]
    public let placeLabel: String?

    public init(
        data: Data,
        filename: String,
        mimeType: String,
        capturedAt: Date,
        durationSeconds: TimeInterval,
        levels: [Double],
        placeLabel: String? = nil
    ) {
        self.data = data
        self.filename = filename
        self.mimeType = mimeType
        self.capturedAt = capturedAt
        self.durationSeconds = durationSeconds
        self.levels = levels
        self.placeLabel = placeLabel
    }
}

/// Ce qu'un envoi a donné : le serveur a reçu — voici les bulles écrites —,
/// ou le tour attend le réseau sur le disque et partira tout seul. Ce second
/// cas **n'est pas un échec** : la bulle reste « en cours d'envoi », et c'est
/// la file qui la terminera (``ChatTransport/deliveries``).
public enum ChatSendOutcome: Sendable, Hashable {
    case received(ChatTurnReceipt)
    case queued
}

/// Le sort d'un tour parti par la file, suivi de bout en bout par son
/// identifiant. Le carnet est là pour que la conversation d'un autre voyage
/// n'y touche pas ; le reçu voyage avec, pour que le fil fusionne ce que le
/// serveur a écrit et se mette à attendre MEMO.
public struct ChatTurnDelivery: Sendable, Equatable {
    public let id: String
    public let tripId: String
    public let state: ChatDelivery
    public let receipt: ChatTurnReceipt?

    public init(id: String, tripId: String, state: ChatDelivery, receipt: ChatTurnReceipt? = nil) {
        self.id = id
        self.tripId = tripId
        self.state = state
        self.receipt = receipt
    }
}

/// Ce que ``ChatModel`` sait faire avec le monde extérieur, sous forme de
/// **fonctions-sources** — la préférence n° 1 de `ios/CLAUDE.md`, comme les
/// closures de `TripSettingsModel`.
///
/// Deux constructeurs, **un seul chemin de code dans le modèle** : ``remote``
/// parle au serveur par ``MemoBookAPI`` ; ``local`` rejoue le même contrat en
/// mémoire avec le moteur de règles, pour les aperçus Xcode, les tests et
/// `-previewSignedIn`. Le modèle ne sait pas lequel il tient.
public struct ChatTransport: Sendable {
    /// Le fil entier, tel que le serveur le sert.
    public var load: @Sendable () async throws -> ChatThread

    /// La suite du fil depuis un instant — le `now` de la lecture précédente.
    public var poll: @Sendable (Date) async throws -> ChatThreadUpdate

    /// Un tour de parole. Rend le reçu — les bulles écrites, l'état du tour —
    /// ou dit que le tour attend le réseau.
    public var send: @Sendable (OutgoingTurn) async throws -> ChatSendOutcome

    /// « À la main » : le texte corrigé fait autorité (`PATCH /v1/entries/:id`).
    public var editTranscript: @Sendable (_ entryId: String, _ text: String) async throws -> Entry

    /// Le fichier d'un vocal ou d'une photo, avec la session.
    public var media: @Sendable (URL) async throws -> Data

    /// Ce qui attend le réseau sur le disque **pour ce fil** — les tours que
    /// la file n'a pas encore fait partir. Le modèle les pose en bulles « en
    /// cours d'envoi » à l'ouverture : un texte dit dans le métro ne
    /// disparaît pas du fil parce qu'on a quitté l'écran et qu'on y revient
    /// (`docs/conversation.md` § 9). Vide sans file.
    public var waiting: @Sendable () async -> [OutgoingTurn]

    /// Le sort des tours partis par la file, au fil de l'eau — le vocal de
    /// l'accueil, un message d'ici qui attendait le réseau. Un flux et non une
    /// valeur observée : deux tours qui partent dans la même seconde font deux
    /// événements, et une bulle ne doit rater ni l'un ni l'autre. Commence par
    /// le dernier connu, pour l'écran ouvert après l'arrivée. Se tait sans
    /// file.
    public var deliveries: @Sendable () async -> AsyncStream<ChatTurnDelivery>

    public init(
        load: @escaping @Sendable () async throws -> ChatThread,
        poll: @escaping @Sendable (Date) async throws -> ChatThreadUpdate,
        send: @escaping @Sendable (OutgoingTurn) async throws -> ChatSendOutcome,
        editTranscript: @escaping @Sendable (String, String) async throws -> Entry,
        media: @escaping @Sendable (URL) async throws -> Data,
        waiting: @escaping @Sendable () async -> [OutgoingTurn] = { [] },
        deliveries: @escaping @Sendable () async -> AsyncStream<ChatTurnDelivery> = { AsyncStream { $0.finish() } }
    ) {
        self.load = load
        self.poll = poll
        self.send = send
        self.editTranscript = editTranscript
        self.media = media
        self.waiting = waiting
        self.deliveries = deliveries
    }

    // MARK: - Le vrai serveur

    /// Le transport de l'app, **sans la file** : chaque envoi part tout de
    /// suite, et rien n'attend. `AppDependencies` le construit, puis pose la
    /// file par-dessus `send`, `waiting` et `deliveries` (``RecordingOutbox``)
    /// — hors ligne, un tour attend au lieu d'échouer.
    public static func remote(api: any MemoBookAPI, tripId: String) -> ChatTransport {
        ChatTransport(
            load: { try await api.chatThread(tripId: tripId) },
            poll: { since in try await api.chatUpdates(tripId: tripId, since: since) },
            send: { turn in .received(try await Self.sendNow(turn, to: tripId, api: api)) },
            editTranscript: { entryId, text in
                try await api.updateEntry(id: entryId, edit: EntryEdit.text(text))
            },
            media: { url in
                // `/v1/entries/<id>/media` : l'identifiant est l'avant-dernier
                // segment. Une URL d'une autre forme ne se télécharge pas ici.
                let parts = url.pathComponents
                guard parts.count >= 2, parts.last == "media", let entryId = parts.dropLast().last else {
                    throw APIError.server(statusCode: 0, code: nil, message: "Média inconnu.")
                }
                return try await api.entryMedia(id: entryId)
            }
        )
    }

    /// L'envoi d'un tour au serveur, tel quel — ce que la file appelle quand
    /// le réseau est là.
    public static func sendNow(
        _ turn: OutgoingTurn,
        to tripId: String,
        api: any MemoBookAPI
    ) async throws -> ChatTurnReceipt {
        switch turn.body {
        case .text(let text, let suggestionId, let entryId):
            return try await api.sendChatText(
                tripId: tripId,
                turn: ChatTextTurn(
                    id: turn.id,
                    text: text,
                    stepId: turn.stepId,
                    suggestionId: suggestionId,
                    entryId: entryId
                )
            )
        case .voice(let audio):
            return try await api.sendChatVoice(
                tripId: tripId,
                turn: ChatVoiceTurn(
                    id: turn.id,
                    data: audio.data,
                    filename: audio.filename,
                    mimeType: audio.mimeType,
                    capturedAt: audio.capturedAt,
                    durationSeconds: audio.durationSeconds,
                    levels: audio.levels,
                    placeLabel: audio.placeLabel,
                    stepId: turn.stepId
                )
            )
        case .photos(let photos, let capturedAt):
            return try await api.sendChatPhotos(
                tripId: tripId,
                turn: ChatPhotosTurn(id: turn.id, photos: photos, capturedAt: capturedAt, stepId: turn.stepId)
            )
        }
    }

    // MARK: - Le moteur local

    /// Le même contrat, sans serveur : le jeu d'essai du voyage et
    /// ``LocalMemoResponder`` derrière un fil en mémoire. Aperçus, tests,
    /// `-previewSignedIn`.
    public static func local(tripId: String, box: PreviewChatBox = PreviewChatBox()) -> ChatTransport {
        ChatTransport(
            load: { await box.read(tripId: tripId) },
            poll: { since in await box.updates(tripId: tripId, since: since) },
            send: { turn in
                let message: ChatMessage
                switch turn.body {
                case .text(let text, let suggestionId, let entryId):
                    if suggestionId == "accept", let entryId { _ = await box.validate(entryId: entryId) }
                    message = ChatMessage(
                        id: turn.id,
                        author: .traveller,
                        body: .text(text),
                        sentAt: .now,
                        stepId: turn.stepId,
                        disposition: suggestionId == nil ? .memory : .command
                    )
                case .voice(let audio):
                    message = ChatMessage(
                        id: turn.id,
                        author: .traveller,
                        body: .voice(VoiceNote(id: turn.id, duration: audio.durationSeconds, levels: audio.levels)),
                        sentAt: audio.capturedAt,
                        stepId: turn.stepId,
                        disposition: .memory
                    )
                case .photos(let photos, let capturedAt):
                    message = ChatMessage(
                        id: turn.id,
                        author: .traveller,
                        body: .photos(photos.indices.map { PhotoAttachment(id: "\(turn.id)-\($0)") }),
                        sentAt: capturedAt,
                        stepId: turn.stepId,
                        disposition: .memory
                    )
                }
                return .received(await box.send(tripId: tripId, message: message))
            },
            editTranscript: { entryId, text in
                await box.edit(entryId: entryId, text: text)
                return Entry(
                    id: entryId,
                    memoId: tripId,
                    kind: .audio,
                    status: .ready,
                    redactionStatus: .ready,
                    editedText: text,
                    editedAt: .now,
                    capturedAt: .now,
                    createdAt: .now
                )
            },
            media: { _ in
                throw APIError.server(statusCode: 404, code: "not_found", message: "Média introuvable.")
            }
        )
    }
}

extension ChatTransport {
    /// Un transport qui échoue à tout — l'aperçu de l'état d'erreur, et les
    /// tests qui vérifient qu'un échec garde le message.
    public static func failing(_ error: any Error & Sendable) -> ChatTransport {
        ChatTransport(
            load: { throw error },
            poll: { _ in throw error },
            send: { _ in throw error },
            editTranscript: { _, _ in throw error },
            media: { _ in throw error }
        )
    }
}
