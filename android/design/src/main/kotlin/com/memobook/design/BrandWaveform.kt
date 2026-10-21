package com.memobook.design

import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * La forme d'onde de MemoBook, sous ses deux emplois : ce qu'on est en train
 * de dire, et ce qu'on a déjà dit. Jumeau de `BrandWaveform.swift`.
 *
 * Ce n'est jamais une visualisation du fichier — c'est le **retour du micro**,
 * puis la trace de ce retour. D'où le parti pris de la maquette, des barres
 * pleines et espacées plutôt qu'une courbe : on lit le rythme de la voix d'un
 * coup d'œil, pas sa forme d'onde.
 *
 * | Emploi | Ce qu'on passe | Ce qu'on voit |
 * |---|---|---|
 * | **En direct**, pendant qu'on parle | `BrandWaveform(live = …)` | une frise qui **glisse** : la voix arrive par la droite et pousse le reste |
 * | **Un vocal terminé** | `BrandWaveform(levels = …)` | les niveaux relevés, la partie jouée teintée |
 *
 * Les deux s'appellent par le **nom** de leur premier argument, comme
 * `init(live:)` et `init(levels:)` sur iOS : sans lui, Kotlin ne saurait pas
 * lequel on veut.
 *
 * **Les deux ne se dessinent pas de la même façon, et c'est nécessaire.** Un
 * vocal terminé peut compter des centaines d'échantillons : il passe par un
 * `Canvas`, qui les rééchantillonne. La frise en direct, elle, est une rangée
 * de capsules — une par **position** —, parce que c'est cette identité de
 * position qui fait que seule la *hauteur* s'anime et que le tout glisse au
 * lieu de sauter.
 *
 * **Les niveaux d'un vocal terminé ne s'inventent pas.** L'enregistreur ne
 * publie qu'un niveau instantané : c'est au modèle de l'écran de les accumuler
 * pendant l'enregistrement. Un relevé vide donne une ligne plate, et c'est
 * honnête — une forme d'onde décorative, identique pour tous les vocaux,
 * dirait quelque chose de faux sur ce qui a été dit.
 *
 * Le dessin ne dit rien à TalkBack : la durée, ou « ça enregistre », est déjà
 * annoncée par ce qui l'entoure.
 *
 * @param levels les niveaux relevés pendant l'enregistrement, dans l'ordre du
 *   temps. Vide donne une ligne plate.
 * @param progress de 0 à 1, la position de lecture. Les barres avant elle
 *   prennent [playedTint].
 */
@Composable
fun BrandWaveform(
    levels: List<Double>,
    modifier: Modifier = Modifier,
    progress: Double = 0.0,
    tint: Color = MemoBookColor.inkMuted,
    playedTint: Color = MemoBookColor.ink,
) {
    val clampedProgress = progress.coerceIn(0.0, 1.0)
    // `Canvas` plutôt qu'une rangée de capsules : une bulle vocale peut porter
    // une centaine de barres, et autant de nœuds à mesurer feraient ramer le
    // défilement du fil.
    Canvas(
        modifier
            .fillMaxWidth()
            .height(BrandWaveform.Bar.height)
            .clearAndSetSemantics {},
    ) {
        val bars = BrandWaveform.resample(levels, toFit = size.width.toDp().value)
        val played = (clampedProgress * bars.size).toInt()
        val barWidth = BrandWaveform.Bar.width.toPx()
        val step = barWidth + BrandWaveform.Bar.spacing.toPx()
        val floor = BrandWaveform.Bar.minimumHeight.toPx()
        bars.forEachIndexed { index, level ->
            val height = max(floor, size.height * level)
            drawRoundRect(
                color = if (index < played) playedTint else tint,
                topLeft = Offset(index * step, (size.height - height) / 2),
                size = androidx.compose.ui.geometry.Size(barWidth, height),
                cornerRadius = CornerRadius(barWidth / 2),
            )
        }
    }
}

