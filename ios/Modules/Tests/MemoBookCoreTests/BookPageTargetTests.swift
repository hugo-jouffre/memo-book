import XCTest

@testable import MemoBookCore

/// Le nombre de pages cible : les paliers, la règle des deux changements telle
/// que la route la sert, et le stade du voyage qui décide d'offrir la
/// réécriture (Hugo, 15/10/2026).
final class BookPageTargetTests: XCTestCase {
    // MARK: Les paliers

    func testWithoutDurationTheTiersAre40_60_80() {
        XCTAssertEqual(BookPageTarget.compact.pageCount(forTripDays: nil), 40)
        XCTAssertEqual(BookPageTarget.standard.pageCount(forTripDays: nil), 60)
        XCTAssertEqual(BookPageTarget.detailed.pageCount(forTripDays: nil), 80)
        XCTAssertNil(BookPageTarget.custom.pageCount(forTripDays: nil))
    }

    func testTheTiersAreTwoThirdsAndFourThirdsOfTheStandard() {
        // Deux mois : 60 pages au palier par défaut.
        XCTAssertEqual(BookPageTarget.compact.pageCount(forTripDays: 60), 40)
        XCTAssertEqual(BookPageTarget.detailed.pageCount(forTripDays: 60), 80)
        // Trois mois : 90, donc 60 et 120.
        XCTAssertEqual(BookPageTarget.compact.pageCount(forTripDays: 90), 60)
        XCTAssertEqual(BookPageTarget.standard.pageCount(forTripDays: 90), 90)
        XCTAssertEqual(BookPageTarget.detailed.pageCount(forTripDays: 90), 120)
        // Le plancher de 30 vaut pour le palier par défaut ; les deux autres
        // en sont des fractions, à la dizaine.
        XCTAssertEqual(BookPageTarget.compact.pageCount(forTripDays: 5), 20)
        XCTAssertEqual(BookPageTarget.detailed.pageCount(forTripDays: 5), 40)
    }

    func testMatchingReadsTheTierBackFromItsCount() {
        XCTAssertEqual(BookPageTarget.matching(pageCount: 40, tripDays: nil), .compact)
        XCTAssertEqual(BookPageTarget.matching(pageCount: 60, tripDays: nil), .standard)
        XCTAssertEqual(BookPageTarget.matching(pageCount: 80, tripDays: nil), .detailed)
        XCTAssertEqual(BookPageTarget.matching(pageCount: 90, tripDays: nil), .custom)
    }

    // MARK: Ce que la route sert

    func testAMissingPageTargetBlockCountsNothing() throws {
        let settings = try JSONDecoder.memoBook.decode(TripSettings.self, from: Self.settingsJSON(pageTarget: nil))
        XCTAssertNil(settings.pageTarget)
        XCTAssertEqual(settings.pageTargetAllowance, .unrestricted)
        XCTAssertFalse(settings.pageTargetAllowance.changesCount)
        XCTAssertFalse(settings.pageTargetAllowance.isExhausted)
    }

    func testThePageTargetBlockIsRead() throws {
        let json = Self.settingsJSON(
            pageTarget: #"{"changesLeft":0,"changeLimit":2,"changesCount":true,"rewriteAvailable":true}"#
        )
        let allowance = try JSONDecoder.memoBook.decode(TripSettings.self, from: json).pageTargetAllowance
        XCTAssertEqual(allowance.changesLeft, 0)
        XCTAssertTrue(allowance.changesCount)
        XCTAssertTrue(allowance.rewriteAvailable)
        XCTAssertTrue(allowance.isExhausted)
    }

