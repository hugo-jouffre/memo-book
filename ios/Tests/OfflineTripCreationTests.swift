@testable import MemoBookFeature
import MemoBookCore
import MemoBookNetworking
import MemoBookRecording
import XCTest

/// « Créer un voyage doit être possible hors ligne de bout en bout, puis
/// envoyé au serveur au retour de la connexion. Pareil pour les vocaux et les
/// textes » (Hugo, 01/10/2026).
///
/// Ce que ça promet, et que ces tests tiennent :
/// - la création va jusqu'au code d'accès **sans le serveur** — seul le code
///   l'attend ;
/// - le voyage part au retour du réseau, sous l'identifiant que l'app a tiré ;
/// - ce qu'on y a raconté part **après** lui, jamais avant (le serveur
///   refuserait un vocal pour un carnet qu'il ne connaît pas, et il serait
///   perdu) ;
/// - la conversation s'ouvre sans réseau, et on peut y raconter.
@MainActor
final class OfflineTripCreationTests: XCTestCase {
    // MARK: - La création

    func testATripCreatedOfflineReachesTheCodeStepWithoutTheServer() async {
        let server = FakeServer()
        let outbox = outbox(server)
        outbox.debugSetOffline(true)
        let model = creationModel(outbox)

        await walkToTheCodeStep(model, title: "Lisbonne")

        XCTAssertEqual(model.step, .companions, "La création ne doit pas rester bloquée faute de réseau.")
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.trip?.title, "Lisbonne", "« Commencer ! » doit avoir un voyage à ouvrir.")
        XCTAssertNil(model.accessCode, "Le code, lui, ne peut venir que du serveur.")
        let log = await server.log
        XCTAssertTrue(log.isEmpty)
    }

    func testTheAccessCodeArrivesWhenTheConnectionComesBack() async throws {
        let server = FakeServer()
        let outbox = outbox(server)
        outbox.debugSetOffline(true)
        let model = creationModel(outbox)
        await walkToTheCodeStep(model, title: "Lisbonne")

        let waiting = Task { await model.awaitAccessCode() }
        outbox.debugSetOffline(false)
        await waiting.value

        XCTAssertEqual(model.accessCode, "ABC123")
        let log = await server.log
        XCTAssertEqual(log, ["trip:\(model.trip?.id ?? "?"):Lisbonne"], "Le serveur reprend l'identifiant de l'app.")
        XCTAssertTrue(outbox.localTrips.isEmpty, "Arrivé, le voyage ne se montre plus que depuis le serveur.")
    }

    func testTheIdentifierIsLowercasedLikeTheServerWritesIt() async {
        let model = creationModel(outbox(FakeServer()))
        await walkToTheCodeStep(model, title: "Lisbonne")

        let id = model.trip?.id ?? ""
        XCTAssertNotNil(UUID(uuidString: id))
        XCTAssertEqual(id, id.lowercased())
    }

    func testGoingBackAndRevalidatingCorrectsTheSameTrip() async throws {
        let server = FakeServer()
        let outbox = outbox(server)
        outbox.debugSetOffline(true)
        let model = creationModel(outbox)

        await walkToTheCodeStep(model, title: "Lisbonne")
        let first = model.trip?.id

        model.goBack()
        model.goBack()
        model.goBack()
        model.draft.title = "Lisbonne et Porto"
        await walkToTheCodeStep(model, title: nil)

        XCTAssertEqual(model.trip?.id, first, "Revenir en arrière ne crée pas un second voyage.")
        XCTAssertEqual(outbox.localTrips.map(\.draft.title), ["Lisbonne et Porto"])

        outbox.debugSetOffline(false)
        try await until("le voyage part") { outbox.localTrips.isEmpty }
        let log = await server.log
        XCTAssertEqual(log, ["trip:\(first ?? "?"):Lisbonne et Porto"], "Une seule création, avec le dernier brouillon.")
    }

    func testARefusedTripSaysSoAndOpensNothing() async {
        let server = FakeServer()
        await server.refuseTrips("La date de fin précède la date de début.")
        let model = creationModel(outbox(server))

        await walkToTheCodeStep(model, title: "Lisbonne")
        await model.awaitAccessCode()

        XCTAssertTrue(model.wasRejected)
        XCTAssertEqual(
            model.errorMessage,
            "Ton voyage « Lisbonne » n’a pas pu être créé. La date de fin précède la date de début."
        )
    }

    // MARK: - Ce qu'on y raconte

    func testWhatIsToldInATripCreatedOfflineLeavesAfterTheTrip() async throws {
        let server = FakeServer()
        let outbox = outbox(server)
        outbox.debugSetOffline(true)

        let trip = try await outbox.saveTrip(TripDraft(title: "Lisbonne"))
        let outcome = await outbox.submit(OutgoingTurn(body: .text("On est arrivés")), to: trip.id)
        XCTAssertEqual(outcome, .queued)

        outbox.debugSetOffline(false)
        try await until("tout est parti") { outbox.pending == 0 && outbox.localTrips.isEmpty }

        let log = await server.log
        XCTAssertEqual(log, ["trip:\(trip.id):Lisbonne", "turn:\(trip.id)"], "Le voyage d'abord, ce qu'on y a dit ensuite.")
    }

    /// « En ligne » ne veut pas dire « l'API répond » : si la création n'est
    /// pas passée, le texte n'est pas envoyé à un carnet que le serveur ne
    /// connaît pas — il serait refusé, et perdu.
    func testATurnWaitsForItsTripEvenOnline() async throws {
        let server = FakeServer()
        await server.setUnreachable(true)
        let outbox = outbox(server)

        let trip = try await outbox.saveTrip(TripDraft(title: "Lisbonne"))
        try await until("la création a échoué au transport") { outbox.sending == 0 }
        let outcome = await outbox.submit(OutgoingTurn(body: .text("On est arrivés")), to: trip.id)

        XCTAssertEqual(outcome, .queued)
        let log = await server.log
        XCTAssertTrue(log.isEmpty)

        await server.setUnreachable(false)
        await outbox.flush()
        let delivered = await server.log
        XCTAssertEqual(delivered, ["trip:\(trip.id):Lisbonne", "turn:\(trip.id)"])
    }

    /// Un voyage que le serveur ne prend pas (une panne de son côté) ne
    /// retient que ce qu'on y a dit : le vocal d'un carnet qu'il connaît part.
    func testAStuckTripDoesNotHoldBackOtherTrips() async throws {
        let server = FakeServer()
        await server.setTripsUnreachable(true)
        let outbox = outbox(server)
        outbox.debugSetOffline(true)

        let stuck = try await outbox.saveTrip(TripDraft(title: "Lisbonne"))
        await outbox.submit(OutgoingTurn(body: .text("Pour Lisbonne")), to: stuck.id)
        await outbox.submit(OutgoingTurn(body: .text("Pour Rome")), to: "rome")

        outbox.debugSetOffline(false)
        try await until("le carnet connu a reçu son tour") { outbox.pending == 1 }

        let log = await server.log
        XCTAssertEqual(log, ["turn:rome"])
        XCTAssertEqual(outbox.localTrips.map(\.id), [stuck.id], "Le voyage attend encore, avec son tour.")
    }

    /// Un serveur qui n'a pas encore la création rejouable tire son propre
    /// identifiant : ce qu'on a raconté part vers **son** carnet.
    func testTurnsFollowTheServerIdentifierWhenItDiffers() async throws {
        let server = FakeServer()
        await server.ignoreClientIdentifiers()
        let outbox = outbox(server)
        outbox.debugSetOffline(true)

        let trip = try await outbox.saveTrip(TripDraft(title: "Lisbonne"))
        await outbox.submit(OutgoingTurn(body: .text("On est arrivés")), to: trip.id)
        outbox.debugSetOffline(false)
        try await until("tout est parti") { outbox.pending == 0 && outbox.localTrips.isEmpty }

        let log = await server.log
        XCTAssertEqual(log, ["trip:serveur-1:Lisbonne", "turn:serveur-1"])
    }

    // MARK: - Où le voyage se montre

    func testTheHomeShowsATripCreatedOfflineFirst() async throws {
        let outbox = outbox(FakeServer())
        outbox.debugSetOffline(true)
        let trip = try await outbox.saveTrip(TripDraft(title: "Lisbonne"))

        let feed = outbox.mergingLocalTrips(into: .fixture)

        XCTAssertEqual(feed.trips.first?.id, trip.id)
        XCTAssertEqual(feed.trips.count, HomeFeed.fixture.trips.count + 1)
        XCTAssertTrue(feed.ongoingTrips.contains { $0.id == trip.id }, "Sans date, il commence maintenant.")
    }

    func testAnotherAccountNeitherSeesNorSendsTheTrip() async throws {
        let server = FakeServer()
        let outbox = outbox(server)
        outbox.debugSetOffline(true)
        outbox.setAccount("compte-a")
        _ = try await outbox.saveTrip(TripDraft(title: "Lisbonne"))

        outbox.setAccount("compte-b")
        outbox.debugSetOffline(false)
        await outbox.flush()

        XCTAssertTrue(outbox.localTrips.isEmpty)
        let log = await server.log
        XCTAssertTrue(log.isEmpty, "Le voyage de quelqu'un ne se crée pas sous le nom d'un autre.")

        outbox.setAccount("compte-a")
        XCTAssertEqual(outbox.localTrips.map(\.draft.title), ["Lisbonne"])
    }

    func testDeletingATripTheServerNeverSawForgetsItsTurnsToo() async throws {
        let outbox = outbox(FakeServer())
        outbox.debugSetOffline(true)
        let trip = try await outbox.saveTrip(TripDraft(title: "Lisbonne"))
        await outbox.submit(OutgoingTurn(body: .text("On est arrivés")), to: trip.id)

        let discarded = await outbox.discardLocalTrip(trip.id)

        XCTAssertTrue(discarded)
        XCTAssertTrue(outbox.localTrips.isEmpty)
        XCTAssertEqual(outbox.pending, 0)
    }

    // MARK: - La conversation sans réseau

    func testTheConversationOpensOfflineAndStillTakesAMessage() async throws {
        let outbox = outbox(FakeServer())
        outbox.debugSetOffline(true)
        let trip = try await outbox.saveTrip(TripDraft(title: "Lisbonne"))

        var transport = ChatTransport(
            load: { throw APIError.transport(URLError(.notConnectedToInternet), url: nil) },
            poll: { _ in throw APIError.transport(URLError(.notConnectedToInternet), url: nil) },
            send: { turn in
                switch await outbox.submit(turn, to: trip.id) {
                case .delivered(let receipt):
                    return .received(receipt ?? ChatTurnReceipt(messages: [], turn: .idle, now: .now))
                case .queued:
                    return .queued
                case .rejected(let message):
                    throw RecordingOutbox.Rejection(message: message)
                }
            },
            editTranscript: { _, _ in throw APIError.server(statusCode: 0, code: nil, message: "Pas ici.") },
            media: { _ in Data() }
        )
        transport.waiting = { await outbox.waiting(for: trip.id) }
        transport.deliveries = { await outbox.turnDeliveries() }
        transport.offlineThread = { _ in .offline(trip: trip, traveller: nil, isNew: true) }

        let model = ChatModel(transport: transport)
        await model.load()

        XCTAssertTrue(model.isOffline)
        XCTAssertNil(model.errorMessage, "Sans réseau, le fil s'ouvre quand même.")
        XCTAssertEqual(model.thread?.suggestions.map(\.id), ["context"], "Un carnet neuf s'ouvre sur le contexte.")

        model.draft = "On est arrivés"
        model.sendDraft()
        try await until("le message attend le réseau") { outbox.pending == 1 }
        XCTAssertEqual(model.messages.last?.delivery, .sending, "La bulle reste « en cours d'envoi ».")
    }

    func testAServerFailureIsNotHiddenBehindALocalThread() async {
        let transport = ChatTransport(
            load: { throw APIError.server(statusCode: 500, code: nil, message: "Le serveur a un souci.") },
            poll: { _ in ChatThreadUpdate(messages: [], suggestions: [], turn: .idle, now: .now) },
            send: { _ in .queued },
            editTranscript: { _, _ in throw APIError.server(statusCode: 0, code: nil, message: "Pas ici.") },
            media: { _ in Data() },
            offlineThread: { error in
                (error as? APIError)?.isTransport == true
                    ? .offline(trip: Trip(id: "t", title: "Rome", stage: .ongoing), traveller: nil, isNew: false)
                    : nil
            }
        )
        let model = ChatModel(transport: transport)

        await model.load()

        XCTAssertFalse(model.isOffline)
        XCTAssertNil(model.thread)
        XCTAssertEqual(model.errorMessage, "Le serveur a un souci.")
    }

    // MARK: - Outils

    private func outbox(_ server: FakeServer) -> RecordingOutbox {
        RecordingOutbox(
            store: .temporary(),
            trips: .temporary(),
            connectivity: .online,
            send: { turn, tripId in try await server.send(turn, to: tripId) },
            createTrip: { draft in try await server.createTrip(draft) }
        )
    }

    private func creationModel(_ outbox: RecordingOutbox) -> TripCreationModel {
        TripCreationModel(
            save: { draft in try await outbox.saveTrip(draft) },
            sync: { id in await outbox.tripSync(for: id) }
        )
    }

    /// Le nom, le départ — les dates n'ont plus de « Passer » —, puis
    /// « Passer » sur les notifications : la validation de la troisième
    /// enregistre le voyage.
    private func walkToTheCodeStep(_ model: TripCreationModel, title: String?) async {
        if let title { model.draft.title = title }
        await model.validate()
        model.draft.startDate = .now
        await model.validate()
        await model.skip()
    }

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

