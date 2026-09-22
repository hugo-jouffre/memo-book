import XCTest

@testable import MemoBookCore

/// Ce que le fil sait de lui-même : à quelle étape appartient un message, et ce
/// qu'il faut retrouver quand on l'ouvre depuis une carte d'étape.
final class ChatThreadTests: XCTestCase {
    private let context = ChatContext(tripId: "trip-rome", stepId: "step-3")

    // MARK: - Retrouver une étape

    /// Ouvrir une étape ne rouvre pas son début : on veut **où on en était**.
    func testFindsTheLastMessageOfAStep() throws {
        let thread = makeThread(
            ("a", "step-1"),
            ("b", "step-1"),
            ("c", "step-2"),
            ("d", "step-1"),
            ("e", "step-2")
        )

        XCTAssertEqual(thread.lastMessage(about: "step-1")?.id, "d")
        XCTAssertEqual(thread.lastMessage(about: "step-2")?.id, "e")
    }

    /// Une étape dont rien n'a été dit n'a rien à montrer : l'écran s'ouvre
    /// alors sur la fin du fil, comme d'habitude.
    func testAnUntouchedStepHasNothingToShow() {
        let thread = makeThread(("a", "step-1"))
        XCTAssertNil(thread.lastMessage(about: "step-9"))
    }

    /// Les bulles qui ne parlent d'aucune étape — l'ouverture de MEMO, une
    /// question sur l'abonnement — ne se font pas rattacher par erreur.
    func testMessagesWithoutAStepAreNeverMatched() {
        let thread = makeThread(("opening", nil), ("a", "step-1"))
        XCTAssertEqual(thread.lastMessage(about: "step-1")?.id, "a")
    }

    // MARK: - La ville du voyage

    /// La ville est une donnée à part entière, distincte du pays : c'est elle
    /// qui permet d'écrire « Nouveau voyage à Rome ! ».
    func testGreetingNamesTheCityNotTheCountry() {
        let rome = Destination(name: "Italie", countryCode: "IT", city: "Rome")

        XCTAssertEqual(
            ChatCopy.greetingTitle(place: try! XCTUnwrap(rome.city), flag: rome.flag),
            "Nouveau voyage à Rome ! 🇮🇹"
        )
    }

    /// Un voyage sans ville — un tour du monde — n'a pas de phrase bancale à
    /// afficher : elle se replie.
    func testATripWithoutACityFallsBack() {
        XCTAssertNil(Destination(name: "Italie", countryCode: "IT").city)
        XCTAssertEqual(ChatCopy.greetingTitleWithoutPlace, "Nouveau carnet de voyage !")
    }

