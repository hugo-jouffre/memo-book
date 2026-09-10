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
