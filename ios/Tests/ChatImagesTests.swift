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

    private func model(downloads: Downloads) -> ChatModel {
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
                send: { _ in .queued },
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
        try await until { model.images[url] != nil }

        let asked = await downloads.urls
        XCTAssertEqual(asked, [url], "Par le transport, donc avec la session.")

        // Réduite au décodage : le fil ne garde pas les pixels d'une photo
        // d'iPhone pour une vignette.
        let image = try XCTUnwrap(model.images[url])
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
        try await until { model.images[file] != nil }

        let asked = await downloads.urls
        XCTAssertTrue(asked.isEmpty, "Rien ne part au serveur pour une photo sur le disque.")
    }

    func testSomethingThatIsNotAnImageIsNotKept() async throws {
        let downloads = Downloads()
        let model = model(downloads: downloads)
        let file = FileManager.default.temporaryDirectory.appending(path: "rien-\(UUID().uuidString).png")
        try Data("pas une image".utf8).write(to: file)

        model.loadImage(file)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(model.images[file], "La bulle garde sa trame.")
    }

    // MARK: -

    private func until(
        timeout: Duration = .seconds(2),
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Jamais atteint", file: file, line: line)
    }
}
