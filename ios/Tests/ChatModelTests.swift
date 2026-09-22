@testable import MemoBookFeature
import MemoBookCore
import MemoBookNetworking
import XCTest

/// Le déroulé d'un tour, avec un transport scripté : ce que le modèle fait du
/// reçu, du sondage et du rythme — `docs/conversation.md` § 8.
@MainActor
final class ChatModelTests: XCTestCase {
    /// Un transport dont on écrit les réponses d'avance, et qui note ce qu'on
    /// lui a envoyé.
    private actor Script {
        var thread: ChatThread
        /// Le reçu se fabrique **à partir du tour** : c'est lui qui porte
        /// l'identifiant que le serveur reprend.
        var receiptFor: (@Sendable (OutgoingTurn) -> ChatTurnReceipt)?
        var updates: [ChatThreadUpdate] = []
        var sent: [OutgoingTurn] = []
        var edited: [(entryId: String, text: String)] = []
        var polls = 0
        var failsSending: (any Error)?
        /// La file dit que le tour attend le réseau, au lieu de le livrer.
        var queuesSends = false
        /// Ce qui attend sur le disque pour ce fil.
        var waiting: [OutgoingTurn] = []
        /// La file, telle que le modèle l'écoute.
        private let deliveryStream = AsyncStream.makeStream(of: ChatTurnDelivery.self)

        init(thread: ChatThread) { self.thread = thread }

        func send(_ turn: OutgoingTurn) throws -> ChatSendOutcome {
            sent.append(turn)
            if let failsSending { throw failsSending }
            if queuesSends { return .queued }
            return .received(receiptFor?(turn) ?? ChatTurnReceipt(messages: [], turn: .idle, now: .now))
        }

        func deliveries() -> AsyncStream<ChatTurnDelivery> { deliveryStream.stream }
        func deliver(_ delivery: ChatTurnDelivery) { deliveryStream.continuation.yield(delivery) }

        func poll() -> ChatThreadUpdate {
            polls += 1
            return updates.isEmpty
                ? ChatThreadUpdate(messages: [], suggestions: [], turn: .idle, now: .now)
                : updates.removeFirst()
        }

        func edit(_ entryId: String, _ text: String) -> Entry {
            edited.append((entryId, text))
            return Entry(
                id: entryId,
                memoId: "trip",
                kind: .audio,
                status: .ready,
                redactionStatus: .ready,
                editedText: text,
                editedAt: .now,
                capturedAt: .now,
                createdAt: .now
            )
        }

        func answerSends(with factory: @escaping @Sendable (OutgoingTurn) -> ChatTurnReceipt) { receiptFor = factory }
        func queueUpdate(_ update: ChatThreadUpdate) { updates.append(update) }
        func failSending(with error: any Error) { failsSending = error }
        func succeedSending() { failsSending = nil }
        func queueSends() { queuesSends = true }
        func deliverSends() { queuesSends = false }
        func setWaiting(_ turns: [OutgoingTurn]) { waiting = turns }
    }

    private func transport(_ script: Script) -> ChatTransport {
        ChatTransport(
            load: { await script.thread },
            poll: { _ in await script.poll() },
            send: { turn in try await script.send(turn) },
            editTranscript: { entryId, text in await script.edit(entryId, text) },
            media: { _ in Data() },
            waiting: { await script.waiting },
            deliveries: { await script.deliveries() }
        )
    }

    private func thread(messages: [ChatMessage] = [], suggestions: [ChatSuggestion] = []) -> ChatThread {
        ChatThread(
            id: "trip",
            title: "Rome 2026",
            context: ChatContext(tripId: "trip", stepId: "step-3"),
            messages: messages,
            suggestions: suggestions,
            now: .now
        )
    }

    private func memo(_ id: String, _ text: String, seq: Int, pause: Int = 450) -> ChatMessage {
        ChatMessage(id: id, author: .memo, body: .text(text), sentAt: .now, seq: seq, pauseMilliseconds: pause)
    }

    private func card(_ id: String, entryId: String, text: String?, phase: TranscriptCard.Phase, seq: Int, validated: Bool = false) -> ChatMessage {
        ChatMessage(
            id: id,
            author: .memo,
            body: .transcript(
                TranscriptCard(
                    title: "Retranscription du contexte",
                    capturedAt: .now,
                    text: text,
                    entryId: entryId,
                    phase: phase,
                    isValidated: validated
                )
            ),
            sentAt: .now,
            seq: seq
        )
    }

    // MARK: - Envoyer

