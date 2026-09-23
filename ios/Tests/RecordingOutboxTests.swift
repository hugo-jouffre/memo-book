@testable import MemoBookFeature
import MemoBookCore
import MemoBookNetworking
import MemoBookRecording
import XCTest

/// La promesse écrite dans la boîte d'information de l'accueil : « tes vocaux
/// enregistrés hors ligne sont bien conservés, ils seront envoyés dès ta
/// reconnexion » — et celle de `docs/conversation.md` § 9 : ce qu'on envoie
/// depuis la conversation sans réseau reste « en cours d'envoi » dans le fil
/// et part au retour du réseau, dans l'ordre, sans doublon.
///
/// C'est une promesse sur des données que personne d'autre n'a — un vocal qui
/// n'est pas parti n'existe qu'ici. Elle se vérifie donc, et sans simulateur
/// hors ligne : la file reçoit un faux réseau qu'on coupe et qu'on rétablit à
/// la main.
@MainActor
final class RecordingOutboxTests: XCTestCase {
    // MARK: - Hors ligne

    func testAVocalRecordedOfflineWaitsInsteadOfFailing() async {
        let sender = Sender()
        let outbox = outbox(sender: sender)
        outbox.debugSetOffline(true)

        let outcome = await outbox.submit(.test, to: "trip-1")

        XCTAssertEqual(outcome, .queued)
        XCTAssertEqual(outbox.pending, 1)
        let sent = await sender.sent
        XCTAssertTrue(sent.isEmpty, "Rien ne doit partir tant qu'il n'y a pas de réseau.")
    }

    func testTheQueueLeavesOnItsOwnWhenTheConnectionComesBack() async throws {
        let sender = Sender()
        let network = AsyncStream.makeStream(of: Bool.self)
        let outbox = outbox(sender: sender, connectivity: Connectivity { network.stream })
        outbox.start()

        network.continuation.yield(false)
        try await until("la file se sait hors ligne") { !outbox.isOnline }

        await outbox.submit(.test, to: "trip-1")
        XCTAssertEqual(outbox.pending, 1)

        // Personne n'appuie sur rien : c'est le retour du réseau qui déclenche
        // l'envoi.
        network.continuation.yield(true)
        try await until("la file se vide") { outbox.pending == 0 }

        let sent = await sender.sent
        XCTAssertEqual(sent, ["trip-1"])
        XCTAssertEqual(outbox.justDelivered, 1, "L'arrivée se dit, le temps d'être lue.")
    }

    /// Le cas qui compte vraiment : l'app a été fermée entre les deux.
    func testAVocalSurvivesTheAppBeingClosed() async {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let sender = Sender()

        let beforeQuitting = outbox(sender: sender, store: PendingRecordingStore(directory: directory))
        beforeQuitting.debugSetOffline(true)
        await beforeQuitting.submit(.test, to: "trip-1")

        // Une autre file, sur le même dossier : c'est ce que voit le lancement
        // suivant, qui n'a rien gardé en mémoire.
        let afterRelaunching = outbox(sender: sender, store: PendingRecordingStore(directory: directory))
        await afterRelaunching.flush()

        let sent = await sender.sent
        XCTAssertEqual(sent, ["trip-1"])
        XCTAssertEqual(afterRelaunching.pending, 0)
    }

    // MARK: - Ce qui passe et ce qui manque

    /// « En ligne » ne veut pas dire « l'API répond » : ce qui échoue au
    /// transport retourne dans la file, et repart quand le serveur revient —
    /// sous le **même** identifiant.
    func testATurnThatFailsInTransitGoesBackToTheQueue() async {
        let sender = Sender()
        await sender.setUnreachable(["trip-1"])
        let outbox = outbox(sender: sender)

        let turn = OutgoingTurn.test
        let outcome = await outbox.submit(turn, to: "trip-1")

        XCTAssertEqual(outcome, .queued)
        XCTAssertEqual(outbox.pending, 1)

        await sender.setUnreachable([])
        await outbox.flush()

        let sentIds = await sender.sentIds
        XCTAssertEqual(sentIds, [turn.id])
        XCTAssertEqual(outbox.pending, 0)
    }

