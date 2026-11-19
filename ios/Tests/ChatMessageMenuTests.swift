@testable import MemoBookFeature
import MemoBookCore
import MemoBookNetworking
import XCTest

/// **Le menu d'un appui long sur une bulle** — T270.
///
/// Ce qui se teste ici n'est pas le dessin du menu (il est du système) mais ce
/// que le modèle en décide : quelles bulles proposent quoi, et ce que l'écran
/// montre **avant** que le serveur ait répondu — une bulle déplacée tout de
/// suite, une bulle supprimée qui disparaît, et les deux qui reviennent en
/// place si l'appel échoue.
@MainActor
final class ChatMessageMenuTests: XCTestCase {
    /// Un transport qui note les deux gestes, et sait les faire échouer.
    private actor Script {
        var thread: ChatThread
        private(set) var moved: [(messageId: String, stepId: String)] = []
        private(set) var deleted: [String] = []
        var failsMoving: (any Error)?
        var failsDeleting: (any Error)?

        init(thread: ChatThread) { self.thread = thread }

        func move(_ messageId: String, _ stepId: String) throws {
            if let failsMoving { throw failsMoving }
            moved.append((messageId, stepId))
        }

        func delete(_ entryId: String) throws {
            if let failsDeleting { throw failsDeleting }
            deleted.append(entryId)
        }

        func failMoving(with error: any Error) { failsMoving = error }
        func failDeleting(with error: any Error) { failsDeleting = error }
    }

    private func transport(_ script: Script) -> ChatTransport {
        ChatTransport(
            load: { await script.thread },
            poll: { _ in ChatThreadUpdate(messages: [], suggestions: [], turn: .idle, now: .now) },
            send: { _ in .queued },
            editTranscript: { _, _ in throw APIError.server(statusCode: 0, code: nil, message: "non") },
            deleteMemory: { entryId in try await script.delete(entryId) },
            moveMessage: { messageId, stepId in try await script.move(messageId, stepId) },
            media: { _ in Data() }
        )
    }

    private let steps = [
        ChatContextStep(id: "step-1", number: 1, placeName: "Trastevere"),
        ChatContextStep(id: "step-2", number: 2, placeName: nil),
    ]

    private func thread(messages: [ChatMessage], steps: [ChatContextStep]? = nil) -> ChatThread {
        ChatThread(
            id: "trip",
            title: "Rome 2026",
            context: ChatContext(tripId: "trip", steps: steps ?? self.steps),
            messages: messages,
            now: .now
        )
    }

