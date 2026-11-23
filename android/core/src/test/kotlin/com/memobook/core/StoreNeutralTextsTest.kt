package com.memobook.core

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

// **Un seul texte pour les deux stores** (Clara, 02/11/2026). Les CGU, la
// politique de confidentialité et la FAQ ne sont plus écrites du point de vue
// d'un téléphone : chaque phrase qui parle d'achat, de résiliation ou de
// remboursement nomme Android *et* iPhone. Son jumeau Swift,
// `StoreNeutralTextsTests.swift`, tient les mêmes assertions sur les mêmes
// phrases : c'est ainsi que les deux apps restent mot pour mot d'accord.

class StoreNeutralTextsTest {
    private fun LegalBlock.texts(): List<String> = when (this) {
        is LegalBlock.Heading -> listOf(text)
        is LegalBlock.Paragraph -> listOf(text)
        is LegalBlock.Lines -> lines
        is LegalBlock.Bullets -> lines
    }

    private val subscriptionChapter: List<String>
        get() = TermsOfUse.subscription.blocks.flatMap { it.texts() }

    private val faqSentences: List<String>
        get() = Faq.entries.flatMap { listOf(it.question) + it.answer() }

    /** Payer, résilier, se faire rembourser : les deux stores, à chaque fois. */
    @Test
    fun everySubscriptionRuleNamesBothStores() {
        val paying = subscriptionChapter.single { it.contains("prélevé") }
        assertTrue(paying.contains("Google Play") && paying.contains("App Store"), paying)

        val cancelling = subscriptionChapter.single { it.contains("gérer et résilier") }
        assertTrue(cancelling.contains("Play Store") && cancelling.contains("compte Apple"), cancelling)

        val refunding = subscriptionChapter.single { it.contains("remboursement au prorata") }
        assertTrue(refunding.contains("Google Play") && refunding.contains("reportaproblem"), refunding)
    }

    /** Un abonnement suit le compte, pas le téléphone. */
    @Test
    fun aSubscriptionFollowsTheAccountAcrossPhones() {
        assertTrue(
            subscriptionChapter.any {
                it.contains("store où il a été souscrit") && it.contains("même compte MemoBook")
            },
            subscriptionChapter.toString(),
        )
    }

    /**
     * Aucune phrase ne traite un store comme **le** store de l'app : dès qu'un
     * texte nomme l'un, il nomme l'autre. C'est la règle qui empêche les deux
     * versions de se reformer.
     */
    @Test
    fun noSentencePrefersOneStore() {
        // La liste des destinataires est faite d'une société par ligne : elle
        // ne peut pas nommer les deux à la fois, et `bothStoresAreRecipients`
        // la tient à part.
        val sentences = listOf(TermsOfUse.document, PrivacyPolicy.document)
            .flatMap { it.chapters }
            .filterNot { it.id == PrivacyPolicy.recipients.id }
            .flatMap { chapter -> chapter.blocks.flatMap { it.texts() } } + faqSentences

        for (sentence in sentences) {
            // « Apple » et « Google » seuls nomment aussi deux fournisseurs de
            // connexion : seuls les mots qui désignent un store comptent ici.
            val saysApple = sentence.contains("App Store") || sentence.contains("iPhone")
            val saysGoogle = sentence.contains("Google Play") || sentence.contains("Play Store") ||
                sentence.contains("Android")
            if (!saysApple && !saysGoogle) continue
            if (sentence.contains("reconnaissance vocale")) continue // propre à l'iPhone (2.3)
            assertTrue(saysApple && saysGoogle, "une seule plateforme nommée : $sentence")
        }
    }

    /** Les deux vendeurs d'abonnement sont déclarés comme destinataires. */
    @Test
    fun bothStoresAreRecipients() {
        val recipients = PrivacyPolicy.recipients.blocks.flatMap { it.texts() }
        assertTrue(recipients.any { it.startsWith("Apple") && it.contains("souscrit sur un iPhone") })
        assertTrue(recipients.any { it.contains("Google Play") && it.contains("Android") })
    }

    /**
     * **Ce que l'app lit d'une photo, la politique le dit** (T203) : sa date
     * de prise de vue et le nom du lieu — jamais la position, qui ne quitte
     * pas le téléphone (T280). Et le même texte sur les deux stores : c'est
     * « le service de cartographie de votre téléphone », pas celui de Google.
     */
    @Test
    fun thePolicyNamesWhatAPhotoCarries() {
        val section = PrivacyPolicy.collectedData.blocks.flatMap { it.texts() }

        val collecte = section.first { it.contains("Données collectées") && it.contains("vos photos") }
        assertTrue(collecte.contains("date de prise de vue"), collecte)
        assertTrue(collecte.contains("nom de l\u2019endroit"), collecte)

        val comment = section.first { it.contains("sur votre téléphone") }
        assertTrue(comment.contains("jamais des coordonnées"), comment)
        assertFalse(comment.contains("Apple") || comment.contains("Google"), comment)
    }

    /** La FAQ promet cinq ans ; la politique doit dire la même chose. */
    @Test
    fun thePolicyAndTheFaqAgreeOnFiveYears() {
        val conservation = PrivacyPolicy.collectedData.blocks.flatMap { it.texts() }
            .first { it.contains("Durée de conservation") && it.contains("tant que le voyage existe") }
        assertTrue(conservation.contains("au moins cinq ans"), conservation)

        val faq = Faq.entry("faq.donnees.conservation")?.answer().orEmpty()
        assertTrue(faq.any { it.contains("5 ans") }, faq.toString())
    }

    /** Le sélecteur de photos est celui du téléphone, quel qu'il soit. */
    @Test
    fun thePhotoAnswerSpeaksOfThePhone() {
        val answer = Faq.entry("faq.photos.provenance")?.answer().orEmpty()
        assertTrue(answer.any { it.contains("ton téléphone") }, answer.toString())
        assertFalse(answer.any { it.contains("de ton iPhone.") }, answer.toString())
    }
}
