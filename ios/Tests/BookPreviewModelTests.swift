import MemoBookCore
@testable import MemoBookFeature
import XCTest

/// Le premier chargement de l'aperçu — avec ou sans cascade —, et sa mise à
/// jour silencieuse quand une étape validée recompose le carnet en fond.
@MainActor
final class BookPreviewModelTests: XCTestCase {
    /// Rend ses réponses dans l'ordre, une par appel — de quoi rejouer un
    /// sondage précis sans double de réseau.
    private final class QueuedSource {
        private var responses: [BookPreview]

        init(_ responses: [BookPreview]) {
            self.responses = responses
        }

        func next() throws -> BookPreview {
            guard !responses.isEmpty else { throw Empty() }
            return responses.removeFirst()
        }

        struct Empty: Error {}
    }

    /// Sans `pdfUrl` — comme `BookPreview.fixture` de la maquette — pour que
    /// ces tests n'ouvrent jamais de vraie connexion réseau : seul l'état du
    /// modèle est en jeu ici, pas le téléchargement PDFKit.
    private func preview(status: BookPreviewStatus, pageCount: Int = 4) -> BookPreview {
        BookPreview(memoId: "memo-1", title: "Rome", status: status, pageCount: pageCount)
    }

    func testAlreadyReadyBookSkipsTheComposingCascade() async throws {
        let source = QueuedSource([preview(status: .ready)])
        let model = BookPreviewModel(memoId: "memo-1", source: { _ in try source.next() })

        let started = ContinuousClock.now
        await model.run()

        XCTAssertEqual(model.stage, .preview)
        // Le plancher de la cascade est de 2,6 s : rester bien en dessous
        // prouve qu'il n'a pas été traversé pour rien.
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(1))
    }

    func testFirstCompositionStillPlaysTheCascade() async throws {
        let source = QueuedSource([preview(status: .composing), preview(status: .ready)])
        let model = BookPreviewModel(memoId: "memo-1", source: { _ in try source.next() })

        await model.run()

        XCTAssertEqual(model.stage, .preview)
        XCTAssertEqual(model.compositionProgress, 1, accuracy: 0.001)
    }

    func testBackgroundRegenerationDoesNotReplayTheComposingStage() async throws {
        let source = QueuedSource([preview(status: .ready), preview(status: .composing)])
        let model = BookPreviewModel(memoId: "memo-1", source: { _ in try source.next() })
        await model.run()
        XCTAssertEqual(model.stage, .preview)

        // `refreshIfNeeded()` sonde une fois, voit « composing », puis entre
        // en veille (`watchRecomposition()`) — on n'a besoin que du tout début
        // de cette veille, pas de son terme.
        let task = Task { await model.refreshIfNeeded() }
        try await waitUntil { model.isRecomposing }
        task.cancel()

        XCTAssertEqual(model.stage, .preview)
        XCTAssertTrue(model.isRecomposing)
    }

    func testBackgroundRegenerationCompletesAndFlashes() async throws {
        let source = QueuedSource([
            preview(status: .ready, pageCount: 4),
            preview(status: .composing),
            preview(status: .ready, pageCount: 5),
        ])
        let model = BookPreviewModel(memoId: "memo-1", source: { _ in try source.next() })
        await model.run()

        // Une seule veille suffit : le troisième appel de la file répond déjà
        // « prêt », donc `watchRecomposition()` s'arrête à son premier
        // sondage — quatre secondes réelles, sa propre cadence.
        await model.refreshIfNeeded()

        XCTAssertEqual(model.stage, .preview)
        XCTAssertFalse(model.isRecomposing)
        XCTAssertTrue(model.freshness.isUpdated)
        XCTAssertEqual(model.preview?.pageCount, 5)
    }

    func testBackgroundRegenerationFailureKeepsTheOldDocument() async throws {
        let source = QueuedSource([
            preview(status: .ready, pageCount: 4),
            preview(status: .failed("Erreur")),
        ])
        let model = BookPreviewModel(memoId: "memo-1", source: { _ in try source.next() })
        await model.run()

        await model.refreshIfNeeded()

        // Un échec de régénération en fond ne doit rien afficher sur un
        // aperçu déjà là : ni bandeau d'erreur, ni recul de la page comptée.
        XCTAssertEqual(model.stage, .preview)
        XCTAssertFalse(model.isRecomposing)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.preview?.pageCount, 4)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            if clock.now > deadline {
                XCTFail("Condition non remplie en \(timeout)")
                throw TimedOut()
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private struct TimedOut: Error {}
}
