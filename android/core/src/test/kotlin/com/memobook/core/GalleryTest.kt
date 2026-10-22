package com.memobook.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ce que la carte d'un carnet de la galerie décide toute seule : quel
 * pictogramme elle porte, et sous quelle catégorie elle se range. Mêmes cas que
 * `GalleryTests.swift`.
 *
 * Les deux règles se lisent en un coup d'œil sur l'écran et se cassent en
 * silence : un tour du monde qui prend le drapeau de son premier pays a l'air
 * juste tant qu'on ne connaît pas le voyage.
 */
class GalleryTripTest {
    private fun trip(destinations: List<Destination>, categoryIds: List<String> = emptyList()): GalleryTrip =
        GalleryTrip(id = "t1", title = "Un voyage", destinations = destinations, categoryIds = categoryIds)

    @Test
    fun singlecountryCarriesItsFlag() {
        val subject = trip(listOf(Destination(name = "Islande", countryCode = "IS")))
        assertEquals("🇮🇸", subject.flag)
    }

    @Test
    fun severalCountriesCarryNoFlag() {
        // C'est ce `null` qui fait poser le globe : choisir un drapeau parmi
        // quatre désignerait le premier pays comme *le* pays du voyage.
        val subject = trip(
            listOf(
                Destination(name = "Argentine", countryCode = "AR"),
                Destination(name = "Chili", countryCode = "CL"),
            ),
        )
        assertNull(subject.flag)
    }

    @Test
    fun countryWithoutUsableCodeCarriesNoFlag() {
        // Mieux vaut un globe qu'un carré blanc.
        assertNull(trip(listOf(Destination(name = "Quelque part"))).flag)
        assertNull(trip(emptyList()).flag)
    }

    @Test
    fun belongsToEveryCategoryWhenNoneIsSelected() {
        // `null`, c'est « Tout » : la barre ouverte, aucun filtre posé.
        assertTrue(trip(emptyList(), categoryIds = emptyList()).belongs(to = null))
    }

    @Test
    fun belongsToEachOfItsCategories() {
        val subject = trip(emptyList(), categoryIds = listOf("rando", "montagne"))

        assertTrue(subject.belongs(to = "rando"))
        assertTrue(subject.belongs(to = "montagne"))
        assertFalse(subject.belongs(to = "velo"))
    }
}
