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
        private(set) var electedStepCovers: [(stepId: String, entryId: String?)] = []
        private(set) var electedTripCovers: [String?] = []
        var failsElecting: (any Error)?

        init(thread: ChatThread) { self.thread = thread }

        func move(_ messageId: String, _ stepId: String) throws {
            if let failsMoving { throw failsMoving }
            moved.append((messageId, stepId))
        }

        func delete(_ entryId: String) throws {
            if let failsDeleting { throw failsDeleting }
            deleted.append(entryId)
        }

        // Le double **garde** l'élection, comme le serveur : le modèle relit
        // le fil juste après, et un double qui l'oublierait rendrait l'étoile
        // au premier rechargement — le test ne prouverait plus rien.
        func electStepCover(_ stepId: String, _ entryId: String?) throws {
            if let failsElecting { throw failsElecting }
            electedStepCovers.append((stepId, entryId))
            mark { message, photo in
                guard message.stepId == stepId else { return photo }
                var marked = photo
                marked.isStepCover = photo.id == entryId
                return marked
            }
        }

        func electTripCover(_ entryId: String?) throws {
            if let failsElecting { throw failsElecting }
            electedTripCovers.append(entryId)
            mark { _, photo in
                var marked = photo
                marked.isTripCover = photo.id == entryId
                return marked
            }
        }

        private func mark(_ change: (ChatMessage, PhotoAttachment) -> PhotoAttachment) {
            thread.messages = thread.messages.map { message in
                guard case .photos(let attachments) = message.body else { return message }
                var updated = message
                updated.body = .photos(attachments.map { change(message, $0) })
                return updated
            }
        }

        func failElecting(with error: any Error) { failsElecting = error }
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
            electStepCover: { stepId, entryId in try await script.electStepCover(stepId, entryId) },
            electTripCover: { entryId in try await script.electTripCover(entryId) },
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

    /// Un souvenir se déplace — récit comme photos. Une précision, non : elle
    /// vise la fiche d'un autre souvenir et n'a pas d'étape à elle, ce que le
    /// serveur refuse aussi.
    func testUnSouvenirSeDeplaceMaisPasUnePrecision() async {
        let messages = [saidText(), photos(), saidText("bulle-precision", disposition: .context)]
        let model = ChatModel(transport: transport(Script(thread: thread(messages: messages))))
        await model.load()

        XCTAssertTrue(model.canMove(model.messages[0]), "Un récit, oui.")
        XCTAssertTrue(model.canMove(model.messages[1]), "Des photos, aussi.")
        XCTAssertFalse(model.canMove(model.messages[2]), "Une précision, non.")
    }

    /// La fiche de MEMO parle du souvenir sans être la bulle qui l'a apporté :
    /// elle se supprime, elle ne se déplace pas — le serveur n'accepte que
    /// les bulles du voyageur.
    func testLaFicheNeSeDeplacePas() async {
        let card = ChatMessage(
            id: "fiche-1",
            author: .memo,
            body: .transcript(TranscriptCard(title: "Retranscription étape 1", capturedAt: .now, text: "Le Janicule.", entryId: "entry-1", phase: .ready)),
            sentAt: .now,
            stepId: "step-1",
            seq: 2
        )
        let model = ChatModel(transport: transport(Script(thread: thread(messages: [card]))))
        await model.load()

        XCTAssertTrue(model.canDelete(model.messages[0]))
        XCTAssertFalse(model.canMove(model.messages[0]))
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

    // MARK: - Les deux photos principales

    /// L'étoile se pose **avant** la réponse du serveur : une étoile qui
    /// arriverait après l'aller-retour se lirait comme un geste raté.
    func testLEtoileDeLEtapeSePoseAvantLaReponse() async throws {
        let script = Script(thread: thread(messages: [photos()]))
        let model = ChatModel(transport: transport(script))
        await model.load()
        let photo = try XCTUnwrap(attachments(of: model.messages[0]).first)

        model.electStepCover(photo, in: model.messages[0])

        XCTAssertTrue(attachments(of: model.messages[0])[0].isStepCover)
        try await until("le serveur a reçu l'élection") { await script.electedStepCovers.count == 1 }
        let elected = await script.electedStepCovers[0]
        XCTAssertEqual(elected.stepId, "step-1")
        XCTAssertEqual(elected.entryId, "photo-1")
    }

    /// Une étoile par étape : élire la seconde photo enlève l'étoile de la
    /// première, et dans le même mouvement.
    func testUneSeuleEtoileParEtape() async throws {
        let script = Script(thread: thread(messages: [photos()]))
        let model = ChatModel(transport: transport(script))
        await model.load()
        model.electStepCover(attachments(of: model.messages[0])[0], in: model.messages[0])

        model.electStepCover(attachments(of: model.messages[0])[1], in: model.messages[0])

        XCTAssertEqual(attachments(of: model.messages[0]).map(\.isStepCover), [false, true])
    }

    /// Le même geste sur une photo déjà élue la défait — c'est `nil` qui part.
    func testLEtoileSeDefaitParLeMemeGeste() async throws {
        let script = Script(thread: thread(messages: [photos()]))
        let model = ChatModel(transport: transport(script))
        await model.load()
        model.electTripCover(attachments(of: model.messages[0])[0])
        try await until("la première élection est partie") { await script.electedTripCovers.count == 1 }

        model.electTripCover(attachments(of: model.messages[0])[0])

        XCTAssertFalse(attachments(of: model.messages[0])[0].isTripCover)
        try await until("le retrait est parti") { await script.electedTripCovers.count == 2 }
        let sent = await script.electedTripCovers
        XCTAssertEqual(sent, ["photo-1", nil])
    }

    /// L'étoile du voyage ne connaît pas les étapes : une seule dans tout le
    /// fil, d'une bulle à l'autre.
    func testUneSeuleEtoileDeVoyageDansToutLeFil() async throws {
        let ailleurs = photos("autre-bulle", ids: ["photo-3"], stepId: "step-2")
        let script = Script(thread: thread(messages: [photos(), ailleurs]))
        let model = ChatModel(transport: transport(script))
        await model.load()
        model.electTripCover(attachments(of: model.messages[0])[0])

        model.electTripCover(attachments(of: model.messages[1])[0])

        XCTAssertEqual(attachments(of: model.messages[0]).map(\.isTripCover), [false, false])
        XCTAssertEqual(attachments(of: model.messages[1]).map(\.isTripCover), [true])
    }

    func testUneElectionRefuseeEnleveLEtoile() async throws {
        let script = Script(thread: thread(messages: [photos()]))
        await script.failElecting(with: APIError.server(statusCode: 500, code: nil, message: "Rien n'a été enregistré."))
        let model = ChatModel(transport: transport(script))
        await model.load()

        model.electTripCover(attachments(of: model.messages[0])[0])
        XCTAssertTrue(attachments(of: model.messages[0])[0].isTripCover, "Posée d'abord.")

        try await until("l'échec est dit") { model.errorMessage != nil }
        XCTAssertFalse(attachments(of: model.messages[0])[0].isTripCover, "Puis reprise.")
    }

    private func attachments(of message: ChatMessage) -> [PhotoAttachment] {
        guard case .photos(let attachments) = message.body else { return [] }
        return attachments
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
