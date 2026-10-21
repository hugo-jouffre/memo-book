package com.memobook.design

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt

/**
 * La pastille de MemoBook : un mot ou deux, dans une capsule, posé à côté de
 * ce qu'il qualifie. C'est **la** pastille de l'app (jumeau de `BrandTagPill.swift`).
 *
 * Quatre tons, et quatre seulement :
 *
 * | Ton | Dessin | Ce qu'il dit |
 * |---|---|---|
 * | [Tone.Accent] | aplat lime | **l'abonnement** — « Illimité » |
 * | [Tone.Outlined] | contour vert | un état — ce que le voyage fait en ce moment |
 * | [Tone.Info] | contour bleu | un décompte, une précision — « ×3 », « À VENIR » |
 * | [Tone.AccentOutlined] | lime cerclé de vert | l'abonnement, quand il doit se voir de loin |
 *
 * Le rayon reste celui d'une capsule pour **tous** les tons (T67).
 *
 * @param isUppercased les **états** se crient en capitales (« EN COURS ») ; les
 *   décomptes et les soldes, non.
 * @param shrinksToFit la pastille se resserre plutôt que de pousser ce qui
 *   partage sa ligne — jusqu'à 80 %, sous quoi le libellé ne se lit plus d'un
 *   coup d'œil. Elle cède sur sa taille, jamais sur ses mots.
 */
@Composable
fun BrandTagPill(
    title: String,
    modifier: Modifier = Modifier,
    tone: BrandTagPill.Tone = BrandTagPill.Tone.Accent,
    isUppercased: Boolean = false,
    shrinksToFit: Boolean = false,
) {
    val shape = RoundedCornerShape(percent = 50)
    val border = tone.border
    // Aux tailles de texte accessibles, une pastille cesse d'imposer sa
    // largeur : « VOIR UN APERÇU DE TON CARNET → » doublait en AX3 et sortait
    // de l'écran. Passé ce seuil, elle se replie sur deux lignes.
    val wraps = !shrinksToFit && isAccessibilityTextSize()
    BrandText(
        text = if (isUppercased) title.uppercase() else title,
        style = if (isUppercased) MemoBookFont.overline.copy(letterSpacing = MemoBookFont.tracking) else MemoBookFont.overline,
        color = tone.foreground,
        maxLines = if (shrinksToFit) 1 else Int.MAX_VALUE,
        minimumScaleFactor = if (shrinksToFit) 0.8f else 1f,
        textAlign = TextAlign.Center,
        modifier = modifier
            .then(if (wraps) Modifier else Modifier.wrapContentWidth(unbounded = !shrinksToFit))
            .background(tone.background, shape)
            .then(if (border != null) Modifier.border(1.dp, border, shape) else Modifier)
            .padding(horizontal = MemoBookSpacing.xs, vertical = 4.dp),
    )
}

object BrandTagPill {
    enum class Tone(internal val foreground: Color, internal val background: Color, internal val border: Color?) {
        /** Lime plein : **l'abonnement**, et rien d'autre — voir [MemoBookColor.accent]. */
        Accent(MemoBookColor.ink, MemoBookColor.accent, null),

        /** Contour vert sur blanc. */
        Outlined(MemoBookColor.action, MemoBookColor.surface, MemoBookColor.action),

        /** Contour bleu sur blanc : un décompte, une précision. */
        Info(MemoBookColor.blueText, MemoBookColor.surface, MemoBookColor.blueText),

        /** Lime plein **et** cerclé de vert, texte vert : « ABONNÉE ». */
        AccentOutlined(MemoBookColor.action, MemoBookColor.accent, MemoBookColor.action),
    }
}

/**
 * **La** jauge de l'app : un rail, et ce qui est rempli dedans. Sans intitulé
 * ni annonce TalkBack, délibérément : c'est l'appelant qui sait ce que la barre
 * veut dire. Voir [BrandProgressBar] pour la version qui écrit sa légende.
 *
 * @param fraction de 0 à 1, bornée ici aussi.
 */
