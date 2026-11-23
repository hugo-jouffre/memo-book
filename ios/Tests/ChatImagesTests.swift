import MemoBookCore
@testable import MemoBookFeature
import UIKit
import XCTest

/// Les images du fil passent par le modèle (T206, 30/09/2026) : une photo du
/// voyage **avec la session**, par le transport — un `AsyncImage` se faisait
/// refuser `/v1/entries/:id/media` en `401` —, une photo qu'on vient de
/// choisir depuis le disque.
@MainActor
final class ChatImagesTests: XCTestCase {
    /// Ce que le transport a téléchargé, et pour qui.
    private actor Downloads {
        var urls: [URL] = []
        func record(_ url: URL) { urls.append(url) }
    }

    /// Une image de 2 000 × 1 500 px : plus grande que ce que le fil garde.
    private var picture: Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 2_000, height: 1_500), format: format)
            .pngData { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 2_000, height: 1_500))
            }
    }

    /// Ce que le modèle a confié au transport.
    private actor Sent {
        var turns: [OutgoingTurn] = []
        func record(_ turn: OutgoingTurn) { turns.append(turn) }
    }

    private func model(downloads: Downloads, sent: Sent? = nil) -> ChatModel {
        let picture = picture
        let thread = ChatThread(
            id: "trip",
            title: "Lisbonne 2024",
            context: ChatContext(tripId: "trip", stepId: nil),
            messages: [],
            suggestions: [],
            now: .now
        )
        return ChatModel(
            transport: ChatTransport(
                load: { thread },
                poll: { _ in ChatThreadUpdate(messages: [], suggestions: [], turn: .idle, now: .now) },
                send: { turn in
                    await sent?.record(turn)
                    return .queued
                },
                editTranscript: { _, _ in throw CancellationError() },
                media: { url in
                    await downloads.record(url)
                    return picture
                }
            )
        )
    }

    func testAPhotoFromTheServerIsDownloadedWithTheSession() async throws {
        let downloads = Downloads()
        let model = model(downloads: downloads)
        let url = try XCTUnwrap(URL(string: "https://api.test/v1/entries/souvenir-a/media"))

        model.loadImage(url)
        try await until { model.image(at: url) != nil }

        let asked = await downloads.urls
        XCTAssertEqual(asked, [url], "Par le transport, donc avec la session.")

        // Réduite au décodage : le fil ne garde pas les pixels d'une photo
        // d'iPhone pour une vignette.
        let image = try XCTUnwrap(model.image(at: url))
        let longest = max(image.size.width * image.scale, image.size.height * image.scale)
        XCTAssertLessThanOrEqual(longest, ChatImage.maximumPixelSize)

        // Une seconde demande ne retélécharge pas.
        model.loadImage(url)
        try await Task.sleep(for: .milliseconds(50))
        let again = await downloads.urls
        XCTAssertEqual(again.count, 1)
    }

    func testAPhotoJustChosenIsReadFromTheDisk() async throws {
        let downloads = Downloads()
        let model = model(downloads: downloads)
        let file = FileManager.default.temporaryDirectory.appending(path: "photo-\(UUID().uuidString).png")
        try picture.write(to: file)

        model.loadImage(file)
        try await until { model.image(at: file) != nil }

        let asked = await downloads.urls
        XCTAssertTrue(asked.isEmpty, "Rien ne part au serveur pour une photo sur le disque.")
    }

    /// **Plus rien n'est coupé** (T265, 23/11/2026).
    ///
    /// Le surplus était jeté — vingt photos gardées sur soixante — avec un
    /// bandeau pour le dire. Le ticket demandait l'inverse : « sans limite ».
    /// Les photos partent donc en autant de messages qu'il faut, vingt par
    /// tour, parce que c'est la borne du serveur et la taille qu'un envoi
    /// passe en moins de soixante secondes (T275).
    func testEveryPhotoLeavesInAsManyMessagesAsNeeded() async throws {
        let sent = Sent()
        let model = model(downloads: Downloads(), sent: sent)
        await model.load()
        let combien = ChatMetrics.maxPhotosPerMessage * 2 + 5

        model.sendPhotos(Array(repeating: PickedPhoto(data: picture), count: combien))
        try await until { await sent.turns.count == 3 }

        let tours = await sent.turns
        let parties = tours.reduce(0) { total, tour in
            if case .photos(let uploads, _) = tour.body { return total + uploads.count }
            return total
        }
        XCTAssertEqual(parties, combien, "Aucune photo ne reste en route.")
        XCTAssertNil(model.errorMessage, "Rien n'est coupé, donc rien à annoncer.")

        // Chaque tour a son identifiant : la file les reprend un à un, et
        // celui qui échoue ne perd pas les autres.
        XCTAssertEqual(Set(tours.map(\.id)).count, 3)
    }

    /// Juste à la borne, un seul message : on ne découpe pas pour rien.
    func testOneMessageWhenEverythingFits() async throws {
        let sent = Sent()
        let model = model(downloads: Downloads(), sent: sent)
        await model.load()

        model.sendPhotos(Array(repeating: PickedPhoto(data: picture), count: ChatMetrics.maxPhotosPerMessage))
        try await until { await sent.turns.count == 1 }

        XCTAssertNil(model.errorMessage, "Tout est parti : rien à signaler.")
    }

    func testSomethingThatIsNotAnImageIsNotKept() async throws {
        let downloads = Downloads()
        let model = model(downloads: downloads)
        let file = FileManager.default.temporaryDirectory.appending(path: "rien-\(UUID().uuidString).png")
        try Data("pas une image".utf8).write(to: file)

        model.loadImage(file)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(model.image(at: file), "La bulle garde sa trame.")
    }

    // MARK: -

    private func until(
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
        XCTFail("Jamais atteint", file: file, line: line)
    }
}