    /// Tout ce qu'on dit passe par la file — un texte, un vocal, des photos —
    /// et repart **dans l'ordre**, une seule fois.
    func testEverythingSaidOfflineLeavesInOrderAndOnlyOnce() async {
        let sender = Sender()
        let outbox = outbox(sender: sender)
        outbox.debugSetOffline(true)

        let text = OutgoingTurn(id: "t-1", body: .text("Hier soir, le Trastevere."))
        let voice = OutgoingTurn.test
        let photos = OutgoingTurn(
            id: "p-3",
            body: .photos([ChatPhotoUpload(data: Data("jpg".utf8), filename: "p-3-0.jpg", mimeType: "image/jpeg")], capturedAt: .now)
        )
        await outbox.submit(text, to: "trip-1")
        await outbox.submit(voice, to: "trip-1")
        await outbox.submit(photos, to: "trip-1")
        await outbox.submit(OutgoingTurn(id: "elsewhere", body: .text("Ailleurs")), to: "trip-2")

        XCTAssertEqual(outbox.pending, 4)
        let waiting = await outbox.waiting(for: "trip-1")
        XCTAssertEqual(waiting.map(\.id), [text.id, voice.id, photos.id], "Ce qui attend se relit, pour ce carnet, dans l'ordre.")
        guard case .voice(let relived) = waiting[1].body, case .voice(let original) = voice.body else {
            return XCTFail("un vocal")
        }
        // Le vocal relu du disque est le vocal entier — octets, durée, forme d'onde.
        XCTAssertEqual(relived.data, original.data)
        XCTAssertEqual(relived.durationSeconds, original.durationSeconds)
        XCTAssertEqual(relived.levels, original.levels)

        outbox.debugSetOffline(false)
        await outbox.flush()
        await outbox.flush()

        let sentIds = await sender.sentIds
        XCTAssertEqual(sentIds, [text.id, voice.id, photos.id, "elsewhere"])
        XCTAssertEqual(outbox.pending, 0)
    }

    /// Un refus du serveur n'est pas une panne de réseau : le garder, ce serait
    /// promettre une arrivée qui n'aura jamais lieu.
    func testAVocalTheServerRefusesIsNotKeptForever() async {
        let sender = Sender()
        await sender.setRefusing(["trip-1"])
        let outbox = outbox(sender: sender)

        let outcome = await outbox.submit(.test, to: "trip-1")

        XCTAssertEqual(outcome, .rejected("Ton vocal n’a pas pu être envoyé. Carnet introuvable."))
        XCTAssertEqual(outbox.pending, 0)
        XCTAssertNotNil(outbox.rejection)
    }

    // MARK: - Ce que l'accueil en dit

    func testTheNoticeSaysTheMostUsefulThingFirst() async throws {
        let outbox = outbox(sender: Sender())
        let model = HomeModel(source: { .fixture }, outbox: outbox)
        await model.load()

        XCTAssertNil(model.notice, "En ligne et sans rien en vol, la boîte ne s'affiche pas.")

        outbox.debugSetOffline(true)
        XCTAssertEqual(model.notice, .offline)

        // Un vocal enregistré hors ligne : la boîte cesse de parler du réseau
        // pour parler de ce qui attend, qui est l'inquiétude du moment.
        await model.upload(.debugSilence)
        XCTAssertEqual(model.notice, .waitingForConnection(count: 1))

        outbox.debugSetOffline(false)
        try await until("le vocal arrive") { model.notice == .delivered(count: 1) }
    }

    /// Le bouton « + vocal en attente » du bac à sable. Il emprunte le même
    /// chemin qu'un vrai vocal — jusqu'au fichier sur le disque —, sinon il
    /// montrerait une boîte d'information qui ne prouve rien.
    func testTheSandboxQueuesARealRecording() async {
        let outbox = outbox(sender: Sender())
        let model = HomeModel(source: { .fixture }, outbox: outbox)
        await model.load()
        outbox.debugSetOffline(true)

        await model.debugQueueRecording()

        XCTAssertEqual(outbox.pending, 1)
        XCTAssertEqual(model.notice, .waitingForConnection(count: 1))
        XCTAssertNil(model.errorMessage)
    }

    func testEveryNoticeSpeaksWithoutItsMarkup() {
        let notices: [HomeNotice] = [
            .offline,
            .waitingForConnection(count: 1),
            .waitingForConnection(count: 3),
            .sending(count: 1),
            .sending(count: 2),
            .delivered(count: 1),
            .delivered(count: 4),
        ]

        for notice in notices {
            XCTAssertTrue(notice.message.contains("**"), "\(notice) : rien n'est mis en avant.")
            XCTAssertFalse(notice.spokenMessage.contains("*"), "\(notice) : VoiceOver lirait des étoiles.")
        }
    }

