import XCTest

@testable import MemoBookCore

/// Ce que le profil déduit de ses données. Quatre règles s'y jouent : une
/// adresse ne vaut que complète, elle se résume sans virgule orpheline, une
/// carte ne montre jamais que ses quatre derniers chiffres, et la ligne « carte
/// enregistrée » ne reste pas vide faute de choix explicite.
final class ProfileTests: XCTestCase {

    // MARK: - Adresse

    func testACompleteAddressIsComplete() {
        let address = PostalAddress(
            street: "7 Rue Simon Fryd",
            postalCode: "69007",
            city: "Lyon",
            country: "France"
        )
        XCTAssertTrue(address.isComplete)
    }

    /// Un champ rempli d'espaces n'est pas un champ rempli : c'est le cas que
    /// produit un clavier tactile, et il ne doit pas laisser partir un colis.
    func testABlankFieldMakesTheAddressIncomplete() {
        var address = PostalAddress(
            street: "7 Rue Simon Fryd",
            postalCode: "69007",
            city: "Lyon",
            country: "France"
        )
        address.city = "   "
        XCTAssertFalse(address.isComplete)

        XCTAssertFalse(PostalAddress().isComplete)
    }

    func testTheSingleLineJoinsWhatItHas() {
        let address = PostalAddress(
            street: "7 Rue Simon Fryd",
            postalCode: "69007",
            city: "Lyon",
            country: "France"
        )
        XCTAssertEqual(address.singleLine, "7 Rue Simon Fryd, Lyon, France")
    }

    /// Une adresse à moitié saisie se lit quand même, sans virgule en trop.
    func testTheSingleLineSkipsEmptyFields() {
        let address = PostalAddress(street: "7 Rue Simon Fryd", city: "Lyon")
        XCTAssertEqual(address.singleLine, "7 Rue Simon Fryd, Lyon")
        XCTAssertEqual(PostalAddress().singleLine, "")
    }

    // MARK: - Carte

    func testACardOnlyEverShowsItsLastFourDigits() {
        let card = PaymentCard(id: "1", label: "Carte perso", last4: "1820")
        XCTAssertEqual(card.maskedNumber, "XXXX XXXX XXXX 1820")
    }

    // MARK: - Profil

    /// Sans choix explicite, c'est la première carte qui s'affiche : la ligne du
    /// profil ne doit pas rester vide parce que personne n'a encore tranché.
    func testTheSelectedCardFallsBackToTheFirstOne() {
        let cards = [
            PaymentCard(id: "a", label: "Carte business", last4: "3246"),
            PaymentCard(id: "b", label: "Carte perso", last4: "1820"),
        ]

        let chosen = TravellerProfile(fullName: "Maylis Garde", cards: cards, selectedCardId: "b")
        XCTAssertEqual(chosen.selectedCard?.id, "b")

        let unchosen = TravellerProfile(fullName: "Maylis Garde", cards: cards)
        XCTAssertEqual(unchosen.selectedCard?.id, "a")

        XCTAssertNil(TravellerProfile(fullName: "Maylis Garde").selectedCard)
    }

    func testInitialsTakeAtMostTwoWords() {
        XCTAssertEqual(TravellerProfile(fullName: "Maylis Garde").initials, "MG")
        XCTAssertEqual(TravellerProfile(fullName: "maylis").initials, "M")
        XCTAssertEqual(TravellerProfile(fullName: "Anne Marie Le Goff").initials, "AM")
        XCTAssertEqual(TravellerProfile(fullName: "").initials, "")
    }
}