/// Le serveur, vu de la file : il note ce qu'il reçoit, **dans l'ordre**.
private actor FakeServer {
    private(set) var log: [String] = []
    private var unreachable = false
    private var tripsUnreachable = false
    private var tripRefusal: String?
    private var ignoresClientIdentifiers = false

    func setUnreachable(_ value: Bool) { unreachable = value }
    func ignoreClientIdentifiers() { ignoresClientIdentifiers = true }
    func setTripsUnreachable(_ value: Bool) { tripsUnreachable = value }
    func refuseTrips(_ message: String) { tripRefusal = message }

    func createTrip(_ draft: TripDraft) throws -> CreatedTrip {
        if unreachable { throw APIError.transport(URLError(.notConnectedToInternet), url: nil) }
        if tripsUnreachable { throw APIError.server(statusCode: 503, code: nil, message: "Saturé.") }
        if let tripRefusal { throw APIError.server(statusCode: 400, code: "bad_request", message: tripRefusal) }
        let id = ignoresClientIdentifiers ? "serveur-\(log.count + 1)" : (draft.id ?? "sans-identifiant")
        log.append("trip:\(id):\(draft.title)")
        return CreatedTrip(trip: .local(draft, id: id), accessCode: "ABC123")
    }

    func send(_ turn: OutgoingTurn, to tripId: String) throws -> ChatTurnReceipt {
        if unreachable { throw APIError.transport(URLError(.notConnectedToInternet), url: nil) }
        log.append("turn:\(tripId)")
        return ChatTurnReceipt(messages: [], turn: .idle, now: .now)
    }
}
