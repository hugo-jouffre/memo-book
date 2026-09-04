import XCTest

@testable import MemoBookCore

/// Ce que l'accueil déduit de ses données. Trois règles s'y jouent : le drapeau
/// se dérive du code pays plutôt que d'être stocké, les voyages se rangent
/// d'après leur étape et non d'après l'ordre reçu, et un état inconnu du
/// serveur ne fait disparaître personne de l'écran.
final class TripTests: XCTestCase {

    // MARK: - Drapeau

    func testCountryCodeGivesTheFlag() {
        XCTAssertEqual(Destination(name: "Italie", countryCode: "IT").flag, "🇮🇹")
        XCTAssertEqual(Destination(name: "Philippines", countryCode: "PH").flag, "🇵🇭")
    }

    func testCountryCodeIsReadWhateverItsCase() {
        XCTAssertEqual(Destination(name: "Portugal", countryCode: "pt").flag, "🇵🇹")
    }

    func testWithoutACodeThereIsNoFlag() {
        XCTAssertNil(Destination(name: "Nulle part").flag)
    }

    /// Un code mal formé doit donner *rien*, jamais un carré blanc ou une
    /// lettre isolée : c'est ce que produirait un décalage Unicode aveugle.
    func testMalformedCodesGiveNothing() {
        for code in ["F", "FRA", "F1", "??", "", "é!"] {
            XCTAssertNil(
                Destination(name: "Test", countryCode: code).flag,
                "le code « \(code) » ne devrait pas produire de drapeau"
            )
        }
    }

    // MARK: - Initiales

    func testInitialsTakeAtMostTwoWords() {
        XCTAssertEqual(Companion(id: "1", name: "Claire Nguyen").initials, "CN")
        XCTAssertEqual(Companion(id: "1", name: "gus").initials, "G")
        XCTAssertEqual(Companion(id: "1", name: "Jean Michel Dupont").initials, "JM")
        XCTAssertEqual(Companion(id: "1", name: "").initials, "")
    }

    // MARK: - Rangement

    func testOngoingTripsComeFirstMostRecentlyStarted() {
        let feed = makeFeed([
            trip("ancien", .ongoing, start: day(-30)),
            trip("récent", .ongoing, start: day(-2)),
            trip("fini", .past, start: day(-90), end: day(-80)),
        ])

        XCTAssertEqual(feed.ongoingTrips.map(\.id), ["récent", "ancien"])
        XCTAssertEqual(feed.pastTrips.map(\.id), ["fini"])
    }

    /// Parti en premier, rentré en dernier : c'est le retour qui décide de la
    /// place dans « Tes voyages précédents ».
    func testPastTripsAreSortedOnTheirEndNotTheirStart() {
        let feed = makeFeed([
            trip("long", .past, start: day(-100), end: day(-10)),
            trip("court", .past, start: day(-60), end: day(-55)),
        ])

        XCTAssertEqual(feed.pastTrips.map(\.id), ["long", "court"])
    }

    func testAnUnknownStageStaysVisibleWithTheOngoingTrips() {
        let feed = makeFeed([trip("futur", .unknown("upcoming"), start: day(10))])

        XCTAssertEqual(feed.ongoingTrips.map(\.id), ["futur"])
        XCTAssertTrue(feed.pastTrips.isEmpty)
    }

    func testATripWithoutDatesIsStillListed() {
        let feed = makeFeed([
            trip("sans date", .ongoing, start: nil),
            trip("daté", .ongoing, start: day(-1)),
        ])

        XCTAssertEqual(feed.ongoingTrips.count, 2)
        XCTAssertEqual(feed.ongoingTrips.first?.id, "daté")
    }

    // MARK: - Décodage de l'étape

    func testKnownStagesRoundTrip() throws {
        for stage in [TripStage.ongoing, .past] {
            let data = try JSONEncoder().encode(stage)
            XCTAssertEqual(try JSONDecoder().decode(TripStage.self, from: data), stage)
        }
    }

    /// Même raison que `Status.unknown` : une étape ajoutée côté serveur ne
    /// doit pas faire échouer le décodage d'une app déjà installée.
    func testAStageAddedByTheServerDecodesAsUnknown() throws {
        let data = Data(#""upcoming""#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(TripStage.self, from: data), .unknown("upcoming"))
    }

    // MARK: - Fabriques

    private func makeFeed(_ trips: [Trip]) -> HomeFeed {
        HomeFeed(traveller: Traveller(id: "t", firstName: "Camille"), trips: trips)
    }

    private func trip(_ id: String, _ stage: TripStage, start: Date?, end: Date? = nil) -> Trip {
        Trip(id: id, title: id, stage: stage, startDate: start, endDate: end)
    }

    /// Une date fixe décalée de `offset` jours : les tests ne doivent pas
    /// dépendre du moment où on les lance.
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(Double(offset) * 86_400)
    }
}
