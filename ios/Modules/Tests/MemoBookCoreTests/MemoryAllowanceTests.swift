import Foundation
import XCTest

@testable import MemoBookCore

/// Les **limites de souvenirs**, côté app : la jauge, le seuil, et ce qui
/// décide de proposer d'étendre. Le barème lui-même est côté serveur — ici on
/// ne teste que ce que l'app en déduit.
final class MemoryAllowanceTests: XCTestCase {
    func testRemainingNeverGoesNegative() {
        // Un barème réétalonné entre deux périodes peut rendre un dépassement.
        // L'écran doit lire « 0 restant », pas « -40 ».
        let allowance = MemoryAllowance(used: 3_040, allowance: 3_000)
        XCTAssertEqual(allowance.remaining, 0)
        XCTAssertEqual(allowance.fraction, 1)
        XCTAssertTrue(allowance.isExhausted)
    }

    func testStaysQuietWellBelowTheThreshold() {
        // **Le point de tout le réglage** : cette limite est un garde-fou, pas
        // un levier. Quelqu'un qui en a consommé un dixième n'a rien à décider,
        // et la jauge ne doit pas apparaître.
        let allowance = MemoryAllowance(used: 312, allowance: 3_000)
        XCTAssertFalse(allowance.isRunningLow)
        XCTAssertFalse(allowance.isExhausted)
    }

    func testWarnsAtFourFifths() {
        let allowance = MemoryAllowance(used: 2_400, allowance: 3_000)
        XCTAssertEqual(allowance.fraction, 0.8, accuracy: 0.0001)
        XCTAssertTrue(allowance.isRunningLow)
    }

    func testNeverProposesToUpgradeAnExtendedPlan() {
        // Il n'y a pas de troisième palier : quelqu'un qui a déjà étendu et qui
        // approche de sa limite n'a rien à acheter de plus, et lui proposer
        // quand même serait une impasse.
        let allowance = MemoryAllowance(plan: .extended, used: 11_900, allowance: 12_000)
        XCTAssertFalse(allowance.isRunningLow)
        XCTAssertTrue(allowance.fraction > MemoryAllowance.warningFraction)
    }

    func testDecodesAServerThatDoesNotServeTheScaleYet() throws {
        // Un serveur plus ancien ne doit pas faire échouer tout l'écran des
        // réglages : on retombe sur les valeurs du catalogue.
        let json = Data(#"{"plan":"included","used":42}"#.utf8)
        let allowance = try JSONDecoder().decode(MemoryAllowance.self, from: json)

        XCTAssertEqual(allowance.used, 42)
        XCTAssertEqual(allowance.allowance, 3_000)
        XCTAssertEqual(allowance.textCost, 1)
        XCTAssertEqual(allowance.voiceCostPerMinute, 10)
        XCTAssertEqual(allowance.upgradeMonthlyPrice, 3.99)
    }

    func testZeroAllowanceDoesNotDivideByZero() {
        let allowance = MemoryAllowance(used: 10, allowance: 0)
        XCTAssertEqual(allowance.fraction, 0)
        XCTAssertEqual(allowance.remaining, 0)
    }
}
