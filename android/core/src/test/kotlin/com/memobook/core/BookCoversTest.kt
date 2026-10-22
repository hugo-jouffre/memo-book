package com.memobook.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/**
 * Les couvertures. Mêmes cas que la suite `BookCoversTests` de
 * `FaqTests.swift` (« Couvertures »).
 */
class BookCoversTest {
    /**
     * Un jeu minimal, monté ici plutôt qu'importé : le jeu d'essai de l'app
     * vit dans `:feature`, que ces tests ne voient pas — c'est la règle de
     * dépendance des modules, et elle est ce qui permet de tester `:core` sans
     * Android.
     */
    private val covers: BookCovers
        get() = BookCovers(
            front = BookCover(styleId = "front-photo", photoId = "photo-1", title = "ROME"),
            back = BookCover(
                styleId = "back-framed",
                statIds = listOf("stat-days", "stat-km", "stat-countries"),
            ),
            frontStyles = listOf(
                CoverStyle(id = "front-photo", name = "Photo", treatment = CoverTreatment.Photo, tint = CoverTint.Ink),
                CoverStyle(id = "front-sand", name = "Sable", treatment = CoverTreatment.Plain, tint = CoverTint.Sand),
            ),
            backStyles = listOf(
                CoverStyle(id = "back-sand", name = "Sable", treatment = CoverTreatment.Plain, tint = CoverTint.Sand),
                CoverStyle(id = "back-framed", name = "Cadre", treatment = CoverTreatment.Framed, tint = CoverTint.Paper),
            ),
            photos = listOf(CoverPhoto(id = "photo-1"), CoverPhoto(id = "photo-2")),
            stats = listOf(
                CoverStat(id = "stat-days", value = "21", label = "jours\nde voyage"),
                CoverStat(id = "stat-km", value = "2,3k", label = "km\nparcourus"),
                CoverStat(id = "stat-countries", value = "1", label = "pays\nvisité"),
                CoverStat(id = "stat-people", value = "27", label = "personnes\nrencontrées"),
            ),
        )

    /** Les ordinaux s’écrivent 1ère et 4e, comme la maquette (T91). */
    @Test
    fun facesUseTheMockupOrdinals() {
        assertEquals("1ère de couverture", CoverFace.Front.title)
        assertEquals("4e de couverture", CoverFace.Back.title)
    }

    /** L’indice lit et écrit le bon plat. */
    @Test
    fun subscriptReachesBothFaces() {
        var covers = covers
        covers = covers.with(CoverFace.Back, covers[CoverFace.Back].copy(title = "Dos"))
        assertEquals("Dos", covers.back.title)
        assertNotEquals("Dos", covers[CoverFace.Front].title)
    }

    /**
     * Le dos accepte trois ou quatre chiffres. La contrainte vient du gabarit :
     * sous trois, le bandeau imprimé a des colonnes vides ; au-delà de quatre,
     * les chiffres ne se lisent plus.
     */
    @Test
    fun statRangeIsThreeOrFour() {
        assertEquals(3..4, BookCovers.statRange)
        assertEquals(3, covers.back.statIds.size)
    }

    /** Les chiffres retenus sortent dans l’ordre choisi : c'est lui qui s'imprime, de gauche à droite. */
    @Test
    fun statSelectionKeepsItsOrder() {
        val covers = covers.let { it.copy(back = it.back.copy(statIds = listOf("stat-km", "stat-days", "stat-people"))) }
        assertEquals(listOf("stat-km", "stat-days", "stat-people"), covers.statSelection.map { it.id })
    }

    /** Un chiffre qui n’existe plus est simplement ignoré. */
    @Test
    fun unknownStatIsDropped() {
        val covers = covers.let { it.copy(back = it.back.copy(statIds = listOf("stat-days", "stat-supprimee", "stat-km"))) }
        assertEquals(listOf("stat-days", "stat-km"), covers.statSelection.map { it.id })
    }

    /** Chaque plat propose des styles, et son style est dedans. */
    @Test
    fun everyFaceHasItsStyles() {
        val covers = covers
        for (face in CoverFace.entries) {
            val styles = covers.styles(face)
            assertFalse(styles.isEmpty())
            assertTrue(
                styles.any { it.id == covers[face].styleId },
                "le style du plat ${face.rawValue} n’est pas dans son catalogue",
            )
        }
    }

    /** La pastille « assortie » suit le style choisi sur l’autre plat. */
    @Test
    fun matchedStyleFollowsTheOtherFace() {
        var covers = covers

        // Devant en photo pleine page : aucune quatrième ne s'accorde.
        covers = covers.copy(front = covers.front.copy(styleId = "front-photo"))
        assertTrue(covers.backStyles.filter { covers.isMatched(it, on = CoverFace.Back) }.isEmpty())

        // Devant en sable : c'est « Sable » au dos qui devient assortie — et
        // une seule.
        covers = covers.copy(front = covers.front.copy(styleId = "front-sand"))
        val matched = covers.backStyles.filter { covers.isMatched(it, on = CoverFace.Back) }
        assertEquals(listOf("back-sand"), matched.map { it.id })

        // Jamais dans l'autre sens : les styles de la 1ère ne portent pas la
        // pastille, même quand l'un va avec le dos choisi (Hugo, 12/10/2026).
        covers = covers.copy(back = covers.back.copy(styleId = "back-sand"))
        assertTrue(covers.frontStyles.filter { covers.isMatched(it, on = CoverFace.Front) }.isEmpty())
    }
}
