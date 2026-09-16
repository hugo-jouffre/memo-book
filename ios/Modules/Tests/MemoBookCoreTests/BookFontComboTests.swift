import Foundation
import XCTest

@testable import MemoBookCore

/// Les **assortiments de typographies** : quatre jeux dont on sait qu'ils
/// tiennent, à la place de quatre lignes qui laissaient tout marier.
final class BookFontComboTests: XCTestCase {
    func testTheDefaultBookRecognisesItsCombo() {
        // **Le point le plus important de tout ce changement** : un carnet
        // existant, réglé avant que cette feuille existe, doit se reconnaître
        // dans « Carnet de voyage » sans qu'on touche à quoi que ce soit. Les
        // défauts de `BookCustomisation` et ceux du combo sont le même jeu.
        let book = BookCustomisation()
        XCTAssertEqual(BookFontCombo.matching(book)?.id, BookFontCombo.travelJournal.id)
    }

    func testEveryComboCoversTheFourRoles() {
        for combo in BookFontCombo.all {
            for role in BookFontRole.allCases {
                XCTAssertFalse(
                    combo.font(role).isEmpty,
                    "\(combo.name) n’habille pas \(role.label)"
                )
            }
        }
    }

    func testCombosAreDistinct() {
        // Quatre assortiments qui se ressembleraient deux à deux ne feraient
        // pas un choix, ils feraient une liste.
        let signatures = BookFontCombo.all.map { combo in
            BookFontRole.allCases.map { combo.font($0) }.joined(separator: "|")
        }
        XCTAssertEqual(Set(signatures).count, BookFontCombo.all.count)
    }

    func testAPartialMatchIsNotAMatch() {
        // Trois polices sur quatre en commun : cocher l'assortiment serait
        // mentir sur ce qui s'imprimera.
        var book = BookCustomisation()
        book.fontHand = "Montserrat"
        XCTAssertNil(BookFontCombo.matching(book))
    }

    func testTheShortNameAndTheFamilyNameAreTheSameFont() {
        // La base a longtemps reçu « Playfair » là où le gabarit dit « Playfair
        // Display » : les deux doivent se reconnaître, sans quoi la moitié des
        // carnets existants sortiraient « Personnalisé ».
        var book = BookCustomisation()
        book.fontDisplay = "Playfair"
        book.fontFacts = "Playfair"
        XCTAssertEqual(BookFontCombo.matching(book)?.id, BookFontCombo.travelJournal.id)
    }

    func testTheLabelIsTheOneTheBrandWrites() {
        XCTAssertEqual(BookFontCombo.travelJournal.fontLabel(.titles), "Playfair")
        XCTAssertEqual(BookFontCombo.travelJournal.fontLabel(.subtitles), "Hansley")
    }

    func testAnUnknownFamilyIsShownAsIs() {
        // Une police posée par un autre client ne doit pas disparaître de
        // l'écran.
        var book = BookCustomisation()
        book.fontHand = "Comic Sans MS"
        XCTAssertEqual(BookFontRole.texts.fontLabel(in: book), "Comic Sans MS")
    }

    func testEachRoleWritesItsOwnColumn() {
        // ⚠️ Le croisement est volontaire : « titres » écrit `fontDisplay`.
        var book = BookCustomisation()
        for role in BookFontRole.allCases {
            book[keyPath: role.keyPath] = "Sonde-\(role.rawValue)"
        }

        XCTAssertEqual(book.fontDisplay, "Sonde-titles")
        XCTAssertEqual(book.fontTitle, "Sonde-subtitles")
        XCTAssertEqual(book.fontHand, "Sonde-texts")
        XCTAssertEqual(book.fontFacts, "Sonde-funFacts")
    }
}
