package com.memobook.design

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Une carte qui se déplie : un titre, un chevron, et un contenu qui ne se
 * montre en entier que si on le demande. **La** carte des pages de texte long —
 * les chapitres des conditions d'utilisation et de la politique de
 * confidentialité. Jumeau de `BrandDisclosureCard.swift`.
 *
 * Repliée, la carte laisse voir le début du texte, assez pour savoir de quoi
 * parle le chapitre et pas assez pour le lire ; dépliée, elle passe au bleu
 * d'aplat de la marque et montre tout. Le bleu dit « celle-ci est ouverte »
 * d'un coup d'œil dans une colonne de neuf cartes crème.
 *
 * **Un seul contenu, qui se déroule** (01/10/2026). La carte dessine le contenu
 * entier **dans les deux états** et n'en montre qu'une hauteur : repliée, ses
 * premières lignes, la dernière en fondu ; dépliée, tout. Ce qui était lu reste
 * en place, seul ce qui manquait arrive, à mesure que la carte grandit.
 *
 * À ne pas confondre avec [BrandToggleCard] (un réglage et sa bascule) ni avec
 * [BrandRow] (une ligne qui mène ailleurs) : ici, on ne quitte pas l'écran et
 * rien ne se règle — on lit.
 *
 * @param title le titre de la carte — le libellé du bouton, pour TalkBack.
 * @param isExpanded l'état. Il appartient à l'écran, qui peut en ouvrir une par
 *   défaut ou les refermer toutes.
 * @param lineFont la police des lignes repliées — celle du texte courant du
 *   contenu. La carte en mesure la hauteur, taille de police comprise.
 * @param collapsedLineCount combien de lignes la carte repliée laisse voir.
 * @param content le contenu **entier**. La carte le coupe elle-même, et sait
 *   donc s'il a une suite : un contenu qui tient dans ses lignes perd le
 *   chevron et ne répond plus au toucher — un chevron qui ne déplie rien
 *   apprend à ne plus toucher les autres.
 */
@Composable
fun BrandDisclosureCard(
    title: String,
    isExpanded: Boolean,
    onIsExpandedChange: (Boolean) -> Unit,
    lineFont: TextStyle,
    modifier: Modifier = Modifier,
    collapsedLineCount: Int = 3,
    content: @Composable () -> Unit,
) {
    val lines = max(collapsedLineCount, 1)
    // Les lignes repliées, mesurées sur la police du texte : autant de lignes
    // d'un seul caractère. C'est leur hauteur — interligne compris, à la taille
    // de texte du moment — qui fait la fenêtre.
    val measurer = rememberTextMeasurer()
    val linesHeight = remember(measurer, lineFont, lines) {
        measurer.measure(List(lines) { "X" }.joinToString("\n"), lineFont).size.height
    }
    // La hauteur du contenu entier ; `null` avant la première mesure.
    var contentHeight by remember { mutableStateOf<Int?>(null) }

    // Y a-t-il une suite à montrer ? **Oui tant qu'on ne sait pas** : un chevron
    // qui apparaît après coup se verrait plus qu'un chevron qui part. Un pixel
    // d'écart, c'est l'arrondi d'une ligne, pas une ligne.
    val isExpandable = contentHeight?.let { it > linesHeight + 1 } ?: true
    // Dépliée, **et** dépliable : une carte sans suite ne se déplie pas, même si
    // l'écran l'avait ouverte par défaut.
    val showsExpanded = isExpandable && isExpanded

    // **Doux** : la carte s'allonge sans rebond, à l'allure d'une page qu'on
    // tourne, et non d'un tiroir qui claque.
    val motion: AnimationSpec<Float> =
        if (isReduceMotionEnabled()) tween(200, easing = SwiftMotion.easeInOut) else SwiftMotion.smooth(0.45f)
    val colorMotion = if (isReduceMotionEnabled()) {
        tween<Color>(200, easing = SwiftMotion.easeInOut)
    } else {
        SwiftMotion.smooth(0.45f)
    }
    val openness by animateFloatAsState(if (showsExpanded) 1f else 0f, motion, label = "dépliage")
    // Le fondu de la dernière ligne : présent repliée, effacé dépliée — et
    // jamais sur un contenu sans suite.
    val fade by animateFloatAsState(if (showsExpanded || !isExpandable) 0f else 1f, motion, label = "fondu")
    val background by animateColorAsState(
        if (showsExpanded) MemoBookColor.outline else MemoBookColor.surface,
        colorMotion,
        label = "aplat",
    )

    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)
    Column(
        modifier
            .fillMaxWidth()
            .background(background, shape)
            // Repliée, la carte est crème sur crème : c'est le filet qui la
            // détache du fond. Dépliée, l'aplat suffit — un filet bleu sur du
            // bleu ne se verrait pas, et un filet encre ferait un cadre.
            .border(1.dp, MemoBookColor.hairline.copy(alpha = MemoBookColor.hairline.alpha * (1f - openness)), shape)
            .padding(MemoBookSpacing.s),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        val chevronTint by animateColorAsState(
            if (showsExpanded) MemoBookColor.ink else MemoBookColor.inkMuted,
            colorMotion,
            label = "chevron",
        )
        DisclosureHeader(title, isExpandable, showsExpanded, openness, chevronTint) { onIsExpandedChange(!isExpanded) }

        // Le contenu entier, vu par une fenêtre qui s'agrandit. Le contenu se
        // pose toujours à sa hauteur naturelle ; c'est le cadre au-dessus de
        // lui qui change, et le masque qui coupe. Le texte suit sa carte d'un
        // bloc : il ne bouge pas, seule la fenêtre grandit.
        Layout(
            content = { Box(Modifier.onSizeChanged { contentHeight = it.height }) { content() } },
            modifier = Modifier
                .fillMaxWidth()
                // Ce qui dépasse de la fenêtre est masqué, et ne se touche pas :
                // un lien du texte caché ne répond pas par-dessus la carte suivante.
                .graphicsLayer {
                    clip = true
                    compositingStrategy = CompositingStrategy.Offscreen
                }
                .drawWithContent {
                    drawContent()
                    // La dernière ligne repliée s'efface : elle dit que le texte
                    // continue, comme les points de suspension qu'elle remplace.
                    if (fade > 0f) {
                        val fadeHeight = linesHeight.toFloat() / lines
                        drawRect(
                            brush = Brush.verticalGradient(
                                0f to Color.Black,
                                1f to Color.Black.copy(alpha = 1f - fade),
                                startY = size.height - fadeHeight,
                                endY = size.height,
                            ),
                            blendMode = BlendMode.DstIn,
                        )
                    }
                },
        ) { measurables, constraints ->
            val placeable = measurables.first().measure(
                constraints.copy(minHeight = 0, maxHeight = Constraints.Infinity),
            )
            val full = placeable.height
            val collapsed = min(full, linesHeight)
            // Rien de plus que les lignes avant la mesure du contenu : un
            // premier rendu qui montrerait tout se refermerait sous les yeux.
            val visible = (collapsed + (full - collapsed) * openness).roundToInt()
            layout(placeable.width, visible) { placeable.place(0, 0) }
        }
    }
}

