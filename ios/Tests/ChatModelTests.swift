@testable import MemoBookFeature
import MemoBookCore
import MemoBookNetworking
import MemoBookRecording
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
        var failsEditing: (any Error)?
        /// Le tour met ce temps à monter — un vocal en 3G.
        var sendDelay: Duration?
        /// La file dit que le tour attend le réseau, au lieu de le livrer.
        var queuesSends = false
        /// Le serveur est injoignable : le fil s'ouvre en local.
        var isOffline = false
        /// Ce qui attend sur le disque pour ce fil.
        var waiting: [OutgoingTurn] = []
        /// Les tours que l'écran a demandé à la file d'oublier.
        var discarded: [String] = []
        /// La file, telle que le modèle l'écoute.
        private let deliveryStream = AsyncStream.makeStream(of: ChatTurnDelivery.self)

        init(thread: ChatThread) { self.thread = thread }

        func send(_ turn: OutgoingTurn) async throws -> ChatSendOutcome {
            sent.append(turn)
            if let sendDelay { try await Task.sleep(for: sendDelay) }
            if let failsSending { throw failsSending }
            if queuesSends { return .queued }
            return .received(receiptFor?(turn) ?? ChatTurnReceipt(messages: [], turn: .idle, now: .now))
        }

        func deliveries() -> AsyncStream<ChatTurnDelivery> { deliveryStream.stream }
        func discard(_ id: String) -> Bool {
            discarded.append(id)
            return true
        }
        func deliver(_ delivery: ChatTurnDelivery) { deliveryStream.continuation.yield(delivery) }

        func poll() -> ChatThreadUpdate {
            polls += 1
            return updates.isEmpty
                ? ChatThreadUpdate(messages: [], suggestions: [], turn: .idle, now: .now)
                : updates.removeFirst()
        }

        func edit(_ entryId: String, _ text: String) throws -> Entry {
            edited.append((entryId, text))
            if let failsEditing { throw failsEditing }
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
        func failEditing(with error: (any Error)?) { failsEditing = error }
        func delaySends(by delay: Duration?) { sendDelay = delay }
        func succeedSending() { failsSending = nil }
        func queueSends() { queuesSends = true }
        func deliverSends() { queuesSends = false }
        func setWaiting(_ turns: [OutgoingTurn]) { waiting = turns }
        func goOffline() { isOffline = true }
        func goOnline(with thread: ChatThread) {
            isOffline = false
            self.thread = thread
        }
    }

    private func transport(_ script: Script) -> ChatTransport {
        ChatTransport(
            load: {
                if await script.isOffline { throw APIError.transport(URLError(.notConnectedToInternet), url: nil) }
                return await script.thread
            },
            poll: { _ in await script.poll() },
            send: { turn in try await script.send(turn) },
            editTranscript: { entryId, text in try await script.edit(entryId, text) },
            media: { _ in Data() },
            waiting: { await script.waiting },
            deliveries: { await script.deliveries() },
            offlineThread: { _ in await script.isOffline ? await script.thread : nil },
            discard: { id in await script.discard(id) }
        )
    }

    private func thread(
        messages: [ChatMessage] = [],
        suggestions: [ChatSuggestion] = [],
        credit: DailyCredit? = nil
    ) -> ChatThread {
        ChatThread(
            id: "trip",
            title: "Rome 2026",
            context: ChatContext(tripId: "trip", stepId: "step-3"),
            messages: messages,
            suggestions: suggestions,
            now: .now,
            dailyCredit: credit
        )
    }

    /// Un crédit du jour dont il reste `remainingMs`.
    private func credit(remainingMs: Int, isUnlimited: Bool = false) -> DailyCredit {
        DailyCredit(
            isUnlimited: isUnlimited,
            usedMs: DailyCredit.Catalog.limitMs - remainingMs,
            day: "2026-10-03",
            resetsAt: .now.addingTimeInterval(3_600)
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

    /// La bande de suggestions garde sa place pendant le tour : ses puces
    /// s'effacent, sa hauteur reste — sinon le fil se tassait sous le message
    /// qu'on venait de poser (T207, 30/09/2026).
    func testTheSuggestionRailKeepsItsPlaceWhileMemoAnswers() async throws {
        let script = Script(
            thread: thread(suggestions: [ChatSuggestion(id: "accept", label: "Ça me convient")])
        )
        await script.answerSends { turn in
            ChatTurnReceipt(
                messages: [ChatMessage(id: turn.id, author: .traveller, body: .text("Ça me convient"), sentAt: .now, seq: 1)],
                turn: .replying(messageId: turn.id),
                now: .now
            )
        }
        let model = ChatModel(transport: transport(script))
        await model.load()
        XCTAssertFalse(model.reservesSuggestionRail, "Au repos, la bande montre ses puces.")

        model.choose(ChatSuggestion(id: "accept", label: "Ça me convient")) { XCTFail("pas de photos") }
        try await until("le tour") { model.turn != .idle }

        XCTAssertTrue(model.visibleSuggestions.isEmpty, "Les puces s'effacent pendant le tour.")
        XCTAssertTrue(model.reservesSuggestionRail, "Mais la bande garde sa hauteur.")
    }

    /// Sans puces au départ du tour, il n'y a pas de place à garder.
    func testNoRailSpaceIsKeptWhenThereWereNoSuggestions() async throws {
        let script = Script(thread: thread())
        await script.answerSends { turn in
            ChatTurnReceipt(messages: [], turn: .replying(messageId: turn.id), now: .now)
        }
        let model = ChatModel(transport: transport(script))
        await model.load()

        model.draft = "Une journée à Rome."
        model.sendDraft()
        try await until("le tour") { model.turn != .idle }

        XCTAssertFalse(model.reservesSuggestionRail)
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

    // MARK: - Le crédit du jour

    /// Le crédit du fil se décompte **à l'envoi**, sans attendre le reçu — un
    /// texte, 75 ms par caractère ; une puce, rien —, et le reçu remet le
    /// chiffre du serveur.
    func testTheCreditIsSpentLocallyThenTakenFromTheReceipt() async throws {
        let script = Script(thread: thread(credit: credit(remainingMs: 200_000)))
        await script.queueSends()
        let model = ChatModel(transport: transport(script), callToActionMemory: .inMemory())
        await model.load()
        XCTAssertEqual(model.dailyCredit?.remainingMs, 200_000)

        model.draft = "Dix lettres"
        model.sendDraft()
        XCTAssertEqual(model.dailyCredit?.remainingMs, 200_000 - 11 * 75, "Onze caractères, décomptés tout de suite.")

        model.choose(
            ChatSuggestion(id: "later", label: "Plus tard", symbol: nil, intent: .send),
            addPhotos: {}
        )
        XCTAssertEqual(model.dailyCredit?.remainingMs, 200_000 - 11 * 75, "Une puce ne coûte rien.")

        await script.deliverSends()
        let served = credit(remainingMs: 150_000)
        await script.answerSends { turn in
            ChatTurnReceipt(messages: [], turn: .idle, now: .now, dailyCredit: served)
        }
        model.draft = "Encore"
        model.sendDraft()
        // Le chiffre du serveur, moins le premier texte — toujours en file :
        // le serveur ne l'a pas reçu, son crédit ne le compte pas.
        try await until("le reçu remet le chiffre du serveur") {
            model.dailyCredit?.remainingMs == 150_000 - 11 * 75
        }
    }

    /// Un brouillon plus long que le reste du jour ne part pas : l'envoi
    /// pâlit et la boîte dit combien il reste. Sous une minute de crédit, un
    /// brouillon qui passe porte le rappel discret des caractères.
    func testADraftLongerThanTheCreditCannotBeSent() async throws {
        let script = Script(thread: thread(credit: credit(remainingMs: 1_500)))  // 20 caractères
        let model = ChatModel(transport: transport(script), callToActionMemory: .inMemory())
        await model.load()
        model.composer = .writing

        model.draft = String(repeating: "a", count: 30)
        XCTAssertTrue(model.draftExceedsCredit)
        XCTAssertFalse(model.canSendDraft)
        XCTAssertEqual(model.creditTextNotice, .tooLong(DailyCreditCopy.textTooLong(charactersLeft: 20)))
        model.sendDraft()
        let nothingSent = await script.sent
        XCTAssertTrue(nothingSent.isEmpty, "Le serveur le refuserait en entier : l'app l'en empêche avant.")
        XCTAssertEqual(model.draft.count, 30, "Le brouillon reste, rien n'est perdu.")

        model.draft = "Court"
        XCTAssertTrue(model.canSendDraft)
        XCTAssertEqual(model.creditTextNotice, .reminder(ChatCopy.Credit.charactersLeft(20)))
    }

    /// Crédit épuisé : le micro et le clavier ne s'ouvrent pas, ils font
    /// paraître le bandeau « épuisé » — qui **passe** : il s'efface au geste
    /// suivant, ou de lui-même. Les puces, gratuites, restent là ; « Raconter
    /// à l'oral », qui n'armerait qu'un micro fermé, se tait.
    func testAnExhaustedCreditShowsTheBannerInsteadOfOpeningTheMicrophone() async throws {
        let accept = ChatSuggestion(id: "accept", label: "Ça me convient", intent: .send)
        let speak = ChatSuggestion(id: "edit-voice", label: "Je raconte à l’oral", intent: .sendThenSpeak)
        let script = Script(thread: thread(suggestions: [accept, speak], credit: credit(remainingMs: 0)))
        let model = ChatModel(transport: transport(script), callToActionMemory: .inMemory())
        await model.load()

        XCTAssertTrue(model.isCreditExhausted)
        XCTAssertNil(model.creditBanner, "Rien tant qu'on n'a rien touché.")
        XCTAssertEqual(model.visibleSuggestions.map(\.id), ["accept"], "Pas de micro à armer.")

        model.tapMicrophone()
        XCTAssertEqual(model.composer, .tools, "Le micro ne s'arme pas.")
        XCTAssertFalse(model.recorder.isRecording)
        XCTAssertEqual(model.creditBanner, .exhausted)
        XCTAssertEqual(model.visibleSuggestions.map(\.id), ["accept"], "Les puces restent à portée de doigt.")

        // Le geste suivant l'emporte : une puce.
        model.choose(accept, addPhotos: {})
        XCTAssertNil(model.creditBanner)

        // Et seul, il s'en va aussi.
        model.exhaustedNoticeLinger = .milliseconds(50)
        XCTAssertFalse(model.tapKeyboard(), "Le clavier ne s'ouvre pas sur un texte qui ne partirait pas.")
        XCTAssertEqual(model.creditBanner, .exhausted)
        try await until("le bandeau s'efface de lui-même") { model.creditBanner == nil }
    }

    /// Un abonné ne voit rien de tout ça : ni bandeau, ni limite de texte.
    func testASubscriberSeesNoneOfIt() async throws {
        let script = Script(thread: thread(credit: credit(remainingMs: 0, isUnlimited: true)))
        let model = ChatModel(transport: transport(script), callToActionMemory: .inMemory())
        await model.load()
        model.composer = .writing
        model.draft = String(repeating: "a", count: 10_000)

        XCTAssertFalse(model.isCreditExhausted)
        XCTAssertFalse(model.draftExceedsCredit)
        XCTAssertNil(model.creditTextNotice)
        XCTAssertNil(model.creditBanner)
        XCTAssertTrue(model.canSendDraft)
    }

    /// La file a vu le serveur refuser faute de crédit : la bulle attend
    /// demain — pas de « Non envoyé », pas de renvoi en boucle — et la barre
    /// passe à « épuisé ».
    func testACreditRefusalWaitsForTomorrowInsteadOfFailing() async throws {
        let script = Script(thread: thread(credit: credit(remainingMs: 2_000)))
        await script.queueSends()
        let model = ChatModel(transport: transport(script), callToActionMemory: .inMemory())
        await model.load()

        model.draft = "Un mot"
        model.sendDraft()
        let id = try XCTUnwrap(model.messages.last?.id)
        try await until("le composeur se rouvre") { model.turn == .idle }

        let tomorrow = Date.now.addingTimeInterval(7_200)
        await script.deliver(
            ChatTurnDelivery(
                id: id,
                tripId: "trip",
                state: .waitingForCredit(until: tomorrow),
                credit: credit(remainingMs: 0)
            )
        )
        try await until("la bulle attend demain") { model.messages.last?.delivery.isWaitingForCredit == true }
        XCTAssertFalse(model.messages.last?.delivery.hasFailed ?? true)
        XCTAssertTrue(model.isCreditExhausted)

        model.retry()
        try await Task.sleep(for: .milliseconds(100))
        let sent = await script.sent
        XCTAssertEqual(sent.count, 1, "Rien à réessayer : la file le renverra à la recharge.")
    }

    /// Un transport sans file — les aperçus — rend le refus tel quel : la
    /// bulle attend demain plutôt que d'échouer.
    func testADirectCreditRefusalIsNotAFailure() async throws {
        let script = Script(thread: thread(credit: credit(remainingMs: 1_000)))
        await script.failSending(
            with: APIError.dailyCreditExhausted(message: "Épuisé.", credit: credit(remainingMs: 0))
        )
        let model = ChatModel(transport: transport(script), callToActionMemory: .inMemory())
        await model.load()

        model.draft = "Un"
        model.sendDraft()
        try await until("la bulle attend demain") { model.messages.last?.delivery.isWaitingForCredit == true }
        XCTAssertEqual(model.turn, .idle)
        XCTAssertTrue(model.isCreditExhausted)
    }

    /// Ce qui attend le crédit de demain sur le disque se rouvre en « Partira
    /// demain », et ne se décompte pas du crédit d'aujourd'hui.
    func testATurnWaitingForCreditReopensAsLeavingTomorrow() async throws {
        let tomorrow = Date.now.addingTimeInterval(3_600)
        let script = Script(thread: thread(credit: credit(remainingMs: 60_000)))
        await script.setWaiting([
            OutgoingTurn(id: "w-1", body: .text("Hier soir"), waitingForCreditUntil: tomorrow),
            OutgoingTurn(id: "w-2", body: .text("Ce matin")),
        ])
        let model = ChatModel(transport: transport(script), callToActionMemory: .inMemory())
        await model.load()

        XCTAssertEqual(model.messages.map(\.delivery), [.waitingForCredit(until: tomorrow), .sending])
        XCTAssertEqual(model.dailyCredit?.remainingMs, 60_000 - 8 * 75, "Seul « Ce matin » entame aujourd'hui.")
    }

    /// Refusé hier soir jusqu'à minuit, rouvert ce matin : l'attente est
    /// échue. La bulle n'est plus « Partira demain » — la file l'enverra dès
    /// la reconnexion —, et son coût entame le crédit d'aujourd'hui, celui du
    /// jour où il part.
    func testATurnWhoseWaitIsOverReopensAsSendingAndCountsToday() async throws {
        let midnight = Date.now.addingTimeInterval(-8 * 3_600)
        let script = Script(thread: thread(credit: credit(remainingMs: 300_000)))
        await script.setWaiting([
            OutgoingTurn(id: "hier", body: .text(String(repeating: "a", count: 2_400)), waitingForCreditUntil: midnight),
        ])
        let model = ChatModel(transport: transport(script), callToActionMemory: .inMemory())
        await model.load()

        XCTAssertEqual(model.messages.map(\.delivery), [.sending], "Plus « Partira demain » : il part à la reconnexion.")
        XCTAssertEqual(model.dailyCredit?.remainingMs, 120_000, "Trois minutes de texte, comptées aujourd'hui.")
    }

    /// Le reçu du tour qui vide le crédit apporte la bulle « reviens demain »
    /// et son bouton ; touché ou ignoré, c'est retenu par bulle, d'un écran à
    /// l'autre.
    func testTheExhaustedNoticeCarriesACallToActionWhoseStateIsRemembered() async throws {
        let script = Script(thread: thread(credit: credit(remainingMs: 1_000)))
        await script.answerSends { turn in
            ChatTurnReceipt(
                messages: [
                    ChatMessage(id: turn.id, author: .traveller, body: .text("Fin"), sentAt: .now, seq: 1),
                    ChatMessage(
                        id: "notice",
                        author: .memo,
                        body: .text(DailyCreditCopy.exhaustedMessage),
                        sentAt: .now,
                        seq: 2,
                        callToAction: .dailyCreditSubscribe
                    ),
                ],
                turn: .idle,
                now: .now,
                dailyCredit: DailyCredit(usedMs: DailyCredit.Catalog.limitMs)
            )
        }
        let memory = ChatCallToActionMemory.inMemory()
        let model = ChatModel(transport: transport(script), callToActionMemory: memory)
        await model.load()

        model.draft = "Fin"
        model.sendDraft()
        try await until("la bulle de MEMO arrive") { model.messages.contains { $0.id == "notice" } }
        XCTAssertEqual(model.messages.last?.callToAction, .dailyCreditSubscribe)
        XCTAssertTrue(model.isCreditExhausted)
        XCTAssertEqual(model.callToActionState(for: "notice"), .pending)

        model.followCallToAction(of: "notice")
        XCTAssertEqual(model.callToActionState(for: "notice"), .followed)

        let reopened = ChatModel(transport: transport(script), callToActionMemory: memory)
        XCTAssertEqual(reopened.callToActionState(for: "notice"), .followed, "Retenu sur l'appareil, pas sur l'écran.")
        reopened.dismissCallToAction(of: "notice")
        XCTAssertEqual(memory.state(for: "notice"), .dismissed)
    }

    /// Hors ligne, le vocal de l'accueil coupé par la limite arrive avec la
    /// bulle « reviens demain » de l'app ; celle du serveur la remplace au
    /// retour — une seule, et la vraie.
    func testTheLocalNoticeIsReplacedByTheServers() async throws {
        // Un voyage à part : le dernier crédit connu de chaque voyage se garde
        // le temps que l'app vive, et les autres tests en laissent sur « trip ».
        let offlineThread = ChatThread(
            id: "trip-offline",
            title: "Rome 2026",
            context: ChatContext(tripId: "trip-offline", stepId: nil),
            now: .now,
            dailyCredit: credit(remainingMs: 4_000)
        )
        let script = Script(thread: offlineThread)
        await script.goOffline()
        let model = ChatModel(transport: transport(script), callToActionMemory: .inMemory())
        let audio = RecordedAudio(data: Data("vocal".utf8), filename: "v.m4a", mimeType: "audio/mp4", duration: 4, recordedAt: .now)
        let handoff = RecordingHandoff(audio: audio, levels: [], stoppedAtLimit: true)
        model.expect(handoff)
        await model.load()

        XCTAssertTrue(model.isOffline)
        XCTAssertEqual(model.messages.map(\.id).first, handoff.id)
        let local = try XCTUnwrap(model.messages.last)
        XCTAssertTrue(local.id.hasPrefix(ChatModel.localNoticePrefix))
        XCTAssertEqual(local.callToAction, .dailyCreditSubscribe)
        XCTAssertTrue(model.isCreditExhausted, "Le vocal coupé a vidé le crédit.")

        // Le réseau revient : le vocal arrive, avec la bulle du serveur.
        let serverNotice = ChatMessage(
            id: "server-notice",
            author: .memo,
            body: .text(DailyCreditCopy.exhaustedMessage),
            sentAt: .now,
            seq: 9,
            callToAction: .dailyCreditSubscribe
        )
        var online = offlineThread
        online.messages = [serverNotice]
        await script.goOnline(with: online)
        await script.deliver(
            ChatTurnDelivery(
                id: handoff.id,
                tripId: "trip-offline",
                state: .sent,
                receipt: ChatTurnReceipt(messages: [serverNotice], turn: .idle, now: .now)
            )
        )
        try await until("la bulle du serveur chasse celle de l'app") {
            model.messages.contains { $0.id == "server-notice" }
                && !model.messages.contains { $0.id.hasPrefix(ChatModel.localNoticePrefix) }
        }
    }

    // MARK: - Le crédit servi et le crédit estimé

    /// Rouvrir le fil hors ligne repart du dernier crédit **servi**, moins ce
    /// qui attend dans la file — une fois. Le décompte n'est pas retenu : trois
    /// réouvertures ne retirent pas trois fois le même texte.
    func testReopeningOfflineDoesNotSpendTheQueueTwice() async throws {
        let tripId = "trip-reopened-offline"
        let offline = ChatThread(
            id: tripId,
            title: "Rome 2026",
            context: ChatContext(tripId: tripId, stepId: nil),
            now: .now,
            dailyCredit: credit(remainingMs: 300_000)
        )
        for opening in 1...3 {
            // Un transport neuf à chaque ouverture, comme l'écran en reçoit un
            // d'`AppDependencies` ; le dernier crédit servi, lui, se garde
            // d'un écran à l'autre.
            let script = Script(thread: offline)
            await script.goOffline()
            // Mille six cents caractères : deux minutes de crédit.
            await script.setWaiting([OutgoingTurn(id: "queued", body: .text(String(repeating: "a", count: 1_600)))])
            let model = ChatModel(transport: transport(script), callToActionMemory: .inMemory())
            await model.load()
            XCTAssertTrue(model.isOffline)
            XCTAssertEqual(model.dailyCredit?.remainingMs, 180_000, "Ouverture n° \(opening) : le texte en file, une fois.")
            await model.load()
            XCTAssertEqual(model.dailyCredit?.remainingMs, 180_000, "Recharger le même écran non plus.")
            model.teardown()
        }
    }

    /// Hors ligne, le dernier crédit retenu par un fil ne passe plus devant
    /// un cache plus récent : retenu à 9 h (rien consommé), il cède devant
    /// celui que l'accueil a relu à 14 h, après les 4 minutes d'un
    /// co-voyageur.
    func testOfflineTheFresherOfRememberedAndCachedCreditWins() async throws {
        let tripId = "trip-retenu-puis-relu"
        ChatModel.forgetRememberedCredits()
        let online = ChatThread(
            id: tripId,
            title: "Rome 2026",
            context: ChatContext(tripId: tripId, stepId: nil),
            now: .now,
            dailyCredit: credit(remainingMs: 300_000)
        )
        let morning = ChatModel(transport: transport(Script(thread: online)), callToActionMemory: .inMemory())
        await morning.load()
        XCTAssertEqual(morning.dailyCredit?.remainingMs, 300_000)
        morning.teardown()

        // Dans le métro : le fil local porte le crédit des caches, plus avancé.
        var cached = online
        cached.dailyCredit = credit(remainingMs: 60_000)
        let script = Script(thread: cached)
        await script.goOffline()
        let afternoon = ChatModel(transport: transport(script), callToActionMemory: .inMemory())
        await afternoon.load()
        XCTAssertTrue(afternoon.isOffline)
        XCTAssertEqual(afternoon.dailyCredit?.remainingMs, 60_000, "Le plus consommé du jour, pas le premier retenu.")
    }

    /// Le crédit retenu appartient au compte qui l'a lu : déconnecté, il est
    /// oublié. B, connecté après A (abonné) sur le même iPhone, ne se croit
    /// pas illimité hors ligne, et sa session n'apprend rien.
    func testTheRememberedCreditDoesNotFollowTheNextAccount() async throws {
        let tripId = "trip-partage-entre-comptes"
        ChatModel.forgetRememberedCredits()
        let thread = ChatThread(
            id: tripId,
            title: "Rome 2026",
            context: ChatContext(tripId: tripId, stepId: nil),
            now: .now,
            dailyCredit: credit(remainingMs: 300_000, isUnlimited: true)
        )
        let alice = ChatModel(transport: transport(Script(thread: thread)), callToActionMemory: .inMemory())
        await alice.load()
        XCTAssertEqual(alice.credit?.isUnlimited, true)
        alice.teardown()

        // A se déconnecte — ce que fait `AppDependencies.forgetAccountContent()`.
        ChatModel.forgetRememberedCredits()

        var offline = thread
        offline.dailyCredit = credit(remainingMs: 180_000)
        let script = Script(thread: offline)
        await script.goOffline()
        let session = SubscriptionSession()
        let bob = ChatModel(transport: transport(script), callToActionMemory: .inMemory())
        bob.subscription = session
        await bob.load()

        XCTAssertEqual(bob.credit?.isUnlimited, false, "Le fil de B compte.")
        XCTAssertEqual(bob.credit?.remainingMs, 180_000)
        XCTAssertNil(session.known, "La session de B n'apprend pas l'abonnement de A.")
        XCTAssertEqual(session.paywallVariant, .firstTime)
    }

    /// Une lecture du fil pendant qu'un tour monte ne rend pas son coût : le
    /// serveur ne l'a pas encore reçu, son chiffre ne le compte pas. Le reçu,
    /// lui, remet le chiffre du serveur.
    func testAReadDuringASendKeepsTheTurnCounted() async throws {
        let script = Script(thread: thread(credit: credit(remainingMs: 200_000)))
        await script.delaySends(by: .milliseconds(400))
        let cost = 11 * 75
        let afterTheTurn = credit(remainingMs: 200_000 - cost)
        await script.answerSends { _ in ChatTurnReceipt(messages: [], turn: .idle, now: .now, dailyCredit: afterTheTurn) }
        await script.queueUpdate(
            ChatThreadUpdate(messages: [], turn: .idle, now: .now, dailyCredit: credit(remainingMs: 200_000))
        )
        let model = ChatModel(transport: transport(script), callToActionMemory: .inMemory())
        await model.load()

        model.draft = "Dix lettres"
        model.sendDraft()
        XCTAssertEqual(model.dailyCredit?.remainingMs, 200_000 - cost)

        // Une lecture pendant que le tour monte : le chiffre servi, sans lui.
        model.refreshAfterSubscribing()
        try await until("la lecture est passée") { await script.polls == 1 }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.dailyCredit?.remainingMs, 200_000 - cost, "La barre ne remonte pas de ce qui est en route.")

        try await until("le reçu") { model.messages.last?.delivery == .sent }
        XCTAssertEqual(model.dailyCredit?.remainingMs, 200_000 - cost, "Le reçu le compte, une fois.")
    }

    /// Une correction « à la main » refusée — faute de crédit, ou autrement —
    /// garde son brouillon : le texte revient dans le champ, sur la même
    /// fiche, et le renvoyer la corrige bien.
    func testARefusedHandEditKeepsItsDraft() async throws {
        let script = Script(
            thread: thread(
                messages: [card("c", entryId: "e1", text: "le texte de MEMO", phase: .ready, seq: 1)],
                credit: credit(remainingMs: 60_000)
            )
        )
        await script.failEditing(with: APIError.dailyCreditExhausted(message: "Épuisé.", credit: credit(remainingMs: 0)))
        let model = ChatModel(transport: transport(script), callToActionMemory: .inMemory())
        await model.load()

        model.edit(model.messages[0])
        model.draft = "le texte de MEMO, et la suite que j’ai tapée"
        model.sendDraft()

        try await until("le refus") { model.errorMessage != nil }
        XCTAssertEqual(model.draft, "le texte de MEMO, et la suite que j’ai tapée", "Rien de ce qu'on a tapé ne se perd.")
        XCTAssertTrue(model.isEditingTranscript)
        XCTAssertEqual(model.composer, .writing)
        XCTAssertTrue(model.isCreditExhausted, "Le solde du refus fait foi.")

        // Le crédit revient (un abonnement, minuit) : le même brouillon corrige
        // la même fiche.
        await script.failEditing(with: nil)
        await script.queueUpdate(ChatThreadUpdate(messages: [], turn: .idle, now: .now, dailyCredit: credit(remainingMs: 60_000)))
        model.refreshAfterSubscribing()
        try await until("le crédit revient") { !model.isCreditExhausted }
        model.sendDraft()
        try await until("la correction repart") { await script.edited.count == 2 }
        let edited = await script.edited
        XCTAssertEqual(edited.last?.entryId, "e1")
    }

    /// La file rejoue son dernier mot à chaque fil qui s'ouvre — ici le reçu
    /// d'un tour parti ce matin. Le fil vient de lire un crédit plus frais :
    /// le vieux reçu ne le défait pas. Un refus rejoué ne retire pas non plus
    /// l'illimité que le fil vient de lire.
    func testAReplayedReceiptDoesNotUndoAFresherCredit() async throws {
        let script = Script(thread: thread(credit: credit(remainingMs: 30_000)))
        let model = ChatModel(transport: transport(script), callToActionMemory: .inMemory())
        await model.load()
        XCTAssertEqual(model.dailyCredit?.remainingMs, 30_000)

        let morning = ChatTurnReceipt(
            messages: [],
            turn: .idle,
            now: Date.now.addingTimeInterval(-5 * 3_600),
            dailyCredit: credit(remainingMs: 240_000)
        )
        await script.deliver(ChatTurnDelivery(id: "matin", tripId: "trip", state: .sent, receipt: morning).replayed)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.dailyCredit?.remainingMs, 30_000, "Le reçu de 10 h ne rend pas 4:00 à 15 h.")

        // Le même mot, s'il était neuf, ferait foi : c'est le rejeu seul
        // qui ne passe pas.
        await script.deliver(ChatTurnDelivery(id: "neuf", tripId: "trip", state: .sent, receipt: ChatTurnReceipt(
            messages: [], turn: .idle, now: .now, dailyCredit: credit(remainingMs: 20_000)
        )))
        try await until("le reçu neuf fait foi") { model.dailyCredit?.remainingMs == 20_000 }
    }

    /// Hors ligne, le fil n'a pas lu le serveur : un mot rejoué se fond dans
    /// ce qu'il tient — le plus consommé du jour, et l'illimité s'il est su.
    func testAReplayedWordMergesIntoTheOfflineCredit() async throws {
        let tripId = "trip-rejeu-hors-ligne"
        ChatModel.forgetRememberedCredits()
        let offline = ChatThread(
            id: tripId,
            title: "Rome 2026",
            context: ChatContext(tripId: tripId, stepId: nil),
            dailyCredit: credit(remainingMs: 30_000, isUnlimited: true)
        )
        let script = Script(thread: offline)
        await script.goOffline()
        let model = ChatModel(transport: transport(script), callToActionMemory: .inMemory())
        await model.load()
        XCTAssertTrue(model.isOffline)

        await script.deliver(
            ChatTurnDelivery(
                id: "refus",
                tripId: tripId,
                state: .waitingForCredit(until: .now.addingTimeInterval(3_600)),
                credit: credit(remainingMs: 0)
            ).replayed
        )
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.dailyCredit?.isUnlimited, true, "Un refus rejoué ne retire pas l'illimité.")
        XCTAssertEqual(model.dailyCredit?.remainingMs, 0, "Le plus consommé du jour.")
    }

    // MARK: - Trop long pour une journée

    /// La file dit qu'un tour coûte plus qu'une journée : sa bulle propose
    /// l'illimité, ne se décompte pas, et le crédit d'aujourd'hui n'est pas
    /// déclaré épuisé pour autant.
    func testATurnLongerThanADayWaitsForUnlimited() async throws {
        let script = Script(thread: thread(credit: credit(remainingMs: 240_000)))
        await script.queueSends()
        let model = ChatModel(transport: transport(script), callToActionMemory: .inMemory())
        await model.load()

        model.draft = String(repeating: "a", count: 3_000)  // 3:45, dans le reste
        model.sendDraft()
        let id = try XCTUnwrap(model.messages.last?.id)
        try await until("le composeur se rouvre") { model.turn == .idle }

        await script.deliver(
            ChatTurnDelivery(id: id, tripId: "trip", state: .waitingForUnlimited, credit: credit(remainingMs: 240_000))
        )
        try await until("la bulle attend l'illimité") { model.messages.last?.delivery == .waitingForUnlimited }
        XCTAssertFalse(model.isCreditExhausted)
        XCTAssertEqual(model.dailyCredit?.remainingMs, 240_000, "Il ne part pas aujourd'hui : il ne coûte rien aujourd'hui.")

        // L'abonnement le libère : la file le dit, la bulle repart.
        await script.deliver(ChatTurnDelivery(id: id, tripId: "trip", state: .sending))
        try await until("la bulle repart") { model.messages.last?.delivery == .sending }
    }

    /// Ce qui attend l'illimité sur le disque se rouvre comme tel ; un refus
    /// direct « trop long » — sans file — aussi.
    func testATurnWaitingForUnlimitedReopensAsSuch() async throws {
        let script = Script(thread: thread(credit: credit(remainingMs: 60_000)))
        await script.setWaiting([OutgoingTurn(id: "long", body: .text("…"), waitingForUnlimited: true)])
        await script.failSending(
            with: APIError.server(statusCode: 422, code: APIError.dailyCreditTooLongCode, message: "Trop long.")
        )
        let model = ChatModel(transport: transport(script), callToActionMemory: .inMemory())
        await model.load()

        XCTAssertEqual(model.messages.map(\.delivery), [.waitingForUnlimited])
        XCTAssertEqual(model.dailyCredit?.remainingMs, 60_000)

        model.draft = "Encore"
        model.sendDraft()
        try await until("la bulle attend l'illimité") { model.messages.last?.delivery == .waitingForUnlimited }
        XCTAssertEqual(model.turn, .idle)
        XCTAssertNil(model.errorMessage, "Pas un échec à réessayer.")
        XCTAssertEqual(model.dailyCredit?.remainingMs, 60_000)
    }

    /// « Supprimer », sous une bulle qui attend l'illimité, une fois
    /// confirmé : la bulle quitte le fil, et la file oublie le tour. Une
    /// bulle qui attend le réseau — peut-être déjà en route — ne se supprime
    /// pas d'ici.
    func testATurnWaitingForUnlimitedCanBeDiscarded() async throws {
        let script = Script(thread: thread(credit: credit(remainingMs: 60_000)))
        await script.setWaiting([
            OutgoingTurn(id: "long", body: .text("…"), waitingForUnlimited: true),
            OutgoingTurn(id: "metro", body: .text("Dans le métro")),
        ])
        let model = ChatModel(transport: transport(script), callToActionMemory: .inMemory())
        await model.load()

        model.discardWaitingTurn("metro")
        XCTAssertEqual(model.messages.map(\.id), ["long", "metro"], "Une bulle en route ne se supprime pas.")

        model.discardWaitingTurn("long")
        XCTAssertEqual(model.messages.map(\.id), ["metro"])
        try await until("la file l'oublie") { await script.discarded == ["long"] }
    }

    /// Hors ligne, sans rien savoir du crédit — un voyage que les caches ne
    /// chiffrent pas —, l'écran plafonne au pot du catalogue, moins ce qui
    /// attend dans la file : un vocal coupe à la limite, un texte trop long
    /// ne part pas. Un abonné que la session connaît ne compte rien ; en
    /// ligne, sans crédit servi, rien non plus.
    func testOfflineWithoutAKnownCreditCapsAtTheCatalogue() async throws {
        let tripId = "trip-sans-credit"
        ChatModel.forgetRememberedCredits()
        let unknown = ChatThread(id: tripId, title: "Rome 2026", context: ChatContext(tripId: tripId, stepId: nil))
        let script = Script(thread: unknown)
        await script.goOffline()
        await script.setWaiting([OutgoingTurn(id: "queued", body: .text(String(repeating: "a", count: 800)))])
        let model = ChatModel(transport: transport(script), callToActionMemory: .inMemory())
        await model.load()

        XCTAssertTrue(model.isOffline)
        XCTAssertNil(model.dailyCredit, "Rien de servi.")
        XCTAssertEqual(model.credit?.remainingMs, 240_000, "Cinq minutes, moins la minute qui attend.")
        XCTAssertEqual(model.credit?.isUnlimited, false)
        model.composer = .writing
        model.draft = String(repeating: "a", count: 3_201)
        XCTAssertTrue(model.draftExceedsCredit)
        model.draft = "Court"
        XCTAssertFalse(model.draftExceedsCredit)

        let session = SubscriptionSession()
        session.learn(isUnlimited: true, hasSubscribedBefore: true)
        model.subscription = session
        XCTAssertNil(model.credit, "Un abonné connu de la session ne compte rien.")

        let online = ChatModel(transport: transport(Script(thread: unknown)), callToActionMemory: .inMemory())
        await online.load()
        XCTAssertFalse(online.isOffline)
        XCTAssertNil(online.credit, "En ligne, un serveur qui ne sert pas de crédit ne fait pas compter.")
    }

    /// Le fil hors ligne reprend le crédit que l'accueil a gardé — rechargé
    /// s'il date d'hier : épuisé la veille, il est plein ce matin.
    func testTheOfflineThreadRefreshesYesterdaysCredit() {
        let yesterday = DailyCredit(usedMs: DailyCredit.Catalog.limitMs, resetsAt: Date.now.addingTimeInterval(-3_600))
        let trip = Trip(id: "trip-hier", title: "Rome 2026", stage: .ongoing, dailyCredit: yesterday)
        let offline = ChatThread.offline(trip: trip, traveller: nil, isNew: false)
        XCTAssertEqual(offline.dailyCredit?.isExhausted, false)
        XCTAssertEqual(offline.dailyCredit?.remainingMs, DailyCredit.Catalog.limitMs)

        let today = DailyCredit(usedMs: 120_000, resetsAt: Date.now.addingTimeInterval(3_600))
        let tripToday = Trip(id: "trip-jour", title: "Rome 2026", stage: .ongoing, dailyCredit: today)
        XCTAssertEqual(ChatThread.offline(trip: tripToday, traveller: nil, isNew: false).dailyCredit, today)
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
