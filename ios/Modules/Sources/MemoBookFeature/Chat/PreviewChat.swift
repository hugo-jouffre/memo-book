import Foundation
import MemoBookCore
import MemoBookNetworking

/// Le serveur de conversation du double d'API — aperçus Xcode, tests
/// d'interface, `-previewSignedIn`.
///
/// **Le même chemin que le vrai serveur, sans serveur.** `ChatModel` ne
/// connaît qu'un ``ChatTransport`` ; ici, derrière `PreviewAPI`, un fil en
/// mémoire par voyage, ouvert sur le jeu d'essai, où ``LocalMemoResponder``
/// répond à la place de MEMO. Ce que le vrai serveur écrit dans un job, ce
/// double l'écrit tout de suite avec une date d'un instant plus tard : le
/// sondage (`chatUpdates(since:)`) le trouve au tour suivant, exactement comme
/// il trouverait la réponse d'un job.
public actor PreviewChatBox {
    private var threads: [String: ChatThread] = [:]
    private var stamps: [String: [String: Date]] = [:]
    private let responder = LocalMemoResponder()

    private func thread(for tripId: String) -> ChatThread {
        if let existing = threads[tripId] { return existing }
        var fresh = ChatThread.fixture(tripId: tripId)
        if fresh.isEmpty, fresh.suggestions.isEmpty {
            fresh.suggestions = responder.opening(for: fresh.context).suggestions
        }
        threads[tripId] = fresh
        stamps[tripId] = Dictionary(uniqueKeysWithValues: fresh.messages.map { ($0.id, .distantPast) })
        return fresh
    }

    private func stamp(_ message: ChatMessage, in tripId: String, at date: Date) {
        stamps[tripId, default: [:]][message.id] = date
    }

    public init() {}

    public func read(tripId: String) -> ChatThread {
        var thread = thread(for: tripId)
        thread = thread.stamped(now: .now)
        return thread
    }

    public func updates(tripId: String, since: Date) -> ChatThreadUpdate {
        let thread = thread(for: tripId)
        let changed = thread.messages.filter { (stamps[tripId]?[$0.id] ?? .distantPast) > since }
        return ChatThreadUpdate(
            messages: changed,
            suggestions: thread.suggestions,
            preview: thread.preview,
            turn: .idle,
            now: .now
        )
    }

    /// Pose la bulle du voyageur, fait répondre MEMO, et date ses bulles **après**
    /// le reçu : c'est ce qui les fait arriver au sondage suivant.
    public func send(tripId: String, message: ChatMessage) async -> ChatTurnReceipt {
        var thread = thread(for: tripId)
        let now = Date.now
        var written: [ChatMessage] = []

        if thread.isEmpty {
            for beat in responder.opening(for: thread.context).beats {
                let opening = beat.message.stamped(sentAt: now, stepId: nil, pause: beat.pauseMilliseconds)
                thread.messages.append(opening)
                stamp(opening, in: tripId, at: now)
                written.append(opening)
            }
        }

        let history = thread.messages
        thread.messages.append(message)
        stamp(message, in: tripId, at: now)
        written.append(message)
        thread.suggestions = []

        let reply = (try? await responder.reply(
            to: ChatTurn(message: message, history: history, context: thread.context)
        )) ?? MemoReply(beats: [], suggestions: [])

        let later = now.addingTimeInterval(0.001)
        for beat in reply.beats {
            var bubble = beat.message.stamped(sentAt: later, stepId: message.stepId, pause: beat.pauseMilliseconds)
            // Une fiche vient avec l'identifiant de son souvenir, comme sur le
            // serveur : c'est elle qu'on valide et qu'on corrige.
            if case .transcript(let card) = bubble.body, card.entryId == nil {
                bubble.body = .transcript(card.identified(as: "entry-\(message.id)"))
            }
            thread.messages.append(bubble)
            stamp(bubble, in: tripId, at: later)
        }
        thread.suggestions = reply.suggestions
        if let preview = reply.preview { thread.preview = preview }
        threads[tripId] = thread

        return ChatTurnReceipt(messages: written, turn: .replying(messageId: message.id), now: now)
    }

    public func validate(entryId: String) -> Bool {
        var found = false
        for (tripId, var thread) in threads {
            for index in thread.messages.indices {
                guard case .transcript(let card) = thread.messages[index].body, card.entryId == entryId
                else { continue }
                thread.messages[index].body = .transcript(card.validated())
                stamp(thread.messages[index], in: tripId, at: .now)
                found = true
            }
            threads[tripId] = thread
        }
        return found
    }

    /// « À la main » : le texte corrigé remplace celui de la fiche, qui reste prête.
    public func edit(entryId: String, text: String) {
        for (tripId, var thread) in threads {
            for index in thread.messages.indices {
                guard case .transcript(let card) = thread.messages[index].body, card.entryId == entryId
                else { continue }
                thread.messages[index].body = .transcript(card.filled(with: text, isSimulated: false))
                stamp(thread.messages[index], in: tripId, at: .now)
            }
            threads[tripId] = thread
        }
    }

    public func clear(tripId: String) {
        var thread = thread(for: tripId).cleared()
        let now = Date.now
        for beat in responder.opening(for: thread.context).beats {
            let opening = beat.message.stamped(sentAt: now, stepId: nil, pause: beat.pauseMilliseconds)
            thread.messages.append(opening)
            stamp(opening, in: tripId, at: now)
        }
        thread.suggestions = responder.opening(for: thread.context).suggestions
        threads[tripId] = thread
    }
}

