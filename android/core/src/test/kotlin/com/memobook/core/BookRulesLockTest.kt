package com.memobook.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Le **verrou des pointillés** : *Manuscrit* et *Éditorial* les éteignent, le
 * retour au défaut rend ceux d'avant. `docs/apercu-personnalisation.md` fait
 * foi. Mêmes cas que `BookRulesLockTests.swift`.
 *
 * Ces tests rejouent les gestes de l'écran sur la règle seule — un carnet, une
 * mémoire — comme le fait `BookCustomisationModel` ; les tests de l'app
 * vérifient qu'il l'applique et l'envoie.
 */
class BookRulesLockTest {
    // MARK: Quel assortiment verrouille

    @Test
    fun onlyTheDefaultComboAllowsRules() {
        assertTrue(BookFontCombo.travelJournal.allowsRules)
        assertFalse(BookFontCombo.handwritten.allowsRules)
        assertFalse(BookFontCombo.editorial.allowsRules)
    }

    @Test
    fun aHandComposedBookIsNotLocked() {
        // « Personnalisé » n'a d'aperçu ni avec ni sans pointillés : le verrou
        // n'y changerait rien, il n'y est pas.
        val book = BookCustomisation().copy(fontHand = "Montserrat")
        assertNull(BookFontCombo.matching(book))
        assertFalse(BookRulesLock.isLocked(book))
    }

    // MARK: Les deux assortiments contraints

    @Test
    fun choosingHandwrittenTurnsRulesOffAndRemembersThem() {
        val walk = Walk(rules = true)
        walk.choose(BookFontCombo.handwritten)

        assertFalse(walk.book.rulesEnabled)
        assertTrue(BookRulesLock.isLocked(walk.book))
        assertEquals(true, walk.memory)
    }

    @Test
    fun choosingEditorialTurnsRulesOffAndRemembersThem() {
        val walk = Walk(rules = true)
        walk.choose(BookFontCombo.editorial)

        assertFalse(walk.book.rulesEnabled)
        assertTrue(BookRulesLock.isLocked(walk.book))
        assertEquals(true, walk.memory)
    }

    // MARK: Le retour au défaut

    @Test
    fun backToDefaultRelightsRulesThatWereOn() {
        val walk = Walk(rules = true)
        walk.choose(BookFontCombo.handwritten)
        walk.choose(BookFontCombo.travelJournal)

        assertTrue(walk.book.rulesEnabled)
        assertFalse(BookRulesLock.isLocked(walk.book))
    }

    @Test
    fun backToDefaultKeepsOffRulesThatWereOff() {
        // Pas `true` par défaut : le voyageur les avait éteints, lui.
        val walk = Walk(rules = false)
        walk.choose(BookFontCombo.editorial)
        assertEquals(false, walk.memory)

        walk.choose(BookFontCombo.travelJournal)
        assertFalse(walk.book.rulesEnabled)
    }

    @Test
    fun aRoundTripThroughBothCombosLeavesTheBookAsItWas() {
        // Manuscrit → Éditorial → défaut : le second verrou ne doit pas écraser
        // la mémoire du premier par le `false` qu'il a lui-même posé.
        for (rules in listOf(true, false)) {
            val walk = Walk(rules = rules)
            val before = walk.book

            walk.choose(BookFontCombo.handwritten)
            walk.choose(BookFontCombo.editorial)
            assertEquals(rules, walk.memory, "le second verrou a écrasé la mémoire")
            walk.choose(BookFontCombo.travelJournal)

            assertEquals(before, walk.book, "pointillés ${if (rules) "allumés" else "éteints"} au départ")
        }
    }

    @Test
    fun anUnknownMemoryRelightsRules() {
        // Le verrou a été posé ailleurs — un autre téléphone, un co-voyageur :
        // personne ici n'a choisi « éteints », on rend la valeur par défaut.
        val walk = Walk(rules = false)
        walk.book = book(BookFontCombo.handwritten, rules = false)
        walk.memory = null

        walk.choose(BookFontCombo.travelJournal)
        assertTrue(walk.book.rulesEnabled)
    }

    @Test
    fun theDefaultComboLeavesUnlockedRulesAlone() {
        // Déjà sur le défaut, ou venant de « Personnalisé » : pas de verrou à
        // défaire, les pointillés restent ce qu'on en a fait.
        val hand = BookCustomisation(rulesEnabled = false).copy(fontHand = "Montserrat")
        val change = BookRulesLock.choosing(BookFontCombo.travelJournal, hand, remembered = true)
        assertEquals(BookRulesLock.Change(rulesEnabled = false), change)
    }

    // MARK: Les carnets d'avant le verrou

    @Test
    fun aLockedBookWithRulesOnIsPutBackInLine() {
        // Passé sur Manuscrit avant le 02/10/2026, pointillés laissés allumés.
        val book = book(BookFontCombo.handwritten, rules = true)
        assertEquals(
            BookRulesLock.Change(rulesEnabled = false, remember = true),
            BookRulesLock.normalised(book, remembered = null),
        )
        // Une mémoire déjà là n'est pas réécrite.
        assertEquals(
            BookRulesLock.Change(rulesEnabled = false),
            BookRulesLock.normalised(book, remembered = false),
        )
    }

    @Test
    fun aBookInLineIsLeftAlone() {
        assertNull(BookRulesLock.normalised(book(BookFontCombo.handwritten, rules = false), remembered = null))
        assertNull(BookRulesLock.normalised(book(BookFontCombo.travelJournal, rules = true), remembered = null))
        assertNull(BookRulesLock.normalised(BookCustomisation(), remembered = null))
    }

    // MARK: Ce que l'écran dit

    @Test
    fun theLockedNoticeNamesTheWayOut() {
        // La phrase est écrite en clair ; elle doit suivre les deux noms
        // qu'elle cite.
        assertTrue(BookCopy.Rules.locked.contains(BookFontCombo.travelJournal.name))
        assertTrue(BookCopy.Rules.locked.contains(BookCopy.Customisation.categoryFonts))
    }

    @Test
    fun theWithdrawnNoticeNamesTheComboThatDidIt() {
        assertEquals(
            "Manuscrit s’imprime sans pointillés : on les a retirés. Ils reviendront si tu repasses sur Carnet de voyage.",
            BookCopy.Rules.withdrawn(by = BookFontCombo.handwritten),
        )
    }

    // MARK: Outils

    /** Un carnet et sa mémoire, menés geste après geste comme l'écran le fait. */
    private class Walk(rules: Boolean) {
        var book: BookCustomisation = BookCustomisation(rulesEnabled = rules)
        var memory: Boolean? = null

        fun choose(combo: BookFontCombo) {
            val change = BookRulesLock.choosing(combo, book, remembered = memory)
            change.remember?.let { memory = it }
            for (role in BookFontRole.entries) {
                book = role.writing(combo.font(role), into = book)
            }
            book = book.copy(rulesEnabled = change.rulesEnabled)
        }
    }

    private fun book(combo: BookFontCombo, rules: Boolean): BookCustomisation {
        var book = BookCustomisation(rulesEnabled = rules)
        for (role in BookFontRole.entries) {
            book = role.writing(combo.font(role), into = book)
        }
        return book
    }
}
