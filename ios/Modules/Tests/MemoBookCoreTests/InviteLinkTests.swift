import XCTest

@testable import MemoBookCore

/// Le lien d'invitation d'un co-voyageur (18/10/2026) : ses trois formes, et ce
/// qu'il ne doit pas prendre pour lui.
final class InviteLinkTests: XCTestCase {
    func testTheUniversalLinkCarriesTheCode() {
        let url = URL(string: "https://api-production-9f35a.up.railway.app/j/JHKFDA")!
        XCTAssertEqual(InviteLink.code(from: url), "JHKFDA")
        XCTAssertEqual(NotificationLink(url: url), .join(code: "JHKFDA"))
    }

    func testTheFallbackPageOpensTheAppWithTheCode() {
        XCTAssertEqual(NotificationLink(url: URL(string: "memobook://join?code=jhk-fda")!), .join(code: "JHKFDA"))
        XCTAssertEqual(NotificationLink(url: URL(string: "memobook://j/JHKFDA")!), .join(code: "JHKFDA"))
    }

    func testOtherLinksAreNotInvitations() {
        XCTAssertNil(InviteLink.code(from: URL(string: "https://api-production-9f35a.up.railway.app/password/reset")!))
        XCTAssertNil(InviteLink.code(from: URL(string: "memobook://join")!))
        XCTAssertEqual(NotificationLink(url: URL(string: "memobook://paywall")!), .paywall)
    }

    func testTheSharedLinkPointsAtTheInvitePath() {
        let base = URL(string: "https://api-production-9f35a.up.railway.app")!
        XCTAssertEqual(
            InviteLink.url(code: "JHKFDA", base: base)?.absoluteString,
            "https://api-production-9f35a.up.railway.app/j/JHKFDA"
        )
        XCTAssertNil(InviteLink.url(code: "JHKFDA", base: nil))
    }
}
