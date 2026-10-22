package com.memobook.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull

/**
 * Les **assortiments de typographies** : quatre jeux dont on sait qu'ils
 * tiennent, à la place de quatre lignes qui laissaient tout marier. Mêmes cas
 * que `BookFontComboTests.swift`.
 */
class BookFontComboTest {
    @Test
    fun theDefaultBookRecognisesItsCombo() {
        // **Le point le plus important de tout ce changement** : un carnet
        // existant, réglé avant que cette feuille existe, doit se reconnaître
        // dans « Carnet de voyage » sans qu'on touche à quoi que ce soit. Les
        // défauts de `BookCustomisation` et ceux du combo sont le même jeu.
        val book = BookCustomisation()
        assertEquals(BookFontCombo.travelJournal.id, BookFontCombo.matching(book)?.id)
    }

    @Test
    fun onlyTheTravelJournalComboIsAvailableForNow() {
        // La V1 n'imprime que « Carnet de voyage » (Hugo, 09/10/2026) : les
        // deux autres restent sur la feuille, « À venir ».
        assertEquals(listOf(BookFontCombo.travelJournal.id), BookFontCombo.all.filter { it.isAvailable }.map { it.id })
        assertFalse(BookFontCombo.editorial.isAvailable)
        assertFalse(BookFontCombo.handwritten.isAvailable)
    }

    @Test
    fun everyComboCoversTheFourRoles() {
        for (combo in BookFontCombo.all) {
            for (role in BookFontRole.entries) {
                assertFalse(combo.font(role).isEmpty(), "${combo.name} n’habille pas ${role.label}")
            }
        }
    }

    @Test
    fun combosAreDistinct() {
        // Quatre assortiments qui se ressembleraient deux à deux ne feraient
        // pas un choix, ils feraient une liste.
        val signatures = BookFontCombo.all.map { combo ->
            BookFontRole.entries.joinToString("|") { combo.font(it) }
        }
        assertEquals(BookFontCombo.all.size, signatures.toSet().size)
    }

    @Test
    fun aPartialMatchIsNotAMatch() {
        // Trois polices sur quatre en commun : cocher l'assortiment serait
        // mentir sur ce qui s'imprimera.
        val book = BookCustomisation().copy(fontHand = "Montserrat")
        assertNull(BookFontCombo.matching(book))
    }

    @Test
    fun theShortNameAndTheFamilyNameAreTheSameFont() {
        // La base a longtemps reçu « Playfair » là où le gabarit dit « Playfair
        // Display » : les deux doivent se reconnaître, sans quoi la moitié des
        // carnets existants sortiraient « Personnalisé ».
        val book = BookCustomisation().copy(fontDisplay = "Playfair", fontFacts = "Playfair")
        assertEquals(BookFontCombo.travelJournal.id, BookFontCombo.matching(book)?.id)
    }

    @Test
    fun theLabelIsTheOneTheBrandWrites() {
        assertEquals("Playfair", BookFontCombo.travelJournal.fontLabel(BookFontRole.Titles))
        assertEquals("Hansley", BookFontCombo.travelJournal.fontLabel(BookFontRole.Subtitles))
    }

    @Test
    fun anUnknownFamilyIsShownAsIs() {
        // Une police posée par un autre client ne doit pas disparaître de
        // l'écran.
        val book = BookCustomisation().copy(fontHand = "Comic Sans MS")
        assertEquals("Comic Sans MS", BookFontRole.Texts.fontLabel(book))
    }

    @Test
    fun eachRoleWritesItsOwnColumn() {
        // ⚠️ Le croisement est volontaire : « titres » écrit `fontDisplay`.
        var book = BookCustomisation()
        for (role in BookFontRole.entries) {
            book = role.writing("Sonde-${role.rawValue}", into = book)
        }

        assertEquals("Sonde-titles", book.fontDisplay)
        assertEquals("Sonde-subtitles", book.fontTitle)
        assertEquals("Sonde-texts", book.fontHand)
        assertEquals("Sonde-funFacts", book.fontFacts)
        // Et la lecture passe par la même colonne.
        for (role in BookFontRole.entries) assertEquals("Sonde-${role.rawValue}", role.keyPath.get(book))
    }
}