    /// Le champ est optionnel côté serveur : une réponse qui ne le porte pas ne
    /// doit pas faire échouer le décodage de tout l'écran.
    func testDecodesADestinationWithoutACity() throws {
        let json = Data(#"{"name":"Italie","countryCode":"IT"}"#.utf8)
        let destination = try JSONDecoder.memoBook.decode(Destination.self, from: json)

        XCTAssertEqual(destination.name, "Italie")
        XCTAssertNil(destination.city)
    }

    // MARK: - Les photos

    /// MEMO recompte ce qu'il a reçu et demande ce qu'on y voit. Il ne décrit
    /// **pas** les images : il ne les a pas regardées.
    func testPhotosAreCountedNeverDescribed() async throws {
        let responder = LocalMemoResponder(voice: .unavailable)
        let attachments = (0..<3).map { PhotoAttachment(id: "p\($0)") }
        let turn = ChatTurn(
            message: ChatMessage(
                id: "t1",
                author: .traveller,
                body: .photos(attachments),
                sentAt: .distantPast
            ),
            history: [],
            context: context
        )

        let reply = try await responder.reply(to: turn)
        let text = try XCTUnwrap(reply.beats.compactMap(textOf).first)

        XCTAssertTrue(text.hasPrefix("3 photos"), text)
        XCTAssertTrue(text.hasSuffix("?"), "MEMO doit demander ce qu'on y voit")
        XCTAssertGreaterThan(reply.beats[0].pauseMilliseconds, 0)
    }

    func testASinglePhotoIsCountedInTheSingular() {
        XCTAssertTrue(ChatCopy.photosReceived(count: 1).hasPrefix("Une photo"))
    }

    /// Le corps d'un message de photos n'a pas de texte : rien à copier, rien à
    /// faire lire à voix haute.
    func testAPhotoMessageHasNothingToSpeak() {
        let message = ChatMessage(
            id: "p",
            author: .traveller,
            body: .photos([PhotoAttachment(id: "p0")]),
            sentAt: .distantPast
        )
        XCTAssertNil(message.spokenText)
    }

    /// Un chemin local ne part **jamais** vers le serveur : il n'a aucun sens
    /// là-bas.
    func testAPhotoNeverEncodesItsLocalPath() throws {
        let attachment = PhotoAttachment(
            id: "p0",
            localUrl: URL(filePath: "/tmp/p0.jpg")
        )
        let json = try JSONEncoder.memoBook.encode(attachment)
        let text = try XCTUnwrap(String(data: json, encoding: .utf8))

        XCTAssertFalse(text.contains("localUrl"), text)
        XCTAssertFalse(text.contains("/tmp/"), text)
    }

    // MARK: - Outils

    private func makeThread(_ entries: (id: String, stepId: String?)...) -> ChatThread {
        ChatThread(
            id: "trip-rome",
            title: "Rome entre frère et sœur",
            context: context,
            messages: entries.map { entry in
                ChatMessage(
                    id: entry.id,
                    author: .traveller,
                    body: .text(entry.id),
                    sentAt: .distantPast,
                    stepId: entry.stepId
                )
            }
        )
    }

    private func textOf(_ beat: MemoBeat) -> String? {
        if case .text(let value) = beat.message.body { return value }
        return nil
    }
}

// MARK: - Ce que le serveur rend

/// Le fil tel que `GET /v1/trips/:id/chat` le sert — `backend/src/routes/chatSerializers.ts`
/// —, et le même sans les champs que le jeu d'essai ne porte pas.
final class ChatThreadDecodingTests: XCTestCase {
    private let served = Data(
        """
        {
          "id": "trip-rome", "title": "Rome 2026", "avatarUrl": null,
          "destination": { "name": "Italie", "countryCode": "IT", "city": "Rome" },
          "greeting": { "title": "Nouveau voyage à Rome ! 🇮🇹", "message": "Je suis là." },
          "preview": { "memoryCount": 4, "pageCount": 8, "isOpenable": false },
          "context": { "tripId": "trip-rome", "tripTitle": "Rome 2026", "travellerFirstName": "Hugo",
                       "placeName": "Trastevere", "stepNumber": 3, "stepId": "step-3",
                       "prompt": "Comment ça se passe à Trastevere ?", "memberCount": 2 },
          "messages": [
            { "id": "m1", "seq": 1, "author": "memo", "authorName": null,
              "body": { "kind": "text", "text": "Bonjour" },
              "sentAt": "2026-09-21T08:00:00.000Z", "stepId": null, "disposition": null, "pauseMilliseconds": 700 },
            { "id": "m2", "seq": 2, "author": "traveller", "authorName": "Clara",
              "body": { "kind": "voice", "voice": { "id": "m2", "duration": 37, "levels": [0.2, 0.8], "remoteUrl": "http://localhost:3000/v1/entries/e1/media" } },
              "sentAt": "2026-09-21T18:02:11.000Z", "stepId": "step-3", "disposition": "memory", "pauseMilliseconds": null },
            { "id": "m3", "seq": 3, "author": "memo", "authorName": null,
              "body": { "kind": "transcript", "transcript": { "title": "Retranscription du contexte",
                        "capturedAt": "2026-09-21T18:02:11.000Z", "placeLabel": "Trastevere, Rome", "duration": 37,
                        "text": "Ce matin…", "isSimulated": false, "entryId": "e1", "footnote": null,
                        "phase": "writing", "isValidated": false } },
              "sentAt": "2026-09-21T18:02:12.000Z", "stepId": "step-3", "disposition": null, "pauseMilliseconds": 2800 }
          ],
          "suggestions": [ { "id": "accept", "label": "Ça me convient", "symbol": "👌", "intent": "send" } ],
          "turn": { "status": "replying", "messageId": "m2" },
          "canClear": false,
          "now": "2026-09-21T18:03:00.412Z"
        }
        """.utf8)

