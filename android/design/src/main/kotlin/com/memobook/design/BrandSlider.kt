package com.memobook.design

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitHorizontalTouchSlopOrCancellation
import androidx.compose.foundation.gestures.horizontalDrag
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Le curseur de MemoBook : un rail, une poignée, et les crans nommés sous le
 * rail. Jumeau de `BrandSlider.swift`.
 *
 * **Ce n'est pas le curseur du système**, et ce n'est pas un caprice de dessin :
 * la maquette pose une poignée crème cerclée avec un point bleu au centre, un
 * rail de 6 et — surtout — **les valeurs écrites sous les crans**, celle du
 * moment en gras.
 *
 * **Ce qu'on perd en le dessinant, on le rend à la main.** Un curseur du
 * système est « réglable » pour TalkBack : on le sélectionne, et on monte ou
 * descend d'un cran. C'est ce que fait l'action `setProgress` ici — le geste
 * d'assistance est le même que partout ailleurs, à un dessin près.
 *
 * ```kotlin
 * BrandSlider(
 *     value = ratio,
 *     onValueChange = { ratio = it },
 *     bounds = 0..100,
 *     step = 25,
 *     ticks = listOf("0%", "25%", "50%", "75%", "100%"),
 *     voiceLabel = "Ratio média",
 *     leadingLabel = "Plus de texte",
 *     trailingLabel = "Plus de photos",
 * )
 * ```
 *
 * @param bounds le `in bounds` de Swift.
 * @param step le pas, **et l'écart entre deux crans écrits**. Les deux sont le
 *   même nombre : un curseur qui s'arrête ailleurs que sous une étiquette ferait
 *   douter de ce qu'on vient de choisir.
 * @param ticks les valeurs écrites sous le rail, de la borne basse à la haute.
 *   Autant d'entrées que de crans.
 * @param leadingLabel ce que dit la borne gauche — « Plus de texte ». `null`
 *   quand la ligne au-dessus du rail porte déjà une phrase entière, comme sur
 *   « Décorations & stickers ».
 * @param voiceValue comment TalkBack annonce la valeur. Par défaut le nombre nu ;
 *   « 50 % » ou « 2 décorations » valent mieux.
 */
@Composable
fun BrandSlider(
    value: Int,
    onValueChange: (Int) -> Unit,
    bounds: IntRange,
    step: Int,
    ticks: List<String>,
    voiceLabel: String,
    modifier: Modifier = Modifier,
    leadingLabel: String? = null,
    trailingLabel: String? = null,
    voiceValue: (Int) -> String = { "$it" },
) {
    val stride = max(1, step)
    val reduceMotion = isReduceMotionEnabled()
    val currentValue by rememberUpdatedState(value)
    val currentOnChange by rememberUpdatedState(onValueChange)
    val selectedTick = BrandSlider.selectedTick(value, bounds, stride, ticks.size)

    Column(
        modifier
            // **Un seul élément pour TalkBack**, et il est réglable : le rail, la
            // poignée et les étiquettes sont un seul contrôle, pas cinq textes à
            // parcourir un par un.
            .clearAndSetSemantics {
                contentDescription = voiceLabel
                stateDescription = voiceValue(value)
                progressBarRangeInfo = ProgressBarRangeInfo(
                    value.toFloat(),
                    bounds.first.toFloat()..bounds.last.toFloat(),
                    steps = max(0, (bounds.last - bounds.first) / stride - 1),
                )
                // Monter ou descendre d'un cran, comme le balayage vertical de
                // VoiceOver sur iOS.
                setProgress { target ->
                    val next = when {
                        target > value -> BrandSlider.moved(value, stride, bounds)
                        target < value -> BrandSlider.moved(value, -stride, bounds)
                        else -> value
                    }
                    if (next != value) onValueChange(next)
                    next != value
                }
            },
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug),
    ) {
        if (leadingLabel != null || trailingLabel != null) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
                if (leadingLabel != null) {
                    BrandText(leadingLabel, MemoBookFont.tagline, Modifier.weight(1f), color = MemoBookColor.inkMuted)
                }
                if (trailingLabel != null) {
                    BrandText(
                        trailingLabel,
                        MemoBookFont.tagline,
                        Modifier.weight(1f),
                        color = MemoBookColor.inkMuted,
                        textAlign = TextAlign.End,
                    )
                }
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs + 2.dp)) {
            // La poignée saute d'un cran à l'autre, elle ne glisse pas sous le
            // doigt : c'est le pas qui commande, et le petit ressort dit qu'on
            // vient d'en franchir un. Le remplissage la suit au même ressort.
            val position = animateFloatAsState(
                BrandSlider.fraction(value, bounds),
                if (reduceMotion) snap() else SwiftMotion.snappy(0.18f),
                label = "poignée",
            )
            var trackWidth by remember { mutableIntStateOf(0) }
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(BrandSlider.thumbSide)
                    .onSizeChanged { trackWidth = it.width }
                    // Le doigt se pose **n'importe où sur le rail** et la poignée
                    // vient à lui : viser une pastille de 24 au bout d'un rail de
                    // 342 est un jeu d'adresse, pas un réglage.
                    .pointerInput(bounds, stride) {
                        val thumb = BrandSlider.thumbSide.toPx()
                        fun follow(x: Float) {
                            val travel = size.width - thumb
                            if (travel <= 0f) return
                            val next = BrandSlider.stepped((x - thumb / 2) / travel, bounds, stride)
                            if (next != currentValue) currentOnChange(next)
                        }
                        awaitEachGesture {
                            val down = awaitFirstDown(requireUnconsumed = false)
                            follow(down.position.x)
                            val drag = awaitHorizontalTouchSlopOrCancellation(down.id) { change, _ -> change.consume() }
                            if (drag != null) {
                                follow(drag.position.x)
                                horizontalDrag(drag.id) { change ->
                                    follow(change.position.x)
                                    change.consume()
                                }
                            }
                        }
                    }
                    .drawBehind {
                        // La poignée reste **entière dans le cadre** : elle va de
                        // son rayon au bord opposé moins son rayon.
                        val track = BrandSlider.trackHeight.toPx()
                        val top = (size.height - track) / 2
                        val capsule = CornerRadius(track / 2)
                        drawRoundRect(MemoBookColor.hairline, Offset(0f, top), Size(size.width, track), capsule)
                        val thumb = BrandSlider.thumbSide.toPx()
                        val center = thumb / 2 + max(0f, size.width - thumb) * position.value
                        drawRoundRect(MemoBookColor.outline, Offset(0f, top), Size(center, track), capsule)
                    },
            ) {
                Box(
                    Modifier
                        .offset {
                            val travel = max(0, trackWidth - BrandSlider.thumbSide.roundToPx())
                            IntOffset((travel * position.value).roundToInt(), 0)
                        }
                        .size(BrandSlider.thumbSide)
                        .brandShadow(MemoBookShadow.Soft, CircleShape)
                        .background(MemoBookColor.surface, CircleShape)
                        .border(1.dp, MemoBookColor.hairline, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Box(
                        Modifier
                            .size(MemoBookSpacing.xs)
                            .background(MemoBookColor.outline, CircleShape),
                    )
                }
            }

            Row(Modifier.fillMaxWidth()) {
                ticks.forEachIndexed { index, tick ->
                    // Celui du moment est en gras : c'est **là** qu'on lit la
                    // valeur choisie, la poignée ne fait que la montrer.
                    val isSelected = index == selectedTick
                    val color by animateColorAsState(
                        if (isSelected) MemoBookColor.ink else MemoBookColor.inkMuted,
                        if (reduceMotion) snap() else SwiftMotion.snappy(0.18f),
                        label = "cran",
                    )
                    BrandText(
                        tick,
                        (if (isSelected) MemoBookFont.tagline else MemoBookFont.caption).copy(fontFeatureSettings = "tnum"),
                        Modifier.width(BrandSlider.tickWidth),
                        color = color,
                        textAlign = TextAlign.Center,
                        maxLines = 1,
                        minimumScaleFactor = 0.7f,
                    )
                    if (index < ticks.lastIndex) Spacer(Modifier.weight(1f))
                }
            }
        }
    }
}

