import XCTest

@testable import MemoBookCore

/**
 **Comment une bulle range ses photos** (T305, Hugo — « les photos en nombre
 impair se rangent comme sur WhatsApp : toute la largeur de la bulle occupée,
 chacune au format qu'elle a »).
 */
final class PhotoBubbleGridTests: XCTestCase {
    /// La largeur utile d'une bulle sur un iPhone courant, arrondie.
    private let width: Double = 240
    private let gap: Double = 4
    private let maximum: Double = 182

    /// **Deux par rangée**, et la dernière seule quand le compte est impair —
    /// c'est elle qui prendra toute la largeur, au lieu du trou d'avant.
    func testRowsGoTwoByTwoAndTheLastOneMayBeAlone() {
        XCTAssertEqual(PhotoBubbleGrid.rows(of: 0), [])
        XCTAssertEqual(PhotoBubbleGrid.rows(of: 1), [0..<1])
        XCTAssertEqual(PhotoBubbleGrid.rows(of: 2), [0..<2])
        XCTAssertEqual(PhotoBubbleGrid.rows(of: 3), [0..<2, 2..<3])
        XCTAssertEqual(PhotoBubbleGrid.rows(of: 6), [0..<2, 2..<4, 4..<6])
    }

    /// **Deux carrés remplissent la largeur** : la hauteur est la moitié de ce
    /// qui reste une fois l'espace retiré.
    func testTwoSquaresShareTheWidth() {
        let height = PhotoBubbleGrid.rowHeight(aspects: [1, 1], width: width, spacing: gap, maximum: maximum)
        XCTAssertEqual(height, (width - gap) / 2, accuracy: 0.001)

        let widths = PhotoBubbleGrid.widths(aspects: [1, 1], height: height, width: width, spacing: gap)
        XCTAssertEqual(widths.reduce(0, +) + gap, width, accuracy: 0.001, "La rangée remplit la bulle.")
    }

    /// **Chacune à son format** : une paysage prend plus de place qu'une
    /// portrait, et les deux ont la même hauteur.
    func testALandscapeAndAPortraitShareTheirHeightNotTheirWidth() {
        let aspects = [16.0 / 9, 3.0 / 4]
        let height = PhotoBubbleGrid.rowHeight(aspects: aspects, width: width, spacing: gap, maximum: maximum)
        let widths = PhotoBubbleGrid.widths(aspects: aspects, height: height, width: width, spacing: gap)

        XCTAssertEqual(widths.reduce(0, +) + gap, width, accuracy: 0.001)
        XCTAssertGreaterThan(widths[0], widths[1], "La paysage est la plus large.")
        XCTAssertEqual(widths[0] / height, 16.0 / 9, accuracy: 0.01, "Et elle garde son format.")
    }

    /// **Une photo seule prend toute la largeur** — c'est la place que le trou
    /// occupait.
    func testASinglePhotoTakesTheWholeWidth() {
        let widths = PhotoBubbleGrid.widths(aspects: [1.5], height: 100, width: width, spacing: gap)
        XCTAssertEqual(widths, [width], "Rien à côté d'elle : elle prend tout.")
    }

    /// ⚠️ **Mais pas toute la hauteur** : une portrait seule mangerait l'écran.
    func testATallPhotoIsCapped() {
        let height = PhotoBubbleGrid.rowHeight(aspects: [0.5], width: width, spacing: gap, maximum: maximum)
        XCTAssertEqual(height, maximum, "La hauteur s'arrête au plafond de la bulle.")
    }

    /// **Une photo sans mesure compte pour un carré** : un serveur d'avant, ou
    /// un format que le serveur n'a pas su lire, range comme avant T305.
    func testAPhotoWithoutAMeasureCountsAsASquare() {
        let known = PhotoBubbleGrid.rowHeight(aspects: [1, 1], width: width, spacing: gap, maximum: maximum)
        let unknown = PhotoBubbleGrid.rowHeight(aspects: [0, 1], width: width, spacing: gap, maximum: maximum)
        XCTAssertEqual(known, unknown, accuracy: 0.001)
    }

    /// Le rapport d'une photo se lit sur ses pixels, et se tait sans eux.
    func testAnAttachmentKnowsItsAspectOnlyWhenMeasured() {
        XCTAssertEqual(PhotoAttachment(id: "a", widthPx: 4000, heightPx: 3000).aspect ?? 0, 4.0 / 3, accuracy: 0.001)
        XCTAssertNil(PhotoAttachment(id: "b").aspect)
        XCTAssertNil(PhotoAttachment(id: "c", widthPx: 0, heightPx: 3000).aspect)
    }
}
