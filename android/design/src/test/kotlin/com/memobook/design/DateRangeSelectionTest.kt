package com.memobook.design

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.YearMonth
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Les règles du geste, telles qu'elles sont énoncées en tête de
 * `BrandRangeCalendar` : une case en cours, le jour touché va dedans, et ce que
 * fait un jour touché à contre-sens. Mêmes cas que `DateRangeSelectionTests.swift`.
 */
class DateRangeSelectionTest {
    private fun day(n: Int): LocalDate = LocalDate.of(2026, 9, n)

    // Case « Départ »

    @Test
    fun poserLeDepartPasseAuRetour() {
        val selection = DateRangeSelection().tap(day(18))

        assertEquals(day(18), selection.start)
        assertNull(selection.end)
        assertEquals(DateRangeSelection.Slot.End, selection.editing)
    }

    @Test
    fun corrigerLeDepartGardeUnRetourQuiLeSuit() {
        val selection = DateRangeSelection(day(18), day(26), DateRangeSelection.Slot.Start).tap(day(20))

        assertEquals(day(20), selection.start)
        assertEquals(day(26), selection.end)
    }

    @Test
    fun corrigerLeDepartApresLeRetourEffaceLeRetour() {
        val selection = DateRangeSelection(day(18), day(26), DateRangeSelection.Slot.Start).tap(day(28))

        assertEquals(day(28), selection.start)
        assertNull(selection.end)
    }

    // Case « Retour »

    @Test
    fun unJourApresLeDepartDevientLeRetour() {
        val selection = DateRangeSelection(start = day(18), editing = DateRangeSelection.Slot.End).tap(day(26))

        assertEquals(day(18), selection.start)
        assertEquals(day(26), selection.end)
        assertEquals(DateRangeSelection.Slot.End, selection.editing)
    }

    @Test
    fun unJourAvantLeDepartDevientLeDepart() {
        val selection = DateRangeSelection(day(18), day(26), DateRangeSelection.Slot.End).tap(day(10))

        assertEquals(day(10), selection.start)
        assertNull(selection.end)
    }

    @Test
    fun toucherLeDepartEnReglantLeRetourNeFaitRien() {
        val selection = DateRangeSelection(start = day(18), editing = DateRangeSelection.Slot.End).tap(day(18))

        assertEquals(day(18), selection.start)
        assertNull(selection.end)
    }

    @Test
    fun pasDeRetourSansDepart() {
        val selection = DateRangeSelection(editing = DateRangeSelection.Slot.End).tap(day(18))

        assertEquals(day(18), selection.start)
        assertNull(selection.end)
    }

    // Effacer

    @Test
    fun effacerLeRetourGardeLeDepart() {
        val selection = DateRangeSelection(day(18), day(26)).clear(DateRangeSelection.Slot.End)

        assertEquals(day(18), selection.start)
        assertNull(selection.end)
        assertEquals(DateRangeSelection.Slot.End, selection.editing)
    }

    @Test
    fun effacerLeDepartEmporteLeRetour() {
        val selection = DateRangeSelection(day(18), day(26), DateRangeSelection.Slot.End).clear(DateRangeSelection.Slot.Start)

        assertTrue(selection.isEmpty)
        assertNull(selection.end)
        assertEquals(DateRangeSelection.Slot.Start, selection.editing)
    }

    // Lecture

    /**
     * Le jumeau de `lesDatesSontRameneesAMinuit` : iOS ramène ses `Date` à minuit,
     * un `LocalDate` n'a pas d'heure. Un après-midi et son jour sont la même case.
     */
    @Test
    fun lesDatesSontDesJours() {
        val afternoon = LocalDateTime.of(2026, 9, 18, 15, 0).toLocalDate()
        val selection = DateRangeSelection(afternoon, LocalDateTime.of(2026, 9, 26, 15, 0).toLocalDate())

        assertEquals(day(18), selection.start)
        assertEquals(day(26), selection.end)
    }

    @Test
    fun chaqueJourConnaitSonRole() {
        val selection = DateRangeSelection(day(18), day(26))

        assertEquals(DateRangeSelection.Role.None, selection.role(day(17)))
        assertEquals(DateRangeSelection.Role.Start(isClosed = true), selection.role(day(18)))
        assertEquals(DateRangeSelection.Role.Inside, selection.role(day(22)))
        assertEquals(DateRangeSelection.Role.End, selection.role(day(26)))
        assertEquals(DateRangeSelection.Role.None, selection.role(day(27)))
    }

    @Test
    fun unDepartSeulEstUneBorneOuverte() {
        val selection = DateRangeSelection(start = day(18))

        assertEquals(DateRangeSelection.Role.Start(isClosed = false), selection.role(day(18)))
        assertEquals(DateRangeSelection.Role.None, selection.role(day(19)))
    }

    @Test
    fun laGrilleDuMoisCommenceDansSaColonne() {
        // Septembre 2026 commence un mardi : avec le lundi en tête de semaine,
        // une case vide devant le 1er.
        val grid = YearMonth.of(2026, 9).monthGrid(DayOfWeek.MONDAY)

        assertEquals(31, grid.size)
        assertNull(grid[0])
        assertEquals(day(1), grid[1])
    }
}