    /// La bulle se pose avant le réseau, et passe « envoyée » au reçu — sous le
    /// **même** identifiant, avec le rang que le serveur lui donne.
    func testTheBubbleIsPostedBeforeTheNetworkAndConfirmedByTheReceipt() async throws {
        let script = Script(thread: thread())
        await script.answerSends { turn in
            ChatTurnReceipt(
                messages: [
                    ChatMessage(id: "opening", author: .memo, body: .text("Bonjour 👋"), sentAt: .now, seq: 1, pauseMilliseconds: 700),
                    ChatMessage(id: turn.id, author: .traveller, body: .text("Une longue journée à Rome."), sentAt: .now, seq: 2),
                ],
                turn: .replying(messageId: turn.id),
                now: .now
            )
        }
        let model = ChatModel(transport: transport(script))
        await model.load()

        model.draft = "Une longue journée à Rome."
        model.sendDraft()

        let posted = try XCTUnwrap(model.messages.last)
        XCTAssertEqual(posted.delivery, .sending, "La bulle est là avant le réseau.")
        XCTAssertNil(posted.seq)
        let sentId = posted.id

        try await until("le reçu confirme la bulle") {
            model.messages.first { $0.id == sentId }?.delivery == .sent
        }
        XCTAssertEqual(model.messages.map(\.id), ["opening", sentId], "L'ouverture passe devant, par son rang.")
        XCTAssertEqual(model.messages.last?.seq, 2)
        XCTAssertEqual(model.turn, .thinking, "MEMO réfléchit : le reçu dit qu'un tour est en vol.")
        let sentIds = await script.sent.map(\.id)
        XCTAssertEqual(sentIds, [sentId])
    }

    /// Les bulles de MEMO arrivent **dans l'ordre et espacées** : l'indicateur
    /// se rallume entre deux, et les puces ne reviennent qu'à la fin.
    func testMemoBeatsArriveInOrderWithTheirPauses() async throws {
        let script = Script(thread: thread())
        let model = ChatModel(transport: transport(script))
        await model.load()

        await script.answerSends { turn in
            ChatTurnReceipt(
                messages: [ChatMessage(id: turn.id, author: .traveller, body: .text("Coucou"), sentAt: .now, seq: 1)],
                turn: .replying(messageId: turn.id),
                now: .now
            )
        }
        await script.queueUpdate(
            ChatThreadUpdate(
                messages: [memo("b", "Deuxième", seq: 3, pause: 450), memo("a", "Première", seq: 2, pause: 450)],
                suggestions: [ChatSuggestion(id: "voice", label: "Je te raconte à l’oral")],
                turn: .idle,
                now: .now
            )
        )

        model.draft = "Coucou"
        model.sendDraft()

        try await until("la première bulle", timeout: .seconds(4)) { model.messages.count == 2 }
        XCTAssertEqual(model.messages.last?.id, "a", "Le rang du serveur, pas l'ordre du tableau.")
        XCTAssertEqual(model.turn, .thinking, "L'indicateur reste allumé entre deux bulles.")
        XCTAssertTrue(model.visibleSuggestions.isEmpty)

        try await until("la seconde bulle", timeout: .seconds(4)) { model.messages.count == 3 }
        try await until("le repos") { model.turn == .idle }
        let firstSent = await script.sent.first
        let id = try XCTUnwrap(firstSent?.id)
        XCTAssertEqual(model.messages.map(\.id), [id, "a", "b"])
        XCTAssertEqual(model.visibleSuggestions.map(\.id), ["voice"])
    }

    /// Une fiche qui mûrit se remplace **sans pause** — ce n'est pas une bulle
    /// qui arrive, c'est la même qui change —, et le sondage s'arrête quand
    /// elle est prête.
    func testASettlingCardIsReplacedInPlaceAndPollingStopsWhenReady() async throws {
        let script = Script(thread: thread(messages: [card("c", entryId: "e1", text: nil, phase: .listening, seq: 1)]))
        let model = ChatModel(transport: transport(script))
        await script.queueUpdate(
            ChatThreadUpdate(messages: [card("c", entryId: "e1", text: "brut", phase: .writing, seq: 1)], turn: .idle, now: .now)
        )
        await script.queueUpdate(
            ChatThreadUpdate(messages: [card("c", entryId: "e1", text: "rédigé", phase: .ready, seq: 1)], turn: .idle, now: .now)
        )

        await model.load()
        XCTAssertEqual(model.turn, .idle, "Une fiche qui mûrit ne bloque pas le composeur.")

        try await until("le brut", timeout: .seconds(4)) {
            if case .transcript(let card) = model.messages.first?.body { return card.text == "brut" }
            return false
        }
        XCTAssertEqual(model.messages.count, 1)

        try await until("le rédigé", timeout: .seconds(4)) {
            if case .transcript(let card) = model.messages.first?.body { return card.phase == .ready }
            return false
        }
        let pollsAtReady = await script.polls
        try await Task.sleep(for: .seconds(2.5))
        let pollsLater = await script.polls
        XCTAssertEqual(pollsLater, pollsAtReady, "Plus rien à attendre : le sondage s'est tu.")
    }