extension PreviewAPI {
    public func chatThread(tripId: String) async throws -> ChatThread {
        await chat.read(tripId: tripId)
    }

    public func chatUpdates(tripId: String, since: Date) async throws -> ChatThreadUpdate {
        await chat.updates(tripId: tripId, since: since)
    }

    public func sendChatText(tripId: String, turn: ChatTextTurn) async throws -> ChatTurnReceipt {
        let message = ChatMessage(
            id: turn.id,
            author: .traveller,
            body: .text(turn.text),
            sentAt: .now,
            stepId: turn.stepId,
            disposition: turn.suggestionId == nil ? .memory : .command
        )
        if turn.suggestionId == "accept", let entryId = turn.entryId {
            _ = await chat.validate(entryId: entryId)
        }
        return await chat.send(tripId: tripId, message: message)
    }

    public func sendChatVoice(tripId: String, turn: ChatVoiceTurn) async throws -> ChatTurnReceipt {
        let message = ChatMessage(
            id: turn.id,
            author: .traveller,
            body: .voice(VoiceNote(id: turn.id, duration: turn.durationSeconds, levels: turn.levels)),
            sentAt: turn.capturedAt,
            stepId: turn.stepId,
            disposition: .memory
        )
        return await chat.send(tripId: tripId, message: message)
    }

    public func sendChatPhotos(tripId: String, turn: ChatPhotosTurn) async throws -> ChatTurnReceipt {
        let attachments = turn.photos.enumerated().map { index, _ in
            PhotoAttachment(id: "\(turn.id)-\(index)")
        }
        let message = ChatMessage(
            id: turn.id,
            author: .traveller,
            body: .photos(attachments),
            sentAt: turn.capturedAt,
            stepId: turn.stepId,
            disposition: .memory
        )
        return await chat.send(tripId: tripId, message: message)
    }

    public func validateEntry(id: String) async throws -> EntryValidation {
        _ = await chat.validate(entryId: id)
        let entry = (try? await entry(id: id)) ?? Entry(
            id: id,
            memoId: "preview-memo",
            kind: .audio,
            status: .ready,
            redactionStatus: .ready,
            validatedAt: .now,
            capturedAt: .now,
            createdAt: .now
        )
        return EntryValidation(entry: entry, offeredSteps: 3, remainingSteps: 2)
    }

    public func clearChat(tripId: String) async throws {
        await chat.clear(tripId: tripId)
    }

    public func entryMedia(id: String) async throws -> Data {
        throw APIError.server(statusCode: 404, code: "not_found", message: "Média introuvable.")
    }
}

extension ChatMessage {
    /// La bulle du répondeur local, datée et rattachée à l'étape — ce que le
    /// serveur fait en l'écrivant.
    fileprivate func stamped(sentAt: Date, stepId: String?, pause: Int) -> ChatMessage {
        ChatMessage(
            id: id,
            author: author,
            body: body,
            sentAt: sentAt,
            stepId: stepId,
            pauseMilliseconds: pause
        )
    }
}

extension ChatThread {
    fileprivate func stamped(now: Date) -> ChatThread {
        ChatThread(
            id: id,
            title: title,
            avatarUrl: avatarUrl,
            destination: destination,
            greeting: greeting,
            preview: preview,
            context: context,
            messages: messages,
            suggestions: suggestions,
            turn: .idle,
            canClear: true,
            now: now
        )
    }
}

extension TranscriptCard {
    fileprivate func identified(as entryId: String) -> TranscriptCard {
        TranscriptCard(
            title: title,
            capturedAt: capturedAt,
            placeLabel: placeLabel,
            duration: duration,
            text: text,
            isSimulated: isSimulated,
            entryId: entryId,
            footnote: footnote,
            phase: phase,
            isValidated: isValidated
        )
    }

    fileprivate func validated() -> TranscriptCard {
        TranscriptCard(
            title: title,
            capturedAt: capturedAt,
            placeLabel: placeLabel,
            duration: duration,
            text: text,
            isSimulated: isSimulated,
            entryId: entryId,
            footnote: footnote,
            phase: phase,
            isValidated: true
        )
    }
}
