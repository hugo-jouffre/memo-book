package com.memobook.feature.trip

import com.memobook.core.Companion as TripCompanion
import com.memobook.core.TripStep
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * **Ce que dit une carte d'étape.** Jumeau de `TripStepRowLabelsTests.swift`,
 * cas pour cas (Hugo, 25/10/2026 — « titres d'étape accrocheurs avec numéro
 * en pastille et ville à la place du co-voyageur répété »).
 *
 * Une liste d'étapes doit se lire comme un itinéraire — Trastevere, Monti,
 * Testaccio —, pas comme une numérotation suivie du même nom à chaque ligne.
 *
 * ⚠️ **Quitter l'écran n'est pas quitter l'app.** Qui écoute la liste ne la
 * parcourt pas du regard : [spokenLabel] lui rend ce que la carte ne dessine
 * plus.
 */
class TripStepRowLabelsTest {
    private fun step(
        number: Int = 1,
        place: String? = "Trastevere",
        companions: List<TripCompanion> = listOf(TripCompanion(id = "c-1", name = "Léa Martin")),
        validated: Boolean = false,
    ) = TripStep(
        id = "step-$number",
        number = number,
        placeName = place,
        companions = companions,
        validatedAt = if (validated) Instant.EPOCH else null,
    )

    @Test
    fun `le lieu prend le titre`() {
        assertEquals("Trastevere", step().title)
    }

    /**
     * Sans lieu, le numéro revient dans le titre : la pastille ne doublerait
     * rien d'autre que lui, et une carte sans titre ne dirait rien.
     */
    @Test
    fun `sans lieu le numero revient dans le titre`() {
        assertEquals("Etape n°4", step(number = 4, place = null).title)
    }

    @Test
    fun `le titre ne nomme jamais un co-voyageur`() {
        val titre = step(companions = listOf(TripCompanion(id = "c-1", name = "Fanny Delorme"))).title
        assertFalse(titre.contains("Fanny"))
        assertFalse(titre.contains("avec"))
    }

    /** Et TalkBack, lui, les entend encore. */
    @Test
    fun `talkback entend encore les co-voyageurs`() {
        val dit = step(number = 2, validated = true).spokenLabel
        assertTrue(dit.contains("Étape 2"), dit)
        assertTrue(dit.contains("Trastevere"), dit)
        assertTrue(dit.contains("avec Léa"), dit)
        assertTrue(dit.contains("validée"), dit)
    }

    /** Une étape sans personne ni lieu ne dit pas de vide. */
    @Test
    fun `une etape vide se lit proprement`() {
        assertEquals("Étape 7", step(number = 7, place = null, companions = emptyList()).spokenLabel)
    }
}
