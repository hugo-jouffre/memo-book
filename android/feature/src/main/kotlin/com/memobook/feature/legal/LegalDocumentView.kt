package com.memobook.feature.legal

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.UriHandler
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.memobook.core.LegalBlock
import com.memobook.core.LegalChapter
import com.memobook.core.LegalCopy
import com.memobook.core.LegalDocument
import com.memobook.core.PrivacyPolicy
import com.memobook.core.TermsOfUse
import com.memobook.design.BrandButton
import com.memobook.design.BrandDisclosureCard
import com.memobook.design.BrandScreenHeader
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.feature.LegalIntent

/**
 * Un document légal — les conditions d'utilisation, la politique de
 * confidentialité — chapitre par chapitre, une carte chacun. Jumeau de
 * `LegalDocumentView.swift`.
 *
 * **On y arrive par les deux lignes du groupe légal du profil.** La page ne
 * charge rien : le texte est celui du site, recopié dans [TermsOfUse] et
 * [PrivacyPolicy], et il appartient à l'app comme la foire aux questions.
 *
 * Chaque carte se déplie **sur place**, et non dans une feuille comme les
 * réponses du support : un contrat se lit d'une traite, chapitre après
 * chapitre, et ouvrir onze feuilles pour le parcourir en ferait un
 * formulaire. Repliée, la carte montre les trois premières lignes du
 * chapitre — **du chapitre lui-même**, intertitres et puces compris, et non
 * d'un résumé : c'est ce qui permet à la carte de dérouler la suite sans
 * redessiner ce qu'on a lu (01/10/2026, voir [BrandDisclosureCard]).
 *
 * **Rien n'est ouvert à l'arrivée, et un seul chapitre l'est à la fois**
 * (Clara, 26/09/2026). Le premier s'ouvrait tout seul, et les cartes bleues
 * s'accumulaient au fil de la lecture : la page ressemblait à un bug plutôt
 * qu'à un sommaire. Ouvrir un chapitre referme celui qu'on lisait.
 *
 * Le pied de page mène au support : quelqu'un qui lit les conditions cherche
 * souvent une réponse plus simple que le contrat, et la FAQ la porte. Il se
 * retire quand on arrive de l'écran d'entrée (T151) : sans compte, le support
 * n'est pas joignable, et la flèche de retour ramène à l'entrée.
 *
 * @param showsHelp « Besoin d'aide ? Découvrir notre FAQ ». Faux depuis l'écran d'entrée.
 */
@Composable
fun LegalDocumentView(
    document: LegalDocument,
    onBack: () -> Unit,
    showsHelp: Boolean = true,
    onIntent: (LegalIntent) -> Unit = {},
) {
    // Le chapitre ouvert, ou aucun. **Un seul** : ouvrir l'un referme l'autre
    // (Clara, 26/09/2026).
    var expandedChapter by rememberSaveable(document.id) { mutableStateOf<String?>(null) }

    Column(
        Modifier
            .fillMaxSize()
            .background(MemoBookColor.background)
            .verticalScroll(rememberScrollState())
            .windowInsetsPadding(WindowInsets.safeDrawing)
            .padding(horizontal = MemoBookSpacing.screenMargin)
            .padding(top = MemoBookSpacing.xs, bottom = MemoBookSpacing.l),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
    ) {
        BrandScreenHeader(document.title, onBack = onBack)

        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
            document.chapters.forEach { chapter ->
                val isExpanded = expandedChapter == chapter.id

                // **Un chapitre qui tient en trois lignes n'a rien à déplier** :
                // la carte le mesure elle-même et retire son chevron — « si le
                // contenu est trop long, on peut appuyer » (Hugo, 17/09/2026),
                // et pas autrement.
                BrandDisclosureCard(
                    title = LegalCopy.chapterTitle(chapter),
                    isExpanded = isExpanded,
                    onIsExpandedChange = { expands ->
                        if (expands) {
                            expandedChapter = chapter.id
                        } else if (expandedChapter == chapter.id) {
                            expandedChapter = null
                        }
                    },
                    lineFont = LegalText.font,
                    collapsedLineCount = PREVIEW_LINE_COUNT,
                ) {
                    LegalChapterBody(chapter, isExpanded)
                }
            }
        }

        if (showsHelp) Help(onIntent)
    }
}

/** Ce qu'une carte repliée laisse voir : trois lignes, comme la maquette. */
private const val PREVIEW_LINE_COUNT = 3

// MARK: - Le pied de page

/**
 * « Besoin d'aide ? Découvrir notre FAQ » — la question en sourdine à gauche,
 * le lien à droite, comme la maquette les pose.
 *
 * Le lien est celui du design system, en petite taille : la maquette le
 * dessine en vert, et `BrandButton.Style.Link` écrit à l'encre — un lien d'une
 * autre couleur serait un second bouton, et il n'y en a qu'un. Signalé (T148).
 */
@Composable
private fun Help(onIntent: (LegalIntent) -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(top = MemoBookSpacing.xs),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        BrandText(LegalCopy.helpPrompt, MemoBookFont.label, Modifier.alignByBaseline(), color = MemoBookColor.inkMuted)
        Spacer(Modifier.weight(1f))
        BrandButton(
            LegalCopy.helpLink,
            modifier = Modifier.alignByBaseline(),
            style = BrandButton.Style.Link,
            size = BrandButton.Size.Small,
        ) { onIntent(LegalIntent.OpenHelp) }
    }
}

