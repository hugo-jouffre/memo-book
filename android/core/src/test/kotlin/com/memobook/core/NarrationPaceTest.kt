package com.memobook.core

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Le rythme du récit se relit sous sa clé — et sous les libellés que
 * l'ancien écran de création écrivait (Hugo, 18/09/2026). Mêmes cas que
 * `NarrationPaceTests.swift` ; `NarrationPace(storedValue:)` s'écrit ici
 * `NarrationPace.from(storedValue)`.
 */
class NarrationPaceTest {
    @Test
    fun keysDecodeToTheirCase() {
        assertEquals(NarrationPace.Daily, NarrationPace.from(storedValue = "daily"))
        assertEquals(NarrationPace.EveryTwoDays, NarrationPace.from(storedValue = "every_two_days"))
        assertEquals(NarrationPace.Weekly, NarrationPace.from(storedValue = "weekly"))
        assertEquals(NarrationPace.Custom, NarrationPace.from(storedValue = "custom"))
    }

    @Test
    fun legacyLabelsDecodeToTheSameCase() {
        assertEquals(NarrationPace.Daily, NarrationPace.from(storedValue = "Tous les jours"))
        assertEquals(NarrationPace.EveryTwoDays, NarrationPace.from(storedValue = "Tous les 2 jours"))
        assertEquals(NarrationPace.Weekly, NarrationPace.from(storedValue = "Toutes les semaines"))
        assertEquals(NarrationPace.Weekly, NarrationPace.from(storedValue = " Une fois par semaine "))
    }

    @Test
    fun unknownWordsKeepTheirSpelling() {
        assertEquals(NarrationPace.Unknown("À la pleine lune"), NarrationPace.from(storedValue = "À la pleine lune"))
        assertEquals("À la pleine lune", NarrationPace.from(storedValue = "À la pleine lune").displayName)
    }

    @Test
    fun everyProposedPaceRoundTripsThroughItsKey() {
        for (pace in NarrationPace.selectable) {
            assertEquals(pace, NarrationPace.from(storedValue = pace.rawValue))
        }
    }
}