    func testAPartialPageTargetBlockFallsBackFieldByField() throws {
        let json = Self.settingsJSON(pageTarget: #"{"changesLeft":1}"#)
        let allowance = try JSONDecoder.memoBook.decode(TripSettings.self, from: json).pageTargetAllowance
        XCTAssertEqual(allowance, PageTargetAllowance(changesLeft: 1))
    }

    func testNoChangeLeftBlocksOnlyOnceAChangeCounts() {
        XCTAssertFalse(PageTargetAllowance(changesLeft: 0, changesCount: false).isExhausted)
        XCTAssertTrue(PageTargetAllowance(changesLeft: 0, changesCount: true).isExhausted)
    }

    // MARK: Le stade du voyage

    func testWithoutEndDateTheStageMustBeAsked() {
        XCTAssertNil(PageTargetTripStage.from(startDate: day(1), endDate: nil, today: day(5)))
    }

    func testAFinishedTripIsAtTheEnd() {
        XCTAssertEqual(PageTargetTripStage.from(startDate: day(1), endDate: day(10), today: day(12)), .end)
    }

    func testTwoThirdsOfTheDaysElapsedIsTheEnd() {
        // 30 jours, du 1er au 30 : le 21, vingt jours entiers sont passés.
        XCTAssertEqual(PageTargetTripStage.from(startDate: day(1), endDate: day(30), today: day(21)), .end)
        XCTAssertEqual(PageTargetTripStage.from(startDate: day(1), endDate: day(30), today: day(20)), .beginningOrMiddle)
        XCTAssertEqual(PageTargetTripStage.from(startDate: day(1), endDate: day(30), today: day(1)), .beginningOrMiddle)
    }

    func testATripNotStartedYetIsAtTheBeginning() {
        XCTAssertEqual(PageTargetTripStage.from(startDate: day(10), endDate: day(20), today: day(2)), .beginningOrMiddle)
    }

    // MARK: Les phrases de la feuille

    func testTheSummaryNamesBothStoriesAndTheDirection() {
        XCTAssertEqual(
            BookCopy.Pages.doneSummary(from: 40, to: 80, tripDays: nil),
            "On passe d’un récit compact à un récit détaillé. Les prochaines étapes seront donc plus étoffées."
        )
        XCTAssertEqual(
            BookCopy.Pages.doneSummary(from: 60, to: 90, tripDays: nil),
            "On passe d’un récit standard de 60 pages à un récit de 90 pages. Les prochaines étapes seront donc plus étoffées."
        )
        XCTAssertTrue(BookCopy.Pages.doneSummary(from: 80, to: 40, tripDays: nil).hasSuffix("moins étoffées."))
    }

    func testTheWarningSaysWhatIsLeft() {
        XCTAssertTrue(BookCopy.Pages.changeWarning(changesLeft: 2).contains("deux fois"))
        XCTAssertTrue(BookCopy.Pages.changeWarning(changesLeft: 1).contains("un seul changement"))
    }

    // MARK: Outils

    private func day(_ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12)) ?? .now
    }

    private static func settingsJSON(pageTarget: String?) -> Data {
        let block = pageTarget.map { #","pageTarget":\#($0)"# } ?? ""
        return Data(
            """
            {"tripId":"t1","name":"Rome","wantsNotifications":true,"notifications":{},\
            "companions":[],"isPublicGallery":false,"isPrintable":false\(block)}
            """.utf8
        )
    }

    func testACustomTargetNamesBothSidesWithTheirPageCount() {
        // Trois semaines : « Détaillé » vaut 40 pages. Partir de 60 pour y
        // aller, c'est condenser — le nom seul disait le contraire.
        XCTAssertEqual(
            BookCopy.Pages.doneSummary(from: 60, to: 40, tripDays: 21),
            "On passe d’un récit de 60 pages à un récit détaillé de 40 pages. Les prochaines étapes seront donc moins étoffées."
        )
    }

    // MARK: Les paliers suivent le ratio, la cible hors d'atteinte (18/10/2026)

    func testTheTiersFollowThePhotoRatio() {
        XCTAssertEqual(BookPageTarget.standard.pageCount(forTripDays: nil, ratio: 0), 40)
        XCTAssertEqual(BookPageTarget.standard.pageCount(forTripDays: nil, ratio: 50), 60)
        XCTAssertEqual(BookPageTarget.standard.pageCount(forTripDays: nil, ratio: 100), 80)
        XCTAssertEqual(BookPageTarget.detailed.pageCount(forTripDays: 40, ratio: 75), 70)
        XCTAssertEqual(BookPageTarget.matching(pageCount: 50, tripDays: 40, ratio: 75), .standard)
    }

    func testAnUnreachableTargetSaysWhatTheBookCanDo() {
        let allowance = PageTargetAllowance(reachableByRatio: [
            25: PageRange(min: 24, max: 34),
            50: PageRange(min: 24, max: 44),
            75: PageRange(min: 24, max: 64),
        ])
        XCTAssertNil(allowance.reach(of: 38, ratio: 25), "à 5 pages de la fourchette, la cible passe")
        let reach = allowance.reach(of: 60, ratio: 25)
        XCTAssertEqual(reach?.range, PageRange(min: 24, max: 34))
        XCTAssertEqual(reach?.closestTarget, 30)
        XCTAssertEqual(reach?.ratioThatReaches, 75)
        XCTAssertTrue(reach?.isTooLong == true)
        XCTAssertNil(PageTargetAllowance().reach(of: 180, ratio: 50), "sans fourchette servie, rien n'est jugé")
    }

    func testTheReachableRangeDecodesFromTheServer() throws {
        let json = #"{"changesLeft":2,"changeLimit":2,"changesCount":true,"rewriteAvailable":false,"reachableByRatio":{"0":{"min":24,"max":24},"50":{"min":24,"max":44}}}"#
        let allowance = try JSONDecoder().decode(PageTargetAllowance.self, from: Data(json.utf8))
        XCTAssertEqual(allowance.reachableByRatio[50], PageRange(min: 24, max: 44))
        XCTAssertEqual(allowance.reachableByRatio.count, 2)
    }
}
