package com.memobook.feature.bookpreview

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * **Le rythme de la page qui se monte** (Hugo, 10/11/2026) — « améliorer
 * l'animation de changement de la mise en page PDF pour la rendre plus longue,
 * plus lente, plus logique (ligne par ligne) ». Jumeau de
 * `BookCompositionCadenceTests.swift`, cas pour cas.
 *
 * Une chorégraphie ne se teste pas à l'œil une fois et pour toutes : c'est une
 * table de nombres, et c'est exactement ce qui se dérègle sans bruit quand on
 * déplace une pièce.
 */
class BookCompositionCadenceTest {
    /** Les huit lignes de texte, dans l'ordre où elles s'écrivent. */
    private val textLines = BookCompositionPiece.all
        .filter { it.kind == BookCompositionPiece.Kind.Bar && it.y > 0.2f }
        .sortedBy { it.start }

    // region Plus longue

    @Test
    fun `la page met une dizaine de secondes a se monter`() {
        // Elle en prenait 4,2, et c'est ce qui la faisait passer pour une
        // vignette qui clignote. On ne fige pas la valeur exacte — c'est un
        // réglage — mais le plancher, lui, est une promesse.
        assertTrue(BookCompositionPiece.timeline > 9f)
        assertTrue(BookCompositionPiece.timeline < 14f)
        // Le plancher de l'attente du modèle suit la chorégraphie, sans que
        // personne ait à recopier le nombre.
        assertEquals(
            BookCompositionPiece.timeline.toDouble(),
            BookCompositionLoop.assembly.inWholeMilliseconds / 1_000.0,
            0.01,
        )
    }

    // endregion

    // region Ligne par ligne

    @Test
    fun `chaque ligne est finie avant que la suivante commence`() {
        assertEquals(8, textLines.size)

        for ((previous, next) in textLines.zipWithNext()) {
            // À la seconde où la suivante part, la précédente est **écrite** :
            // c'est toute la différence entre « ligne par ligne » et un bloc
            // qui se remplit.
            val whenNextStarts = next.start / BookCompositionPiece.timeline
            assertEquals(
                "La ligne partie à ${previous.start} s n'est pas finie quand celle de ${next.start} s commence.",
                1f,
                BookCompositionPiece.settled(previous, whenNextStarts),
                0.001f,
            )
            // Et elles ne partent pas toutes en même temps : un demi-pas au
            // moins les sépare, sans quoi l'œil ne suit pas.
            assertTrue(next.start - previous.start > 0.4f)
        }
    }

    @Test
    fun `une ligne de texte s'ecrit au lieu d'arriver du hors-cadre`() {
        for (line in textLines) {
            assertEquals(BookCompositionPiece.Arrival.Written, line.arrival)
            assertEquals(0f, line.rotation, 0f)
        }
    }

    // endregion

    // region Ce qui arrive d'ailleurs

    @Test
    fun `seuls les elements colles voyagent et penchent`() {
        for (piece in BookCompositionPiece.all.filter { it.rotation != 0f }) {
            assertTrue(
                "Seul un élément collé penche — ${piece.kind} ne devrait pas.",
                piece.arrival is BookCompositionPiece.Arrival.Glued,
            )
        }
        // La carte, la photo et le tampon : trois pièces collées, et elles
        // arrivent **après** le texte, parce qu'on colle sur une page écrite.
        val glued = BookCompositionPiece.all.filter {
            it.arrival is BookCompositionPiece.Arrival.Glued && it.kind != BookCompositionPiece.Kind.Bookmark
        }
        assertEquals(3, glued.size)
        val lastLine = textLines.last()
        for (piece in glued) {
            assertTrue(piece.start >= lastLine.start + lastLine.span)
        }
    }

    // endregion

    @Test
    fun `rien n'a bouge a zero, tout est pose a un`() {
        for (piece in BookCompositionPiece.all) {
            assertEquals(0f, BookCompositionPiece.settled(piece, 0f), 0.001f)
            // Une pièce encore en vol à `progress == 1` ferait sauter le
            // passage à l'aperçu : la page doit être **exactement** finie.
            assertEquals(1f, BookCompositionPiece.settled(piece, 1f), 0.001f)
        }
    }
}