/** Les mesures et le calcul du curseur, à part du dessin pour se tester seuls. */
internal object BrandSlider {
    /**
     * Diamètre de la poignée. **Fixe, hors taille de police** : c'est une cible
     * tactile et un dessin, pas du texte — et la faire grandir décalerait le rail
     * sous les étiquettes, qui, elles, grandissent d'un autre facteur.
     */
    val thumbSide = 24.dp
    val trackHeight = 6.dp

    /** Largeur réservée à chaque étiquette de cran : celle de la maquette, qui tient « 100 % ». */
    val tickWidth = 32.dp

    /** La part du rail à gauche de la poignée. */
    fun fraction(value: Int, bounds: IntRange): Float {
        val span = (bounds.last - bounds.first).toFloat()
        if (span <= 0f) return 0f
        return (value - bounds.first) / span
    }

    /**
     * L'étiquette sous laquelle la poignée se trouve. `null` si les crans ne
     * correspondent pas aux pas — l'appelant s'est trompé, mais l'écran ne doit
     * pas s'en trouver mal.
     */
    fun selectedTick(value: Int, bounds: IntRange, step: Int, tickCount: Int): Int? {
        val index = (value - bounds.first) / step
        return index.takeIf { it in 0 until tickCount }
    }

    /** La valeur sous le doigt, arrondie au pas et bornée — `set(fraction:)` de Swift. */
    fun stepped(ratio: Float, bounds: IntRange, step: Int): Int {
        val span = (bounds.last - bounds.first).toDouble()
        val raw = bounds.first + ratio.coerceIn(0f, 1f) * span
        val next = Math.round(raw / step).toInt() * step
        return next.coerceIn(bounds.first, bounds.last)
    }

    /** Un cran de plus ou de moins, borné — `move(by:)` de Swift. */
    fun moved(value: Int, delta: Int, bounds: IntRange): Int = (value + delta).coerceIn(bounds.first, bounds.last)
}

@Preview(name = "Curseur", widthDp = 390)
@Composable
private fun BrandSliderPreview() {
    var ratio by remember { mutableIntStateOf(50) }
    var decorations by remember { mutableIntStateOf(2) }
    Column(
        Modifier
            .background(MemoBookColor.surface)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xl),
    ) {
        BrandSlider(
            value = ratio,
            onValueChange = { ratio = it },
            bounds = 0..100,
            step = 25,
            ticks = listOf("0%", "25%", "50%", "75%", "100%"),
            voiceLabel = "Ratio média",
            leadingLabel = "Plus de texte",
            trailingLabel = "Plus de photos",
            voiceValue = { "$it pour cent de photos" },
        )
        BrandSlider(
            value = decorations,
            onValueChange = { decorations = it },
            bounds = 0..4,
            step = 1,
            ticks = listOf("0", "1", "2", "3", "4"),
            voiceLabel = "Quantité de décorations",
            leadingLabel = "Quantité de décorations par étape",
        )
    }
}
