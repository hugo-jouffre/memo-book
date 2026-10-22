package com.memobook.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

// La foire aux questions est du **contenu**, et le contenu se relit mal : une
// question ajoutée avec l'identifiant de sa voisine, une variable oubliée dans
// une phrase, un ordinal écrit à l'ancienne — rien de tout ça ne casse la
// compilation, et tout se voit en production.
//
// Ces règles-là viennent de la page Notion « FAQ in-app MemoBook », section
// « Notes d'implémentation ». Elles sont écrites ici parce que c'est le seul
// endroit qui puisse les tenir dans le temps. Mêmes cas que la suite « Foire
// aux questions » de `FaqTests.swift` ; la suite « Couvertures » du même
// fichier suit `BookCovers`.

class FaqTest {
    // Les identifiants

    /** Chaque identifiant est unique. */
    @Test
    fun identifiersAreUnique() {
        val ids = Faq.entries.map { it.id }
        assertEquals(ids.size, ids.toSet().size)
    }

    /**
     * Chaque identifiant suit faq.categorie.slug.
     *
     * « `faq.categorie.slug` immuable, porte les traductions, les deep links et
     * les statistiques. » C'est la forme qui compte : un identifiant à deux
     * segments ne saurait pas dire de quelle catégorie il vient.
     */
    @Test
    fun identifiersFollowTheirShape() {
        for (entry in Faq.entries) {
            val parts = entry.id.split(".").filter { it.isNotEmpty() }
            assertEquals(3, parts.size, "${entry.id} n’a pas trois segments")
            assertEquals("faq", parts.firstOrNull(), "${entry.id} ne commence pas par faq")
            assertTrue(
                entry.id.all { it.isLowerCase() || it == '.' || it == '-' || it.isDigit() },
                "${entry.id} porte une capitale ou un caractère inattendu",
            )
        }
    }

    /** Un identifiant retrouve sa question. */
    @Test
    fun entryIsFoundByIdentifier() {
        assertEquals("Combien de pages fait un carnet ?", Faq.entry("faq.carnet.pages")?.question)
        assertNull(Faq.entry("faq.inconnue.jamais-ecrite"))
    }

    // Les variables

    /**
     * Aucune réponse n’affiche une variable non résolue.
     *
     * « Les valeurs qui bougent sont des variables `{{…}}`, résolues à
     * l'affichage depuis une config distante, jamais écrites en dur. »
     */
    @Test
    fun noAnswerLeaksAVariable() {
        for (entry in Faq.entries) {
            for (paragraph in entry.answer(FaqVariables.current)) {
                assertTrue(
                    !paragraph.contains("{{"),
                    "${entry.id} laisse une variable non résolue : $paragraph",
                )
            }
        }
    }

    /** Le seuil de pages se résout à la valeur en vigueur. */
    @Test
    fun minimumPageCountResolves() {
        val entry = Faq.entry("faq.carnet.pages")
        val resolved = entry?.answer(FaqVariables(minimumPageCount = 24)) ?: emptyList()
        assertTrue(resolved.any { it.contains("minimum de 24 pages") })
    }

    /**
     * Le prix et le crédit du jour se résolvent à la valeur en vigueur : ils
     * vivent dans [FaqVariables], et changer le barème ne demande pas de
     * relire les réponses.
     */
    @Test
    fun pricingVariablesResolve() {
        val variables = FaqVariables(
            minimumPageCount = 16,
            monthlyPrice = "5,49 €",
            dailyCredit = "6 minutes",
            charactersPerMinute = "900 caractères",
        )
        val app = Faq.entry("faq.prix.app")?.answer(variables) ?: emptyList()
        assertTrue(app.any { it.contains("5,49 € par mois") })
        assertTrue(app.any { it.contains("6 minutes peuvent être racontées par jour") })

        val credit = Faq.entry("faq.prix.credit-du-jour")?.answer(variables) ?: emptyList()
        assertTrue(credit.any { it.contains("900 caractères écrits valent une minute") })

        val subscription = Faq.entry("faq.prix.abonnement")?.answer(variables) ?: emptyList()
        assertTrue(subscription.any { it.contains("5,49 € par mois") })
    }

    /**
     * Plus un mot de l’ancien modèle d’abonnement. Le crédit du jour a
     * remplacé les étapes offertes et l'abonnement à la semaine (Hugo,
     * 03/10/2026). Une réponse oubliée promettrait un modèle qui n'existe
     * plus — et c'est ce qu'App Review lit aussi.
     */
    @Test
    fun noTraceOfTheWeeklyModel() {
        val gone = listOf(
            "étapes offertes", "étape offerte", "par semaine", "chaque semaine",
            "1,99", "abonnements déduits", "limites de souvenirs",
            // La cagnotte est supprimée (Hugo, 06/10/2026, T230).
            "cagnotte",
        )
        for (entry in Faq.entries) {
            val text = (listOf(entry.question) + entry.answer(FaqVariables.current)).joinToString(" ")
            for (phrase in gone) {
                assertTrue(!text.contains(phrase), "${entry.id} parle encore de « $phrase » : $text")
            }
        }
        assertTrue(Faq.pricing.entries.any { it.id == "faq.prix.credit-du-jour" })
    }