    func testTheSingularIsNotWrittenAsAPlural() {
        XCTAssertTrue(HomeNotice.waitingForConnection(count: 1).message.contains("Ton vocal"))
        XCTAssertTrue(HomeNotice.waitingForConnection(count: 2).message.contains("Tes vocaux"))
        XCTAssertTrue(HomeNotice.delivered(count: 1).message.contains("Ton vocal"))
        XCTAssertTrue(HomeNotice.delivered(count: 5).message.contains("Tes 5 vocaux"))
    }

    // MARK: - La continuité : on raconte, et on voit son vocal partir

    /// La bulle suit **la file**, pas l'écran : hors ligne elle reste sur
    /// « envoi en cours », et c'est la reconnexion qui la termine.
    func testTheBubbleSaysSentOnlyOnceTheVocalHasReallyLeft() async throws {
        let sender = Sender()
        let network = AsyncStream.makeStream(of: Bool.self)
        let outbox = outbox(sender: sender, connectivity: Connectivity { network.stream })
        outbox.start()
        let model = HomeModel(source: { .fixture }, outbox: outbox)
        await model.load()

        network.continuation.yield(false)
        try await until("la file se sait hors ligne") { !outbox.isOnline }

        let handoff = RecordingHandoff(audio: .debugSilence, levels: [])
        Task { await model.upload(.debugSilence, handoffId: handoff.id) }

        try await until("le vocal attend sur le disque") { outbox.pending == 1 }
        XCTAssertEqual(outbox.lastDelivery?.id, handoff.id, "La file suit **cet** envoi-là, par l'identifiant de sa bulle.")
        XCTAssertEqual(
            outbox.lastDelivery?.state,
            .sending,
            "Un vocal encore sur le disque n'est pas un vocal envoyé."
        )

        network.continuation.yield(true)
        try await until("le vocal part") { outbox.lastDelivery?.state == .sent }
        XCTAssertNotNil(outbox.lastDelivery?.receipt, "Le reçu du serveur voyage avec, pour que le fil fusionne ses bulles.")
        XCTAssertEqual(outbox.lastDelivery?.tripId, model.ongoingTrips.first?.id)
    }

    /// Un refus du serveur se lit sur la bulle, avec le mot du serveur.
    func testARefusalShowsOnTheBubble() async throws {
        let sender = Sender()
        let outbox = outbox(sender: sender)
        let model = HomeModel(source: { .fixture }, outbox: outbox)
        await model.load()

        await sender.setRefusing(model.ongoingTrips.map(\.id))
        let handoff = RecordingHandoff(audio: .debugSilence, levels: [])
        Task { await model.upload(.debugSilence, handoffId: handoff.id) }

        try await until("le refus arrive à la bulle") {
            outbox.lastDelivery?.state.hasFailed == true
        }
    }

    /// La conversation pose la bulle, et **ne décide pas** de son envoi : c'est
    /// la file qui le dit, même quand MEMO a déjà répondu.
    func testTheConversationPostsTheVocalWithoutOwningItsDelivery() async throws {
        let handoff = RecordingHandoff(audio: .debugSilence, levels: [0.3, 0.7])

        let chat = ChatModel(transport: .local(tripId: "trip-rome"))
        chat.expect(handoff)
        await chat.load()

        let bubble = try XCTUnwrap(chat.messages.first { $0.id == handoff.id })
        XCTAssertEqual(bubble.author, .traveller)
        XCTAssertEqual(
            bubble.delivery,
            .sending,
            "Tant que la file n'a rien dit, la bulle ne peut pas se déclarer arrivée."
        )

        // Le fil est chargé et au repos : la bulle reste sur l'état que la file
        // donne — le chat ne l'envoie pas lui-même, elle est déjà partie.
        XCTAssertEqual(chat.turn, .idle)
        XCTAssertEqual(chat.messages.first { $0.id == handoff.id }?.delivery, .sending)

        // C'est la file, et elle seule, qui la termine — et pas celle d'un
        // autre voyage.
        chat.markDelivery(ChatTurnDelivery(id: handoff.id, tripId: "trip-lisbonne", state: .sent))
        XCTAssertEqual(chat.messages.first { $0.id == handoff.id }?.delivery, .sending)
        chat.markDelivery(ChatTurnDelivery(id: handoff.id, tripId: "trip-rome", state: .sent))
        XCTAssertEqual(chat.messages.first { $0.id == handoff.id }?.delivery, .sent)
    }