/**
 * La frise du micro pendant qu'on parle.
 *
 * Elle **avance** : tant qu'il y a moins d'échantillons que de barres, elle se
 * remplit depuis la gauche ; ensuite chaque nouvel échantillon pousse les
 * autres. C'est le même geste dans la grande feuille d'enregistrement et dans
 * la barre d'envoi du chat, et c'est ce qui fait qu'on voit sa voix *arriver*
 * plutôt que clignoter.
 *
 * **Elle se mesure avant de se dessiner** (Hugo, 19/09/2026) : c'est la
 * largeur, et elle seule, qui dit combien de barres on dessine — avec un
 * nombre fixe, la frise s'arrêtait avant le bord droit de la feuille. Et elle
 * prend la largeur qu'on lui donne sans jamais en redemander : dans la barre
 * d'envoi du chat, une frise qui proposait sa largeur idéale s'élargissait à
 * chaque échantillon, jusqu'à pousser le fil hors de l'écran.
 *
 * @param live tous les niveaux relevés depuis le début, du plus ancien au plus
 *   récent. Seuls ceux qui tiennent dans la largeur sont dessinés.
 * @param size où la frise est posée. Voir [BrandWaveform.Size].
 * @param isDimmed la capture est en pause. Les barres restent en place — on
 *   n'efface pas ce qui a été dit — mais s'éteignent, pour qu'on ne les lise
 *   pas comme du son qui continue d'arriver.
 */
@Composable
fun BrandWaveform(
    live: List<Double>,
    modifier: Modifier = Modifier,
    size: BrandWaveform.Size = BrandWaveform.Size.Sheet,
    isDimmed: Boolean = false,
    tint: Color = MemoBookColor.action,
) {
    val sheet = size == BrandWaveform.Size.Sheet
    val sheetHeight = scaled(56.dp)
    val sheetBarWidth = scaled(4.dp)
    val sheetSpacing = scaled(5.dp)
    val barWidth = if (sheet) sheetBarWidth else BrandWaveform.Bar.width
    val barSpacing = if (sheet) sheetSpacing else BrandWaveform.Bar.spacing
    val maximumHeight = if (sheet) sheetHeight else BrandWaveform.Bar.height
    // La barre d'un silence. Pas zéro : une frise qui disparaît par endroits
    // se lit comme un trou dans l'enregistrement, alors que se taire une
    // seconde est normal.
    val minimumBarHeight = if (sheet) sheetBarWidth else BrandWaveform.Bar.minimumHeight
    val opacity by animateFloatAsState(if (isDimmed) 0.35f else 1f, tween(250, easing = EaseOut), label = "dim")

    BoxWithConstraints(
        modifier
            .fillMaxWidth()
            .height(maximumHeight)
            .graphicsLayer { alpha = opacity }
            .clearAndSetSemantics {},
    ) {
        val fitting = max(1, ((maxWidth + barSpacing) / (barWidth + barSpacing)).toInt())
        val shown = live.takeLast(fitting)
        Row(
            Modifier.fillMaxSize(),
            horizontalArrangement = Arrangement.spacedBy(barSpacing),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // La frise pousse depuis la gauche tant qu'elle n'est pas pleine.
            // Chaque barre est une position : seule sa hauteur change.
            for (level in shown) {
                val clamped = level.coerceIn(0.0, 1.0).toFloat()
                // Assez court pour suivre la voix, assez long pour que deux
                // échantillons se rejoignent au lieu de clignoter.
                val height by animateDpAsState(
                    minimumBarHeight + (maximumHeight - minimumBarHeight) * clamped,
                    tween(90, easing = LinearEasing),
                    label = "bar",
                )
                Box(
                    Modifier
                        .size(barWidth, height)
                        .background(tint, RoundedCornerShape(percent = 50)),
                )
            }
        }
    }
}

object BrandWaveform {
    /**
     * Où la frise est posée, ce qui décide de sa taille. Deux emplacements, et
     * un seul jeu de mesures pour chacun.
     */
    enum class Size {
        /**
         * La feuille d'enregistrement : des barres larges, hautes, et qui
         * grandissent avec la taille de police — c'est la seule chose que cet
         * écran montre, elle doit suivre les réglages d'accessibilité.
         */
        Sheet,

