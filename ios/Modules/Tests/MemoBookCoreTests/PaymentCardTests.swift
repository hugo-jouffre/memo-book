import XCTest

@testable import MemoBookCore

/// La date d'expiration se compose toute seule : le champ n'accepte que des
/// chiffres et pose la barre à la place de celui qui tape.
final class PaymentCardExpiryTests: XCTestCase {

    func testTheFirstTwoDigitsStayBare() {
        XCTAssertEqual(PaymentCard.formattedExpiry(""), "")
        XCTAssertEqual(PaymentCard.formattedExpiry("1"), "1")
        XCTAssertEqual(PaymentCard.formattedExpiry("12"), "12")
    }

    func testTheSlashAppearsOnTheThirdDigit() {
        XCTAssertEqual(PaymentCard.formattedExpiry("122"), "12/2")
        XCTAssertEqual(PaymentCard.formattedExpiry("1228"), "12/28")
    }

    /// La fonction est rappelée sur sa propre sortie à chaque frappe : elle ne
    /// doit donc rien ajouter à ce qu'elle a déjà écrit.
    func testAnAlreadyFormattedValueDoesNotDouble() {
        XCTAssertEqual(PaymentCard.formattedExpiry("12/28"), "12/28")
        XCTAssertEqual(PaymentCard.formattedExpiry(PaymentCard.formattedExpiry("1228")), "12/28")
    }

    /// Le cas qui justifie la fonction : effacer le troisième chiffre emporte
    /// la barre, sinon il faut un second retour arrière sur un caractère qu'on
    /// n'a jamais tapé.
    func testDeletingADigitTakesTheSlashWithIt() {
        XCTAssertEqual(PaymentCard.formattedExpiry("12/"), "12")
        XCTAssertEqual(PaymentCard.formattedExpiry("1"), "1")
    }

    func testEverythingButDigitsIsDroppedAndItStopsAtFour() {
        XCTAssertEqual(PaymentCard.formattedExpiry("1-2/3"), "12/3")
        XCTAssertEqual(PaymentCard.formattedExpiry("ab12cd28ef"), "12/28")
        XCTAssertEqual(PaymentCard.formattedExpiry("122899"), "12/28")
    }
}
