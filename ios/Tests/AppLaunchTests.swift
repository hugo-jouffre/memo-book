import MemoBookCore
import MemoBookFeature
import MemoBookNetworking
import XCTest

/// Tests de la cible application. Le gros du code est testé dans les modules
/// (`ios/Modules/Tests`) ; ici on vérifie l'assemblage.
@MainActor
final class AppLaunchTests: XCTestCase {
    /// Sans compte, le lancement s'arrête sur le Welcome Screen — c'est le
    /// routage décrit par le détail fonctionnel de l'onboarding.
    func testLaunchWithoutAnAccountLandsOnWelcome() async {
        let dependencies = AppDependencies(
            api: PreviewAPI(seeded: false),
            sessions: InMemorySessionStore()
        )

        await dependencies.onboarding.start()

        XCTAssertEqual(dependencies.onboarding.step, .welcome)
    }

    /// Quelqu'un qui a déjà vu le Welcome ne le revoit pas : il repart sur la
    /// connexion, même après une désinstallation.
    func testLaunchAfterOnboardingLandsOnSignIn() async {
        let dependencies = AppDependencies(
            api: PreviewAPI(seeded: false),
            sessions: InMemorySessionStore(hasSeenOnboarding: true)
        )

        await dependencies.onboarding.start()

        XCTAssertEqual(dependencies.onboarding.step, .credentials(.signIn))
    }

    /// Une session valide court-circuite tout le flow.
    func testLaunchWithAValidSessionGoesStraightHome() async {
        let api = PreviewAPI(seeded: false)
        _ = try? await api.signUp(
            NewAccount(
                firstName: "Cla",
                lastName: "Thioll",
                email: "cla.thioll@gmail.com",
                password: "carnet2026"
            )
        )

        let dependencies = AppDependencies(api: api, sessions: InMemorySessionStore())
        await dependencies.onboarding.start()

        XCTAssertEqual(dependencies.onboarding.step, .home)
    }

    /// Le lien reçu par email est le seul chemin vers l'écran de nouveau mot
    /// de passe, et il porte le jeton.
    func testResetPasswordDeepLinkCarriesItsToken() {
        let dependencies = AppDependencies(
            api: PreviewAPI(seeded: false),
            sessions: InMemorySessionStore()
        )

        let handled = dependencies.onboarding.open(
            deepLink: URL(string: "memobook://reset-password?token=abc123")!
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(dependencies.onboarding.step, .resetPassword(token: "abc123"))
    }

    func testUnknownDeepLinkIsIgnored() {
        let dependencies = AppDependencies(
            api: PreviewAPI(seeded: false),
            sessions: InMemorySessionStore()
        )

        XCTAssertFalse(
            dependencies.onboarding.open(deepLink: URL(string: "memobook://autre-chose")!)
        )
        XCTAssertFalse(
            dependencies.onboarding.open(deepLink: URL(string: "memobook://reset-password")!)
        )
    }

    func testMemoListLoadsAndCreates() async {
        let dependencies = AppDependencies(api: PreviewAPI(), sessions: InMemorySessionStore())
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