    /**
     * Une variable inconnue reste écrite plutôt qu’effacée. Une phrase
     * amputée passerait inaperçue ; « {{delai}} » dans l'app se corrige.
     */
    @Test
    fun unknownVariableIsLeftInPlace() {
        val text = "Compte {{delai_livraison}} jours."
        assertEquals(text, FaqVariables.current.resolve(text))
    }

    // Le ton

    /**
     * Aucune réponse ne vouvoie. R9 : l'app tutoie, sans exception. Le
     * vouvoiement se glisse par les formes en « vous » et « votre », qui sont
     * les plus fréquentes.
     *
     * **Un « vous » pluriel n'est pas un vouvoiement** : « si vous êtes
     * plusieurs sur le voyage » (`faq.raconter.plusieurs-voix`) s'adresse aux
     * co-voyageurs ensemble, et c'est le texte de la page Notion (29/09/2026).
     */
    @Test
    fun nothingIsFormal() {
        val formal = listOf(" vous ", " votre ", " vos ", "Vous ", "Votre ")
        val plural = listOf("si vous êtes plusieurs")
        for (entry in Faq.entries) {
            var text = (listOf(entry.question) + entry.answer).joinToString(" ")
            for (phrase in plural) text = text.replace(phrase, "")
            for (form in formal) {
                assertTrue(!text.contains(form), "${entry.id} vouvoie : $text")
            }
        }
    }

    /**
     * Le vocabulaire interdit n’apparaît pas. Le vocabulaire de la page
     * Notion : « carnet », « souvenirs », « voyageurs ». Jamais « livre »,
     * jamais « utilisateur », jamais « client ».
     */
    @Test
    fun bannedVocabularyIsAbsent() {
        val banned = listOf("livre", "utilisateur", "client")
        for (entry in Faq.entries) {
            val text = (listOf(entry.question) + entry.answer).joinToString(" ").lowercase()
            for (word in banned) {
                assertTrue(!text.contains(word), "${entry.id} emploie « $word » : $text")
            }
        }
    }

    /**
     * « Carnet » ne prend plus de majuscule. T213 (Hugo, 06/10/2026) : plus
     * de majuscule à l'anglaise, « carnet » compris — c'était la plus
     * fréquente de la FAQ.
     */
    @Test
    fun carnetIsLowercase() {
        for (category in Faq.topics + Faq.contact) {
            assertTrue(!category.title.contains("Carnet"), "${category.id} : ${category.title}")
            for (entry in category.entries) {
                val text = (listOf(entry.question) + entry.answer).joinToString(" ")
                assertTrue(!text.contains("Carnet"), "${entry.id} écrit encore « Carnet » : $text")
            }
        }
    }

    /** Les apostrophes sont typographiques. */
    @Test
    fun apostrophesAreTypographic() {
        for (entry in Faq.entries) {
            val text = (listOf(entry.question) + entry.answer).joinToString(" ")
            assertTrue(!text.contains("'"), "${entry.id} porte une apostrophe droite")
        }
    }

    // La structure

    /** Les neuf sujets courants sont là, et le contact à part. */
    @Test
    fun sectionsAreComplete() {
        assertEquals(9, Faq.topics.size)
        assertTrue(Faq.topics.none { it.id == Faq.contact.id })
        assertEquals(2, Faq.contact.entries.size)
    }

    /** Aucune catégorie n’est vide. */
    @Test
    fun noCategoryIsEmpty() {
        for (category in Faq.topics + Faq.contact) {
            assertTrue(category.entries.isNotEmpty(), "${category.id} est vide")
        }
    }

    /**
     * Aucune réponse n’est vide. Sauf les deux entrées d'aide, « de type
     * action » sur la page Notion : elles ouvrent la modale « Nous contacter »
     * et n'ont pas de corps de réponse (29/09/2026).
     */
    @Test
    fun noAnswerIsEmpty() {
        val actions = Faq.contact.entries.map { it.id }.toSet()
        for (entry in Faq.entries) {
            if (entry.id !in actions) {
                assertTrue(entry.answer.isNotEmpty(), "${entry.id} n’a pas de réponse")
            }
            assertTrue(entry.question.isNotEmpty())
        }
    }
}
