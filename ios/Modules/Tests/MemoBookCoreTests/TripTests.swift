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
        // « upcoming » a été un état inconnu jusqu'à ce qu'il devienne un vrai
        // cas : c'est justement ce que ce test protège, un serveur qui prend de
        // l'avance sur l'app.
        let data = Data(#""cancelled""#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(TripStage.self, from: data), .unknown("cancelled"))
    }

    func testTheThreeKnownStagesDecodeAsThemselves() throws {
        let decoder = JSONDecoder()

        XCTAssertEqual(try decoder.decode(TripStage.self, from: Data(#""upcoming""#.utf8)), .upcoming)
        XCTAssertEqual(try decoder.decode(TripStage.self, from: Data(#""ongoing""#.utf8)), .ongoing)
        XCTAssertEqual(try decoder.decode(TripStage.self, from: Data(#""past""#.utf8)), .past)
    }

    /// Un voyage à venir n'est **pas** un voyage en cours : il n'a rien à
    /// raconter, et il ne doit donc pas remonter dans la section du haut.
    func testAnUpcomingTripIsNeitherOngoingNorPast() {
        let feed = makeFeed([
            trip("à-venir", .upcoming, start: day(30)),
            trip("en-cours", .ongoing, start: day(-2)),
            trip("passé", .past, start: day(-60), end: day(-50)),
        ])

        XCTAssertEqual(feed.upcomingTrips.map(\.id), ["à-venir"])
        XCTAssertEqual(feed.ongoingTrips.map(\.id), ["en-cours"])
        XCTAssertEqual(feed.pastTrips.map(\.id), ["passé"])
    }

    // MARK: - Avancement

    func testProgressIsBoundedAtBothEnds() {
        XCTAssertEqual(TripProgress(memoryCount: 0, pageCount: 0, targetPageCount: 80).fraction, 0)
        XCTAssertEqual(TripProgress(memoryCount: 9, pageCount: 40, targetPageCount: 80).fraction, 0.5)

        // Un carnet qui dépasse sa cible ne fait pas déborder sa barre.
        XCTAssertEqual(TripProgress(memoryCount: 9, pageCount: 120, targetPageCount: 80).fraction, 1)

        // Et une cible absente ne divise pas par zéro.
        XCTAssertEqual(TripProgress(memoryCount: 9, pageCount: 12, targetPageCount: 0).fraction, 0)
    }

    // MARK: - Le crédit du jour (Hugo, 03/10/2026)

    /// Le serveur sert le crédit sur chaque voyage **en cours** de l'accueil :
    /// c'est celui que vise le vocal de l'accueil.
    func testAnOngoingTripCarriesItsDailyCredit() throws {
        let json = #"""
        {
          "id": "rome", "title": "Rome", "stage": "ongoing",
          "stats": { "dayCount": 3, "distanceKilometres": 0, "photoCount": 0 },
          "companions": [], "isPrintable": false,
          "dailyCredit": { "isUnlimited": false, "limitMs": 300000, "usedMs": 270000, "remainingMs": 30000,
                           "textMsPerCharacter": 75, "warningRemainingMs": 30000, "urgentRemainingMs": 5000,
                           "day": "2026-10-03", "resetsAt": "2026-10-03T22:00:00.000Z" }
        }
        """#
        let trip = try JSONDecoder.memoBook.decode(Trip.self, from: Data(json.utf8))
        XCTAssertEqual(trip.dailyCredit?.remainingMs, 30_000)
        XCTAssertEqual(trip.dailyCredit?.phase, .warning)
    }

    /// Un voyage passé, ou un serveur d'avant le crédit : pas de crédit, et le
    /// voyage se décode comme avant.
    func testATripWithoutCreditStillDecodes() throws {
        let json = #"""
        {
          "id": "rome", "title": "Rome", "stage": "past",
          "stats": { "dayCount": 3, "distanceKilometres": 0, "photoCount": 0 },
          "companions": [], "isPrintable": true
        }
        """#
        let trip = try JSONDecoder.memoBook.decode(Trip.self, from: Data(json.utf8))
        XCTAssertNil(trip.dailyCredit)
        // Ni `canDelete` : la croix reste montrée, et c'est le serveur qui
        // refusera (T233).
        XCTAssertTrue(trip.isDeletable)
    }

    /// T233 : un co-voyageur ne voit pas « Supprimer le voyage ».
    func testACompanionsTripIsNotDeletable() throws {
        let json = #"""
        {
          "id": "rome", "title": "Rome", "stage": "past",
          "stats": { "dayCount": 3, "distanceKilometres": 0, "photoCount": 0 },
          "companions": [], "isPrintable": true, "canDelete": false
        }
        """#
        let trip = try JSONDecoder.memoBook.decode(Trip.self, from: Data(json.utf8))
        XCTAssertFalse(trip.isDeletable)
        // Un voyage créé hors ligne appartient à son créateur.
        XCTAssertTrue(Trip.local(TripDraft(title: "Lisbonne"), id: "l").isDeletable)
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
