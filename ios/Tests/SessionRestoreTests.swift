import MemoBookCore
@testable import MemoBookFeature
import MemoBookNetworking
import XCTest

/// Ce que le lancement fait d'une session gardée : seul un 401 fait sortir.
/// Du 27 au 29/09/2026, un 500 sur `GET /v1/auth/me` sortait tout le monde.
@MainActor
final class SessionRestoreTests: XCTestCase {
    private let yesterday = Account(id: "compte-1", firstName: "Camille", createdAt: .distantPast)
    private let fresh = Account(id: "compte-1", firstName: "Camille-Rose", createdAt: .distantPast)

    private let serverDown = APIError.server(statusCode: 500, code: nil, message: "Erreur interne du serveur.")
    private let offline = APIError.transport(URLError(.notConnectedToInternet), url: nil)

    /// Rejoue `resolve` avec une suite d'issues pour `verify`, une par essai.
    private func resolve(
        _ outcomes: [Result<Account, APIError>],
        stillStored: Bool = true,
        remembered: Account? = nil
    ) async -> (restore: SessionRestore, attempts: Int) {
        var attempts = 0
        let restore = await SessionRestore.resolve(
            verify: {
                defer { attempts += 1 }
                return try outcomes[min(attempts, outcomes.count - 1)].get()
            },
            isStillStored: { stillStored },
            remembered: { remembered },
            retryDelays: [.zero, .zero]
        )
        return (restore, attempts)
    }

    func testTheServerAnswerWinsOverTheRememberedAccount() async {
        let (restore, _) = await resolve([.success(fresh)], remembered: yesterday)
        XCTAssertEqual(restore, .verified(fresh))
    }

    func testAServerErrorEntersWithYesterdaysAccount() async {
        let (restore, attempts) = await resolve([.failure(serverDown)], remembered: yesterday)
        XCTAssertEqual(restore, .remembered(yesterday))
        XCTAssertEqual(attempts, 1, "Avec un compte gardé, on entre sans faire attendre.")
    }

    func testNoNetworkEntersWithYesterdaysAccount() async {
        let (restore, _) = await resolve([.failure(offline)], remembered: yesterday)
        XCTAssertEqual(restore, .remembered(yesterday))
    }

    /// Le 401 : le client a effacé le jeton, et c'est ce qui décide — pas le
    /// compte gardé, qui ne vaut plus rien.
    func testARefusedSessionClosesEvenWithARememberedAccount() async {
        let refused = APIError.server(statusCode: 401, code: nil, message: "Session expirée.")
        let (restore, attempts) = await resolve([.failure(refused)], stillStored: false, remembered: yesterday)
        XCTAssertEqual(restore, .closed)
        XCTAssertEqual(attempts, 1)
    }

    func testWithoutARememberedAccountAPassingOutageIsRetried() async {
        let (restore, attempts) = await resolve([.failure(serverDown), .success(fresh)])
        XCTAssertEqual(restore, .verified(fresh))
        XCTAssertEqual(attempts, 2)
    }

    func testWithoutARememberedAccountALastingOutageGivesUpAfterTheRetries() async {
        let (restore, attempts) = await resolve([.failure(serverDown)])
        XCTAssertEqual(restore, .unreachable)
        XCTAssertEqual(attempts, 3, "Un essai, puis un par attente.")
    }

    /// Une réponse qu'on ne sait pas lire ne se lira pas mieux dans trois
    /// secondes.
    func testAnUnreadableAnswerIsNotRetried() async {
        let unreadable = APIError.decoding(URLError(.cannotDecodeContentData))
        let (restore, attempts) = await resolve([.failure(unreadable)])
        XCTAssertEqual(restore, .unreachable)
        XCTAssertEqual(attempts, 1)
    }

    func testNoStoredSessionIsClosed() async {
        let dependencies = AppDependencies(api: PreviewAPI(seeded: false))
        let restore = await dependencies.restoreSession()
        XCTAssertEqual(restore, .closed)
    }
}
