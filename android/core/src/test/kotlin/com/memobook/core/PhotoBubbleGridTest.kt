package com.memobook.core

import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * **Comment une bulle range ses photos** (T305) — le jumeau de
 * `PhotoBubbleGridTests.swift`.
 */
class PhotoBubbleGridTest {
    private val width = 240.0
    private val gap = 4.0
    private val maximum = 182.0

    private fun assertClose(expected: Double, actual: Double, tolerance: Double = 0.001, message: String = "") {
        assertTrue(abs(expected - actual) <= tolerance, "$message (attendu $expected, obtenu $actual)")
    }

    /** **Deux par rangée**, et la dernière seule quand le compte est impair. */
    @Test
    fun rowsGoTwoByTwoAndTheLastOneMayBeAlone() {
        assertEquals(emptyList(), PhotoBubbleGrid.rows(0))
        assertEquals(listOf(0 until 1), PhotoBubbleGrid.rows(1))
        assertEquals(listOf(0 until 2), PhotoBubbleGrid.rows(2))
        assertEquals(listOf(0 until 2, 2 until 3), PhotoBubbleGrid.rows(3))
        assertEquals(listOf(0 until 2, 2 until 4, 4 until 6), PhotoBubbleGrid.rows(6))
    }

    /** **Deux carrés remplissent la largeur.** */
    @Test
    fun twoSquaresShareTheWidth() {
        val height = PhotoBubbleGrid.rowHeight(listOf(1.0, 1.0), width, gap, maximum)
        assertClose((width - gap) / 2, height)

        val widths = PhotoBubbleGrid.widths(listOf(1.0, 1.0), height, width, gap)
        assertClose(width, widths.sum() + gap, message = "La rangée remplit la bulle")
    }

    /** **Chacune à son format** : même hauteur, largeurs différentes. */
    @Test
    fun aLandscapeAndAPortraitShareTheirHeightNotTheirWidth() {
        val aspects = listOf(16.0 / 9, 3.0 / 4)
        val height = PhotoBubbleGrid.rowHeight(aspects, width, gap, maximum)
        val widths = PhotoBubbleGrid.widths(aspects, height, width, gap)

        assertClose(width, widths.sum() + gap)
        assertTrue(widths[0] > widths[1], "La paysage est la plus large")
        assertClose(16.0 / 9, widths[0] / height, tolerance = 0.01, message = "Et elle garde son format")
    }

    /** **Une photo seule prend toute la largeur** — la place du trou d'avant. */
    @Test
    fun aSinglePhotoTakesTheWholeWidth() {
        assertEquals(listOf(width), PhotoBubbleGrid.widths(listOf(1.5), 100.0, width, gap))
    }

    /** ⚠️ **Mais pas toute la hauteur** : une portrait seule mangerait l'écran. */
    @Test
    fun aTallPhotoIsCapped() {
        assertClose(maximum, PhotoBubbleGrid.rowHeight(listOf(0.5), width, gap, maximum))
    }

    /** **Une photo sans mesure compte pour un carré.** */
    @Test
    fun aPhotoWithoutAMeasureCountsAsASquare() {
        val known = PhotoBubbleGrid.rowHeight(listOf(1.0, 1.0), width, gap, maximum)
        val unknown = PhotoBubbleGrid.rowHeight(listOf(0.0, 1.0), width, gap, maximum)
        assertClose(known, unknown)
    }

    /** Le rapport d'une photo se lit sur ses pixels, et se tait sans eux. */
    @Test
    fun anAttachmentKnowsItsAspectOnlyWhenMeasured() {
        assertClose(4.0 / 3, PhotoAttachment(id = "a", widthPx = 4000, heightPx = 3000).aspect ?: 0.0)
        assertNull(PhotoAttachment(id = "b").aspect)
        assertNull(PhotoAttachment(id = "c", widthPx = 0, heightPx = 3000).aspect)
    }
}
