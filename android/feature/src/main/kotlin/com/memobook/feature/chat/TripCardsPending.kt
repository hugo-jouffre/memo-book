package com.memobook.feature.chat

import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.IndicationNodeFactory
import androidx.compose.foundation.interaction.InteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.node.DelegatableNode
import androidx.compose.ui.node.DrawModifierNode
import androidx.compose.ui.node.invalidateDraw
import com.memobook.design.SwiftMotion
import kotlinx.coroutines.launch

// À brancher : Home/TripCards.swift (`CardPressStyle`).
//
// Le lot de l'accueil porte cette pièce (`com.memobook.feature.home.CardPressStyle`) ;
// la conversation l'emploie sous son nom Swift — la capsule de l'aperçu, les
// puces de suggestion, la pastille « Retourner en bas », celle du contexte du
// voyage. Ce qui est écrit ici en est une version minimale, au dessin d'iOS.
// L'intégrateur supprime ce fichier à la fusion et importe la vraie depuis
// `com.memobook.feature.home`.

/**
 * Une carte s'enfonce légèrement sous le doigt, sans changer d'opacité : c'est
 * du papier, pas un bouton — `scaleEffect(0.985)` et `.smooth(duration: 0.18)`
 * sur iOS. Le `ButtonStyle` devient une indication.
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
                val target = if (presses.isEmpty()) 1f else 0.985f
                launch { scale.animateTo(target, SwiftMotion.smooth(0.18f)) { invalidateDraw() } }
            }
        }
    }

    override fun ContentDrawScope.draw() {
        val value = scale.value
        if (value == 1f) {
            drawContent()
        } else {
            scale(value, pivot = Offset(size.width / 2, size.height / 2)) { this@draw.drawContent() }
        }
    }
}
