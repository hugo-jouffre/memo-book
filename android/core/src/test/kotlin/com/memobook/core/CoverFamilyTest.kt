package com.memobook.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Les sept gabarits de `assets/covers` (08/10/2026) : la paire 1ère / 4e, ce
 * que chaque plat accepte, et le repli d'un style sans famille. Mêmes cas que
 * `CoverFamilyTests.swift`.
 */
class CoverFamilyTest {
    private fun style(family: CoverFamily?, face: CoverFace, treatment: CoverTreatment = CoverTreatment.Framed): CoverStyle =
        CoverStyle(
            id = "${face.rawValue}-${family?.rawValue ?: "legacy"}",
            name = family?.rawValue ?: "legacy",
            treatment = treatment,
            tint = CoverTint.Paper,
            family = family,
        )

    private fun covers(front: CoverFamily, back: CoverFamily): BookCovers =
        BookCovers(
            front = BookCover(styleId = "front-${front.rawValue}"),
            back = BookCover(styleId = "back-${back.rawValue}"),
            frontStyles = CoverFamily.entries.map { style(it, CoverFace.Front) },
            backStyles = CoverFamily.entries.map { style(it, CoverFace.Back) },
            photos = emptyList(),
            stats = emptyList(),
        )

    /**
     * La 4e « dessin » va avec la 1ère « dessin », et avec elle seule — même
     * quand deux familles partagent la composition de repli.
     */
    @Test
    fun theMatchingBackIsTheOneOfTheSameFamily() {
        val chosen = covers(front = CoverFamily.Drawing, back = CoverFamily.Default)
        assertTrue(chosen.isMatched(style(CoverFamily.Drawing, CoverFace.Back), on = CoverFace.Back))
        assertFalse(chosen.isMatched(style(CoverFamily.Elegant, CoverFace.Back), on = CoverFace.Back))
        assertFalse(chosen.isMatched(style(CoverFamily.TravelBook, CoverFace.Back), on = CoverFace.Back))
    }

    @Test
    fun eachPlateSaysWhatItAccepts() {
        val assouline = covers(front = CoverFamily.Assouline, back = CoverFamily.Assouline)
        assertFalse(assouline.acceptsPhoto(on = CoverFace.Front), "Une palme, pas de photo.")
        assertTrue(assouline.acceptsText(on = CoverFace.Back))
        assertTrue(assouline.acceptsStats(on = CoverFace.Back))

        val byDefault = covers(front = CoverFamily.Default, back = CoverFamily.Default)
        assertTrue(byDefault.acceptsPhoto(on = CoverFace.Front))
        assertFalse(byDefault.acceptsText(on = CoverFace.Back), "Le trajet et les chiffres, pas de texte.")
        assertTrue(byDefault.acceptsStats(on = CoverFace.Back))

        val travel = covers(front = CoverFamily.TravelBook, back = CoverFamily.TravelBook)
        assertTrue(travel.acceptsPhoto(on = CoverFace.Back))
        assertFalse(travel.acceptsStats(on = CoverFace.Back))
        assertFalse(travel.acceptsStats(on = CoverFace.Front))
    }

    /**
     * Une famille que cette app ne connaît pas ne fait pas tomber le
     * catalogue : le style se décode, sans famille, et se dessine d'après sa
     * composition.
     */
    @Test
    fun anUnknownFamilyFallsBackToItsTreatment() {
        val json = """{"id":"front-collage","name":"Collage","treatment":"photo","tint":"ink","family":"collage"}"""
        val decoded = MemoBookJson.decodeFromString(CoverStyle.serializer(), json)
        assertNull(decoded.family)
        assertEquals(CoverTreatment.Photo, decoded.treatment)
        assertTrue(decoded.matches(style(null, CoverFace.Back, treatment = CoverTreatment.Photo).withInk))
    }

    @Test
    fun aKnownFamilyDecodes() {
        val json = """{"id":"back-photo-drawing","name":"Photo-dessin","treatment":"plain","tint":"paper","family":"photo-drawing"}"""
        assertEquals(CoverFamily.PhotoDrawing, MemoBookJson.decodeFromString(CoverStyle.serializer(), json).family)
    }

    /** Le même style, à l'aplat encre — pour comparer au style décodé. */
    private val CoverStyle.withInk: CoverStyle
        get() = CoverStyle(id = id, name = name, treatment = treatment, tint = CoverTint.Ink, family = family)
}
