package com.memobook.design

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

/**
 * Le pont entre une clé et le catalogue d'images. Mêmes cas que
 * `LucideIconTests.swift` : deux règles de nommage qui divergent, et les
 * pastilles se retrouvent vides sans que rien n'échoue.
 */
class LucideIconTest {
    @Test
    fun everyKnownKeyHasAnImageInTheCatalogue() {
        for (key in LucideIcon.known) {
            val name = LucideIcon.assetName(key)
            assertNotNull(BrandImages[name], "$key → $name : lancer `./gradlew :tools:importBrandAssets`")
        }
    }

    @Test
    fun unknownKeyFallsBackToTheCompass() {
        assertEquals("IconLucideCompass", LucideIcon.assetName("montgolfiere"))
        assertEquals("IconLucideCompass", LucideIcon.assetName(null))
    }

    @Test
    fun hyphenatedKeysBecomePascalCase() {
        assertEquals("IconLucideMountainSnow", LucideIcon.assetName("mountain-snow"))
        assertEquals("IconLucideBuilding2", LucideIcon.assetName("building-2"))
        assertEquals("IconLucideGlobe", LucideIcon.assetName("globe"))
    }
}
