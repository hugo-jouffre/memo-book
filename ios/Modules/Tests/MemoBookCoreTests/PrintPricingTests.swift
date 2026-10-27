import XCTest

@testable import MemoBookCore

/// La grille des prix telle que l'app la lit — voir ``PrintPricing``.
///
/// Les mêmes bornes que côté serveur (`printPricing.test.ts`), parce que les
/// deux doivent répondre pareil : l'écran annonce ce que la commande
/// facturera.
final class PrintPricingTests: XCTestCase {
    /// La grille du 21/10/2026, fermée à 300 pages.
    private let grid = PrintPricing(
        tiers: [
            .init(id: "compact", from: 16, to: 45, price: 55),
            .init(id: "standard", from: 46, to: 65, price: 75),
            .init(id: "detailed", from: 66, to: 85, price: 80),
            .init(id: "detailed-plus", from: 86, to: 100, price: 85),
            .init(id: "large", from: 101, to: 120, price: 105),
            .init(id: "large-plus", from: 121, to: 200, price: 110),
            .init(id: "very-large", from: 201, to: 300, price: 129),
        ],
        minPages: 16,
        maxPages: 300,
        tolerancePages: 5,
        freeZonesPrice: 3
    )

    // MARK: Les bornes

    func testEachTierHoldsToItsLastPage() {
        let bornes: [(Int, Decimal)] = [
            (16, 55), (45, 55),
            (46, 75), (65, 75),
            (66, 80), (85, 80),
            (86, 85), (100, 85),
            (101, 105), (120, 105),
            (121, 110), (200, 110),
            (201, 129), (300, 129),
        ]
        for (pages, price) in bornes {
            XCTAssertEqual(grid.price(forPages: pages), price, "\(pages) pages")
        }
    }

    func testUnderTheMinimumTheBookIsBilledAsSixteenPages() {
        XCTAssertEqual(grid.price(forPages: 1), 55)
        XCTAssertEqual(grid.price(forPages: 15), 55)
    }

    func testBeyondTheMaximumThereIsNoPriceToShow() {
        XCTAssertNil(grid.price(forPages: 301))
        XCTAssertNil(grid.price(forPages: 401))
        XCTAssertFalse(grid.allows(pages: 301))
        XCTAssertTrue(grid.allows(pages: 300))
        XCTAssertFalse(grid.allows(pages: 15))
    }

    func testTheOpenedLastTierPricesUpToFourHundredPages() {
        var opened = grid
        opened.tiers.append(.init(id: "beyond", from: 301, to: 400, price: 145))
        opened.maxPages = 400
        XCTAssertEqual(opened.price(forPages: 301), 145)
        XCTAssertEqual(opened.price(forPages: 400), 145)
        XCTAssertNil(opened.price(forPages: 401))
    }

    // MARK: Ce que l'écran annonce

    /// Les cas de l'onglet « Cibles » du sheet, au ratio photo de 50 % : le
    /// prix affiché est celui du palier de **cible + 5**, et il ne peut donc
    /// qu'être au-dessus de ce qui sera facturé.
    func testTheDisplayedPriceFollowsTheTargetsOfTheSheet() {
        let cas: [(Int?, Decimal, Decimal, Decimal)] = [
            (30, 55, 55, 55),
            (60, 55, 75, 80),
            (90, 75, 85, 110),
            (180, 110, 110, 129),
            (nil, 55, 75, 80),
        ]

        for (days, compact, standard, detailed) in cas {
            let attendus = [compact, standard, detailed]
            let paliers: [BookPageTarget] = [.compact, .standard, .detailed]
            for (target, attendu) in zip(paliers, attendus) {
                let pages = target.pageCount(forTripDays: days, ratio: 50)
                XCTAssertEqual(
                    pages.flatMap { grid.displayedPrice(forTarget: $0) },
                    attendu,
                    "\(String(describing: days)) jours, \(target.rawValue)"
                )
            }
        }
    }

    func testTheDisplayedPriceNeverFallsBelowWhatIsBilled() {
        // Le carnet composé tient dans sa cible à ± 5 pages : quoi qu'il
        // arrive, il se facture au plus au prix annoncé.
        for target in stride(from: 20, through: 290, by: 10) {
            guard let affiché = grid.displayedPrice(forTarget: target) else { continue }
            for composé in (target - 5)...(target + 5) {
                guard let facturé = grid.price(forPages: composé) else { continue }
                XCTAssertLessThanOrEqual(facturé, affiché, "cible \(target), composé \(composé)")
            }
        }
    }

    // MARK: Le décodage

    func testAServerThatSaysNothingLeavesTheDefaults() throws {
        let vide = try JSONDecoder().decode(PrintPricing.self, from: Data("{}".utf8))
        XCTAssertTrue(vide.tiers.isEmpty)
        XCTAssertEqual(vide.minPages, 16)
        XCTAssertEqual(vide.maxPages, 300)
        XCTAssertEqual(vide.tolerancePages, 5)
        XCTAssertNil(vide.freeZonesPrice)
        // Sans palier, aucun prix : l'écran se tait plutôt que d'inventer.
        XCTAssertNil(vide.price(forPages: 60))
    }

    func testItDecodesWhatTheRouteServes() throws {
        let json = """
            {
              "tiers": [{ "id": "compact", "from": 16, "to": 45, "price": 55 }],
              "minPages": 16,
              "maxPages": 45,
              "tolerancePages": 5,
              "freeZonesPrice": 3
            }
            """
        let servi = try JSONDecoder().decode(PrintPricing.self, from: Data(json.utf8))
        XCTAssertEqual(servi.tiers.count, 1)
        XCTAssertEqual(servi.price(forPages: 40), 55)
        XCTAssertEqual(servi.freeZonesPrice, 3)
        XCTAssertEqual(servi.tier(forPages: 40)?.id, "compact")
    }
}
