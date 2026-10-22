package com.memobook.design

import androidx.annotation.DrawableRes
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import java.text.NumberFormat

/**
 * Le compteur « − 2 + » de la commande. Jumeau de `BrandStepper.swift`.
 *
 * **Un composant et non deux boutons posés autour d'un nombre** : les deux
 * cercles doivent faire la même taille, tomber à la même distance du chiffre,
 * et garder leur cible tactile même quand le dessin fait 43. C'est exactement
 * ce qu'on rate en le réécrivant. Le compteur du système impose son propre
 * dessin, que la maquette ne dessine nulle part.
 *
 * ```kotlin
 * BrandStepper(value = draft.copies, onDecrement = { … }, onIncrement = { … })
 * ```
 *
 * @param canDecrement le « − » répond-il encore. À `false` il **reste visible
 *   mais grisé** : un bouton qui disparaît au minimum fait sauter la mise en
 *   page d'un cran à chaque bout de course.
 */
@Composable
fun BrandStepper(
    value: Int,
    modifier: Modifier = Modifier,
    canDecrement: Boolean = true,
    canIncrement: Boolean = true,
    onDecrement: () -> Unit,
    onIncrement: () -> Unit,
) {
    // Le cercle suit le corps de texte : à taille accessible, le compteur
    // grandit avec le reste de l'écran au lieu de rester un jeton minuscule.
    val side = scaled(43.dp)
    val spoken = NumberFormat.getIntegerInstance().format(value)
    Row(
        modifier
            // Une seule cible pour TalkBack, qui porte les deux gestes en
            // actions — l'équivalent du balayage vertical que VoiceOver attend
            // d'un compteur.
            .clearAndSetSemantics {
                contentDescription = "Nombre d’exemplaires"
                stateDescription = spoken
                customActions = listOfNotNull(
                    CustomAccessibilityAction("Ajouter un exemplaire") {
                        onIncrement()
                        true
                    }.takeIf { canIncrement },
                    CustomAccessibilityAction("Retirer un exemplaire") {
                        onDecrement()
                        true
                    }.takeIf { canDecrement },
                )
            },
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StepperButton(R.drawable.system_minus, isEnabled = canDecrement, isFilled = false, side, onDecrement)

        // Le chiffre roule d'une valeur à l'autre plutôt que de se remplacer :
        // c'est le seul endroit de l'écran qui bouge quand on touche « + », il
        // doit se voir. Il monte quand on ajoute, descend quand on retire.
        val motion = SwiftMotion.snappy<IntOffset>(0.25f)
        val fade = SwiftMotion.snappy<Float>(0.25f)
        AnimatedContent(
            targetState = value,
            // Une largeur tenue par le gabarit le plus large : sans elle, passer
            // de 9 à 10 décalerait les deux cercles.
            modifier = Modifier.widthIn(min = side * 0.9f),
            transitionSpec = {
                val rising = targetState > initialState
                (slideInVertically(motion) { if (rising) it / 2 else -it / 2 } + fadeIn(fade)) togetherWith
                    (slideOutVertically(motion) { if (rising) -it / 2 else it / 2 } + fadeOut(fade)) using
                    SizeTransform(clip = false)
            },
            contentAlignment = Alignment.Center,
            label = "nombre",
        ) { shown ->
            BrandText(
                NumberFormat.getIntegerInstance().format(shown),
                MemoBookFont.h2.copy(fontFeatureSettings = "tnum"),
                textAlign = TextAlign.Center,
            )
        }

        StepperButton(R.drawable.system_plus, isEnabled = canIncrement, isFilled = true, side, onIncrement)
    }
}

/**
 * Un cercle du compteur. Le « + » est un aplat vert, le « − » un contour :
 * c'est la maquette, et c'est juste — ajouter est l'action qu'on propose.
 * Les symboles « plus » et « minus » d'iOS, redessinés, au tiers du cercle.
 */
@Composable
private fun StepperButton(
    @DrawableRes symbol: Int,
    isEnabled: Boolean,
    isFilled: Boolean,
    side: Dp,
    action: () -> Unit,
) {
    val opacity by animateFloatAsState(if (isEnabled) 1f else 0.35f, SwiftMotion.smooth(0.2f), label = "disponible")
    Box(
        Modifier
            .graphicsLayer { alpha = opacity }
            // La cible tactile ne descend jamais sous le minimum, quelle que
            // soit la taille du dessin.
            .sizeIn(minWidth = MemoBookSpacing.minimumTapTarget, minHeight = MemoBookSpacing.minimumTapTarget)
            .clickable(
                interactionSource = null,
                indication = PlainButtonIndication,
                enabled = isEnabled,
                role = Role.Button,
                onClick = action,
            ),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(side)
                .then(
                    if (isFilled) {
                        Modifier.background(MemoBookColor.action, CircleShape)
                    } else {
                        Modifier.border(1.5.dp, MemoBookColor.action, CircleShape)
                    },
                ),
            contentAlignment = Alignment.Center,
        ) {
            Image(
                painter = painterResource(symbol),
                contentDescription = null,
                colorFilter = ColorFilter.tint(if (isFilled) MemoBookColor.onAction else MemoBookColor.action),
                modifier = Modifier.size(side * 0.32f),
            )
        }
    }
}

@Preview(locale = "fr-rFR", name = "Compteur")
@Composable
private fun BrandStepperPreview() {
    var value by remember { mutableIntStateOf(2) }
    Box(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.s),
    ) {
        BrandStepper(
            value = value,
            canDecrement = value > 1,
            canIncrement = value < 20,
            onDecrement = { value -= 1 },
            onIncrement = { value += 1 },
        )
    }
}
