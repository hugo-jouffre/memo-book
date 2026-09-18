import XCTest

@testable import MemoBookCore

/// Le rythme du récit se relit sous sa clé — et sous les libellés que
/// l'ancien écran de création écrivait (Hugo, 18/09/2026).
final class NarrationPaceTests: XCTestCase {
    func testKeysDecodeToTheirCase() {
        XCTAssertEqual(NarrationPace(storedValue: "daily"), .daily)
        XCTAssertEqual(NarrationPace(storedValue: "every_two_days"), .everyTwoDays)
        XCTAssertEqual(NarrationPace(storedValue: "weekly"), .weekly)
        XCTAssertEqual(NarrationPace(storedValue: "custom"), .custom)
    }

    func testLegacyLabelsDecodeToTheSameCase() {
        XCTAssertEqual(NarrationPace(storedValue: "Tous les jours"), .daily)
        XCTAssertEqual(NarrationPace(storedValue: "Tous les 2 jours"), .everyTwoDays)
        XCTAssertEqual(NarrationPace(storedValue: "Toutes les semaines"), .weekly)
        XCTAssertEqual(NarrationPace(storedValue: " Une fois par semaine "), .weekly)
    }

    func testUnknownWordsKeepTheirSpelling() {
        XCTAssertEqual(NarrationPace(storedValue: "À la pleine lune"), .unknown("À la pleine lune"))
        XCTAssertEqual(NarrationPace(storedValue: "À la pleine lune").displayName, "À la pleine lune")
    }

    func testEveryProposedPaceRoundTripsThroughItsKey() {
        for pace in NarrationPace.selectable {
            XCTAssertEqual(NarrationPace(storedValue: pace.rawValue), pace)
        }
    }
}
