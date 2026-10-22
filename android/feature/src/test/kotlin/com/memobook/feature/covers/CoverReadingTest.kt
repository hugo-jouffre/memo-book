package com.memobook.feature.covers

import com.memobook.core.BookCover
import com.memobook.core.CoverFace
import com.memobook.core.CoverPhoto
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** Ce que les gabarits lisent d'un plat (`CoverTemplates.kt`) : qui, quand, le récit, les photos. */
class CoverReadingTest {
    private val front = BookCover(styleId = "drawing", title = "Philippines", subtitle = "  Maylis, Claire et Augustin \n\nAoût 2026 ")
    private val back = BookCover(styleId = "drawing", subtitle = "Trois semaines.\n\n  Des ferries à l’aube.  \n\n\n\nEl Nido.")

    /** La signature se lit en deux temps : sa première ligne est qui, sa dernière quand. */
    @Test fun theSignatureSaysWhoAndWhen() {
        val reading = CoverReading(CoverFace.Front, front, companion = null, photo = null, gallery = emptyList())
        assertEquals(listOf("Maylis, Claire et Augustin", "Août 2026"), reading.signatureLines)
        assertEquals("Maylis, Claire et Augustin", reading.authors)
        assertEquals("Août 2026", reading.`when`)
        assertEquals("Philippines", reading.frontTitle)

        // Une seule ligne : c'est quand, et personne n'est nommé.
        val single = CoverReading(CoverFace.Front, front.copy(subtitle = "Août 2026"), null, null, emptyList())
        assertNull(single.authors)
        assertEquals("Août 2026", single.`when`)
    }

    /** Le dos lit la signature et le titre du devant, et coupe son récit en paragraphes. */
    @Test fun theBackReadsTheFront() {
        val reading = CoverReading(CoverFace.Back, back, companion = front, photo = null, gallery = emptyList())
        assertEquals("Maylis, Claire et Augustin", reading.authors)
        assertEquals("Philippines", reading.frontTitle)
        assertEquals(listOf("Trois semaines.", "Des ferries à l’aube.", "El Nido."), reading.backParagraphs)
    }

    /** La photo choisie passe en tête, sans doublon. */
    @Test fun theChosenPhotoComesFirst() {
        val gallery = listOf(CoverPhoto("a"), CoverPhoto("b"), CoverPhoto("c"))
        val reading = CoverReading(CoverFace.Front, front, null, photo = CoverPhoto("b"), gallery = gallery)
        assertEquals(listOf("b", "a", "c"), reading.photos.map { it.id })
        assertEquals(listOf("a", "b", "c"), CoverReading(CoverFace.Front, front, null, null, gallery).photos.map { it.id })
    }
}
