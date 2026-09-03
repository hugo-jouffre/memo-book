import MemoBookCore
import MemoBookFeature
import MemoBookNetworking
import XCTest

/// Tests de la cible application. Le gros du code est testé dans les modules
/// (`ios/Modules/Tests`) ; ici on vérifie l'assemblage.
@MainActor
final class AppLaunchTests: XCTestCase {
    /// L'enregistrement de l'appareil est paresseux : il ne bloque plus le
    /// démarrage, et un deuxième appel ne relance pas de requête.
    func testDeviceRegistrationIsLazyAndIdempotent() async throws {
        let dependencies = AppDependencies(api: PreviewAPI(seeded: false))

        try await dependencies.ensureRegistered()
        try await dependencies.ensureRegistered()
    }

    func testMemoListLoadsAndCreates() async {
        let dependencies = AppDependencies(api: PreviewAPI())
        let model = MemoListModel(dependencies: dependencies)

        await model.load()
        XCTAssertEqual(model.memos.count, 1)

        let created = await model.createMemo(title: "Nouveau carnet", theme: "naissance")
        XCTAssertNotNil(created)
        XCTAssertEqual(model.memos.count, 2)
    }

    func testMemoListRefusesAnEmptyTitle() async {
        let model = MemoListModel(dependencies: AppDependencies(api: PreviewAPI(seeded: false)))

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

    /// Le jeu d'essai contient un souvenir dont la rédaction tourne encore.
    /// Générer maintenant mettrait sa transcription brute dans le PDF : le
    /// bouton doit attendre, même s'il y a déjà des souvenirs prêts.
    func testGenerationWaitsWhileASouvenirIsStillBeingPrepared() async {
        let api = PreviewAPI()
        let model = MemoDetailModel(memoId: "preview-memo", api: api)

        await model.load()

        XCTAssertFalse(model.entries.isEmpty)
        XCTAssertTrue(model.hasWorkInProgress)
        XCTAssertFalse(model.canGenerate, "Un souvenir en cours de rédaction bloque la génération.")

        model.stopPolling()
    }
}
