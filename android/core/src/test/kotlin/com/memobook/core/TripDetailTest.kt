package com.memobook.core

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/**
 * « Valider cette étape » : une nouvelle clé côté serveur ne doit jamais
 * faire échouer le décodage d'un voyage déjà installé — même parti pris que
 * l'étape de voyage inconnue de `TripTest`. Mêmes cas que `TripDetailTests.swift`.
 */
class TripDetailTest {
    private fun decode(json: String): TripStep = MemoBookJson.decodeFromString(TripStep.serializer(), json)

    @Test
    fun validatedAtDecodesWhenPresent() {
        val step = decode("""{"id":"s1","number":1,"companions":[],"validatedAt":"2026-08-28T18:00:00Z"}""")
        assertNotNull(step.validatedAt)
    }

    @Test
    fun validatedAtDecodesAsNilWhenAbsent() {
        val step = decode("""{"id":"s1","number":1,"companions":[]}""")
        assertNull(step.validatedAt)
    }

    @Test
    fun validatedKeepsEveryOtherFieldAndSetsTheDate() {
        val step = TripStep(id = "s1", number = 1, placeName = "Trastevere")
        val validated = step.validated(at = Instant.ofEpochSecond(0))

        assertEquals(Instant.ofEpochSecond(0), validated.validatedAt)
        assertEquals(step.id, validated.id)
        assertEquals(step.placeName, validated.placeName)
        assertNull(step.validatedAt, "l'étape d'origine ne doit pas bouger : `validated()` en rend une copie")
    }
}
