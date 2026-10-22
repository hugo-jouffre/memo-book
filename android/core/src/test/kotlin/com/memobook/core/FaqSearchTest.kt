package com.memobook.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * La **recherche du support** : ce qui répond à ce qu'on tape. Mêmes cas que
 * `FaqSearchTests.swift`.
 *
 * Elle se teste ici et non à l'écran parce que c'est une règle, pas un
 * dessin — et parce que les quarante-cinq questions sont dans le binaire.
 */
class FaqSearchTest {
    @Test
    fun anEmptyQueryKeepsEverything() {
        val query = FaqQuery("   ")
        assertTrue(query.isEmpty)
        for (category in Faq.topics) {
            assertEquals(category.entries.size, category.filtered(query)?.entries?.size)
        }
    }

    @Test
    fun ignoresCaseAndAccents() {
        // On tape « reglage » et on trouve « réglage » : personne ne pense à
        // faire marcher ça, et tout le monde le remarque quand ça ne marche
        // pas.
        val query = FaqQuery("CARNET")
        assertTrue(query.matches("Où est mon carnet ?"))
        assertTrue(FaqQuery("impression").matches("L’imprèssion du carnet"))
    }

    @Test
    fun everyWordNarrowsTheResults() {
        // Ajouter un mot **réduit**, comme partout ailleurs.
        val one = FaqQuery("carnet")
        val two = FaqQuery("carnet papier")

        assertTrue(one.matches("Le carnet arrive en combien de temps ?"))
        assertFalse(two.matches("Le carnet arrive en combien de temps ?"))
        assertTrue(two.matches("Le papier du carnet est-il recyclé ?"))
    }

    @Test
    fun searchesInsideTheAnswerAndNotOnlyTheQuestion() {
        // Quelqu'un qui tape un mot précis cherche une phrase, pas un titre.
        // On prend une question au hasard et un mot de sa réponse.
        val entry = assertNotNull(Faq.entries.firstOrNull { e -> e.answer.any { it.length > 40 } })
        val firstAnswer = assertNotNull(entry.answer(FaqVariables.current).firstOrNull())
        val word = assertNotNull(
            firstAnswer
                .split(Regex("[^\\p{L}]+"))
                .firstOrNull { it.length > 6 }
        )

        assertTrue(entry.matches(FaqQuery(word)), "« $word » devrait trouver sa réponse")
    }

    @Test
    fun aCategoryTitleBringsItsWholePack() {
        // On cherche souvent le rayon avant l'article.
        val photos = assertNotNull(Faq.topics.firstOrNull { it.title.contains("photo", ignoreCase = true) })
        val filtered = photos.filtered(FaqQuery("photo"))
        assertEquals(photos.entries.size, filtered?.entries?.size)
    }

    @Test
    fun aPackWithNothingToSayDisappears() {
        // Un titre de section sans lignes dessous se lit comme un écran cassé.
        val nonsense = FaqQuery("zzzzqqq")
        for (category in Faq.topics) {
            assertNull(category.filtered(nonsense))
        }
    }

    @Test
    fun variablesAreResolvedBeforeComparing() {
        // On doit pouvoir trouver « 16 » alors que le texte dit
        // `{{nb_pages_min}}`.
        val entry = FaqEntry(
            id = "faq.test.pages",
            question = "Combien de pages minimum ?",
            answer = listOf("Un Carnet relié fait au moins {{nb_pages_min}} pages."),
        )
        assertTrue(entry.matches(FaqQuery("16")))
    }
}
