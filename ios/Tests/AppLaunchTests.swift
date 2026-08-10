import MemoBookCore
import MemoBookFeature
import MemoBookNetworking
import XCTest

/// Tests de la cible application. Le gros du code est testé dans les modules
/// (`ios/Modules/Tests`) ; ici on vérifie l'assemblage.
@MainActor
final class AppLaunchTests: XCTestCase {
    func testPrepareMarksDependenciesReady() async {
        let dependencies = AppDependencies(api: PreviewAPI(seeded: false))

        await dependencies.prepare()

        XCTAssertTrue(dependencies.isReady)
        XCTAssertNil(dependencies.startupError)
    }

    func testMemoListLoadsAndCreates() async {
        let dependencies = AppDependencies(api: PreviewAPI())
        let model = MemoListModel(api: dependencies.api)

        await model.load()
        XCTAssertEqual(model.memos.count, 1)

        let created = await model.createMemo(title: "Nouveau carnet", theme: "naissance")
        XCTAssertNotNil(created)
        XCTAssertEqual(model.memos.count, 2)
    }

    func testMemoListRefusesAnEmptyTitle() async {
        let model = MemoListModel(api: PreviewAPI(seeded: false))

        let created = await model.createMemo(title: "   ", theme: nil)

        XCTAssertNil(created)
        XCTAssertNotNil(model.errorMessage)
    }

    func testGenerationIsBlockedWhileMemoIsEmpty() async {
        let api = PreviewAPI(seeded: false)
        let memo = try? await api.createMemo(NewMemo(title: "Vide"))
        let model = MemoDetailModel(memoId: memo?.id ?? "", api: api)

        await model.load()

        XCTAssertFalse(model.canGenerate, "Un carnet sans souvenir ne doit pas être générable.")
    }

    func testGenerationBecomesAvailableOnceASouvenirExists() async {
        let api = PreviewAPI()
        let model = MemoDetailModel(memoId: "preview-memo", api: api)

        await model.load()

        XCTAssertTrue(model.canGenerate)
        // Le jeu d'essai contient un vocal encore en transcription.
        XCTAssertTrue(model.hasWorkInProgress)

        model.stopPolling()
    }
}
