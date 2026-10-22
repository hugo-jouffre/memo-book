package com.memobook.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Les documents légaux sont du **contenu**, comme la foire aux questions, et
// se relisent aussi mal : un chapitre numéroté deux fois, un identifiant
// recopié de son voisin, une adresse de contact tapée avec une faute dans l'un
// des endroits où elle apparaît. Rien de tout ça ne casse la compilation.
// Mêmes cas que `LegalDocumentTests.swift` ; ses tests paramétrés deviennent
// une boucle sur les deux documents.

class LegalDocumentTest {
    /**
     * Les deux documents, passés à chaque règle : une règle qui ne tiendrait
     * que pour l'un des deux ne serait pas une règle.
     */
    private val documents = listOf(TermsOfUse.document, PrivacyPolicy.document)

    /** Les chapitres sont numérotés de 1 à n, dans l’ordre. */
    @Test
    fun chaptersAreNumberedInOrder() {
        for (document in documents) {
            assertEquals((1..document.chapters.size).toList(), document.chapters.map { it.number }, document.id)
        }
    }

    /** Chaque identifiant est unique et suit document.slug. */
    @Test
    fun identifiersAreUniqueAndWellFormed() {
        for (document in documents) {
            val ids = document.chapters.map { it.id }
            assertEquals(ids.size, ids.toSet().size, document.id)
            for (id in ids) {
                val parts = id.split(".").filter { it.isNotEmpty() }
                assertEquals(2, parts.size, id)
                assertEquals(document.id, parts.firstOrNull(), id)
            }
        }
    }

    /**
     * Chaque chapitre a un aperçu. Une carte repliée montre le début du
     * chapitre : il faut donc qu'il y ait du texte à montrer, et pas seulement
     * un intertitre.
     */
    @Test
    fun everyChapterHasAPreview() {
        for (document in documents) {
            for (chapter in document.chapters) {
                assertTrue(chapter.preview.isNotEmpty(), chapter.id)
            }
        }
    }

    /**
     * L’adresse de contact est toujours un lien. Elle est écrite une fois et
     * liée partout : aucun texte ne doit la porter **nue**, sans le lien qu'on
     * touche pour écrire.
     */
    @Test
    fun contactEmailIsAlwaysLinked() {
        for (document in documents) {
            for (chapter in document.chapters) {
                for (text in chapter.texts().filter { it.contains(LegalContact.email) }) {
                    assertTrue(text.contains(LegalContact.emailLink), "${chapter.id} : $text")
                }
            }
        }
    }

    /**
     * Les textes n’emploient que l’apostrophe typographique. Même convention
     * que la FAQ : l'apostrophe typographique, pas celle du clavier.
     */
    @Test
    fun textsUseTypographicApostrophe() {
        for (document in documents) {
            for (chapter in document.chapters) {
                assertTrue(!chapter.title.contains("'"), chapter.id)
                for (text in chapter.texts()) {
                    assertTrue(!text.contains("'"), "${chapter.id} : $text")
                }
            }
        }
    }

    /** Les demi-gras sont refermés : un `**` ouvert et jamais refermé s'afficherait tel quel dans l'app. */
    @Test
    fun emphasisIsBalanced() {
        for (document in documents) {
            for (chapter in document.chapters) {
                for (text in chapter.texts()) {
                    val marks = text.split("**").size - 1
                    assertTrue(marks % 2 == 0, "${chapter.id} : $text")
                }
            }
        }
    }

    /** Un chapitre se retrouve par son identifiant. */
    @Test
    fun chapterIsFoundById() {
        for (document in documents) {
            val first = document.chapters[0]
            assertEquals(first, document.chapter(first.id))
            assertNull(document.chapter("${document.id}.inconnu"))
        }
    }
}
