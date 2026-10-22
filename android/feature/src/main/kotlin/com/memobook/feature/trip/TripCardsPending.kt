package com.memobook.feature.trip

import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.Image
import androidx.compose.foundation.IndicationNodeFactory
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.InteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.node.DelegatableNode
import androidx.compose.ui.node.DrawModifierNode
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.memobook.core.TripStats
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.SwiftMotion
import com.memobook.design.isAccessibilityTextSize
import com.memobook.design.scaled
import com.memobook.feature.home.TripStatItem
import com.memobook.feature.home.items
import kotlinx.coroutines.launch

// À brancher : Home/TripCards.swift (`TripStatsRow`, `homeCard()`, `CardPressStyle`).
//
// Le lot de l'accueil porte ces pièces ; l'écran du voyage les emploie sous
// leur nom Swift et leur signature probable — l'en-tête pose les compteurs sur
// la photo, les cartes d'étape prennent la coque et l'enfoncement des cartes
// de l'accueil. Ce qui est écrit ici en est une version minimale, au dessin
// d'iOS. L'intégrateur supprime ce fichier à la fusion et importe les vraies
// depuis `com.memobook.feature.home`.

/**
 * Durée, distance, photos — réparti sur la largeur d'une carte de l'accueil,
 * ou serré à gauche et teinté de blanc sur la photo d'un voyage.
 *
 * @param tint teinte unique de l'icône **et** du texte. `null` garde le
 *   deux-tons de la carte : icône estompée, texte en encre pleine.
 * @param isSpread répartis sur toute la largeur, ou serrés les uns contre les autres.
 */
@Composable
internal fun TripStatsRow(stats: TripStats, modifier: Modifier = Modifier, tint: Color? = null, isSpread: Boolean = true) {
    val items = stats.items
    if (items.isEmpty()) return
    if (isAccessibilityTextSize()) {
        // En taille accessible les trois compteurs ne tiennent plus sur une
        // ligne : ils s'empilent au lieu de se tronquer.
        Column(modifier, verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2)) {
            items.forEach { StatItem(it, tint) }
        }
    } else {
        Row(
            modifier,
            horizontalArrangement = if (isSpread) Arrangement.SpaceBetween else Arrangement.spacedBy(MemoBookSpacing.s),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            items.forEach { StatItem(it, tint) }
        }
    }
}

@Composable
private fun StatItem(item: TripStatItem, tint: Color?) {
    Row(
        Modifier.clearAndSetSemantics { contentDescription = item.text },
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(
            painterResource(item.kind.icon),
            contentDescription = null,
            colorFilter = ColorFilter.tint(tint ?: MemoBookColor.inkMuted),
            modifier = Modifier.size(scaled(16.dp)),
        )
        BrandText(item.text, MemoBookFont.label, color = tint ?: MemoBookColor.ink)
    }
}

/** La carte de l'accueil : surface blanche, rayon 20, un filet pour la décoller du crème du fond. */
internal fun Modifier.homeCard(): Modifier {
    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)
    return background(MemoBookColor.surface, shape)
        .border(1.dp, MemoBookColor.hairline, shape)
}

/**
 * Une carte s'enfonce légèrement sous le doigt, sans changer d'opacité : c'est
 * du papier, pas un bouton. Le `CardPressStyle` d'iOS, en indication.
 */
internal object CardPressStyle : IndicationNodeFactory {
    override fun create(interactionSource: InteractionSource): DelegatableNode = CardPressNode(interactionSource)

    override fun equals(other: Any?): Boolean = other === this

    override fun hashCode(): Int = System.identityHashCode(this)
}

private class CardPressNode(private val source: InteractionSource) : Modifier.Node(), DrawModifierNode {
    private val scale = Animatable(1f)

    override fun onAttach() {
        coroutineScope.launch {
            val presses = mutableListOf<PressInteraction.Press>()
            source.interactions.collect { interaction ->
                when (interaction) {
                    is PressInteraction.Press -> presses += interaction
                    is PressInteraction.Release -> presses -= interaction.press
                    is PressInteraction.Cancel -> presses -= interaction.press
                }
                launch { scale.animateTo(if (presses.isEmpty()) 1f else 0.985f, SwiftMotion.smooth(0.18f)) }
            }
        }
    }

    override fun ContentDrawScope.draw() {
        val value = scale.value
        if (value == 1f) {
            drawContent()
        } else {
            scale(value) { this@draw.drawContent() }
        }
    }
}
