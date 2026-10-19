import MemoBookCore
@testable import MemoBookFeature
import MemoBookNetworking
import XCTest

/// D11 (Hugo, 19/10/2026) : hors ligne, un voyage jamais ouvert sur ce
/// téléphone s'ouvre d'après la carte de l'accueil — et non plus sur un
/// squelette sans chemin vers la conversation. Une réponse du serveur garde
/// son écran d'erreur.
@MainActor
final class TripOfflineOpeningTests: XCTestCase {
    private let card = Trip(id: "rome", title: "Rome", stage: .ongoing)

    private var offline: APIError { .transport(URLError(.notConnectedToInternet), url: nil) }

    func testWithoutNetworkNorCacheTheHomeCardOpensTheTrip() async {
        let model = TripHomeModel(
            tripId: "rome",
            source: { _ in throw self.offline },
            homeCard: { [card] in card }
        )
        await model.load()

        XCTAssertEqual(model.detail?.trip, card)
        XCTAssertEqual(model.detail?.steps, [])
        XCTAssertNotNil(model.errorMessage, "Le bandeau reste : la page ne prétend pas être à jour.")
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.freshness, .restored)
    }

    func testAServerAnswerKeepsItsErrorScreen() async {
        let model = TripHomeModel(
            tripId: "rome",
            source: { _ in throw APIError.server(statusCode: 404, code: nil, message: "Voyage introuvable.") },
            homeCard: { [card] in card }
        )
        await model.load()

        XCTAssertNil(model.detail)
        XCTAssertEqual(model.errorMessage, "Voyage introuvable.")
    }

    /// Ce qu'on avait gardé de l'écran du voyage passe avant la carte : il en
    /// sait plus (les étapes).
    func testTheTripCacheWinsOverTheHomeCard() async {
        let stored = TripDetail(trip: card, steps: [TripStep(id: "a", number: 1)])
        let model = TripHomeModel(
            tripId: "rome",
            source: { _ in throw self.offline },
            cached: { stored },
            homeCard: { Trip(id: "rome", title: "Autre", stage: .ongoing) }
        )
        await model.load()

        XCTAssertEqual(model.detail, stored)
    }

    /// Le réseau revenu, le serveur remplace la carte.
    func testTheServerReplacesTheCardOnTheNextLoad() async {
        var isOnline = false
        let served = TripDetail(trip: card, steps: [TripStep(id: "a", number: 1)])
        let model = TripHomeModel(
            tripId: "rome",
            source: { _ in
                guard isOnline else { throw self.offline }
                return served
            },
            homeCard: { [card] in card }
        )
        await model.load()
        isOnline = true
        await model.load()

        XCTAssertEqual(model.detail, served)
        XCTAssertNil(model.errorMessage)
    }
}
