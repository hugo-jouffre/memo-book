import MemoBookCore
import UIKit
import XCTest

@testable import MemoBookFeature

/// **Une photo passée par une messagerie n'a plus de mémoire** (T315, Hugo,
/// 08/11/2026 — « les métadonnées d'une photo ne doivent pas se perdre : lieu,
/// date, heure. Une photo venue de WhatsApp les a déjà perdues — ça se voit à
/// son nom de fichier »).
///
/// Ce que la photothèque en garde est la date de son **arrivée** sur le
/// téléphone, et rien dans la fiche ne distingue les deux. Le nom du fichier,
/// lui, le dit — et c'est tout ce qu'on a.
@MainActor
final class PhotoWithoutMemoryTests: XCTestCase {
    private var picture: Data {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    // MARK: Ce que le nom raconte

    func testWhatsAppNamesAreRecognised() {
        XCTAssertTrue(PhotoFilename.isForwarded("IMG-20260811-WA0012.jpg"))
        XCTAssertTrue(PhotoFilename.isForwarded("img-20260811-wa0012.jpeg"), "La casse ne décide de rien.")
        XCTAssertTrue(PhotoFilename.isForwarded("IMG_20260811_WA0003.jpg"), "Certaines versions Android séparent au tiret bas.")
        XCTAssertTrue(PhotoFilename.isForwarded("WhatsApp Image 2026-08-11 at 12.34.56.jpeg"))
    }

    /// **Le garde-fou qui compte.** Une question de trop sur une photo saine
    /// coûte plus cher qu'une photo mal rangée de plus : ces noms-là portent
    /// très bien leur date, et on ne leur demande rien.
    func testAPhotoFromTheCameraIsNotAsked() {
        XCTAssertFalse(PhotoFilename.isForwarded("IMG_4821.HEIC"), "L'appareil photo d'un iPhone.")
        XCTAssertFalse(
            PhotoFilename.isForwarded("IMG_20260811_123456.jpg"),
            "Un appareil photo Android — même forme, et c'est pour ça que Telegram n'est pas détecté."
        )
        XCTAssertFalse(PhotoFilename.isForwarded("PXL_20260811_123456789.jpg"), "Un Pixel.")
        XCTAssertFalse(PhotoFilename.isForwarded("IMG-20260811-0012.jpg"), "Sans le code de l'app, rien ne dit d'où elle vient.")
        XCTAssertFalse(PhotoFilename.isForwarded("capture décran.png"))
        XCTAssertFalse(PhotoFilename.isForwarded(""))
    }

    // MARK: Ce que la réponse du voyageur devient

    /// Le jour est posé à **midi** : à minuit, une journée bascule à la veille
    /// dès que le serveur la lit en UTC depuis l'est de Greenwich, et la photo
    /// change de page.
    func testTheAnsweredDayIsPlacedAtNoon() throws {
        let photo = PickedPhoto(data: picture, capturedAt: .now, isForwarded: true)
        let day = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 0))
        )

        let placed = photo.placed(day: day, place: "Hvolsvöllur")

        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour], from: try XCTUnwrap(placed.capturedAt))
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 8)
        XCTAssertEqual(parts.day, 11)
        XCTAssertEqual(parts.hour, 12)
        XCTAssertEqual(placed.placeName, "Hvolsvöllur")
    }

    /// Les deux champs sont facultatifs : ce qu'on laisse vide ne remplace
    /// rien, et surtout n'efface rien.
    func testAnEmptyAnswerErasesNothing() throws {
        let arrived = Date(timeIntervalSince1970: 1_775_000_000)
        let photo = PickedPhoto(data: picture, capturedAt: arrived, placeName: "Kanazawa", isForwarded: true)

        let placed = photo.placed(day: nil, place: "   ")

        XCTAssertEqual(placed.capturedAt, arrived)
        XCTAssertEqual(placed.placeName, "Kanazawa")
    }

    // MARK: Ce que l'envoi en fait

    private func model(sent: Sent) -> ChatModel {
        let thread = ChatThread(
            id: "trip",
            title: "Rome",
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
                    await sent.record(turn)
                    return .queued
                },
                editTranscript: { _, _ in throw CancellationError() },
                media: { _ in Data() }
            )
        )
    }

    private actor Sent {
        var turns: [OutgoingTurn] = []
        func record(_ turn: OutgoingTurn) { turns.append(turn) }
        var isEmpty: Bool { turns.isEmpty }
    }

    private func until(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("La condition n'est jamais arrivée.")
    }

    /// Le cas de Hugo : rien ne part tant qu'on n'a pas répondu, et la feuille
    /// dit combien de photos sont concernées.
    func testAForwardedPhotoHoldsTheWholeBatch() async throws {
        let sent = Sent()
        let model = model(sent: sent)
        await model.load()

        model.sendPhotos([
            PickedPhoto(data: picture, capturedAt: .now, placeName: "Kanazawa"),
            PickedPhoto(data: picture, capturedAt: .now, isForwarded: true),
        ])

        XCTAssertEqual(model.photosAwaitingOrigin?.count, 2, "L'envoi entier attend la réponse.")
        XCTAssertEqual(model.forwardedPhotoCount, 1, "Une seule a perdu sa mémoire.")
        let turns = await sent.turns
        XCTAssertTrue(turns.isEmpty, "Rien ne part avant la réponse.")
    }

    /// **La réponse ne touche que les photos sans mémoire.** Celle qui portait
    /// sa date et son lieu en sait plus que le voyageur.
    func testTheAnswerOnlyPlacesThePhotosThatLostTheirs() async throws {
        let sent = Sent()
        let model = model(sent: sent)
        await model.load()
        let kanazawa = Date(timeIntervalSince1970: 1_775_000_000)

        model.sendPhotos([
            PickedPhoto(data: picture, capturedAt: kanazawa, placeName: "Kanazawa"),
            PickedPhoto(data: picture, capturedAt: .now, isForwarded: true),
        ])
        model.placeAwaitingPhotos(day: Date(timeIntervalSince1970: 1_770_000_000), place: "Takayama")

        try await until { await sent.isEmpty == false }
        let turns = await sent.turns
        let turn = try XCTUnwrap(turns.first)
        guard case .photos(let uploads, _) = turn.body else {
            return XCTFail("Un envoi de photos était attendu.")
        }
        XCTAssertNil(model.photosAwaitingOrigin)
        XCTAssertEqual(uploads.map(\.capturedPlaceName), ["Kanazawa", "Takayama"])
        XCTAssertEqual(uploads.first?.capturedAt, kanazawa, "Celle qui savait n'a pas été retouchée.")
    }

    /// La sortie, et le glissé qui referme la feuille : les photos partent
    /// comme avant T315. Une sélection perdue faute de réponse serait pire
    /// qu'une photo mal rangée.
    func testTheWayOutStillSendsThePhotos() async throws {
        let sent = Sent()
        let model = model(sent: sent)
        await model.load()
        let arrived = Date(timeIntervalSince1970: 1_775_000_000)

        model.sendPhotos([PickedPhoto(data: picture, capturedAt: arrived, isForwarded: true)])
        model.sendAwaitingPhotosAsIs()

        try await until { await sent.isEmpty == false }
        let turns = await sent.turns
        let turn = try XCTUnwrap(turns.first)
        guard case .photos(let uploads, _) = turn.body else {
            return XCTFail("Un envoi de photos était attendu.")
        }
        XCTAssertEqual(uploads.first?.capturedAt, arrived)
        XCTAssertNil(uploads.first?.capturedPlaceName)
    }

    /// Un envoi dont **aucune** photo n'a perdu sa mémoire ne pose aucune
    /// question : la feuille ne s'ouvre pas, et rien ne change pour lui.
    func testPhotosThatKeptTheirMemoryLeaveWithoutAQuestion() async throws {
        let sent = Sent()
        let model = model(sent: sent)
        await model.load()

        model.sendPhotos([PickedPhoto(data: picture, capturedAt: .now, placeName: "Rome")])

        XCTAssertNil(model.photosAwaitingOrigin)
        try await until { await sent.isEmpty == false }
    }
}
