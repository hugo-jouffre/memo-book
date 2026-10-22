package com.memobook.design

import androidx.compose.ui.geometry.Size
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Le cadrage du M. Il n'a pas de test côté iOS : les valeurs attendues sont
 * celles de Core Graphics (`boundingBoxOfPath` du tracé de `BrandMark.swift`,
 * élargi du demi-trait), relevées le 21/10/2026. Si elles divergent, le M ne
 * tombe plus au même endroit que sur l'iPhone, et le passage du lancement à
 * l'accueil saute.
 */
class BrandMarkTest {
    @Test
    fun boundsMatchCoreGraphics() {
        val bounds = BrandMark.designBounds
        assertEquals(-267.0923f, bounds.left, 0.01f)
        assertEquals(357.9857f, bounds.top, 0.01f)
        assertEquals(1815.6588f, bounds.width, 0.01f)
        assertEquals(1523.6473f, bounds.height, 0.01f)
    }

    @Test
    fun aspectRatioMatchesIos() {
        assertEquals(1.191653f, BrandMark.aspectRatio, 0.00001f)
    }

    @Test
    fun strokeKeepsItsWeightAtEveryScale() {
        val bounds = BrandMark.designBounds
        // À la taille du dessin, l'épaisseur est celle du SVG ; à moitié, la moitié.
        assertEquals(164.949f, BrandMark.lineWidth(Size(bounds.width, bounds.height)), 0.001f)
        assertEquals(164.949f / 2, BrandMark.lineWidth(Size(bounds.width / 2, bounds.height)), 0.001f)
    }
}