    func testDecodesEverythingTheServerAdds() throws {
        let thread = try JSONDecoder.memoBook.decode(ChatThread.self, from: served)

        XCTAssertEqual(thread.context.memberCount, 2)
        XCTAssertEqual(thread.turn, .replying(messageId: "m2"))
        XCTAssertFalse(thread.canClear)
        XCTAssertNotNil(thread.now)
        XCTAssertEqual(thread.messages.map(\.seq), [1, 2, 3])
        XCTAssertEqual(thread.messages[1].authorName, "Clara")
        XCTAssertEqual(thread.messages[1].disposition, .memory)
        XCTAssertEqual(thread.messages[2].pauseMilliseconds, 2800)

        guard case .transcript(let card) = thread.messages[2].body else { return XCTFail("une fiche") }
        XCTAssertEqual(card.phase, .writing)
        XCTAssertEqual(card.entryId, "e1")
        XCTAssertTrue(card.isSettling)
        XCTAssertFalse(card.isValidated)

        guard case .voice(let note) = thread.messages[1].body else { return XCTFail("un vocal") }
        XCTAssertEqual(note.remoteUrl?.lastPathComponent, "media")
        XCTAssertNil(note.localUrl, "Un chemin d'appareil ne vient jamais du serveur.")
    }

    /// Le jeu d'essai des aperçus ne porte aucun des champs ajoutés : il décode
    /// encore, avec les valeurs qui ne changent rien.
    func testDecodesAThreadWithoutTheServerFields() throws {
        let bare = Data(
            """
            {
              "id": "t", "title": "T",
              "context": { "tripId": "t" },
              "messages": [
                { "id": "m", "author": "memo", "body": { "kind": "transcript", "transcript": {
                    "title": "Retranscription du contexte", "capturedAt": "2026-09-21T08:00:00.000Z",
                    "text": "…", "isSimulated": true } }, "sentAt": "2026-09-21T08:00:00.000Z" }
              ],
              "suggestions": []
            }
            """.utf8)
        let thread = try JSONDecoder.memoBook.decode(ChatThread.self, from: bare)

        XCTAssertEqual(thread.context.memberCount, 1)
        XCTAssertEqual(thread.turn, .idle)
        XCTAssertTrue(thread.canClear)
        XCTAssertNil(thread.now)
        XCTAssertNil(thread.messages[0].seq)
        guard case .transcript(let card) = thread.messages[0].body else { return XCTFail("une fiche") }
        XCTAssertEqual(card.phase, .ready)
        XCTAssertFalse(card.isSettling)
    }

    /// Un temps ou un classement que cette version ne connaît pas ne casse pas
    /// le fil — même parti que `Status.unknown`.
    func testUnknownPhaseAndDispositionSurvive() throws {
        let json = Data(
            """
            { "id": "m", "author": "traveller", "body": { "kind": "text", "text": "x" },
              "sentAt": "2026-09-21T08:00:00.000Z", "disposition": "dream" }
            """.utf8)
        let message = try JSONDecoder.memoBook.decode(ChatMessage.self, from: json)
        XCTAssertEqual(message.disposition, .unknown("dream"))

        let phase = try JSONDecoder.memoBook.decode(TranscriptCard.Phase.self, from: Data("\"dreaming\"".utf8))
        XCTAssertEqual(phase, .unknown("dreaming"))
    }

    /// La suite du fil et le reçu d'un tour, tels que l'app les sonde et les reçoit.
    func testDecodesAnUpdateAndAReceipt() throws {
        let update = try JSONDecoder.memoBook.decode(
            ChatThreadUpdate.self,
            from: Data(
                """
                { "messages": [], "suggestions": [], "preview": null,
                  "turn": { "status": "idle" }, "now": "2026-09-21T18:03:02.418Z" }
                """.utf8)
        )
        XCTAssertEqual(update.turn, .idle)
        XCTAssertTrue(update.messages.isEmpty)

        let receipt = try JSONDecoder.memoBook.decode(
            ChatTurnReceipt.self,
            from: Data(
                """
                { "messages": [ { "id": "m9", "seq": 9, "author": "traveller", "body": { "kind": "text", "text": "…" },
                                  "sentAt": "2026-09-21T18:03:00.000Z" } ],
                  "turn": { "status": "replying", "messageId": "m9" }, "now": "2026-09-21T18:03:00.412Z" }
                """.utf8)
        )
        XCTAssertEqual(receipt.turn, .replying(messageId: "m9"))
        XCTAssertEqual(receipt.messages.first?.seq, 9)
    }
}