// MARK: - Le corps d'un chapitre

/**
 * Les blocs d'un chapitre, les uns sous les autres.
 *
 * Les mêmes dans les deux états de la carte : seule la couleur change — en
 * sourdine replié, comme sur la maquette ; à l'encre déplié, pour le contraste
 * sur l'aplat bleu.
 */
@Composable
private fun LegalChapterBody(chapter: LegalChapter, isExpanded: Boolean) {
    val tone = if (isExpanded) LegalText.Tone.Full else LegalText.Tone.Preview
    val muted = if (isExpanded) MemoBookColor.ink else MemoBookColor.inkMuted
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
        chapter.blocks.forEach { block ->
            when (block) {
                is LegalBlock.Heading -> BrandText(
                    block.text,
                    MemoBookFont.tagline,
                    Modifier
                        // Un intertitre se rapproche de ce qu'il annonce, pas de
                        // ce qui le précède.
                        .padding(top = MemoBookSpacing.xs)
                        .semantics { heading() },
                    color = muted,
                )
                is LegalBlock.Paragraph -> LegalText(block.text, tone)
                is LegalBlock.Lines -> Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    block.lines.forEach { LegalText(it, tone) }
                }
                is LegalBlock.Bullets -> Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
                    block.lines.forEach { item ->
                        Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
                            BrandText("•", LegalText.font, Modifier.clearAndSetSemantics {}, color = muted)
                            LegalText(item, tone, Modifier.weight(1f))
                        }
                    }
                }
            }
        }
    }
}

/**
 * Un paragraphe d'un document légal, avec ses liens et ses étiquettes.
 *
 * Le Markdown est lu ici et nulle part ailleurs : le document écrit
 * `[adresse](mailto:adresse)` et `**Finalité :**`, et c'est ce qui fait de
 * l'adresse un lien qu'on touche et de l'étiquette un demi-gras. Le reste du
 * texte n'a aucun balisage.
 */
@Composable
private fun LegalText(markup: String, tone: LegalText.Tone, modifier: Modifier = Modifier) {
    val uriHandler = LocalUriHandler.current
    val text = remember(markup, uriHandler) { LegalText.resolved(markup, uriHandler) }
    BasicText(
        text,
        modifier.fillMaxWidth(),
        style = LegalText.font.copy(color = if (tone == LegalText.Tone.Preview) MemoBookColor.inkMuted else MemoBookColor.ink),
    )
}

private object LegalText {
    enum class Tone {
        /** Le début d'un chapitre replié : en sourdine, comme sur la maquette. */
        Preview,

        /** Le chapitre déplié, sur l'aplat bleu : à l'encre, pour le contraste. */
        Full,
    }

    /**
     * 14 et non 16 : c'est un texte qu'on parcourt, et onze chapitres au corps
     * de texte feraient trois écrans de plus. C'est aussi la police dont la
     * carte compte les lignes repliées.
     */
    val font: TextStyle = MemoBookFont.taglineRegular

    private val markup = Regex("""\*\*(.+?)\*\*|\[([^\]]+)]\(([^)]+)\)""")

    /**
     * Traduit `**…**` en portions de texte en demi-gras — le même passage que
     * `BrandNotice`, et pour la même raison : le gras est une **autre police**
     * (General Sans Semibold), pas un épaississement du tracé. Et
     * `[…](adresse)` en lien : **le lien seul est vert**, c'est la couleur de ce
     * qu'on peut toucher, partout dans l'app.
     *
     * Un lien qu'aucune app ne sait ouvrir — une adresse e-mail sur un
     * téléphone sans messagerie — ne fait rien, plutôt que de planter l'app.
     */
    fun resolved(text: String, uriHandler: UriHandler): AnnotatedString = buildAnnotatedString {
        var cursor = 0
        markup.findAll(text).forEach { match ->
            append(text.substring(cursor, match.range.first))
            val bold = match.groups[1]
            if (bold != null) {
                withStyle(MemoBookFont.tagline.toSpanStyle()) { append(bold.value) }
            } else {
                val label = match.groupValues[2]
                val url = match.groupValues[3]
                withLink(
                    LinkAnnotation.Url(url, TextLinkStyles(SpanStyle(color = MemoBookColor.action))) {
                        runCatching { uriHandler.openUri(url) }
                    },
                ) { append(label) }
            }
            cursor = match.range.last + 1
        }
        append(text.substring(cursor))
    }
}

@Preview(locale = "fr-rFR", name = "Conditions d’utilisation", widthDp = 390, heightDp = 844)
@Composable
private fun TermsOfUsePreview() {
    LegalDocumentView(TermsOfUse.document, onBack = {})
}

@Preview(locale = "fr-rFR", name = "Politique de confidentialité", widthDp = 390, heightDp = 844)
@Composable
private fun PrivacyPolicyPreview() {
    LegalDocumentView(PrivacyPolicy.document, onBack = {})
}
