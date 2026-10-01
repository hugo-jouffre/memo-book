import MemoBookCore
@testable import MemoBookFeature
import XCTest

/// Le chemin vers les couvertures, posé sur la première et la dernière page
/// de l'aperçu (Hugo, 30/09/2026, maquette `3545:21634`) — **même sans PDF** :
/// l'aperçu de l'app vit encore sur son jeu d'essai, et le garde-fou d'avant
/// l'effaçait partout.
@MainActor
final class BookPreviewCoverTests: XCTestCase {
    private func model(hasConfiguredCovers: Bool) async -> BookPreviewModel {
        let preview = BookPreview(
            memoId: "memo",
            title: "Rome",
            status: .ready,
            pageCount: 10,
            hasConfiguredCovers: hasConfiguredCovers
        )
        let model = BookPreviewModel(memoId: "memo", source: { _ in preview })
        await model.run()
        return model
    }

    func testTheFirstAndLastPagesInviteToConfigureTheCoversWithoutAPdf() async {
        let model = await model(hasConfiguredCovers: false)
        XCTAssertEqual(model.stage, .preview)

        XCTAssertEqual(model.coverCallToAction, .invitation)
        model.show(sheet: 9)
        XCTAssertEqual(model.coverCallToAction, .invitation, "La quatrième de couverture aussi.")
        model.show(sheet: 4)
        XCTAssertNil(model.coverCallToAction, "Une page du récit ne mène pas aux couvertures.")
    }

    func testOnceChosenBothCoversKeepTheirConfigureButton() async {
        let model = await model(hasConfiguredCovers: true)

        XCTAssertEqual(model.coverCallToAction, .edit)
        XCTAssertFalse(model.isOnConfigurableCover, "Plus de voile une fois les couvertures choisies.")
        model.show(sheet: 9)
        XCTAssertEqual(model.coverCallToAction, .edit)
    }
}
