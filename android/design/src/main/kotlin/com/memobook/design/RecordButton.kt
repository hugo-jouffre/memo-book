package com.memobook.design

import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.EaseInOut
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import kotlin.math.PI

/**
 * Le bouton d'enregistrement — l'élément central du cœur produit. Jumeau de
 * `RecordButton.swift`.
 *
 * Un disque vert, le micro du jeu de marque, et un mot dessous. **Il ne change
 * pas de couleur en enregistrant** : le rouge de Dictaphone dit « attention,
 * ça tourne », alors que dans MemoBook enregistrer est l'état normal, celui
 * qu'on cherche. Ce qui change, c'est le mot — « Start », puis « Envoyer » —
 * et le fait que le disque se met à respirer.
 *
 * **« Envoyer », pas « Stop ».** Appuyer sur le disque pendant qu'on parle
 * referme le micro *et* envoie le vocal dans la conversation : un « Stop »
 * laissait croire qu'on ne faisait que s'arrêter (Hugo, 29/09/2026). En pause,
 * le disque dit « Reprendre » — et il reprend, il n'envoie pas.
 *
 * **Le micro reste le micro**, même en enregistrement : le carré « arrêter »
 * ferait croire qu'on manipule un magnétophone. Ici on parle à quelqu'un qui
 * écoute.
 *
 * Trois animations, et pas une de plus :
 *
 * - **au toucher**, le disque s'enfonce et rebondit ; c'est le seul retour
 *   tactile, il doit se sentir ;
 * - **en enregistrement**, il respire avec la voix — le niveau du micro le fait
 *   grossir de quelques pour cent, jamais plus, sinon la page entière bouge ;
 * - **un halo** part du bord et se dissout, en continu : c'est ce qui dit que
 *   le micro est ouvert quand personne ne parle.
 *
 * @param level le niveau du micro, de 0 à 1. C'est lui qui fait respirer le
 *   disque ; à 0 le bouton est simplement immobile.
 * @param isPaused la capture est suspendue. Le disque garde sa taille mais
 *   cesse de respirer — c'est ça qui distingue « en pause » de « en train
 *   d'écouter le silence ».
 */
