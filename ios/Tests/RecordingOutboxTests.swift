@testable import MemoBookFeature
import MemoBookCore
import MemoBookNetworking
import MemoBookRecording
import XCTest

/// La promesse écrite dans la boîte d'information de l'accueil : « tes vocaux
/// enregistrés hors ligne sont bien conservés, ils seront envoyés dès ta
/// reconnexion ».
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

        let outcome = await outbox.submit(.test, to: ["trip-1"])

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

        await outbox.submit(.test, to: ["trip-1"])
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
        await beforeQuitting.submit(.test, to: ["trip-1"])

        // Une autre file, sur le même dossier : c'est ce que voit le lancement
        // suivant, qui n'a rien gardé en mémoire.
        let afterRelaunching = outbox(sender: sender, store: PendingRecordingStore(directory: directory))
        await afterRelaunching.flush()

        let sent = await sender.sent
        XCTAssertEqual(sent, ["trip-1"])
        XCTAssertEqual(afterRelaunching.pending, 0)
    }

    // MARK: - Ce qui passe et ce qui manque

    func testOnlyTheNotebooksThatMissedItStayInTheQueue() async {
        let sender = Sender()
        await sender.setUnreachable(["trip-2"])
        let outbox = outbox(sender: sender)

        let outcome = await outbox.submit(.test, to: ["trip-1", "trip-2"])

        XCTAssertEqual(outcome, .queued)
        XCTAssertEqual(outbox.pending, 1)

        await sender.setUnreachable([])
        await outbox.flush()

        let sent = await sender.sent.sorted()
        XCTAssertEqual(sent, ["trip-1", "trip-2"], "Le carnet servi du premier coup ne doit pas l'être deux fois.")
        XCTAssertEqual(outbox.pending, 0)
    }

    /// Un refus du serveur n'est pas une panne de réseau : le garder, ce serait
    /// promettre une arrivée qui n'aura jamais lieu.
    func testAVocalTheServerRefusesIsNotKeptForever() async {
        let sender = Sender()
        await sender.setRefusing(["trip-1"])
        let outbox = outbox(sender: sender)

        let outcome = await outbox.submit(.test, to: ["trip-1"])

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

    // MARK: - Le contenu relu hors ligne

    func testTheLastFeedIsReadableAgainAndForgottenOnSignOut() async {
        let cache = HomeFeedCache(
            url: FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        )

        await cache.write(.fixture)
        let reread = await cache.read()
        XCTAssertEqual(reread?.trips.map(\.id), HomeFeed.fixture.trips.map(\.id))

        await cache.clear()
        let afterSignOut = await cache.read()
        XCTAssertNil(afterSignOut, "Les voyages de quelqu'un ne restent pas sur le téléphone après sa sortie.")
    }

    // MARK: - Outils

    private func outbox(
        sender: Sender,
        store: PendingRecordingStore = .temporary(),
        connectivity: Connectivity = .online
    ) -> RecordingOutbox {
        RecordingOutbox(store: store, connectivity: connectivity) { audio, tripId in
            try await sender.send(audio, to: tripId)
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

/// Le serveur, vu de la file : il accepte, il est injoignable, ou il refuse.
private actor Sender {
    private(set) var sent: [String] = []
    private var unreachable: Set<String> = []
    private var refused: Set<String> = []

    func setUnreachable(_ tripIds: [String]) { unreachable = Set(tripIds) }
    func setRefusing(_ tripIds: [String]) { refused = Set(tripIds) }

    func send(_ audio: RecordedAudio, to tripId: String) throws {
        if unreachable.contains(tripId) {
            throw APIError.transport(URLError(.notConnectedToInternet), url: nil)
        }
        if refused.contains(tripId) {
            throw APIError.server(statusCode: 404, code: nil, message: "Carnet introuvable.")
        }
        sent.append(tripId)
    }
}

extension RecordedAudio {
    fileprivate static var test: RecordedAudio {
        RecordedAudio(
            data: Data("un vocal".utf8),
            filename: "test.m4a",
            mimeType: "audio/m4a",
            duration: 4,
            recordedAt: .now
        )
    }
}