@Composable
fun BrandProgressTrack(
    fraction: Double,
    modifier: Modifier = Modifier,
    tone: BrandProgressTrack.Tone = BrandProgressTrack.Tone.Subtle,
) {
    val clamped = fraction.coerceIn(0.0, 1.0).toFloat()
    val shape = RoundedCornerShape(percent = 50)
    Box(
        modifier
            .fillMaxWidth()
            .height(MemoBookSpacing.progressBarHeight)
            .background(tone.rail, shape)
            .clearAndSetSemantics {},
    ) {
        // Une jauge à zéro disparaît, elle ne dessine pas un point.
        if (clamped > 0f) {
            Box(
                Modifier
                    .fillMaxWidth(clamped)
                    .fillMaxHeight()
                    .background(MemoBookColor.action, shape),
            )
        }
    }
}

object BrandProgressTrack {
    enum class Tone(internal val rail: Color) {
        /** Le filet de la marque : la jauge est posée **sur le crème**, information de coin d'œil. */
        Subtle(MemoBookColor.hairline),

        /** Le vert d'action à 15 % : la jauge est **dans** une carte blanche dont elle est le sujet. */
        Tinted(MemoBookColor.action.copy(alpha = 0.15f)),
    }
}

/**
 * L'avancement d'un carnet : ce qui est rempli, et ce qui reste. Un filet et
 * non une jauge épaisse : c'est une information de coin d'œil.
 *
 * @param label ce que la barre veut dire, en toutes lettres. **TalkBack ne lit
 *   que lui** : une barre sans mots ne s'annonce pas.
 */
@Composable
fun BrandProgressBar(fraction: Double, modifier: Modifier = Modifier, label: String? = null) {
    val clamped = fraction.coerceIn(0.0, 1.0)
    Column(
        modifier.semantics(mergeDescendants = true) {
            contentDescription = label ?: "Avancement du carnet"
            stateDescription = "${(clamped * 100).roundToInt()} %"
        },
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        label?.let { BrandText(it, MemoBookFont.caption, color = MemoBookColor.inkMuted) }
        BrandProgressTrack(clamped)
    }
}

/**
 * Le contour en pointillés des blocs « il n'y a rien ici, mais il y aura
 * quelque chose ». Le pointillé ne sert qu'à ça : un trait plein en ferait une
 * carte vide, ce qui est une autre idée.
 */
fun Modifier.brandDashedCard(
    color: Color = MemoBookColor.separator,
    cornerRadius: Dp = MemoBookSpacing.largeCornerRadius,
): Modifier = drawWithContent {
    drawContent()
    val stroke = 1.dp.toPx()
    drawRoundRect(
        color = color,
        topLeft = Offset(stroke / 2, stroke / 2),
        size = Size(size.width - stroke, size.height - stroke),
        cornerRadius = CornerRadius(cornerRadius.toPx()),
        style = Stroke(width = stroke, pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 4.dp.toPx()))),
    )
}

@Preview(locale = "fr-rFR", name = "Pastilles et jauge", widthDp = 390)
@Composable
private fun BrandTagPillPreview() {
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            BrandTagPill("Illimité")
            BrandTagPill("×1")
            BrandTagPill("En cours", tone = BrandTagPill.Tone.Outlined, isUppercased = true)
            BrandTagPill("Bientôt", tone = BrandTagPill.Tone.Info)
            BrandTagPill("Abonnée", tone = BrandTagPill.Tone.AccentOutlined, isUppercased = true)
        }
        BrandProgressBar(0.025, label = "5 souvenirs et 2/80 pages")
        Box(
            Modifier
                .fillMaxWidth()
                .brandDashedCard()
                .padding(MemoBookSpacing.l),
            contentAlignment = Alignment.Center,
        ) {
            BrandText("Tes voyages passés s’afficheront ici", MemoBookFont.body, color = MemoBookColor.inkMuted)
        }
    }
}
