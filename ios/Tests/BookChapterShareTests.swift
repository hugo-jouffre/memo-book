import MemoBookCore
@testable import MemoBookFeature
import PDFKit
import UIKit
import XCTest

/**
 **Choisir les étapes qu'on envoie** (T285, Hugo, 05/11/2026 — « au partage
 d'un PDF, pouvoir choisir ce qu'on envoie »).

 Le PDF est déjà chargé dans l'app : on le découpe sur place. Ces tests
 portent sur les deux calculs que ça demande — où tombent les pages d'une
 étape dans le document, et ce que l'extraction en garde.
 */
@MainActor
final class BookChapterShareTests: XCTestCase {
    /// Un PDF de `count` pages, chacune numérotée : c'est ce numéro qu'on
    /// relit pour savoir lesquelles ont survécu au découpage.
    private func pdf(pages count: Int) -> Data {
        let page = CGRect(x: 0, y: 0, width: 420, height: 595)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            for index in 0..<count {
                context.beginPage()
                "\(index)".draw(
                    at: CGPoint(x: 40, y: 40),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 48)]
                )
            }
        }
    }

    /// Le carnet de référence : 2 couvertures + 6 pages intérieures,
    /// trois étapes de deux pages, précédées du colophon et de l'intro.
    private let chapters = [
        BookChapter(title: "Jour 1 – Bogotá", firstPage: 3, pageCount: 2),
        BookChapter(title: "Jour 2 – Monserrate", firstPage: 5, pageCount: 2),
        BookChapter(title: "Jour 3 – Guatapé", firstPage: 7, pageCount: 2),
    ]

    private func preview(pageCount: Int = 8) -> BookPreview {
        BookPreview(memoId: "memo", title: "Colombie", status: .ready, pageCount: pageCount, chapters: chapters)
    }

    // MARK: - Où tombe une étape dans le document

    func testAChapterFindsItsPagesPastTheCovers() {
        // 10 pages au document, 8 comptées par le serveur : une couverture
        // devant, une derrière. L'étape 1 (page 3 hors couvertures) tombe
        // donc sur les index 3 et 4.
        XCTAssertEqual(Array(chapters[0].pages(inDocumentOf: 10, inner: 8)), [3, 4])
        XCTAssertEqual(Array(chapters[2].pages(inDocumentOf: 10, inner: 8)), [7, 8])
    }

    func testAChapterWithoutCoversNeedsNoShift() {
        // Autant de pages des deux côtés : rien à décaler.
        XCTAssertEqual(Array(chapters[0].pages(inDocumentOf: 8, inner: 8)), [2, 3])
    }

    func testAChapterNeverRunsPastTheDocument() {
        // Un document plus court que ce que le serveur annonce — un PDF
        // tronqué, un compte périmé. L'étape 3 tombe alors hors du document :
        // elle ne rend **aucune** page plutôt qu'une mauvaise.
        let dehors = chapters[2].pages(inDocumentOf: 4, inner: 8)
        XCTAssertTrue(dehors.isEmpty, "Hors du document : rien, pas n'importe quoi.")
        XCTAssertLessThanOrEqual(dehors.upperBound, 4)

        // Et une étape à cheval s'arrête au bord.
        let aCheval = chapters[1].pages(inDocumentOf: 4, inner: 8)
        XCTAssertLessThanOrEqual(aCheval.upperBound, 4)
    }

    // MARK: - Ce que l'extraction garde

    func testOnlyTheChosenChaptersSurvive_withTheCovers() throws {
        let data = pdf(pages: 10)

        let extrait = try XCTUnwrap(
            BookPreviewModel.extrait(data, chapitres: [chapters[1].firstPage], preview: preview())
        )

        let document = try XCTUnwrap(PDFDocument(data: extrait))
        // Couverture + les deux pages de l'étape 2 + quatrième de couverture.
        XCTAssertEqual(document.pageCount, 4)
        XCTAssertEqual(texts(of: document), ["0", "5", "6", "9"])
    }

    func testEverythingTickedSharesTheDocumentUntouched() {
        // Rien à recomposer : on renvoie nul, et l'appelant partage l'original
        // octet pour octet.
        let toutes = Set(chapters.map(\.firstPage))
        XCTAssertNil(BookPreviewModel.extrait(pdf(pages: 10), chapitres: toutes, preview: preview()))
    }

    func testNoSelectionSharesEverything() {
        XCTAssertNil(BookPreviewModel.extrait(pdf(pages: 10), chapitres: nil, preview: preview()))
    }

    func testAServerWithoutChaptersSharesEverything() {
        // Un rendu d'avant T285 : rien à choisir, rien à découper.
        let ancien = BookPreview(memoId: "memo", title: "Colombie", status: .ready, pageCount: 8)
        XCTAssertNil(BookPreviewModel.extrait(pdf(pages: 10), chapitres: [3], preview: ancien))
    }

    func testTwoChaptersKeepTheBookInOrder() throws {
        let data = pdf(pages: 10)

        let extrait = try XCTUnwrap(
            BookPreviewModel.extrait(
                data,
                chapitres: [chapters[2].firstPage, chapters[0].firstPage],
                preview: preview()
            )
        )

        // Choisies dans le désordre, elles sortent dans l'ordre du carnet.
        XCTAssertEqual(texts(of: try XCTUnwrap(PDFDocument(data: extrait))), ["0", "3", "4", "7", "8", "9"])
    }

    /// Le numéro écrit sur chaque page, dans l'ordre.
    private func texts(of document: PDFDocument) -> [String] {
        (0..<document.pageCount).compactMap {
            document.page(at: $0)?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