    /// `docs/conversation.md` § 9, de bout en bout : deux messages dits sans
    /// réseau depuis la conversation restent « en cours d'envoi », le
    /// composeur se rouvre entre les deux, on quitte et on revient — ils sont
    /// encore là —, et le retour du réseau les fait partir dans l'ordre, une
    /// fois, avec la bulle qui passe « envoyée » toute seule.
    func testMessagesSentOfflineFromTheConversationStayAndLeaveInOrder() async throws {
        let sender = Sender()
        let network = AsyncStream.makeStream(of: Bool.self)
        let outbox = outbox(sender: sender, connectivity: Connectivity { network.stream })
        outbox.start()
        network.continuation.yield(false)
        try await until("la file se sait hors ligne") { !outbox.isOnline }

        let chat = ChatModel(transport: Self.transport(through: outbox, tripId: "trip-1"))
        await chat.load()

        chat.draft = "Un"
        chat.sendDraft()
        try await until("le premier attend") { outbox.pending == 1 }
        try await until("le composeur se rouvre") { chat.turn == .idle }
        chat.draft = "Deux"
        chat.sendDraft()
        try await until("le second attend") { outbox.pending == 2 }

        let ids = chat.messages.map(\.id)
        XCTAssertEqual(ids.count, 2)
        XCTAssertTrue(chat.messages.allSatisfy { $0.delivery == .sending }, "Attendre le réseau n'est pas échouer.")
        XCTAssertNil(chat.errorMessage)

        // On quitte, on revient : ce qui attend est encore dans le fil.
        chat.teardown()
        let reopened = ChatModel(transport: Self.transport(through: outbox, tripId: "trip-1"))
        await reopened.load()
        XCTAssertEqual(reopened.messages.map(\.id), ids)
        XCTAssertTrue(reopened.messages.allSatisfy { $0.delivery == .sending })

        network.continuation.yield(true)
        try await until("la file se vide") { outbox.pending == 0 }
        try await until("les bulles passent envoyées", timeout: .seconds(3)) {
            reopened.messages.allSatisfy { $0.delivery == .sent }
        }

        let sentIds = await sender.sentIds
        XCTAssertEqual(sentIds, ids, "Dans l'ordre, et une seule fois.")
        XCTAssertEqual(reopened.messages.compactMap(\.seq), [1, 2], "Le rang que le serveur leur a donné.")
    }

    /// Le relevé du micro qui part avec le vocal est **celui du vocal entier**,
    /// et non la frise des quarante dernières barres.
    func testTheWaveformIsTheWholeRecording() {
        let recording = RecordingModel()
        XCTAssertTrue(recording.capturedLevels.isEmpty)
        XCTAssertTrue(recording.levels.isEmpty)
    }

    // MARK: - Le contenu relu hors ligne

    func testTheLastFeedIsReadableAgainAndForgottenOnSignOut() async {
        // `ContentCache` a remplacé `HomeFeedCache` le 16/09/2026 : le cache ne
        // sert plus seulement à relire l'accueil hors ligne, il sert aussi à
        // **ouvrir vite** cinq écrans. La question, elle, n'a pas changé — ce
        // qu'on écrit se relit, et s'efface à la déconnexion.
        let cache = ContentCache(directory: Self.scratchDirectory())

        await cache.write(.home, HomeFeed.fixture)
        let reread = await cache.read(.home, as: HomeFeed.self)
        XCTAssertEqual(reread?.trips.map(\.id), HomeFeed.fixture.trips.map(\.id))

        await cache.clearAll()
        let afterSignOut = await cache.read(.home, as: HomeFeed.self)
        XCTAssertNil(afterSignOut, "Les voyages de quelqu'un ne restent pas sur le téléphone après sa sortie.")
    }

    /// **Deux écrans ne se marchent pas dessus.** Chaque case a son fichier, et
    /// un voyage a le sien par identifiant : sans ça, ouvrir un second voyage
    /// aurait servi le premier au lancement suivant.
    func testEachSlotHasItsOwnFile() async {
        let cache = ContentCache(directory: Self.scratchDirectory())

        await cache.write(.home, HomeFeed.fixture)

        // `XCTAssertNil` prend une autoclosure, qui ne sait pas attendre : on
        // lit d'abord, on affirme ensuite.
        let fromAnotherSlot = await cache.read(.gallery, as: HomeFeed.self)
        let fromItsOwnSlot = await cache.read(.home, as: HomeFeed.self)
        XCTAssertNil(fromAnotherSlot)
        XCTAssertNotNil(fromItsOwnSlot)

        XCTAssertNotEqual(
            ContentCache.Slot.trip("rome").filename,
            ContentCache.Slot.trip("lisbonne").filename
        )
        // Et l'identifiant du voyage n'est pas écrit en clair dans
        // l'arborescence de l'appareil.
        XCTAssertFalse(ContentCache.Slot.trip("rome").filename.contains("rome"))
    }

