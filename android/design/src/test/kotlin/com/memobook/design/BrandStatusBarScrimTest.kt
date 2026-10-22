package com.memobook.design

import androidx.compose.ui.unit.dp
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Le fondu du voile de la barre d'état reste **dans** la barre : au plus
 * 16 dp, au plus un tiers de sa hauteur. Pas de test côté iOS ; c'est la règle
 * de `BrandStatusBarScrim.fadeHeight(for:)`.
 */
class BrandStatusBarScrimTest {
    @Test
    fun tallBarCapsTheFade() {
        assertEquals(16.dp, BrandStatusBarScrim.fadeHeight(60.dp))
    }

    @Test
    fun shortBarShrinksTheFadeToAThird() {
        assertEquals(8.dp, BrandStatusBarScrim.fadeHeight(24.dp))
    }

    @Test
    fun hiddenBarHasNoFade() {
        assertEquals(0.dp, BrandStatusBarScrim.fadeHeight(0.dp))
    }
}
