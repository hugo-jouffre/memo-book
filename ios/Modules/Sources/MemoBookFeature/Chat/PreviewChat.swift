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

    /// Le jour où la bulle « reviens demain » de chaque voyage a été posée :
    /// une fois par voyage et par jour, comme le serveur (`limitNotifiedAt`).
    private var noticedDays: [String: String] = [:]

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

    /// Ouvre le fil d'un voyage créé dans le bac à sable : **vide**, sur
    /// l'accueil de MEMO et la puce du contexte, comme le serveur ouvre celui
    /// d'un carnet neuf — et non sur l'histoire de Rome du jeu d'essai.
    public func open(_ trip: Trip) {
        guard threads[trip.id] == nil else { return }
        var fresh = ChatThread.offline(trip: trip, traveller: HomeFeed.fixture.traveller, isNew: true)
        fresh = ChatThread(
            id: fresh.id,
            title: fresh.title,
            greeting: fresh.greeting,
            context: fresh.context,
            suggestions: responder.opening(for: fresh.context).suggestions
        )
        threads[trip.id] = fresh
        stamps[trip.id] = [:]
    }

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

    /// **La bulle « reviens demain »** (03/10/2026), posée comme le serveur
    /// la pose : quand un tour fait tomber le crédit du jour à zéro, ou quand
    /// un tour est refusé faute de crédit. Une fois par voyage et par jour ;
    /// `nil` quand elle l'est déjà. Datée d'un instant plus tard que le tour,
    /// pour que le sondage la trouve après lui.
    public func noteCreditExhausted(tripId: String, credit: DailyCredit) -> ChatMessage? {
        let now = Date.now
        let day = credit.day ?? ISO8601DateFormatter.memoBookString(from: now).prefix(10).description
        guard noticedDays[tripId] != day else { return nil }
        noticedDays[tripId] = day

        var thread = thread(for: tripId)
        let later = now.addingTimeInterval(0.002)
        let notice = ChatMessage(
            id: "memo-daily-credit-\(tripId)-\(day)",
            author: .memo,
            body: .text(DailyCreditCopy.exhaustedMessage),
            sentAt: later,
            pauseMilliseconds: 900,
            callToAction: .dailyCreditSubscribe
        )
        thread.messages.append(notice)
        stamp(notice, in: tripId, at: later)
        threads[tripId] = thread
        return notice
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
    // Le crédit du jour voyage avec le fil, ses mises à jour et chaque reçu,
    // comme sur le serveur — voir `SandboxCredit` (PreviewSupport.swift).

    public func chatThread(tripId: String) async throws -> ChatThread {
        try SandboxNetwork.failIfOffline()
        var thread = await chat.read(tripId: tripId)
        thread.dailyCredit = sandboxCredit(tripId: tripId)
        return thread
    }

    public func chatUpdates(tripId: String, since: Date) async throws -> ChatThreadUpdate {
        try SandboxNetwork.failIfOffline()
        var update = await chat.updates(tripId: tripId, since: since)
        update.dailyCredit = sandboxCredit(tripId: tripId)
        return update
    }

    public func sendChatText(tripId: String, turn: ChatTextTurn) async throws -> ChatTurnReceipt {
        let credit = try await chargingCredit(tripId: tripId) {
            try chargeSandboxText(turn.text, suggestionId: turn.suggestionId, turnId: turn.id, tripId: tripId)
        }
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
        return await receipt(of: chat.send(tripId: tripId, message: message), tripId: tripId, credit: credit)
    }

    public func sendChatVoice(tripId: String, turn: ChatVoiceTurn) async throws -> ChatTurnReceipt {
        let credit = try await chargingCredit(tripId: tripId) {
            try chargeSandboxVoice(seconds: turn.durationSeconds, turnId: turn.id, tripId: tripId)
        }
        let message = ChatMessage(
            id: turn.id,
            author: .traveller,
            body: .voice(VoiceNote(id: turn.id, duration: turn.durationSeconds, levels: turn.levels)),
            sentAt: turn.capturedAt,
            stepId: turn.stepId,
            disposition: .memory
        )
        return await receipt(of: chat.send(tripId: tripId, message: message), tripId: tripId, credit: credit)
    }

    /// Décompte un tour ; refusé faute de crédit, la bulle « reviens demain »
    /// se pose avant que le refus ne remonte — comme le serveur, qui l'écrit
    /// dans sa propre petite transaction avant de lever le `429`.
    private func chargingCredit(
        tripId: String,
        _ charge: () throws -> DailyCredit
    ) async throws -> DailyCredit {
        do {
            return try charge()
        } catch let error as APIError where error.isDailyCreditExhausted {
            _ = await chat.noteCreditExhausted(tripId: tripId, credit: error.dailyCredit ?? sandboxCredit(tripId: tripId))
            throw error
        }
    }

    /// Le reçu, le crédit compté — et, quand ce tour l'a vidé, la bulle
    /// « reviens demain » avec lui, comme sur le serveur.
    private func receipt(of receipt: ChatTurnReceipt, tripId: String, credit: DailyCredit) async -> ChatTurnReceipt {
        var messages = receipt.messages
        if credit.isExhausted, let notice = await chat.noteCreditExhausted(tripId: tripId, credit: credit) {
            messages.append(notice)
        }
        return ChatTurnReceipt(messages: messages, turn: receipt.turn, now: receipt.now, dailyCredit: credit)
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
        var receipt = await chat.send(tripId: tripId, message: message)
        receipt.dailyCredit = sandboxCredit(tripId: tripId)
        return receipt
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
        return EntryValidation(entry: entry)
    }

    public func clearChat(tripId: String) async throws {
        await chat.clear(tripId: tripId)
    }

    public func entryMedia(id: String) async throws -> Data {
        throw APIError.server(statusCode: 404, code: "not_found", message: "Média introuvable.")
    }

    public func chatMessageMedia(id: String) async throws -> Data {
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
            pauseMilliseconds: pause,
            // Le bouton que le répondeur a posé reste sur la bulle.
            callToAction: callToAction
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
