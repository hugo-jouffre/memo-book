package com.memobook.core

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Les mots de la corbeille — le jumeau de `HomeCopyTests.swift`, cas pour cas.
 *
 * Le compte à rebours est ce qu'on lit en premier sur une ligne : il doit
 * dire vrai au jour près, et se finir sur « aujourd'hui » plutôt que sur un
 * zéro.
 */
class HomeCopyTest {
    private val jour = 86_400L

    @Test
    fun theCountdownSpeaksInWholeDays() {
        assertEquals("S’efface dans 30 jours", HomeCopy.Trash.erasesIn(30))
        assertEquals("S’efface dans 2 jours", HomeCopy.Trash.erasesIn(2))
        assertEquals("S’efface demain", HomeCopy.Trash.erasesIn(1))
        assertEquals("S’efface aujourd’hui", HomeCopy.Trash.erasesIn(0))
    }

    /** Une purge en retard ne compte pas à l'envers. */
    @Test
    fun aLatePurgeNeverCountsBackwards() {
        assertEquals("S’efface aujourd’hui", HomeCopy.Trash.erasesIn(-3))
        val now = Instant.ofEpochSecond(1_000_000)
        assertEquals(0, HomeCopy.Trash.daysLeft(until = now.minusSeconds(5 * jour), from = now))
    }

    @Test
    fun theDaysLeftAreCountedUpwards() {
        val now = Instant.ofEpochSecond(1_000_000)
        // Dans trente jours pile : trente jours.
        assertEquals(30, HomeCopy.Trash.daysLeft(until = now.plusSeconds(30 * jour), from = now))
        // Une heure de plus que vingt-neuf jours : on arrondit vers le haut,
        // pour ne jamais promettre moins de temps qu'il n'en reste.
        assertEquals(30, HomeCopy.Trash.daysLeft(until = now.plusSeconds(29 * jour + 3_600), from = now))
        assertEquals(1, HomeCopy.Trash.daysLeft(until = now.plusSeconds(60), from = now))
    }
}
