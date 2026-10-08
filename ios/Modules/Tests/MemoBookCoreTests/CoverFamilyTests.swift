import Foundation
import XCTest

@testable import MemoBookCore

/// Les sept gabarits de `assets/covers` (08/10/2026) : la paire 1ère / 4e, ce
/// que chaque plat accepte, et le repli d'un style sans famille.
final class CoverFamilyTests: XCTestCase {
    private func style(_ family: CoverFamily?, _ face: CoverFace, treatment: CoverTreatment = .framed) -> CoverStyle {
        CoverStyle(
            id: "\(face.rawValue)-\(family?.rawValue ?? "legacy")",
            name: family?.rawValue ?? "legacy",
            treatment: treatment,
            tint: .paper,
            family: family
        )
    }

    private func covers(front: CoverFamily, back: CoverFamily) -> BookCovers {
        BookCovers(
            front: BookCover(styleId: "front-\(front.rawValue)"),
            back: BookCover(styleId: "back-\(back.rawValue)"),
            frontStyles: CoverFamily.allCases.map { style($0, .front) },
            backStyles: CoverFamily.allCases.map { style($0, .back) },
            photos: [],
            stats: []
        )
    }

    /// La 4e « dessin » va avec la 1ère « dessin », et avec elle seule — même
    /// quand deux familles partagent la composition de repli.
    func testTheMatchingBackIsTheOneOfTheSameFamily() {
        let chosen = covers(front: .drawing, back: .default)
        XCTAssertTrue(chosen.isMatched(style(.drawing, .back), on: .back))
        XCTAssertFalse(chosen.isMatched(style(.elegant, .back), on: .back))
        XCTAssertFalse(chosen.isMatched(style(.travelBook, .back), on: .back))
    }

    func testEachPlateSaysWhatItAccepts() {
        let assouline = covers(front: .assouline, back: .assouline)
        XCTAssertFalse(assouline.acceptsPhoto(on: .front), "Une palme, pas de photo.")
        XCTAssertTrue(assouline.acceptsText(on: .back))
        XCTAssertTrue(assouline.acceptsStats(on: .back))

        let byDefault = covers(front: .default, back: .default)
        XCTAssertTrue(byDefault.acceptsPhoto(on: .front))
        XCTAssertFalse(byDefault.acceptsText(on: .back), "Le trajet et les chiffres, pas de texte.")
        XCTAssertTrue(byDefault.acceptsStats(on: .back))

        let travel = covers(front: .travelBook, back: .travelBook)
        XCTAssertTrue(travel.acceptsPhoto(on: .back))
        XCTAssertFalse(travel.acceptsStats(on: .back))
        XCTAssertFalse(travel.acceptsStats(on: .front))
    }

    /// Une famille que cette app ne connaît pas ne fait pas tomber le
    /// catalogue : le style se décode, sans famille, et se dessine d'après sa
    /// composition.
    func testAnUnknownFamilyFallsBackToItsTreatment() throws {
        let json = Data(#"{"id":"front-collage","name":"Collage","treatment":"photo","tint":"ink","family":"collage"}"#.utf8)
        let decoded = try JSONDecoder().decode(CoverStyle.self, from: json)
        XCTAssertNil(decoded.family)
        XCTAssertEqual(decoded.treatment, .photo)
        XCTAssertTrue(decoded.matches(style(nil, .back, treatment: .photo).withInk))
    }

    func testAKnownFamilyDecodes() throws {
        let json = Data(#"{"id":"back-photo-drawing","name":"Photo-dessin","treatment":"plain","tint":"paper","family":"photo-drawing"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(CoverStyle.self, from: json).family, .photoDrawing)
    }
}

private extension CoverStyle {
    /// Le même style, à l'aplat encre — pour comparer au style décodé.
    var withInk: CoverStyle {
        CoverStyle(id: id, name: name, treatment: treatment, tint: .ink, family: family)
    }
}
