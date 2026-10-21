package com.memobook.design

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.tween
import androidx.compose.foundation.IndicationNodeFactory
import androidx.compose.foundation.interaction.InteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.node.DelegatableNode
import androidx.compose.ui.node.DrawModifierNode
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.pow

// Le mouvement et le retour tactile de SwiftUI, partagés par les composants
// portés — comme `Platform.kt`, des pièces du système sans jumeau dans
// `MemoBookDesign`.

/**
 * Les courbes de SwiftUI, pour que les composants portés bougent à l'allure de
 * leurs jumeaux. `.smooth` et `.snappy` sont des ressorts décrits par une durée
 * perçue et un rebond : raideur (2π / durée)², amortissement 1 − rebond.
 */
internal object SwiftMotion {
    /** `.smooth(duration:)` : sans rebond. */
    fun <T> smooth(duration: Float): SpringSpec<T> = springWithBounce(duration, bounce = 0f)

    /** `.snappy(duration:extraBounce:)` : le léger rebond de SwiftUI (0,15), plus `extraBounce`. */
    fun <T> snappy(duration: Float, extraBounce: Float = 0f): SpringSpec<T> = springWithBounce(duration, bounce = 0.15f + extraBounce)

    /** `.spring(response:dampingFraction:)` : le ressort de SwiftUI, décrit par sa période et son amortissement. */
    fun <T> spring(response: Float, dampingFraction: Float): SpringSpec<T> =
        androidx.compose.animation.core.spring(
            dampingRatio = dampingFraction,
            stiffness = (2 * PI / response).pow(2).toFloat(),
        )

    private fun <T> springWithBounce(duration: Float, bounce: Float): SpringSpec<T> = spring(response = duration, dampingFraction = 1f - bounce)

    /** `.easeOut` de SwiftUI. */
    val easeOut = CubicBezierEasing(0f, 0f, 0.58f, 1f)

    /** `.easeInOut` de SwiftUI. */
    val easeInOut = CubicBezierEasing(0.42f, 0f, 0.58f, 1f)
}

/**
 * Le `.buttonStyle(.plain)` de SwiftUI : ni fond ni contour, et le contenu
 * pâlit un instant sous le doigt, comme un bouton du système. Le même 0,7 que
 * le `PressStyle` de [BrandButton].
 */
internal object PlainButtonIndication : IndicationNodeFactory {
    override fun create(interactionSource: InteractionSource): DelegatableNode = PlainPressNode(interactionSource)

    override fun equals(other: Any?): Boolean = other === this

    override fun hashCode(): Int = System.identityHashCode(this)
}

private class PlainPressNode(private val source: InteractionSource) : Modifier.Node(), DrawModifierNode {
    private val alpha = Animatable(1f)
    private val layer = Paint()

    override fun onAttach() {
        coroutineScope.launch {
            val presses = mutableListOf<PressInteraction.Press>()
            source.interactions.collect { interaction ->
                when (interaction) {
                    is PressInteraction.Press -> presses += interaction
                    is PressInteraction.Release -> presses -= interaction.press
                    is PressInteraction.Cancel -> presses -= interaction.press
                }
                val target = if (presses.isEmpty()) 1f else 0.7f
                launch { alpha.animateTo(target, tween(120, easing = SwiftMotion.easeOut)) }
            }
        }
    }

    override fun ContentDrawScope.draw() {
        val value = alpha.value
        if (value >= 1f) {
            drawContent()
            return
        }
        layer.alpha = value
        drawContext.canvas.saveLayer(Rect(Offset.Zero, size), layer)
        drawContent()
        drawContext.canvas.restore()
    }
}