    // MARK: - Valider, corriger

    /// « Ça me convient » vise la dernière fiche du fil, par son souvenir.
    func testAcceptSendsTheSuggestionWithTheLatestCardEntry() async throws {
        let script = Script(
            thread: thread(
                messages: [
                    card("c1", entryId: "e1", text: "hier", phase: .ready, seq: 1),
                    card("c2", entryId: "e2", text: "aujourd’hui", phase: .ready, seq: 2),
                ],
                suggestions: [ChatSuggestion(id: "accept", label: "Ça me convient")]
            )
        )
        let model = ChatModel(transport: transport(script))
        await model.load()

        model.choose(ChatSuggestion(id: "accept", label: "Ça me convient")) { XCTFail("pas de photos") }

        try await until("l'envoi") { await script.sent.count == 1 }
        let accepted = await script.sent
        guard case .text(let text, let suggestionId, let entryId) = accepted[0].body else {
            return XCTFail("un texte")
        }
        XCTAssertEqual(text, "Ça me convient")
        XCTAssertEqual(suggestionId, "accept")
        XCTAssertEqual(entryId, "e2")
    }

    /// « À la main » : le texte de la fiche est dans le champ ; envoyer corrige
    /// le souvenir, redessine la fiche, puis fait accuser réception à MEMO.
    func testEditingByHandPatchesTheEntryThenAcknowledges() async throws {
        let script = Script(
            thread: thread(messages: [card("c", entryId: "e1", text: "le texte de MEMO", phase: .ready, seq: 1)])
        )
        let model = ChatModel(transport: transport(script))
        await model.load()

        model.choose(
            ChatSuggestion(id: "edit-hand", label: "À la main", intent: .sendThenEditTranscript)
        ) { XCTFail("pas de photos") }
        XCTAssertEqual(model.draft, "le texte de MEMO")
        XCTAssertTrue(model.isEditingTranscript)
        XCTAssertEqual(model.composer, .writing)

        model.draft = "ma version"
        model.sendDraft()

        try await until("la correction") { await script.edited.count == 1 }
        let edited = await script.edited
        XCTAssertEqual(edited.first?.entryId, "e1")
        XCTAssertEqual(edited.first?.text, "ma version")
        try await until("l'accusé") { await script.sent.count == 2 }
        let sentTurns = await script.sent
        guard case .text(_, let suggestionId, let entryId) = sentTurns[1].body else { return XCTFail("un texte") }
        XCTAssertEqual(suggestionId, "transcript_edited")
        XCTAssertEqual(entryId, "e1")

        guard case .transcript(let card) = model.messages.first?.body else { return XCTFail("une fiche") }
        XCTAssertEqual(card.text, "ma version")
        XCTAssertFalse(model.isEditingTranscript)
    }

    // MARK: - Hors ligne

    /// Un tour qui attend le réseau **n'a pas échoué** : la bulle reste « en
    /// cours d'envoi », le composeur se rouvre, et c'est la file qui la
    /// termine — par son identifiant, avec le reçu du serveur, dont le fil
    /// prend les bulles et le tour en vol. Un tour d'un autre voyage ne
    /// touche à rien.
    func testAQueuedTurnStaysSendingUntilTheQueueSaysItLeft() async throws {
        let script = Script(thread: thread())
        await script.queueSends()
        let model = ChatModel(transport: transport(script))
        await model.load()

        model.draft = "Dit dans le métro."
        model.sendDraft()
        let id = try XCTUnwrap(model.messages.last?.id)

        try await until("le tour est confié à la file") { await script.sent.count == 1 }
        try await until("le composeur se rouvre") { model.turn == .idle }
        XCTAssertEqual(model.messages.last?.delivery, .sending)
        XCTAssertNil(model.errorMessage)

        await script.deliver(ChatTurnDelivery(id: id, tripId: "ailleurs", state: .failed("non")))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.messages.last?.delivery, .sending, "Le sort d'un tour d'un autre voyage ne regarde pas ce fil.")