/**
 * Le titre et le chevron, sur une seule cible : on ouvre en touchant
 * **n'importe où** sur la ligne du titre, pas seulement le chevron.
 */
@Composable
private fun DisclosureHeader(
    title: String,
    isExpandable: Boolean,
    showsExpanded: Boolean,
    openness: Float,
    chevronTint: Color,
    toggle: () -> Unit,
) {
    // Le chevron, à la taille de celui d'une `BrandRow` : c'est le même glyphe.
    val chevronSide = scaled(22.dp)
    val action = if (showsExpanded) "Replier" else "Déplier"
    Row(
        Modifier
            .fillMaxWidth()
            // Pas `enabled = false` : un chapitre qui tient en trois lignes
            // n'est pas un chapitre en moins. Le toucher ne passe simplement
            // pas, et TalkBack ne voit plus un bouton.
            .then(
                if (isExpandable) {
                    Modifier.clickable(
                        interactionSource = null,
                        indication = PlainButtonIndication,
                        onClickLabel = action,
                        role = Role.Button,
                        onClick = toggle,
                    )
                } else {
                    Modifier
                },
            )
            // Le geste — « Déplier », « Replier » — est le libellé du toucher :
            // seule la carte sait s'il y a une suite.
            .semantics(mergeDescendants = true) {
                heading()
                if (isExpandable) stateDescription = if (showsExpanded) "Dépliée" else "Repliée"
            },
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        verticalAlignment = Alignment.Top,
    ) {
        BrandText(title, MemoBookFont.cardTitle, Modifier.weight(1f))
        if (isExpandable) {
            // Le chevron du jeu de marque, tourné : vers le bas repliée (« il y
            // a la suite en dessous »), vers le haut dépliée. En haut de la
            // ligne, en face de la **première** ligne du titre ; sa boîte de 22
            // fait à peu près la hauteur d'une ligne de Sora 16.
            Image(
                painter = painterResource(R.drawable.icon_chevron),
                contentDescription = null,
                colorFilter = ColorFilter.tint(chevronTint),
                modifier = Modifier
                    .size(chevronSide)
                    .rotate(90f - 180f * openness),
            )
        }
    }
}

@Preview(locale = "fr-rFR", name = "Carte dépliable", widthDp = 390, heightDp = 640)
@Composable
private fun BrandDisclosureCardPreview() {
    var isFirstOpen by remember { mutableStateOf(true) }
    var isSecondOpen by remember { mutableStateOf(false) }
    val text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut " +
        "labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris " +
        "nisi ut aliquip ex ea commodo consequat."
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        BrandDisclosureCard("Chapitre 1 — Principes", isFirstOpen, { isFirstOpen = it }, MemoBookFont.taglineRegular) {
            BrandText(text, MemoBookFont.taglineRegular)
        }
        BrandDisclosureCard("Chapitre 2 — Règles", isSecondOpen, { isSecondOpen = it }, MemoBookFont.taglineRegular) {
            BrandText(text, MemoBookFont.taglineRegular)
        }
        BrandDisclosureCard("Chapitre 3 — Court", false, {}, MemoBookFont.taglineRegular) {
            BrandText("Une seule ligne.", MemoBookFont.taglineRegular)
        }
    }
}
