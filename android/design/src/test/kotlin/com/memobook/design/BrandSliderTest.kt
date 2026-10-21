package com.memobook.design

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * Le calcul de [BrandSlider], à part de son dessin : la poignée s'arrête sous
 * une étiquette, jamais entre deux, et ne sort pas de ses bornes.
 */
class BrandSliderTest {
    @Test
    fun theFingerSnapsToTheNearestStep() {
        assertEquals(50, BrandSlider.stepped(0.49f, 0..100, 25))
        assertEquals(75, BrandSlider.stepped(0.63f, 0..100, 25))
        assertEquals(2, BrandSlider.stepped(0.5f, 0..4, 1))
    }

    @Test
    fun theFingerBeyondTheRailStaysInBounds() {
        assertEquals(0, BrandSlider.stepped(-0.4f, 0..100, 25))
        assertEquals(100, BrandSlider.stepped(1.7f, 0..100, 25))
    }

    @Test
    fun oneStepAtATimeForTalkBack() {
        assertEquals(75, BrandSlider.moved(50, 25, 0..100))
        assertEquals(100, BrandSlider.moved(100, 25, 0..100))
        assertEquals(0, BrandSlider.moved(0, -1, 0..4))
    }

    @Test
    fun theSelectedTickIsTheOneUnderTheThumb() {
        assertEquals(2, BrandSlider.selectedTick(50, 0..100, 25, tickCount = 5))
        assertEquals(4, BrandSlider.selectedTick(100, 0..100, 25, tickCount = 5))
        // Des crans qui ne correspondent pas aux pas : pas d'étiquette en gras,
        // mais pas de plantage non plus.
        assertNull(BrandSlider.selectedTick(100, 0..100, 25, tickCount = 3))
    }

    @Test
    fun fractionOfAnEmptyRangeIsZero() {
        assertEquals(0f, BrandSlider.fraction(3, 3..3))
        assertEquals(0.5f, BrandSlider.fraction(50, 0..100))
    }
}
