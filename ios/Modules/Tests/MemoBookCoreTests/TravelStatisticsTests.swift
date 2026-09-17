import XCTest

@testable import MemoBookCore

/// Ce que la feuille « Statistiques » déduit de ce que le serveur rend : la
/// part du voyage écrite, l'accord d'un moyen de transport, et un décodage qui
/// survit à un serveur plus ancien ou à un transport que l'app ne connaît pas.
final class TravelStatisticsTests: XCTestCase {
    private let decoder = JSONDecoder.memoBook

    // MARK: - Ce qui se déduit

    func testWrittenFractionIsValidatedDaysOverDayCount() {
        let trip = CurrentTripStatistics(id: "t", dayCount: 21, validatedDays: 2)
        XCTAssertEqual(trip.writtenFraction, 2.0 / 21.0, accuracy: 0.0001)
    }

    /// Un pourcentage d'une durée inconnue ne veut rien dire : zéro, et pas une
    /// division par zéro.
    func testWrittenFractionIsZeroWithoutDayCount() {
        XCTAssertEqual(CurrentTripStatistics(id: "t", dayCount: 0, validatedDays: 3).writtenFraction, 0)
    }

    /// Plus de jours validés que de jours de voyage — un voyage prolongé sans
    /// que la fiche le sache — reste à 100 %, pas au-delà.
    func testWrittenFractionIsCapped() {
        XCTAssertEqual(CurrentTripStatistics(id: "t", dayCount: 3, validatedDays: 5).writtenFraction, 1)
    }

    func testTransportLabelsAgreeWithTheirCount() {
        XCTAssertEqual(TransportUsage(kind: .plane, count: 1).label, "1 avion")
        XCTAssertEqual(TransportUsage(kind: .train, count: 2).label, "2 trains")
        XCTAssertEqual(TransportUsage(kind: .boat, count: 3).label, "3 bateaux")
        // Sans nombre relevé, le mot seul — « scooter », comme la maquette.
        XCTAssertEqual(TransportUsage(kind: .scooter).label, "scooter")
        // La marche ne se compte jamais.
        XCTAssertEqual(TransportUsage(kind: .walk, count: 4).label, "à pied")
    }

    /// Deux lectures à quelques secondes d'écart ne diffèrent que par leur
    /// horodatage : la feuille ne doit pas les prendre pour un changement.
    func testSameFiguresIgnoreTheTimestamp() {
        var first = TravelStatistics.sample
        var second = first
        second.updatedAt = Date(timeIntervalSince1970: 10)
        XCTAssertTrue(first.hasSameFigures(as: second))

        first.overall.cities += 1
        XCTAssertFalse(first.hasSameFigures(as: second))
    }

    // MARK: - Décodage

    func testDecodesTheServerShape() throws {
        let json = Data(
            """
            {
              "tripCount": 3,
              "overall": { "countries": 3, "regions": 1, "cities": 4, "encounters": 6, "distanceKilometres": 129 },
              "currentTrip": {
                "id": "rome",
                "startDate": "2026-08-26T00:00:00.000Z",
                "endDate": "2026-09-15T00:00:00.000Z",
                "currentPlace": "Rome",
                "dayCount": 13,
                "validatedDays": 2,
                "figures": { "countries": 1, "regions": 1, "cities": 2, "encounters": 6, "distanceKilometres": 87 },
                "recordings": 4,
                "transports": [{ "kind": "train", "count": 2 }, { "kind": "scooter", "count": null }]
              },
              "pendingDetections": 1,
              "updatedAt": "2026-09-17T14:11:19.003Z"
            }
            """.utf8
        )

        let statistics = try decoder.decode(TravelStatistics.self, from: json)

        XCTAssertEqual(statistics.tripCount, 3)
        XCTAssertEqual(statistics.overall.distanceKilometres, 129)
        XCTAssertTrue(statistics.isDetecting)
        let trip = try XCTUnwrap(statistics.currentTrip)
        XCTAssertEqual(trip.currentPlace, "Rome")
        XCTAssertEqual(trip.transports, [
            TransportUsage(kind: .train, count: 2),
            TransportUsage(kind: .scooter, count: nil),
        ])
    }

    /// Un moyen de transport que cette version ne connaît pas est sauté, pas
    /// fatal : l'agent peut apprendre un mot avant l'app.
    func testSkipsUnknownTransportsInsteadOfFailing() throws {
        let json = Data(
            """
            {
              "tripCount": 1,
              "overall": { "countries": 1, "regions": 0, "cities": 1, "encounters": 0, "distanceKilometres": 0 },
              "currentTrip": {
                "id": "rome",
                "transports": [{ "kind": "helicopter", "count": 1 }, { "kind": "bus", "count": 1 }]
              },
              "pendingDetections": 0
            }
            """.utf8
        )

        let statistics = try decoder.decode(TravelStatistics.self, from: json)
        XCTAssertEqual(statistics.currentTrip?.transports, [TransportUsage(kind: .bus, count: 1)])
        // Les champs que ce serveur ne sert pas tombent sur leur zéro.
        XCTAssertEqual(statistics.currentTrip?.dayCount, 0)
        XCTAssertEqual(statistics.currentTrip?.figures, .empty)
    }

    /// Un serveur plus ancien, qui ne connaît pas encore la route, rend un
    /// objet vide : la feuille s'ouvre quand même, à zéro.
    func testDecodesAnEmptyObject() throws {
        let statistics = try decoder.decode(TravelStatistics.self, from: Data("{}".utf8))
        XCTAssertEqual(statistics.tripCount, 0)
        XCTAssertNil(statistics.currentTrip)
        XCTAssertFalse(statistics.isDetecting)
    }
}

private extension TravelStatistics {
    static let sample = TravelStatistics(
        tripCount: 2,
        overall: TravelFigures(countries: 2, regions: 1, cities: 3, encounters: 4, distanceKilometres: 120),
        currentTrip: CurrentTripStatistics(id: "rome", dayCount: 10, validatedDays: 1),
        pendingDetections: 0,
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}
