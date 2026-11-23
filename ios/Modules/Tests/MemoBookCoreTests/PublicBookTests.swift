import XCTest

@testable import MemoBookCore

/// Ce qu'un carnet de la communauté décide tout seul : quel drapeau il porte,
/// quelles étapes valent d'être déroulées, et ce qu'il fait d'un transport que
/// cette version de l'app ne connaît pas.
///
/// Les trois se cassent en silence. La dernière surtout : un huitième transport
/// ajouté côté serveur ne doit pas faire cesser de décoder **tout l'écran**.
final class PublicBookTests: XCTestCase {
    private func step(
        _ id: String = "s1",
        number: Int = 1,
        place: String? = "Paros",
        countryCode: String? = "GR",
        transport: String? = nil,
        story: [String] = [],
        photoUrls: [URL] = []
    ) -> PublicBookStep {
        PublicBookStep(
            id: id,
            number: number,
            place: place,
            countryCode: countryCode,
            transport: transport,
            story: story,
            photoUrls: photoUrls
        )
    }

    private func book(
        destinations: [Destination] = [],
        steps: [PublicBookStep] = []
    ) -> PublicBook {
        PublicBook(id: "b1", title: "D'île en île", destinations: destinations, steps: steps)
    }

    // MARK: - Le transport

    func testKnownTransportIsTranslated() {
        XCTAssertEqual(step(transport: "boat").mode, .boat)
        XCTAssertEqual(step(transport: "walk").mode?.displayName, "À pied")
    }

    func testUnknownTransportIsSilentRatherThanFatal() {
        // Le cœur de l'affaire : une clé que cette version ne connaît pas donne
        // `nil` — l'écran n'en dit rien — au lieu de faire échouer le décodage.
        XCTAssertNil(step(transport: "hélicoptère").mode)
        XCTAssertNil(step(transport: nil).mode)
    }

    func testAnUnknownTransportStillDecodesTheWholeStep() throws {
        // La preuve par le décodage, et pas seulement par la traduction : c'est
        // ce qui casserait si `transport` devenait un `TripTransport`.
        let json = """
            {
              "id": "s1",
              "number": 1,
              "place": "Quelque part",
              "countryCode": null,
              "dates": null,
              "photoUrl": null,
              "transport": "funiculaire",
              "story": ["Le récit est là."],
              "photoUrls": []
            }
            """
        let decoded = try JSONDecoder().decode(PublicBookStep.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.story, ["Le récit est là."])
        XCTAssertNil(decoded.mode)
    }

    // MARK: - Les étapes qui portent quelque chose

    func testAStepWithNeitherStoryNorPhotoIsBare() {
        XCTAssertTrue(step().isBare)
        XCTAssertFalse(step(story: ["Un mot"]).isBare)
        XCTAssertFalse(step(photoUrls: [URL(string: "https://cdn.test/a.jpg")!]).isBare)
    }

    func testOnlyTellingStepsAreDeroulees() {
        // Une étape vide n'est qu'un jalon du trajet : en dérouler cinq donnerait
        // un carnet qui a l'air cassé.
        let subject = book(steps: [
            step("s1", story: ["Arrivée au port."]),
            step("s2", number: 2, place: "Naxos"),
            step("s3", number: 3, place: "Amorgos", story: ["Trois cents marches."]),
        ])

        XCTAssertEqual(subject.tellingSteps.map(\.id), ["s1", "s3"])
        XCTAssertFalse(subject.hasNothingToRead)
    }

    func testABookWhoseStepsAreAllBareHasNothingToRead() {
        // L'état d'un vrai carnet partagé le jour même : il a ses étapes, et pas
        // une ligne rédigée.
        XCTAssertTrue(book(steps: [step(), step("s2", number: 2)]).hasNothingToRead)
        XCTAssertTrue(book().hasNothingToRead)
    }

    // MARK: - Le drapeau

    func testSingleCountryCarriesItsFlag() {
        let subject = book(destinations: [Destination(name: "Grèce", countryCode: "GR")])
        XCTAssertEqual(subject.flag, "🇬🇷")
    }

    func testSeveralCountriesCarryNoFlag() {
        // Même règle que la carte dont on vient : choisir un drapeau parmi
        // quatre désignerait le premier pays comme *le* pays du carnet.
        let subject = book(destinations: [
            Destination(name: "Argentine", countryCode: "AR"),
            Destination(name: "Chili", countryCode: "CL"),
        ])
        XCTAssertNil(subject.flag)
    }

    func testAStepCarriesItsOwnCountryFlag() {
        XCTAssertEqual(step(countryCode: "GR").flag, "🇬🇷")
        XCTAssertNil(step(countryCode: nil).flag)
    }
}
