package com.memobook.design

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Le rééchantillonnage d'un vocal terminé (`BrandWaveform.resample`). Pas de
 * test côté iOS ; ceux-ci fixent les deux règles écrites dans son commentaire :
 * c'est la largeur qui commande, et chaque barre garde le pic de sa tranche.
 */
class BrandWaveformTest {
    @Test
    fun emptyRecordingIsAFlatLine() {
        assertEquals(listOf(0f), BrandWaveform.resample(emptyList(), toFit = 100f))
    }

    @Test
    fun shortRecordingKeepsEverySampleClamped() {
        assertEquals(listOf(0f, 0.5f, 1f), BrandWaveform.resample(listOf(-0.2, 0.5, 1.4), toFit = 100f))
    }

    @Test
    fun widthDecidesHowManyBarsAreDrawn() {
        // Une barre de 3 et un espace de 2 : 23 dp tiennent (23 + 2) / 5 = 5 barres.
        val bars = BrandWaveform.resample(List(100) { 0.5 }, toFit = 23f)
        assertEquals(5, bars.size)
    }

    @Test
    fun eachBarKeepsThePeakOfItsSlice() {
        val levels = listOf(0.1, 0.9, 0.2, 0.3, 0.8, 0.1, 0.4, 0.2, 0.7, 0.1)
        // 8 dp : deux barres, chacune sur cinq échantillons.
        assertEquals(listOf(0.9f, 0.7f), BrandWaveform.resample(levels, toFit = 8f))
    }

    @Test
    fun aTooNarrowWidthStillDrawsOneBar() {
        assertEquals(listOf(0.9f), BrandWaveform.resample(listOf(0.2, 0.9, 0.4), toFit = 0f))
    }
}
