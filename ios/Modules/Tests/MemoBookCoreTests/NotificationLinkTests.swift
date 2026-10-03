import XCTest

@testable import MemoBookCore

/// Les liens que le serveur met dans ses notifications — au chemin près de
/// `NOTIFICATION_LINKS` (`backend/src/services/notificationPlanner.ts`).
final class NotificationLinkTests: XCTestCase {
    private func link(_ string: String) -> NotificationLink? {
        NotificationLink(url: URL(string: string)!)
    }

    func testEachServerLinkOpensItsScreen() {
        let trip = "6f1c2e7a-3b2d-4c55-9a7e-0d4b8f2a1c90"
        XCTAssertEqual(link("memobook://subscription"), .subscription)
        XCTAssertEqual(link("memobook://trips/new"), .newTrip)
        XCTAssertEqual(link("memobook://trips/\(trip)/chat"), .chat(tripId: trip))
        XCTAssertEqual(link("memobook://trips/\(trip)/wallet"), .wallet(tripId: trip))
        XCTAssertEqual(link("memobook://trips/\(trip)/preview"), .bookPreview(tripId: trip))
    }

    /// Le serveur ne l'envoie plus, mais des notifications déjà livrées le
    /// portent : il ouvre encore l'offre.
    func testTheFormerPaywallLinkStillOpensTheOffer() {
        XCTAssertEqual(link("memobook://paywall"), .paywall)
    }

    func testOtherLinksOfTheAppAreNotNotifications() {
        // Ceux-là ont leur propre chemin : le retour de Stripe, l'e-mail.
        XCTAssertNil(link("memobook://stripe-redirect"))
        XCTAssertNil(link("memobook://password/reset?token=abc"))
        XCTAssertNil(link("memobook://trips/abc/unknown"))
        XCTAssertNil(link("https://memo-book.com/paywall"))
    }

    func testThePayloadKeyIsReadAsALink() {
        XCTAssertEqual(NotificationLink(payloadLink: "memobook://subscription"), .subscription)
        XCTAssertNil(NotificationLink(payloadLink: nil))
    }

    func testTheTokenIsWrittenAsAPNsExpectsIt() {
        XCTAssertEqual(PushTokenRegistration.hex(Data([0x00, 0xAB, 0x10, 0xFF])), "00ab10ff")
    }
}
