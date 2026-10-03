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

    /// Le tour attend, sur le disque de la file, que le crédit du jour se
    /// recharge — ``PendingTurn/waitingForCreditUntil``. `nil` pour un tour
    /// qu'on vient de dire, ou qui n'attend que le réseau. C'est ce qui fait
    /// rouvrir le fil sur une bulle « Partira demain » plutôt que sur « en
    /// cours d'envoi ».
    public let waitingForCreditUntil: Date?

    /// Le tour attend, sur le disque de la file, que le compte passe en
    /// illimité : il coûte plus qu'une journée entière de crédit —
    /// ``PendingTurn/waitingForUnlimited``. Le fil se rouvre alors sur une
    /// bulle « Trop long pour une journée ».
    public let waitingForUnlimited: Bool

    public init(
        id: String = UUID().uuidString.lowercased(),
        stepId: String? = nil,
        body: Body,
        waitingForCreditUntil: Date? = nil,
        waitingForUnlimited: Bool = false
    ) {
        self.id = id
        self.stepId = stepId
        self.body = body
        self.waitingForCreditUntil = waitingForCreditUntil
        self.waitingForUnlimited = waitingForUnlimited
    }

    /// Le tour est retenu sur le disque — par le crédit de demain, ou par
    /// l'illimité. Ni l'un ni l'autre n'entame le crédit d'aujourd'hui.
    ///
    /// **Une attente échue ne retient plus rien** (03/10/2026) : refusé hier
    /// à 22 h jusqu'à minuit, le tour repart au prochain vidage, sur le crédit
    /// du jour où il part — comme ``PendingTurn/isOnHold(at:)`` côté disque.
    /// Lu sans la date, il se rouvrait le lendemain en « Partira demain »,
    /// hors du décompte du jour, alors que la file l'enverrait dès la
    /// reconnexion.
    public var isOnHold: Bool { waitingForUnlimited || isWaitingForCredit() }

    /// Le tour attend encore le crédit du jour à cet instant.
    public func isWaitingForCredit(at now: Date = .now) -> Bool {
        guard let waitingForCreditUntil else { return false }
        return waitingForCreditUntil > now
    }

    /// Ce que ce tour coûtera au crédit du jour, d'après ce que l'app en sait
    /// — l'estimation qu'elle tient entre deux réponses du serveur, qui
    /// tranche (`services/dailyCredit.ts`). Un vocal, sa durée ; un texte libre,
    /// ses caractères ; une puce ou une commande silencieuse (`suggestionId`),
    /// rien — le serveur ne fait payer qu'un texte qui n'est pas exactement
    /// son libellé, et l'app envoie toujours le libellé ; des photos, rien.
    public func creditCost(in credit: DailyCredit) -> Int {
        switch body {
        case .text(let text, let suggestionId, _):
            suggestionId == nil ? credit.cost(ofText: text) : 0
        case .voice(let audio):
            Int((audio.durationSeconds * 1000).rounded())
        case .photos:
            0
        }
    }

    /// Le tour coûte **plus qu'une journée entière** de crédit : le serveur
    /// le refusera même pot plein — un vocal au-delà de la limite et de la
    /// tolérance, un texte libre au-delà de la limite. Attendre demain ne
    /// servirait à rien (03/10/2026). Jamais une puce ni des photos.
    public func exceedsAWholeDay(in credit: DailyCredit) -> Bool {
        guard !credit.isUnlimited else { return false }
        let isVoice = if case .voice = body { true } else { false }
        return creditCost(in: credit) > credit.limitWithTolerance(forVoice: isVoice)
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
    /// Le crédit du jour que le serveur a rendu avec un refus faute de crédit
    /// (``ChatDelivery/waitingForCredit(until:)``) : la barre passe à
    /// « épuisé » sans attendre de relire le fil. `nil` le reste du temps — un
    /// reçu porte le sien.
    public let credit: DailyCredit?

    /// Ce mot n'est pas nouveau : la file le **rejoue** à qui se met à
    /// l'écoute (``RecordingOutbox/turnDeliveries()``), pour qu'un écran
    /// ouvert après l'arrivée d'un vocal ne l'attende pas pour rien. Son état
    /// vaut toujours pour la bulle ; son crédit, lui, peut dater de l'envoi
    /// d'il y a des heures — il ne remplace jamais celui que le fil vient de
    /// lire (03/10/2026).
    public var isReplay: Bool

    public init(
        id: String,
        tripId: String,
        state: ChatDelivery,
        receipt: ChatTurnReceipt? = nil,
        credit: DailyCredit? = nil,
        isReplay: Bool = false
    ) {
        self.id = id
        self.tripId = tripId
        self.state = state
        self.receipt = receipt
        self.credit = credit
        self.isReplay = isReplay
    }

    /// Le même mot, marqué comme rejoué.
    public var replayed: ChatTurnDelivery {
        var copy = self
        copy.isReplay = true
        return copy
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

    /// Le fil à ouvrir quand ``load`` a échoué — sans réseau, ou pour un
    /// voyage créé hors ligne que le serveur n'a pas encore reçu. `nil` : il
    /// n'y en a pas, et l'échec se dit. Le modèle reçoit l'erreur pour que la
    /// décision reste ici : une panne du serveur ne se cache pas derrière un
    /// fil local.
    public var offlineThread: @Sendable (any Error) async -> ChatThread?

    /// Oublie un tour qui attend sur le disque — « Supprimer », sous une
    /// bulle qui attend l'illimité (03/10/2026) : sans abonnement, rien ne le
    /// ferait jamais partir, et sa bulle se reposerait à chaque ouverture.
    /// `false` quand la file ne le retient pas — il n'y est pas, ou il est en
    /// train de partir. Rien sans file.
    public var discard: @Sendable (_ turnId: String) async -> Bool

    public init(
        load: @escaping @Sendable () async throws -> ChatThread,
        poll: @escaping @Sendable (Date) async throws -> ChatThreadUpdate,
        send: @escaping @Sendable (OutgoingTurn) async throws -> ChatSendOutcome,
        editTranscript: @escaping @Sendable (String, String) async throws -> Entry,
        media: @escaping @Sendable (URL) async throws -> Data,
        waiting: @escaping @Sendable () async -> [OutgoingTurn] = { [] },
        deliveries: @escaping @Sendable () async -> AsyncStream<ChatTurnDelivery> = { AsyncStream { $0.finish() } },
        offlineThread: @escaping @Sendable (any Error) async -> ChatThread? = { _ in nil },
        discard: @escaping @Sendable (String) async -> Bool = { _ in false }
    ) {
        self.load = load
        self.poll = poll
        self.send = send
        self.editTranscript = editTranscript
        self.media = media
        self.waiting = waiting
        self.deliveries = deliveries
        self.offlineThread = offlineThread
        self.discard = discard
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
                // `/v1/entries/<id>/media` pour un souvenir,
                // `/v1/chat-messages/<id>/media` pour un vocal du contexte du
                // voyage, qui n'en est pas un. L'identifiant est l'avant-dernier
                // segment, la ressource celui d'avant. Une URL d'une autre forme
                // ne se télécharge pas ici.
                let parts = url.pathComponents
                guard parts.count >= 3, parts.last == "media" else {
                    throw APIError.server(statusCode: 0, code: nil, message: "Média inconnu.")
                }
                let id = parts[parts.count - 2]
                switch parts[parts.count - 3] {
                case "entries": return try await api.entryMedia(id: id)
                case "chat-messages": return try await api.chatMessageMedia(id: id)
                default: throw APIError.server(statusCode: 0, code: nil, message: "Média inconnu.")
                }
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
