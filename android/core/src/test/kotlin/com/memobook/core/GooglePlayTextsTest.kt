package com.memobook.core

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

// Les textes légaux et la FAQ d'Android disent Google Play (A8b, 23/10/2026).
// Apple et l'iPhone n'y restent que pour un abonnement **pris sur un iPhone** :
// le même compte MemoBook passe d'un téléphone à l'autre, et son abonnement
// reste chez le store qui l'a vendu.

class GooglePlayTextsTest {
    private fun LegalBlock.texts(): List<String> = when (this) {
        is LegalBlock.Heading -> listOf(text)
        is LegalBlock.Paragraph -> listOf(text)
        is LegalBlock.Lines -> lines
        is LegalBlock.Bullets -> lines
    }

    /**
     * Les CGU seulement : la politique de confidentialité est la même sur les
     * deux stores (23/10/2026), et parle d'Apple pour la connexion et les
     * notifications de l'iPhone.
     */
    private val legalSentences: List<String>
        get() = listOf(TermsOfUse.document)
            .flatMap { it.chapters }
            .flatMap { chapter -> chapter.blocks.flatMap { it.texts() } }

    private val faqSentences: List<String>
        get() = Faq.entries.flatMap { listOf(it.question) + it.answer() }

    /** L'abonnement se paie, se résilie et se rembourse par Google Play. */
    @Test
    fun theSubscriptionChapterNamesGooglePlay() {
        val chapter = TermsOfUse.subscription.blocks.flatMap { it.texts() }
        assertTrue(chapter.any { it.contains("payé via Google Play") })
        assertTrue(chapter.any { it.contains("Play Store") && it.contains("résilier") })
        assertTrue(chapter.any { it.contains("règles de Google Play") && it.contains("remboursement") })
    }

    /** Google rejoint les destinataires, à côté d'Apple pour un abonnement pris sur iPhone. */
    @Test
    fun googleIsARecipient() {
        val recipients = PrivacyPolicy.recipients.blocks.flatMap { it.texts() }
        assertTrue(recipients.any { it.contains("Google Play") })
        assertTrue(recipients.any { it.startsWith("Apple") && it.contains("souscrit sur un iPhone") })
    }

    /**
     * Dans les CGU et la FAQ d'Android, Apple et l'iPhone ne se disent plus
     * que d'un abonnement pris sur un iPhone — jamais comme le store de cette
     * app.
     */
    @Test
    fun appleIsOnlyNamedForAnIphoneSubscription() {
        for (sentence in legalSentences + faqSentences) {
            if (!sentence.contains("Apple") && !sentence.contains("iPhone")) continue
            assertTrue(
                sentence.contains("sur un iPhone") || sentence.contains("pris là-bas") ||
                    sentence.contains("Pris sur un iPhone"),
                sentence,
            )
        }
    }

    /** Le sélecteur de photos est celui du téléphone. */
    @Test
    fun thePhotoAnswerSpeaksOfThePhone() {
        val answer = Faq.entry("faq.photos.provenance")?.answer().orEmpty()
        assertFalse(answer.any { it.contains("iPhone") })
        assertTrue(answer.any { it.contains("ton téléphone") })
    }
}
