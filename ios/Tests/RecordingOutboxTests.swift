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

    // MARK: - Le crédit du jour

    /// Un `429 daily_credit_exhausted` n'est pas un refus définitif : le tour
    /// reste sur le disque, marqué jusqu'à la recharge, sans bandeau d'erreur ;
    /// sa bulle dit « Partira demain » — et le code a traversé jusqu'à elle.
    func testACreditRefusalKeepsTheTurnForTomorrow() async throws {
        let sender = Sender()
        // À la seconde : la fiche passe par l'ISO 8601 du disque.
        let resetsAt = Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 + 3_600).rounded())
        await sender.setOutOfCredit(["trip-1"], resetsAt: resetsAt)
        let store = PendingRecordingStore.temporary()
        let outbox = outbox(sender: sender, store: store)

        let outcome = await outbox.submit(.test, to: "trip-1")

        XCTAssertEqual(outcome, .queued, "Il attend, comme sous un tunnel — plus longtemps.")
        XCTAssertNil(outbox.rejection, "Rien de raté : pas de bandeau d'erreur sur l'accueil.")
        XCTAssertEqual(outbox.waitingForCredit, 1)
        XCTAssertEqual(outbox.pending, 0, "Il n'attend pas le réseau : la boîte de l'accueil ne promet rien pour lui.")
        XCTAssertEqual(outbox.lastDelivery?.state, .waitingForCredit(until: resetsAt))
        XCTAssertEqual(outbox.lastDelivery?.credit?.isExhausted, true, "Le solde du refus voyage jusqu'à la bulle.")
        let stored = await store.all()
        XCTAssertEqual(stored.first?.waitingForCreditUntil, resetsAt, "Marqué sur la fiche : une app relancée le sait.")

        // Un vidage avant la recharge ne le renvoie pas au même refus.
        await sender.refill()
        await outbox.flush()
        let sent = await sender.sent
        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(outbox.waitingForCredit, 1)
    }

    /// Passé l'heure de la recharge, le tour repart tout seul au vidage
    /// suivant ; ce qui attend encore reste de côté.
    func testATurnWaitingForCreditLeavesOnceTheCreditReturns() async throws {
        let sender = Sender()
        let store = PendingRecordingStore.temporary()
        let due = PendingTurn(
            id: "due",
            tripId: "trip-1",
            kind: .text,
            text: "Hier soir, un dernier verre.",
            recordedAt: .now,
            waitingForCreditUntil: Date.now.addingTimeInterval(-60)
        )
        let later = PendingTurn(
            id: "later",
            tripId: "trip-2",
            kind: .text,
            text: "Pas encore.",
            recordedAt: .now,
            waitingForCreditUntil: Date.now.addingTimeInterval(3_600)
        )
        _ = try await store.enqueue(due, files: [])
        _ = try await store.enqueue(later, files: [])
        let outbox = outbox(sender: sender, store: store)

        await outbox.flush()

        let sentIds = await sender.sentIds
        XCTAssertEqual(sentIds, ["due"])
        XCTAssertEqual(outbox.waitingForCredit, 1)
        XCTAssertEqual(outbox.pending, 0)
    }

    /// Le dernier mot de la file se rejoue à qui se met à l'écoute, **marqué
    /// comme tel** : son reçu peut dater du matin. Ce qui suit est neuf.
    func testTheLastWordIsReplayedAsSuch() async throws {
        let outbox = outbox(sender: Sender())
        await outbox.submit(.test, to: "trip-1")
        XCTAssertEqual(outbox.lastDelivery?.isReplay, false)

        let deliveries = outbox.turnDeliveries()
        await outbox.submit(OutgoingTurn(id: "suivant", body: .text("Et après")), to: "trip-1")
        let words = await first(3, of: deliveries) { _ in true }
        XCTAssertEqual(words.map(\.isReplay), [true, false, false])
        XCTAssertEqual(words.first?.state, .sent)
        XCTAssertEqual(words.dropFirst().map(\.state), [.sending, .sent])
    }

    /// Une fiche dont l'attente est échue se relit **sans** sa date : la
    /// conversation rouvre le tour « en cours d'envoi » et le décompte du
    /// jour où il partira. Une attente à venir, elle, se relit telle quelle.
    func testATurnWhoseWaitIsOverIsReadBackWithoutIt() async throws {
        let store = PendingRecordingStore.temporary()
        let tomorrow = Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 + 3_600).rounded())
        _ = try await store.enqueue(
            PendingTurn(id: "due", tripId: "trip-1", kind: .text, text: "Hier soir", recordedAt: .now,
                        waitingForCreditUntil: Date.now.addingTimeInterval(-60)),
            files: []
        )
        _ = try await store.enqueue(
            PendingTurn(id: "later", tripId: "trip-1", kind: .text, text: "Ce soir", recordedAt: .now,
                        waitingForCreditUntil: tomorrow),
            files: []
        )
        let outbox = outbox(sender: Sender(), store: store)
        outbox.debugSetOffline(true)

        let waiting = await outbox.waiting(for: "trip-1")
        XCTAssertEqual(waiting.map(\.id), ["due", "later"])
        XCTAssertNil(waiting[0].waitingForCreditUntil)
        XCTAssertFalse(waiting[0].isOnHold, "Échue : il ne retient plus rien.")
        XCTAssertEqual(waiting[1].waitingForCreditUntil, tomorrow)
        XCTAssertTrue(waiting[1].isOnHold)
    }

    /// Le refus au vidage marque la fiche et publie « Partira demain ». Les
    /// tours suivants du même voyage qui ne tiennent plus dans le reste sont
    /// marqués aussi, sans un aller-retour pour le même refus — sinon
    /// l'accueil les compterait « hors ligne » alors qu'on est en ligne.
    /// Ce qui ne consomme rien — une puce, des photos — part quand même.
    func testACreditRefusalWhileDrainingHoldsTheRestOfThatTrip() async throws {
        let sender = Sender()
        let store = PendingRecordingStore.temporary()
        let outbox = outbox(sender: sender, store: store)
        outbox.debugSetOffline(true)

        let voice = OutgoingTurn.test
        let text = OutgoingTurn(body: .text("Et ensuite ?"))
        let chip = OutgoingTurn(body: .text("Ça me convient", suggestionId: "accept", entryId: "e1"))
        let photos = OutgoingTurn(
            body: .photos([ChatPhotoUpload(data: Data([1]), filename: "p.jpg", mimeType: "image/jpeg")], capturedAt: .now)
        )
        await outbox.submit(voice, to: "trip-1")
        await outbox.submit(text, to: "trip-1")
        await outbox.submit(chip, to: "trip-1")
        await outbox.submit(photos, to: "trip-1")

        let deliveries = outbox.turnDeliveries()
        await sender.setOutOfCredit(["trip-1"], resetsAt: nil, exceptFreeTurns: true)
        outbox.debugSetOffline(false)
        try await until("le vidage est passé") { outbox.sending == 0 && outbox.waitingForCredit == 2 }

        let sentIds = await sender.sentIds
        XCTAssertEqual(sentIds, [chip.id, photos.id], "La puce et les photos passent ; le texte attend demain.")
        XCTAssertEqual(outbox.pending, 0, "Rien n'attend le réseau : on est en ligne.")
        let stored = await store.all()
        XCTAssertEqual(stored.map(\.id), [voice.id, text.id])
        XCTAssertNotNil(stored.first { $0.id == voice.id }?.waitingForCreditUntil)
        XCTAssertNotNil(stored.first { $0.id == text.id }?.waitingForCreditUntil, "Marqué tout de suite : il ne tient pas dans un reste nul.")

        // Sa bulle le dit, elle aussi.
        let held = await first(2, of: deliveries) { $0.state.isWaitingForCredit }
        XCTAssertEqual(held.map(\.id), [voice.id, text.id])
    }

    /// Derrière un refus, au vidage, un tour plus long qu'une journée n'est
    /// pas annoncé « Partira demain » : il attend l'illimité tout de suite,
    /// sans un aller-retour pour l'apprendre — et le vocal court refusé, lui,
    /// attend bien demain.
    func testATurnLongerThanADayBehindARefusalWaitsForUnlimited() async throws {
        let sender = Sender()
        let store = PendingRecordingStore.temporary()
        let outbox = outbox(sender: sender, store: store)
        outbox.debugSetOffline(true)

        let short = OutgoingTurn.voice(
            RecordedAudio(data: Data("court".utf8), filename: "court.m4a", mimeType: "audio/m4a", duration: 120, recordedAt: .now),
            levels: []
        )
        let long = OutgoingTurn.voice(
            RecordedAudio(data: Data("long".utf8), filename: "long.m4a", mimeType: "audio/m4a", duration: 420, recordedAt: .now),
            levels: []
        )
        await outbox.submit(short, to: "trip-1")
        await outbox.submit(long, to: "trip-1")

        let deliveries = outbox.turnDeliveries()
        await sender.setOutOfCredit(["trip-1"], resetsAt: Date.now.addingTimeInterval(3_600), usedMs: 240_000)
        outbox.debugSetOffline(false)
        try await until("le vidage est passé") {
            outbox.sending == 0 && outbox.waitingForCredit == 1 && outbox.waitingForUnlimited == 1
        }

        let sentIds = await sender.sentIds
        XCTAssertTrue(sentIds.isEmpty)
        let attempts = await sender.attempts
        XCTAssertEqual(attempts, [short.id], "Le vocal de 7 minutes n'est pas essayé pour le même refus.")
        let stored = await store.all()
        XCTAssertNotNil(stored.first { $0.id == short.id }?.waitingForCreditUntil, "Le court attend demain.")
        let marked = try XCTUnwrap(stored.first { $0.id == long.id })
        XCTAssertTrue(marked.waitingForUnlimited)
        XCTAssertNil(marked.waitingForCreditUntil, "Pas « demain » : l'illimité.")
        XCTAssertEqual(outbox.pending, 0)

        let held = await first(2, of: deliveries) { !$0.isReplay && $0.state != .sending }
        XCTAssertEqual(held.map(\.id), [short.id, long.id])
        XCTAssertEqual(held.last?.state, .waitingForUnlimited)
    }

    /// Un tour qui coûte plus qu'une journée entière n'attend pas demain, qui
    /// donnerait le même refus : il attend l'illimité, sans réveil à minuit,
    /// sans retenir les autres tours du voyage — et repart dès que le compte
    /// passe en illimité.
    func testATurnLongerThanADayWaitsForUnlimited() async throws {
        let sender = Sender()
        let store = PendingRecordingStore.temporary()
        // Il reste 4 minutes : un vocal de 6 minutes 40 ne tiendra jamais.
        await sender.setOutOfCredit(["trip-1"], resetsAt: Date.now.addingTimeInterval(3_600), usedMs: 60_000)
        let outbox = outbox(sender: sender, store: store)

        let long = OutgoingTurn.voice(
            RecordedAudio(data: Data("long".utf8), filename: "long.m4a", mimeType: "audio/m4a", duration: 400, recordedAt: .now),
            levels: []
        )
        let outcome = await outbox.submit(long, to: "trip-1")

        XCTAssertEqual(outcome, .queued, "Gardé : le jeter, ce serait perdre sept minutes de souvenir.")
        XCTAssertNil(outbox.rejection)
        XCTAssertEqual(outbox.lastDelivery?.state, .waitingForUnlimited)
        XCTAssertEqual(outbox.waitingForUnlimited, 1)
        XCTAssertEqual(outbox.waitingForCredit, 0, "Pas « demain ».")
        XCTAssertEqual(outbox.pending, 0, "Pas « dès ta reconnexion » non plus.")
        let stored = await store.all()
        XCTAssertEqual(stored.first?.waitingForUnlimited, true)
        XCTAssertNil(stored.first?.waitingForCreditUntil)

        // Le lendemain, pot plein : toujours pas renvoyé au même refus.
        await sender.refill()
        await outbox.flush()
        var sent = await sender.sentIds
        XCTAssertTrue(sent.isEmpty)

        // L'abonnement le libère.
        await outbox.releaseCreditHolds()
        sent = await sender.sentIds
        XCTAssertEqual(sent, [long.id])
        XCTAssertEqual(outbox.waitingForUnlimited, 0)
        let left = await store.all()
        XCTAssertTrue(left.isEmpty)
    }

    /// Le serveur dit lui-même « trop long pour une journée »
    /// (`daily_credit_too_long`) — ou refuse pot plein un tour que l'app
    /// croyait court : même attente de l'illimité.
    func testTheServerCanSayATurnIsTooLongForADay() async throws {
        let sender = Sender()
        await sender.setTooLong(["trip-1"])
        let outbox = outbox(sender: sender)

        let text = OutgoingTurn(body: .text("Un récit sans fin"))
        let first = await outbox.submit(text, to: "trip-1")
        XCTAssertEqual(first, .queued)
        XCTAssertEqual(outbox.lastDelivery?.state, .waitingForUnlimited)
        XCTAssertNil(outbox.rejection, "Rien de raté : il attend.")

        // Pot plein (rien consommé aujourd'hui) et refusé quand même : la
        // mesure du serveur fait foi, pas la durée que l'app a notée.
        await sender.setTooLong([])
        await sender.setOutOfCredit(["trip-2"], resetsAt: Date.now.addingTimeInterval(3_600), usedMs: 0)
        let second = await outbox.submit(.test, to: "trip-2")
        XCTAssertEqual(second, .queued)
        XCTAssertEqual(outbox.lastDelivery?.state, .waitingForUnlimited)
        XCTAssertEqual(outbox.waitingForUnlimited, 2)
    }

    /// « Supprimer » : un tour qui attend l'illimité quitte le disque et les
    /// compteurs. Un tour qui n'attend que le réseau — peut-être en train de
    /// partir — ne se supprime pas ; un tour déjà oublié non plus.
    func testATurnWaitingForUnlimitedCanBeDiscarded() async throws {
        let sender = Sender()
        let store = PendingRecordingStore.temporary()
        await sender.setTooLong(["trip-1"])
        let outbox = outbox(sender: sender, store: store)
        let long = OutgoingTurn(body: .text("Un récit sans fin"))
        await outbox.submit(long, to: "trip-1")
        XCTAssertEqual(outbox.waitingForUnlimited, 1)

        outbox.debugSetOffline(true)
        let metro = OutgoingTurn(body: .text("Dans le métro"))
        await outbox.submit(metro, to: "trip-1")
        XCTAssertEqual(outbox.pending, 1)

        var discarded = await outbox.discardTurn(id: metro.id)
        XCTAssertFalse(discarded, "Il n'attend que le réseau : il peut être en route.")
        discarded = await outbox.discardTurn(id: long.id)
        XCTAssertTrue(discarded)
        XCTAssertEqual(outbox.waitingForUnlimited, 0)
        XCTAssertEqual(outbox.pending, 1)
        let left = await store.all()
        XCTAssertEqual(left.map(\.id), [metro.id])
        discarded = await outbox.discardTurn(id: long.id)
        XCTAssertFalse(discarded, "Déjà oublié.")
    }

    /// Un voyage créé hors ligne porte son crédit du jour, **plein**, jusqu'au
    /// minuit local : le fil et la feuille de l'accueil comptent dès le
    /// premier vocal — illimité si l'accueil gardé dit que le compte l'est.
    /// Un voyage qui porte déjà un crédit garde le sien.
    func testATripCreatedOfflineCountsFromAFullPot() async throws {
        let outbox = outbox(sender: Sender())
        outbox.debugSetOffline(true)
        let trip = try await outbox.saveTrip(TripDraft(title: "Lisbonne"))

        let feed = outbox.mergingLocalTrips(into: HomeFeed(traveller: Traveller(id: "t", firstName: "Camille"), trips: []))
        let credit = try XCTUnwrap(feed.trips.first { $0.id == trip.id }?.dailyCredit)
        XCTAssertEqual(credit.remainingMs, DailyCredit.Catalog.limitMs)
        XCTAssertFalse(credit.isUnlimited)
        XCTAssertGreaterThan(try XCTUnwrap(credit.resetsAt), .now, "Rechargé au prochain minuit, pas déjà périmé.")

        let subscriber = outbox.mergingLocalTrips(
            into: HomeFeed(traveller: Traveller(id: "t", firstName: "Camille", isUnlimited: true), trips: [])
        )
        XCTAssertEqual(subscriber.trips.first?.dailyCredit?.isUnlimited, true)

        let served = DailyCredit(usedMs: 120_000)
        let known = Trip(id: "rome", title: "Rome", stage: .ongoing, dailyCredit: served)
        XCTAssertEqual(RecordingOutbox.withFreshCredit(known, isUnlimited: true).dailyCredit, served)
    }

    /// S'abonner libère ce qui attendait le crédit de demain : il part tout
    /// de suite, sans attendre minuit, et sa bulle quitte « Partira demain ».
    func testSubscribingReleasesWhatWaitsForTomorrow() async throws {
        let sender = Sender()
        let store = PendingRecordingStore.temporary()
        let held = PendingTurn(
            id: "held",
            tripId: "trip-1",
            kind: .text,
            text: "Refusé à 15 h.",
            recordedAt: .now,
            waitingForCreditUntil: Date.now.addingTimeInterval(3_600)
        )
        _ = try await store.enqueue(held, files: [])
        let outbox = outbox(sender: sender, store: store)
        await outbox.flush()
        var sentIds = await sender.sentIds
        XCTAssertTrue(sentIds.isEmpty, "Avant l'achat, il attend minuit.")

        let deliveries = outbox.turnDeliveries()
        await outbox.releaseCreditHolds()

        sentIds = await sender.sentIds
        XCTAssertEqual(sentIds, ["held"])
        XCTAssertEqual(outbox.waitingForCredit, 0)
        XCTAssertEqual(outbox.pending, 0)
        let states = await first(2, of: deliveries) { $0.id == "held" }.map(\.state)
        XCTAssertEqual(states, [.sending, .sent], "La bulle repart, puis arrive.")
    }

    /// Sans `resetsAt` lisible — ou déjà passé —, le tour attend le minuit
    /// local suivant : ni bloqué pour toujours, ni renvoyé en boucle.
    func testTheCreditReturnsAtMidnightWhenTheServerDoesNotSay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 21, minute: 40))!
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4))!
        let served = now.addingTimeInterval(1_200)

        XCTAssertEqual(RecordingOutbox.creditReturns(served, now: now, calendar: calendar), served)
        XCTAssertEqual(RecordingOutbox.creditReturns(nil, now: now, calendar: calendar), midnight)
        XCTAssertEqual(
            RecordingOutbox.creditReturns(now.addingTimeInterval(-5), now: now, calendar: calendar),
            midnight,
            "Une recharge déjà passée — horloge en avance — ne garde pas le tour en otage."
        )
    }

    /// La fiche d'avant le crédit du jour se relit sans marque ; la marque, elle,
    /// survit à l'aller-retour sur le disque.
    func testThePendingTurnKeepsItsCreditMarkOnDisk() throws {
        let until = Date(timeIntervalSince1970: 1_790_000_000)
        let turn = PendingTurn(id: "t", tripId: "trip", kind: .text, text: "Bonsoir", recordedAt: until, waitingForCreditUntil: until)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(PendingTurn.self, from: encoder.encode(turn))
        XCTAssertEqual(decoded.waitingForCreditUntil, until)
        XCTAssertFalse(decoded.waitingForUnlimited)

        let tooLong = PendingTurn(id: "l", tripId: "trip", kind: .text, text: "…", recordedAt: until, waitingForUnlimited: true)
        let decodedTooLong = try decoder.decode(PendingTurn.self, from: encoder.encode(tooLong))
        XCTAssertTrue(decodedTooLong.waitingForUnlimited, "L'attente de l'illimité survit à une relance.")
        XCTAssertTrue(decodedTooLong.isOnHold(at: .distantFuture))

        let legacy = Data(#"{"id":"t","tripId":"trip","kind":"text","text":"Bonsoir","filenames":[],"mimeTypes":[],"levels":[],"recordedAt":"2026-10-03T10:00:00Z","queuedAt":"2026-10-03T10:00:00Z"}"#.utf8)
        XCTAssertNil(try decoder.decode(PendingTurn.self, from: legacy).waitingForCreditUntil)
        XCTAssertFalse(try decoder.decode(PendingTurn.self, from: legacy).waitingForUnlimited)
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

    /// Les premiers mots de la file qui répondent à `keep` — ou ce qui est
    /// arrivé au bout de `timeout` : un mot qui manque fait échouer le test au
    /// lieu de le laisser attendre pour toujours.
    private func first(
        _ count: Int,
        of stream: AsyncStream<ChatTurnDelivery>,
        timeout: Duration = .seconds(2),
        where keep: @escaping @Sendable (ChatTurnDelivery) -> Bool
    ) async -> [ChatTurnDelivery] {
        await withTaskGroup(of: [ChatTurnDelivery]?.self) { group in
            group.addTask {
                var kept: [ChatTurnDelivery] = []
                for await delivery in stream where keep(delivery) {
                    kept.append(delivery)
                    if kept.count == count { break }
                }
                return kept
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result ?? []
        }
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
    /// Tous les tours présentés, refusés compris : ce qu'on n'a pas eu
    /// besoin d'essayer n'y est pas.
    private(set) var attempts: [String] = []
    private var unreachable: Set<String> = []
    private var refused: Set<String> = []
    /// Les carnets dont le crédit du jour est épuisé, et l'heure de recharge
    /// que le serveur annonce.
    private var outOfCredit: [String: Date?] = [:]
    /// Ce que le voyage a déjà consommé au moment du refus : tout, par défaut.
    private var usedMs = DailyCredit.Catalog.limitMs
    /// Ce qui ne consomme rien passe malgré le refus — une puce, des photos.
    private var freeTurnsPass = false
    /// Les carnets qui refusent tout tour « plus long qu'une journée ».
    private var tooLong: Set<String> = []

    func setUnreachable(_ tripIds: [String]) { unreachable = Set(tripIds) }
    func setRefusing(_ tripIds: [String]) { refused = Set(tripIds) }
    func setOutOfCredit(
        _ tripIds: [String],
        resetsAt: Date?,
        exceptFreeTurns: Bool = false,
        usedMs: Int = DailyCredit.Catalog.limitMs
    ) {
        outOfCredit = Dictionary(uniqueKeysWithValues: tripIds.map { ($0, resetsAt) })
        freeTurnsPass = exceptFreeTurns
        self.usedMs = usedMs
    }
    func setTooLong(_ tripIds: [String]) { tooLong = Set(tripIds) }
    func refill() { outOfCredit = [:] }

    func send(_ turn: OutgoingTurn, to tripId: String) throws -> ChatTurnReceipt {
        attempts.append(turn.id)
        if unreachable.contains(tripId) {
            throw APIError.transport(URLError(.notConnectedToInternet), url: nil)
        }
        if refused.contains(tripId) {
            throw APIError.server(statusCode: 404, code: nil, message: "Carnet introuvable.")
        }
        if tooLong.contains(tripId) {
            throw APIError.server(
                statusCode: 422,
                code: APIError.dailyCreditTooLongCode,
                message: "C’est plus long que le crédit d’une journée entière."
            )
        }
        let isFree = turn.creditCost(in: DailyCredit()) == 0
        if let resetsAt = outOfCredit[tripId], !(freeTurnsPass && isFree) {
            throw APIError.dailyCreditExhausted(
                message: "Le crédit du jour de ce voyage est épuisé.",
                credit: DailyCredit(usedMs: usedMs, resetsAt: resetsAt)
            )
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
