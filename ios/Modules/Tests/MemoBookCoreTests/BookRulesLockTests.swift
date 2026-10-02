import Foundation
import XCTest

@testable import MemoBookCore

/// Le **verrou des pointillés** : *Manuscrit* et *Éditorial* les éteignent, le
/// retour au défaut rend ceux d'avant. `docs/apercu-personnalisation.md` fait
/// foi.
///
/// Ces tests rejouent les gestes de l'écran sur la règle seule — un carnet, une
/// mémoire — comme le fait ``BookCustomisationModel`` ; les tests de l'app
/// vérifient qu'il l'applique et l'envoie.
final class BookRulesLockTests: XCTestCase {
    // MARK: Quel assortiment verrouille

    func testOnlyTheDefaultComboAllowsRules() {
        XCTAssertTrue(BookFontCombo.travelJournal.allowsRules)
        XCTAssertFalse(BookFontCombo.handwritten.allowsRules)
        XCTAssertFalse(BookFontCombo.editorial.allowsRules)
    }

    func testAHandComposedBookIsNotLocked() {
        // « Personnalisé » n'a d'aperçu ni avec ni sans pointillés : le verrou
        // n'y changerait rien, il n'y est pas.
        var book = BookCustomisation()
        book.fontHand = "Montserrat"
        XCTAssertNil(BookFontCombo.matching(book))
        XCTAssertFalse(BookRulesLock.isLocked(book))
    }

    // MARK: Les deux assortiments contraints

    func testChoosingHandwrittenTurnsRulesOffAndRemembersThem() {
        var walk = Walk(rules: true)
        walk.choose(.handwritten)

        XCTAssertFalse(walk.book.rulesEnabled)
        XCTAssertTrue(BookRulesLock.isLocked(walk.book))
        XCTAssertEqual(walk.memory, true)
    }

    func testChoosingEditorialTurnsRulesOffAndRemembersThem() {
        var walk = Walk(rules: true)
        walk.choose(.editorial)

        XCTAssertFalse(walk.book.rulesEnabled)
        XCTAssertTrue(BookRulesLock.isLocked(walk.book))
        XCTAssertEqual(walk.memory, true)
    }

    // MARK: Le retour au défaut

    func testBackToDefaultRelightsRulesThatWereOn() {
        var walk = Walk(rules: true)
        walk.choose(.handwritten)
        walk.choose(.travelJournal)

        XCTAssertTrue(walk.book.rulesEnabled)
        XCTAssertFalse(BookRulesLock.isLocked(walk.book))
    }

    func testBackToDefaultKeepsOffRulesThatWereOff() {
        // Pas `true` par défaut : le voyageur les avait éteints, lui.
        var walk = Walk(rules: false)
        walk.choose(.editorial)
        XCTAssertEqual(walk.memory, false)

        walk.choose(.travelJournal)
        XCTAssertFalse(walk.book.rulesEnabled)
    }

    func testARoundTripThroughBothCombosLeavesTheBookAsItWas() {
        // Manuscrit → Éditorial → défaut : le second verrou ne doit pas écraser
        // la mémoire du premier par le `false` qu'il a lui-même posé.
        for rules in [true, false] {
            var walk = Walk(rules: rules)
            let before = walk.book

            walk.choose(.handwritten)
            walk.choose(.editorial)
            XCTAssertEqual(walk.memory, rules, "le second verrou a écrasé la mémoire")
            walk.choose(.travelJournal)

            XCTAssertEqual(walk.book, before, "pointillés \(rules ? "allumés" : "éteints") au départ")
        }
    }

    func testAnUnknownMemoryRelightsRules() {
        // Le verrou a été posé ailleurs — un autre téléphone, un co-voyageur :
        // personne ici n'a choisi « éteints », on rend la valeur par défaut.
        var walk = Walk(rules: false)
        walk.book = Self.book(.handwritten, rules: false)
        walk.memory = nil

        walk.choose(.travelJournal)
        XCTAssertTrue(walk.book.rulesEnabled)
    }

    func testTheDefaultComboLeavesUnlockedRulesAlone() {
        // Déjà sur le défaut, ou venant de « Personnalisé » : pas de verrou à
        // défaire, les pointillés restent ce qu'on en a fait.
        var hand = BookCustomisation(rulesEnabled: false)
        hand.fontHand = "Montserrat"
        let change = BookRulesLock.choosing(.travelJournal, in: hand, remembered: true)
        XCTAssertEqual(change, BookRulesLock.Change(rulesEnabled: false))
    }

    // MARK: Les carnets d'avant le verrou

    func testALockedBookWithRulesOnIsPutBackInLine() {
        // Passé sur Manuscrit avant le 02/10/2026, pointillés laissés allumés.
        let book = Self.book(.handwritten, rules: true)
        XCTAssertEqual(
            BookRulesLock.normalised(book, remembered: nil),
            BookRulesLock.Change(rulesEnabled: false, remember: true)
        )
        // Une mémoire déjà là n'est pas réécrite.
        XCTAssertEqual(
            BookRulesLock.normalised(book, remembered: false),
            BookRulesLock.Change(rulesEnabled: false)
        )
    }

    func testABookInLineIsLeftAlone() {
        XCTAssertNil(BookRulesLock.normalised(Self.book(.handwritten, rules: false), remembered: nil))
        XCTAssertNil(BookRulesLock.normalised(Self.book(.travelJournal, rules: true), remembered: nil))
        XCTAssertNil(BookRulesLock.normalised(BookCustomisation(), remembered: nil))
    }

    // MARK: Ce que l'écran dit

    func testTheLockedNoticeNamesTheWayOut() {
        // La phrase est écrite en clair ; elle doit suivre les deux noms
        // qu'elle cite.
        XCTAssertTrue(BookCopy.Rules.locked.contains(BookFontCombo.travelJournal.name))
        XCTAssertTrue(BookCopy.Rules.locked.contains(BookCopy.Customisation.categoryFonts))
    }

    func testTheWithdrawnNoticeNamesTheComboThatDidIt() {
        XCTAssertEqual(
            BookCopy.Rules.withdrawn(by: .handwritten),
            "Manuscrit s’imprime sans pointillés : on les a retirés. Ils reviendront si tu repasses sur Carnet de voyage."
        )
    }

    // MARK: Outils

    /// Un carnet et sa mémoire, menés geste après geste comme l'écran le fait.
    private struct Walk {
        var book: BookCustomisation
        var memory: Bool?

        init(rules: Bool) {
            book = BookCustomisation(rulesEnabled: rules)
        }

        mutating func choose(_ combo: BookFontCombo) {
            let change = BookRulesLock.choosing(combo, in: book, remembered: memory)
            if let remember = change.remember { memory = remember }
            for role in BookFontRole.allCases {
                book[keyPath: role.keyPath] = combo.font(role)
            }
            book.rulesEnabled = change.rulesEnabled
        }
    }

    private static func book(_ combo: BookFontCombo, rules: Bool) -> BookCustomisation {
        var book = BookCustomisation(rulesEnabled: rules)
        for role in BookFontRole.allCases {
            book[keyPath: role.keyPath] = combo.font(role)
        }
        return book
    }
}