    /// Un dossier neuf par test : deux tests qui partageraient le même
    /// écriraient dans les mêmes fichiers, et le second lirait ce que le
    /// premier a laissé.
    private static func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    // MARK: - Outils

    private func outbox(
        sender: Sender,
        store: PendingRecordingStore = .temporary(),
        connectivity: Connectivity = .online
    ) -> RecordingOutbox {
        RecordingOutbox(store: store, connectivity: connectivity) { turn, tripId in
            try await sender.send(turn, to: tripId)
        }
    }

    /// Le transport de la conversation tel que `AppDependencies.chatModel` le
    /// monte : l'envoi, ce qui attend et ce qui part passent par la file. Le
    /// fil lui-même est vide et ne bouge pas — c'est la file qu'on regarde.
    private static func transport(through outbox: RecordingOutbox, tripId: String) -> ChatTransport {
        ChatTransport(
            load: {
                ChatThread(
                    id: tripId,
                    title: "Rome 2026",
                    context: ChatContext(tripId: tripId, stepId: nil),
                    messages: [],
                    suggestions: [],
                    now: .now
                )
            },
            poll: { _ in ChatThreadUpdate(messages: [], suggestions: [], turn: .idle, now: .now) },
            send: { turn in
                switch await outbox.submit(turn, to: tripId) {
                case .delivered(let receipt):
                    return .received(receipt ?? ChatTurnReceipt(messages: [], turn: .idle, now: .now))
                case .queued:
                    return .queued
                case .rejected(let message):
                    throw RecordingOutbox.Rejection(message: message)
                }
            },
            editTranscript: { _, _ in throw APIError.server(statusCode: 0, code: nil, message: "Pas ici.") },
            media: { _ in Data() },
            waiting: { await outbox.waiting(for: tripId) },
            deliveries: { await outbox.turnDeliveries() }
        )
    }

    /// Attend qu'une condition devienne vraie, ou échoue en le disant. Les
    /// envois partent dans leurs propres tâches : on ne peut pas les attendre
    /// directement sans donner à la file une trappe qui n'existerait que pour
    /// les tests.
    private func until(
        _ what: String,
        timeout: Duration = .seconds(2),
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Jamais atteint : \(what)", file: file, line: line)
    }
}

/// Le serveur, vu de la file : il accepte — et rend le reçu, la bulle du
/// voyageur avec son rang —, il est injoignable, ou il refuse.
private actor Sender {
    /// Les carnets servis, dans l'ordre des envois.
    private(set) var sent: [String] = []
    /// Les tours servis, dans l'ordre — c'est l'ordre et l'unicité qu'on
    /// vérifie.
    private(set) var sentIds: [String] = []
    private var unreachable: Set<String> = []
    private var refused: Set<String> = []

    func setUnreachable(_ tripIds: [String]) { unreachable = Set(tripIds) }
    func setRefusing(_ tripIds: [String]) { refused = Set(tripIds) }

    func send(_ turn: OutgoingTurn, to tripId: String) throws -> ChatTurnReceipt {
        if unreachable.contains(tripId) {
            throw APIError.transport(URLError(.notConnectedToInternet), url: nil)
        }
        if refused.contains(tripId) {
            throw APIError.server(statusCode: 404, code: nil, message: "Carnet introuvable.")
        }
        sent.append(tripId)
        sentIds.append(turn.id)

        let body: ChatMessageBody
        switch turn.body {
        case .text(let text, _, _): body = .text(text)
        case .voice(let audio): body = .voice(VoiceNote(id: turn.id, duration: audio.durationSeconds, levels: audio.levels))
        case .photos(let photos, _): body = .photos(photos.indices.map { PhotoAttachment(id: "\(turn.id)-\($0)") })
        }
        return ChatTurnReceipt(
            messages: [ChatMessage(id: turn.id, author: .traveller, body: body, sentAt: .now, seq: sentIds.count)],
            turn: .idle,
            now: .now
        )
    }
}

extension OutgoingTurn {
    /// Un vocal de quatre secondes, tel que l'accueil le confie.
    fileprivate static var test: OutgoingTurn {
        .voice(
            RecordedAudio(
                data: Data("un vocal".utf8),
                filename: "test.m4a",
                mimeType: "audio/m4a",
                duration: 4,
                recordedAt: .now
            ),
            levels: [0.2, 0.8]
        )
    }
}
