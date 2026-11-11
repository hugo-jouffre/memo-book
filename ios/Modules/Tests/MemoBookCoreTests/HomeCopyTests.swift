import XCTest

@testable import MemoBookCore

/// Les mots de la corbeille — le jumeau de `HomeCopyTest.kt`, cas pour cas.
///
/// Le compte à rebours est ce qu'on lit en premier sur une ligne : il doit
/// dire vrai au jour près, et se finir sur « aujourd'hui » plutôt que sur un
/// zéro.
final class HomeCopyTests: XCTestCase {
    private let jour: TimeInterval = 86_400

    func testTheCountdownSpeaksInWholeDays() {
        XCTAssertEqual(HomeCopy.Trash.erasesIn(days: 30), "S’efface dans 30 jours")
        XCTAssertEqual(HomeCopy.Trash.erasesIn(days: 2), "S’efface dans 2 jours")
        XCTAssertEqual(HomeCopy.Trash.erasesIn(days: 1), "S’efface demain")
        XCTAssertEqual(HomeCopy.Trash.erasesIn(days: 0), "S’efface aujourd’hui")
    }

    /// Une purge en retard ne compte pas à l'envers.
    func testALatePurgeNeverCountsBackwards() {
        XCTAssertEqual(HomeCopy.Trash.erasesIn(days: -3), "S’efface aujourd’hui")
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(HomeCopy.Trash.daysLeft(until: now.addingTimeInterval(-5 * jour), from: now), 0)
    }

    func testTheDaysLeftAreCountedUpwards() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        // Dans trente jours pile : trente jours.
        XCTAssertEqual(HomeCopy.Trash.daysLeft(until: now.addingTimeInterval(30 * jour), from: now), 30)
        // Une heure de plus que vingt-neuf jours : on arrondit vers le haut,
        // pour ne jamais promettre moins de temps qu'il n'en reste.
        XCTAssertEqual(
            HomeCopy.Trash.daysLeft(until: now.addingTimeInterval(29 * jour + 3_600), from: now),
            30
        )
        XCTAssertEqual(HomeCopy.Trash.daysLeft(until: now.addingTimeInterval(60), from: now), 1)
    }
}