        /**
         * Une barre d'outils ou une bulle du fil. Mesures **fixes** : à cette
         * échelle, une forme d'onde est un dessin et non un mot, et la grossir
         * avec le texte la transformerait en histogramme — en poussant au
         * passage le chronomètre et le micro hors de la barre.
         */
        Bar,
    }

    /** Les mesures d'une frise de barre d'outils ou de bulle. Fixes, à dessein : voir [Size.Bar]. */
    internal object Bar {
        val width: Dp = 3.dp
        val spacing: Dp = 2.dp

        /** Le plancher d'une barre. Sans lui, un silence disparaît et la forme d'onde a l'air rognée. */
        val minimumHeight: Dp = 3.dp

        /**
         * La maquette dessine 22,6 pt ; on prend le cran de l'échelle juste
         * au-dessus (§2.2 de `docs/archive/ui-development-journal.md`).
         */
        val height: Dp = MemoBookSpacing.m
    }

    /**
     * Ramène un relevé au nombre de barres que la largeur peut tenir.
     *
     * C'est **la largeur disponible qui commande**, pas la donnée : un vocal de
     * trois minutes a des centaines d'échantillons, et les entasser donnerait
     * un aplat gris. Chaque barre dessinée prend le **maximum** de sa tranche,
     * et non la moyenne — une moyenne aplatit les pics, c'est-à-dire tout ce
     * qu'une forme d'onde a à montrer.
     *
     * @param toFit la largeur, en dp.
     */
    internal fun resample(levels: List<Double>, toFit: Float): List<Float> {
        val step = Bar.width.value + Bar.spacing.value
        val capacity = max(1, ((toFit + Bar.spacing.value) / step).toInt())
        if (levels.isEmpty()) return listOf(0f)
        if (levels.size <= capacity) return levels.map { it.coerceIn(0.0, 1.0).toFloat() }
        return (0 until capacity).map { slot ->
            val start = slot * levels.size / capacity
            val end = max(start + 1, (slot + 1) * levels.size / capacity)
            val peak = levels.subList(start, min(end, levels.size)).maxOrNull() ?: 0.0
            peak.coerceIn(0.0, 1.0).toFloat()
        }
    }

    /**
     * Un relevé d'exemple pour les aperçus. Une sinusoïde bruitée
     * **déterministe** : pas d'aléa, sinon deux captures d'un même aperçu ne
     * se superposent plus.
     */
    val sampleLevels: List<Double> = (0 until 64).map { index ->
        val base = sin(index / 3.1) * 0.35 + 0.5
        val grain = sin(index * 1.7) * 0.15
        (base + grain).coerceIn(0.08, 1.0)
    }
}

@Preview(locale = "fr-rFR", name = "Formes d’onde", widthDp = 390)
@Composable
private fun BrandWaveformPreview() {
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
    ) {
        BrandWaveform(levels = BrandWaveform.sampleLevels, progress = 0.35)
        BrandWaveform(levels = emptyList())
        BrandWaveform(live = BrandWaveform.sampleLevels, size = BrandWaveform.Size.Bar)
        BrandWaveform(live = BrandWaveform.sampleLevels.take(6), size = BrandWaveform.Size.Bar)
        BrandWaveform(live = BrandWaveform.sampleLevels, size = BrandWaveform.Size.Bar, isDimmed = true)
    }
}

@Preview(locale = "fr-rFR", name = "Frise de la feuille", widthDp = 390, heightDp = 500)
@Composable
private fun BrandWaveformSheetPreview() {
    Column(
        Modifier
            .fillMaxSize()
            .background(MemoBookColor.listeningBackground)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.l, Alignment.CenterVertically),
    ) {
        BrandWaveform(live = BrandWaveform.sampleLevels)
        BrandWaveform(live = BrandWaveform.sampleLevels, isDimmed = true)
        BrandWaveform(live = BrandWaveform.sampleLevels.take(8))
    }
}
