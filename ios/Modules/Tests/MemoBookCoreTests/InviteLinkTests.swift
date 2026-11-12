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

    /// **Le beau lien** (Hugo, 10/11/2026) : le code à la racine du domaine
    /// des invitations, sans `/j/`.
    func testTheCodeAtTheRootOfTheInviteDomainIsRead() {
        let url = URL(string: "https://join.memo-book.com/JHKFDA")!
        XCTAssertEqual(InviteLink.code(from: url), "JHKFDA")
        XCTAssertEqual(NotificationLink(url: url), .join(code: "JHKFDA"))
        // Recopié d'une dictée, avec un tiret et en minuscules.
        XCTAssertEqual(InviteLink.code(from: URL(string: "https://join.memo-book.com/jhk-fda")!), "JHKFDA")
    }

    /// ⚠️ À la racine d'un domaine, **toute page est un segment unique** :
    /// seule la forme d'un code en fait une invitation.
    func testAPageIsNotAnInvitation() {
        XCTAssertNil(InviteLink.code(from: URL(string: "https://memo-book.com/cgu")!))
        XCTAssertNil(InviteLink.code(from: URL(string: "https://memo-book.com/conditions")!))
        XCTAssertNil(InviteLink.code(from: URL(string: "https://join.memo-book.com/")!))
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
        // Sans aucune adresse — ni domaine d'invitations, ni production —, le
        // message se contente du code en clair.
        XCTAssertNil(InviteLink.url(code: "", base: base))
    }
}
