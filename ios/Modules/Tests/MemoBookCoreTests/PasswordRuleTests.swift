import XCTest

@testable import MemoBookCore

final class PasswordRuleTests: XCTestCase {
    func testAcceptsEightCharactersWithALetterAndADigit() {
        XCTAssertTrue(PasswordRule.isValid("carnet2026"))
        XCTAssertTrue(PasswordRule.isValid("a1234567"))
    }

    func testRefusesWhatTheServerRefuses() {
        XCTAssertFalse(PasswordRule.isValid("court1"), "moins de 8 caractères")
        XCTAssertFalse(PasswordRule.isValid("12345678"), "aucune lettre")
        XCTAssertFalse(PasswordRule.isValid("motdepasse"), "aucun chiffre")
        XCTAssertFalse(PasswordRule.isValid(""))
    }
}
