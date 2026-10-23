package com.memobook.core

// Les documents légaux de l'app — conditions d'utilisation, politique de
// confidentialité — recopiés du site memobook.fr. Le jumeau de
// `MemoBookCore/LegalDocument.swift`. Ce fichier porte la **forme** ; chaque
// document a le sien ([TermsOfUse], [PrivacyPolicy]).
//
// C'est du contenu **juridique**, et il se lit autrement que le reste de l'app :
//   - il **vouvoie**, seule exception à R9. Un contrat n'est pas une phrase de
//     l'interface ; on ne tutoie pas dans un contrat, et le texte du site est
//     celui qui engage. Recopié tel quel, signalé dans la fiche (T147).
//   - il dit « utilisateur », « consommateur », « produit » — le vocabulaire
//     du Code de la consommation et du RGPD, pas celui de la marque.
//
// Mêmes conventions typographiques que [Faq] : apostrophe `’`, espace
// insécable avant `?` et `!`, `…`.

/**
 * Un document légal : son titre d'écran et ses chapitres.
 *
 * @property id `cgu`, `confidentialite` — le préfixe des identifiants de chapitres.
 */
data class LegalDocument(
    val id: String,
    val title: String,
    val chapters: List<LegalChapter>,
) {
    /** Le chapitre que pointe un identifiant. */
    fun chapter(id: String): LegalChapter? = chapters.firstOrNull { it.id == id }
}

/**
 * Un chapitre : son numéro, son titre, et ce qu'il dit.
 *
 * @property id `<document>.slug` — immuable, comme [FaqEntry.id] : c'est lui
 *   qu'un écran pointerait pour ouvrir la page sur un chapitre précis.
 * @property number le numéro du chapitre, celui du site. Il **s'écrit** dans le
 *   titre de la carte (« Chapitre 4 — … ») et ordonne la page.
 * @property blocks le corps, bloc par bloc. Une liste et non une chaîne à `\n`,
 *   pour la même raison que [FaqEntry.answer] : l'écart entre deux blocs est une
 *   mesure du design system, et un intertitre n'est pas un paragraphe.
 */
data class LegalChapter(
    val id: String,
    val number: Int,
    val title: String,
    val blocks: List<LegalBlock>,
) {
    /**
     * Ce que la carte montre **repliée** : le texte courant du chapitre, d'un
     * seul tenant, que l'écran tronque à quelques lignes.
     *
     * Tout le texte et non le premier paragraphe : celui du chapitre 4 des
     * CGU tient en deux lignes et s'arrête sur deux-points — une carte qui
     * montrerait ça seul aurait l'air vide. Les intertitres n'y sont pas :
     * « 4.1 Utilisation gratuite » au milieu d'une phrase ne se lit pas.
     */
    val preview: String
        get() = texts(includingHeadings = false).joinToString(" ")

    /** Tous les textes du chapitre, quel que soit le bloc qui les porte. */
    fun texts(includingHeadings: Boolean = true): List<String> =
        blocks.flatMap { block ->
            when (block) {
                is LegalBlock.Heading -> if (includingHeadings) listOf(block.text) else emptyList()
                is LegalBlock.Paragraph -> listOf(block.text)
                is LegalBlock.Lines -> block.lines
                is LegalBlock.Bullets -> block.lines
            }
        }
}

/**
 * Un bloc du corps d'un chapitre.
 *
 * Le texte peut porter deux balises Markdown, et seulement celles-là : un
 * lien (`[…](mailto:…)`, `[…](https://…)`) et un demi-gras (`**…**`) pour
 * l'étiquette d'une ligne — « **Finalité :** … ».
 */
sealed interface LegalBlock {
    /** Un intertitre — « 4.1 Utilisation gratuite et crédit du jour », « Droit de rétractation ». */
    data class Heading(val text: String) : LegalBlock

    /** Un paragraphe. */
    data class Paragraph(val text: String) : LegalBlock

    /**
     * Des lignes serrées, sans puce : un bloc d'identité, une fiche
     * « données collectées / finalité / base légale / durée ».
     */
    data class Lines(val lines: List<String>) : LegalBlock

    /** Une liste à puces. */
    data class Bullets(val lines: List<String>) : LegalBlock
}

/**
 * Ce que les deux documents partagent : l'adresse à laquelle tout renvoie.
 * Écrite une fois, liée partout.
 */
object LegalContact {
    const val email = "contact@memo-book.com"
    const val emailLink = "[$email](mailto:$email)"
}