@Composable
fun RecordButton(
    isRecording: Boolean,
    modifier: Modifier = Modifier,
    isPaused: Boolean = false,
    isBusy: Boolean = false,
    level: Double = 0.0,
    action: () -> Unit,
) {
    val reduceMotion = isReduceMotionEnabled()
    // Le disque de la maquette. Il suit la taille de police comme le reste :
    // c'est une cible tactile avant d'être un dessin.
    val diameter = scaled(128.dp)
    val iconSide = scaled(40.dp)

    // Le micro capte vraiment : ni arrêté, ni en pause.
    val isCapturing = isRecording && !isPaused
    // De 1 à 1,05 selon la voix. Volontairement minuscule : au-delà, le disque
    // pompe et la page se met à trembler autour de lui.
    val breathTarget = if (isCapturing && !reduceMotion) 1f + level.coerceIn(0.0, 1.0).toFloat() * 0.05f else 1f
    // Le ressort, et pas une courbe douce : c'est lui qui donne le rebond quand
    // la voix repart d'un coup.
    val breath by animateFloatAsState(breathTarget, SwiftMotion.spring(response = 0.32f, dampingFraction = 0.55f), label = "breath")

    // Le disque s'enfonce sous le doigt et **rebondit** en revenant. Un simple
    // fondu linéaire donnait un bouton mou ; le ressort lui donne sa matière.
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val press by animateFloatAsState(
        if (pressed) 0.94f else 1f,
        SwiftMotion.spring(response = 0.25f, dampingFraction = 0.5f),
        label = "press",
    )

    val label = when {
        isPaused -> "Reprendre"
        isRecording -> "Envoyer"
        else -> "Start"
    }
    val accessibilityLabel = when {
        isPaused -> "Reprendre l’enregistrement"
        isRecording -> "Envoyer le vocal"
        else -> "Enregistrer un souvenir"
    }

    // Le cadre ne bouge pas avec la respiration : le halo et le disque
    // débordent dedans, la mise en page autour reste fixe.
    Box(
        modifier
            .size(diameter * 1.25f)
            .graphicsLayer {
                scaleX = press
                scaleY = press
            }
            .clickable(
                interactionSource = interaction,
                indication = null,
                enabled = !isBusy,
                role = Role.Button,
                onClick = action,
            )
            .semantics { contentDescription = accessibilityLabel },
        contentAlignment = Alignment.Center,
    ) {
        if (isCapturing && !reduceMotion) Halo(Modifier.size(diameter))

        Box(
            Modifier
                .size(diameter)
                .graphicsLayer {
                    scaleX = breath
                    scaleY = breath
                }
                .background(MemoBookColor.action, CircleShape),
        )

        Box(Modifier.clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
            if (isBusy) {
                ActivitySpinner(MemoBookColor.onAction)
            } else {
                Column(
                    verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    // Un rebond court à chaque changement d'état : le micro
                    // « prend » quand on démarre. L'image ne change pas — c'est
                    // son échelle qui dit qu'il s'est passé quelque chose.
                    val iconScale by animateFloatAsState(
                        if (isCapturing) 1.08f else 1f,
                        SwiftMotion.spring(response = 0.3f, dampingFraction = 0.45f),
                        label = "mic",
                    )
                    Image(
                        painter = painterResource(R.drawable.icon_mic),
                        contentDescription = null,
                        colorFilter = ColorFilter.tint(MemoBookColor.onAction),
                        modifier = Modifier
                            .size(iconSide)
                            .graphicsLayer {
                                scaleX = iconScale
                                scaleY = iconScale
                            },
                    )
                    // Le mot change, pas sa place : un fondu croisé, pas un
                    // remplacement sec.
                    Crossfade(label, animationSpec = tween(200, easing = EaseInOut), label = "label") { word ->
                        BrandText(word, MemoBookFont.label, color = MemoBookColor.onAction)
                    }
                }
            }
        }
    }
}

/**
 * Le halo qui part du disque et se dissout. Il vit **derrière** le disque,
 * donc on n'en voit que ce qui dépasse : un anneau qui s'éloigne.
 *
 * Il part dès qu'il est posé ; sur iOS, il attendait le passage à
 * l'enregistrement (`onChange`), et un bouton qui s'ouvrait déjà en train
 * d'écouter n'en avait pas.
 */
@Composable
private fun Halo(modifier: Modifier) {
    val transition = rememberInfiniteTransition(label = "halo")
    val spread by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(2000, easing = EaseOut), RepeatMode.Restart),
        label = "spread",
    )
    Box(
        modifier
            .graphicsLayer {
                scaleX = 1f + 0.25f * spread
                scaleY = 1f + 0.25f * spread
                alpha = 1f - spread
            }
            .background(MemoBookColor.action.copy(alpha = 0.25f), CircleShape),
    )
}


@Preview(locale = "fr-rFR", name = "Repos", widthDp = 390, heightDp = 400)
@Composable
private fun RecordButtonIdlePreview() {
    Box(Modifier.fillMaxSize().background(MemoBookColor.listeningBackground), contentAlignment = Alignment.Center) {
        RecordButton(isRecording = false) {}
    }
}

@Preview(locale = "fr-rFR", name = "Enregistrement", widthDp = 390, heightDp = 400)
@Composable
private fun RecordButtonRecordingPreview() {
    Box(Modifier.fillMaxSize().background(MemoBookColor.listeningBackground), contentAlignment = Alignment.Center) {
        RecordButton(isRecording = true, level = 0.7) {}
    }
}

@Preview(locale = "fr-rFR", name = "En pause", widthDp = 390, heightDp = 400)
@Composable
private fun RecordButtonPausedPreview() {
    Box(Modifier.fillMaxSize().background(MemoBookColor.listeningBackground), contentAlignment = Alignment.Center) {
        RecordButton(isRecording = true, isPaused = true) {}
    }
}