    private func photos(
        _ id: String = "bulle-photos",
        ids: [String] = ["photo-1", "photo-2"],
        stepId: String? = "step-1",
        delivery: ChatDelivery = .sent
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            author: .traveller,
            body: .photos(ids.map { PhotoAttachment(id: $0, remoteUrl: URL(string: "https://x/\($0)/media")) }),
            sentAt: .now,
            stepId: stepId,
            delivery: delivery,
            seq: 2,
            disposition: .memory,
            entryId: ids.first
        )
    }

    private func saidText(_ id: String = "bulle-texte", entryId: String? = "entry-1", disposition: ChatDisposition? = .memory) -> ChatMessage {
        ChatMessage(
            id: id,
            author: .traveller,
            body: .text("On a marché jusqu'au Janicule."),
            sentAt: .now,
            stepId: "step-1",
            delivery: .sent,
            seq: 1,
            disposition: disposition,
            entryId: entryId
        )
    }

    // MARK: - Ce que chaque bulle propose

    func testUneBulleDePhotosPorteUnSouvenirParImage() async throws {
        let model = ChatModel(transport: transport(Script(thread: thread(messages: [photos()]))))
        await model.load()

        let bubble = try XCTUnwrap(model.messages.first)
        XCTAssertEqual(model.memories(of: bubble), ["photo-1", "photo-2"])
        XCTAssertTrue(model.canDelete(bubble))
    }

    func testUneBulleDeMemoNeSeSupprimePas() async throws {
        let reply = ChatMessage(id: "memo-1", author: .memo, body: .text("Quel beau programme !"), sentAt: .now, seq: 3)
        let model = ChatModel(transport: transport(Script(thread: thread(messages: [reply]))))
        await model.load()

        let bubble = try XCTUnwrap(model.messages.first)
        XCTAssertEqual(model.memories(of: bubble), [], "La réponse de MEMO n'est pas un souvenir.")
        XCTAssertFalse(model.canDelete(bubble))
        XCTAssertFalse(model.canMove(bubble))
    }

    /// Une précision — « en fait c'était mardi » — se rattache au souvenir en
    /// cours sans en être un : la supprimer n'a pas de sens, et le serveur
    /// refuserait.
    func testUnePrecisionNeSeSupprimePas() async {
        let model = ChatModel(transport: transport(Script(thread: thread(messages: [saidText(disposition: .context)]))))
        await model.load()

        XCTAssertEqual(model.memories(of: model.messages[0]), [])
    }

    /// Un serveur d'avant ne servait pas `disposition` : ses bulles du
    /// voyageur sont bien des souvenirs, comme ailleurs dans l'app.
    func testUneBulleSansDispositionCompteCommeUnSouvenir() async {
        let model = ChatModel(transport: transport(Script(thread: thread(messages: [saidText(disposition: nil)]))))
        await model.load()

        XCTAssertEqual(model.memories(of: model.messages[0]), ["entry-1"])
    }

    /// Un récit ne se déplace pas : son étape se calcule, et le serveur le
    /// refuse. Le menu ne le propose donc pas.
    func testSeulesLesPhotosSeDeplacent() async {
        let model = ChatModel(transport: transport(Script(thread: thread(messages: [saidText(), photos()]))))
        await model.load()

        XCTAssertFalse(model.canMove(model.messages[0]), "Un récit, non.")
        XCTAssertTrue(model.canMove(model.messages[1]), "Des photos, oui.")
    }

    /// Un voyage d'une seule étape n'offre pas un déplacement qui ne mène
    /// qu'à l'étape où l'on est déjà.
    func testPasDeDeplacementSansAutreEtape() async {
        let seule = [ChatContextStep(id: "step-1", number: 1, placeName: "Trastevere")]
        let model = ChatModel(transport: transport(Script(thread: thread(messages: [photos()], steps: seule))))
        await model.load()

        XCTAssertEqual(model.destinations(for: model.messages[0]), [])
        XCTAssertFalse(model.canMove(model.messages[0]))
    }

    /// Une bulle qui attend le réseau ne se supprime pas par le menu : c'est
    /// « Supprimer » de sa mention qui parle à la file.
    func testUneBulleQuiAttendNeSeSupprimePasParLeMenu() async {
        let waiting = photos(delivery: .waitingForUnlimited)
        let model = ChatModel(transport: transport(Script(thread: thread(messages: [waiting]))))
        await model.load()

        XCTAssertFalse(model.canDelete(model.messages[0]))
        XCTAssertFalse(model.canMove(model.messages[0]))
    }

    // MARK: - Déplacer

    func testDeplacerChangeLEtapeToutDeSuitePuisAppelleLeServeur() async throws {
        let script = Script(thread: thread(messages: [photos()]))
        let model = ChatModel(transport: transport(script))
        await model.load()

        model.move(model.messages[0], toStepId: "step-2")

        XCTAssertEqual(model.messages[0].stepId, "step-2", "La bulle est déplacée avant la réponse.")
        try await until("le serveur a reçu le déplacement") { await script.moved.count == 1 }
        let moved = await script.moved[0]
        XCTAssertEqual(moved.messageId, "bulle-photos")
        XCTAssertEqual(moved.stepId, "step-2")
    }

    func testUnDeplacementRefuseRemetLEtapeDAvant() async throws {
        let script = Script(thread: thread(messages: [photos()]))
        await script.failMoving(with: APIError.server(statusCode: 400, code: nil, message: "Seules des photos se déplacent."))
        let model = ChatModel(transport: transport(script))
        await model.load()

        model.move(model.messages[0], toStepId: "step-2")

        try await until("l'étape d'avant est revenue") { model.messages[0].stepId == "step-1" }
        XCTAssertNotNil(model.errorMessage, "Un déplacement qui échoue se dit.")
    }

    // MARK: - Supprimer

    func testSupprimerRetireLaBulleEtEffaceChaquePhoto() async throws {
        let script = Script(thread: thread(messages: [saidText(), photos()]))
        let model = ChatModel(transport: transport(script))
        await model.load()

        model.delete(model.messages[1])

        XCTAssertEqual(model.messages.map(\.id), ["bulle-texte"], "La bulle part de l'écran tout de suite.")
        try await until("les deux photos sont effacées") { await script.deleted.count == 2 }
        let deleted = await script.deleted
        XCTAssertEqual(deleted, ["photo-1", "photo-2"])
    }

    func testUneSuppressionRefuseeRemetLaBulleAuMemeEndroit() async throws {
        let script = Script(thread: thread(messages: [saidText(), photos(), saidText("bulle-trois", entryId: "entry-3")]))
        await script.failDeleting(with: APIError.server(statusCode: 500, code: nil, message: "Rien n'a été supprimé."))
        let model = ChatModel(transport: transport(script))
        await model.load()

        model.delete(model.messages[1])
        XCTAssertEqual(model.messages.count, 2)

        try await until("la bulle est revenue") { model.messages.count == 3 }
        XCTAssertEqual(
            model.messages.map(\.id),
            ["bulle-texte", "bulle-photos", "bulle-trois"],
            "À sa place, et non à la fin : trois bulles plus bas, elle se lirait comme un nouveau message."
        )
        XCTAssertNotNil(model.errorMessage)
    }

    // MARK: - Partager

    func testPartagerUnTexteOuvreLaFeuilleAvecSonTexte() async {
        let model = ChatModel(transport: transport(Script(thread: thread(messages: [saidText()]))))
        await model.load()

        model.share(model.messages[0])

        XCTAssertEqual(model.shared?.text, "On a marché jusqu'au Janicule.")
    }

    func testPartagerUneBulleDeMemoPartageSonTexte() async {
        let reply = ChatMessage(id: "memo-1", author: .memo, body: .text("Quel beau programme !"), sentAt: .now, seq: 3)
        let model = ChatModel(transport: transport(Script(thread: thread(messages: [reply]))))
        await model.load()

        model.share(model.messages[0])

        XCTAssertEqual(model.shared?.text, "Quel beau programme !")
    }

    private func until(
        _ what: String,
        timeout: Duration = .seconds(5),
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
