import XCTest

@testable import MemoBookCore

/// Ce que le profil déduit de ses données. Cinq règles s'y jouent : une
/// adresse ne vaut que complète — et sait dire ce qui lui manque —, elle se
/// résume sans virgule orpheline et avec le pays en toutes lettres, une carte
/// ne montre jamais que ses quatre derniers chiffres, et la ligne « carte
/// enregistrée » ne reste pas vide faute de choix explicite.
final class ProfileTests: XCTestCase {
    private let decoder = JSONDecoder.memoBook

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

    /// Le pays est un code, mais la ligne l'écrit en toutes lettres : « FR »
    /// en bout d'adresse se lirait comme une coquille.
    func testTheSingleLineWritesTheCountryName() {
        let address = PostalAddress(
            street: "7 Rue Simon Fryd",
            postalCode: "69007",
            city: "Lyon",
            country: "FR",
            countryName: "France"
        )
        XCTAssertEqual(address.singleLine, "7 Rue Simon Fryd, Lyon, France")
    }

    /// « Valider » nomme ce qui manque, dans l'ordre des champs et en une
    /// phrase qui se lit.
    func testTheAddressNamesWhatIsMissing() {
        XCTAssertNil(
            PostalAddress(street: "7 Rue", postalCode: "69007", city: "Lyon", country: "FR")
                .missingFieldsDescription
        )
        XCTAssertEqual(
            PostalAddress(street: "7 Rue", city: "Lyon", country: "FR").missingFieldsDescription,
            "le code postal"
        )
        XCTAssertEqual(
            PostalAddress(street: "7 Rue", country: "FR").missingFieldsDescription,
            "le code postal et la ville"
        )
        XCTAssertEqual(
            PostalAddress().missingFieldsDescription,
            "l’adresse, le code postal, la ville et le pays"
        )
        XCTAssertEqual(PostalAddress(street: "  ").missingFields.first, .street)
    }

    /// Un serveur d'avant la liste des pays n'envoie ni `countryName` ni
    /// `shippingCountries` : le profil se décode quand même, et le code tient
    /// lieu de nom.
    func testTheProfileDecodesWithoutTheCountryList() throws {
        let json = Data(
            """
            {
              "fullName": "Maylis Garde",
              "address": { "street": "7 Rue", "postalCode": "69007", "city": "Lyon", "country": "France" },
              "wantsNewsletter": false,
              "walletBalance": 0,
              "cards": [],
              "connectors": [],
              "subscription": { "weeklyPrice": 1.99, "isActive": false, "cancelledAt": null, "paidThrough": null, "hasEndedBefore": false },
              "orders": []
            }
            """.utf8
        )

        let profile = try decoder.decode(TravellerProfile.self, from: json)

        XCTAssertEqual(profile.address.countryName, "France")
        XCTAssertEqual(profile.address.singleLine, "7 Rue, Lyon, France")
        XCTAssertEqual(profile.shippingCountries, [])
        XCTAssertNil(profile.shippingCountry(code: "FR"))
    }

    /// Ce que le serveur envoie aujourd'hui : le code, le nom dérivé, et la
    /// liste dans laquelle le choisir.
    func testTheProfileReadsTheCountryList() throws {
        let json = Data(
            """
            {
              "fullName": "Maylis Garde",
              "address": { "street": "7 Rue", "postalCode": "69007", "city": "Lyon", "country": "FR", "countryName": "France" },
              "shippingCountries": [{ "code": "FR", "name": "France" }, { "code": "BE", "name": "Belgique" }],
              "wantsNewsletter": false,
              "walletBalance": 0,
              "cards": [],
              "connectors": [],
              "subscription": { "weeklyPrice": 1.99, "isActive": false, "cancelledAt": null, "paidThrough": null, "hasEndedBefore": false },
              "orders": []
            }
            """.utf8
        )

        let profile = try decoder.decode(TravellerProfile.self, from: json)

        XCTAssertEqual(profile.address.country, "FR")
        XCTAssertEqual(profile.address.singleLine, "7 Rue, Lyon, France")
        XCTAssertEqual(profile.shippingCountry(code: "BE")?.name, "Belgique")
        XCTAssertNil(profile.shippingCountry(code: "MC"))
    }

    /// La liste reconnaît un code comme un nom, sans tenir compte de la casse
    /// ni des accents : c'est ce qui ramène une adresse d'avant la liste sur
    /// sa ligne du menu.
    func testTheCountryListMatchesACodeOrAName() {
        let countries = [
            ShippingCountry(code: "FR", name: "France"),
            ShippingCountry(code: "US", name: "États-Unis"),
        ]

        XCTAssertEqual(countries.matching("FR")?.code, "FR")
        XCTAssertEqual(countries.matching("fr")?.code, "FR")
        XCTAssertEqual(countries.matching("FRANCE")?.code, "FR")
        XCTAssertEqual(countries.matching(" France ")?.code, "FR")
        XCTAssertEqual(countries.matching("Etats-Unis")?.code, "US")
        XCTAssertNil(countries.matching("Monaco"))
        XCTAssertNil(countries.matching(""))

        let profile = TravellerProfile(fullName: "Maylis Garde", shippingCountries: countries)
        XCTAssertEqual(profile.shippingCountry(code: "France")?.code, "FR")
    }

    /// Le cache réécrit le profil tel quel : le nom du pays doit survivre à
    /// l'aller-retour, sans quoi la ligne afficherait « FR » au réveil.
    func testTheAddressRoundTripsThroughCoding() throws {
        let address = PostalAddress(
            street: "7 Rue",
            postalCode: "69007",
            city: "Lyon",
            country: "FR",
            countryName: "France"
        )
        let data = try JSONEncoder().encode(address)
        XCTAssertEqual(try decoder.decode(PostalAddress.self, from: data), address)
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