// MARK: - Ce que chaque photo sait d'elle-même (T280)

extension ChatImagesTests {
    /// **Sa journée et son lieu voyagent avec elle**, pas avec le tour
    /// (T280, 20/11/2026 — « Shanghai alors qu'on est à Tokyo »).
    ///
    /// Un envoi n'avait qu'une date pour ses quatre photos, et aucune ne
    /// disait où elle avait été prise : le lieu d'une étape ne tenait alors
    /// qu'à un seul récit.
    func testEachPhotoCarriesItsOwnDayAndPlace() async throws {
        let sent = Sent()
        let model = model(downloads: Downloads(), sent: sent)
        // Le modèle n'envoie rien sans fil : `send` sort tout de suite.
        await model.load()
        let kanazawa = Date(timeIntervalSince1970: 1_775_000_000)
        let takayama = Date(timeIntervalSince1970: 1_775_300_000)

        model.sendPhotos([
            PickedPhoto(data: picture, capturedAt: kanazawa, placeName: "Kanazawa"),
            PickedPhoto(data: picture, capturedAt: takayama, placeName: "Takayama"),
        ])

        try await until { await sent.turns.isEmpty == false }
        let turns = await sent.turns
        let turn = try XCTUnwrap(turns.first)
        guard case .photos(let uploads, _) = turn.body else {
            return XCTFail("Un envoi de photos était attendu.")
        }
        XCTAssertEqual(uploads.map(\.capturedAt), [kanazawa, takayama])
        XCTAssertEqual(uploads.map(\.capturedPlaceName), ["Kanazawa", "Takayama"])
    }

    /// Une photo prise à l'instant n'a ni l'un ni l'autre, et ce n'est pas un
    /// manque : le serveur retombe sur la date du tour, qui est maintenant.
    func testAPhotoTakenNowSaysNothingOfItself() async throws {
        let sent = Sent()
        let model = model(downloads: Downloads(), sent: sent)
        await model.load()

        model.sendPhotos([PickedPhoto(data: picture)])

        try await until { await sent.turns.isEmpty == false }
        let turns = await sent.turns
        let turn = try XCTUnwrap(turns.first)
        guard case .photos(let uploads, _) = turn.body else {
            return XCTFail("Un envoi de photos était attendu.")
        }
        XCTAssertEqual(uploads.count, 1)
        XCTAssertNil(uploads[0].capturedAt)
        XCTAssertNil(uploads[0].capturedPlaceName)
    }
}