        await script.deliver(
            ChatTurnDelivery(
                id: id,
                tripId: "trip",
                state: .sent,
                receipt: ChatTurnReceipt(
                    messages: [ChatMessage(id: id, author: .traveller, body: .text("Dit dans le métro."), sentAt: .now, seq: 7)],
                    turn: .replying(messageId: id),
                    now: .now
                )
            )
        )
        try await until("la bulle est envoyée") { model.messages.last?.delivery == .sent }
        XCTAssertEqual(model.messages.last?.seq, 7, "Le rang du serveur, pris dans le reçu.")
        XCTAssertEqual(model.turn, .thinking, "Le reçu dit que MEMO répond : on l'attend.")
        XCTAssertEqual(model.messages.count, 1)
    }

    /// La file a vu le serveur refuser un tour parti d'ici : la bulle passe
    /// « non envoyée », et « Réessayer » le renvoie **sous le même
    /// identifiant** — même si le modèle ne le tenait plus en main.
    func testARefusalFromTheQueueIsRetriedUnderTheSameId() async throws {
        let script = Script(thread: thread())
        await script.queueSends()
        let model = ChatModel(transport: transport(script))
        await model.load()

        model.draft = "Refusé plus tard."
        model.sendDraft()
        let id = try XCTUnwrap(model.messages.last?.id)
        try await until("le composeur se rouvre") { model.turn == .idle }

        await script.deliver(ChatTurnDelivery(id: id, tripId: "trip", state: .failed("Quota atteint.")))
        try await until("la bulle est non envoyée") { model.messages.last?.delivery.hasFailed == true }

        await script.deliverSends()
        model.retry()
        try await until("le renvoi aboutit") { model.messages.last?.delivery == .sent }
        let sentIds = await script.sent.map(\.id)
        XCTAssertEqual(sentIds, [id, id])
        XCTAssertEqual(model.messages.count, 1)
    }

    /// Ce qui attend sur le disque pour ce fil se pose en bulles « en cours
    /// d'envoi » à l'ouverture — et pas deux fois quand on recharge.
    func testWhatWaitsOnDiskIsPostedAsSendingBubbles() async throws {
        let script = Script(thread: thread(messages: [memo("opening", "Bonjour 👋", seq: 1)]))
        await script.setWaiting([
            OutgoingTurn(id: "w-1", body: .text("Hier soir")),
            OutgoingTurn(id: "w-2", body: .text("Ce matin")),
        ])
        let model = ChatModel(transport: transport(script))
        await model.load()

        XCTAssertEqual(model.messages.map(\.id), ["opening", "w-1", "w-2"], "Après le fil, dans l'ordre de la file.")
        XCTAssertEqual(model.messages.dropFirst().map(\.delivery), [.sending, .sending])
        XCTAssertEqual(model.turn, .idle)

        await model.load()
        XCTAssertEqual(model.messages.count, 3, "Recharger ne double pas ce qui attend.")
    }

    // MARK: - Échouer

    /// Une panne laisse la bulle « non envoyée », et ``ChatModel/retry()`` la
    /// renvoie sous le même identifiant — jamais une seconde bulle.
    func testAFailureKeepsTheBubbleAndRetryResendsTheSameId() async throws {
        let script = Script(thread: thread())
        await script.failSending(with: URLError(.notConnectedToInternet))
        let model = ChatModel(transport: transport(script))
        await model.load()

        model.draft = "Une longue journée à Rome."
        model.sendDraft()

        try await until("l'échec") { model.messages.last?.delivery.hasFailed == true }
        guard case .failed(let messageId, _) = model.turn else { return XCTFail("un échec") }
        XCTAssertEqual(messageId, model.messages.last?.id)
        XCTAssertTrue(model.isComposerEnabled, "On ne piège personne derrière un message qui ne passe pas.")

        await script.succeedSending()
        model.retry()
        try await until("le renvoi") { model.messages.last?.delivery == .sent }
        XCTAssertEqual(model.messages.count, 1)
        let resent = await script.sent.map(\.id)
        XCTAssertEqual(resent.count, 2)
        XCTAssertEqual(Set(resent).count, 1)
    }

    // MARK: -

    private func until(
        _ what: String,
        timeout: Duration = .seconds(2),
        _ condition: @MainActor () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Jamais atteint : \(what)", file: file, line: line)
    }
}
