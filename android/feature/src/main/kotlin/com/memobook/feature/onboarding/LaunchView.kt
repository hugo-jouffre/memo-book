package com.memobook.feature.onboarding

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import com.memobook.design.BrandMark
import com.memobook.design.BrandMarkBackdrop
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.SwiftMotion
import com.memobook.design.isReduceMotionEnabled
import com.memobook.feature.LaunchCopy
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay

/**
 * L'écran de lancement : le M de MemoBook s'écrit d'un trait sur le crème,
 * puis **reste** derrière le contenu. Le jumeau de `Onboarding/LaunchView.swift`.
 *
 * **Le signe seul, et rien d'autre** (Hugo, 18/09/2026). Il est dessiné par
 * [BrandMarkBackdrop], la même vue que l'accueil garde en fond : au passage,
 * l'opacité du M descend de 50 % à 20 %, et le M ne bouge pas.
 *
 * **La courbe du tracé est celle du fichier de marque** ([BrandMark.drawingEasing]) :
 * un départ enlevé, une fin qui se pose — le trait paraît écrit à la main.
 *
 * @param onDrawingFinished appelé quand le M a fini de s'écrire. C'est
 *   l'appelant qui fait disparaître l'écran, pour pouvoir attendre en plus ce
 *   qu'il a à charger.
 */
@Composable
fun LaunchView(developerDetails: String? = null, onDrawingFinished: () -> Unit = {}) {
    val reduceMotion = isReduceMotionEnabled()
    // Part du trait déjà tracée, et le signe qui se pose : il arrive à 97 % et
    // se détend jusqu'à sa taille.
    val drawn = remember { Animatable(if (reduceMotion) 1f else 0f) }
    val settle = remember { Animatable(if (reduceMotion) 1f else 0.97f) }

    LaunchedEffect(Unit) {
        if (reduceMotion) {
            // Pas de tracé : le signe est là, on laisse le temps de le voir.
            delay(400)
            onDrawingFinished()
            return@LaunchedEffect
        }
        coroutineScope {
            async { settle.animateTo(1f, SwiftMotion.smooth(duration = 1.2f)) }
            // Court : c'est un lancement, pas une intro.
            drawn.animateTo(1f, tween(DRAW_DURATION_MS, easing = BrandMark.drawingEasing))
        }
        onDrawingFinished()
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MemoBookColor.background)
            .semantics { contentDescription = LaunchCopy.ACCESSIBILITY_LABEL },
    ) {
        BrandMarkBackdrop(
            progress = drawn.value,
            opacity = BrandMarkBackdrop.drawingOpacity,
            scale = settle.value,
        )
        if (developerDetails != null) {
            BrandText(
                text = developerDetails,
                style = MemoBookFont.caption,
                color = MemoBookColor.inkMuted,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .navigationBarsPadding()
                    .padding(MemoBookSpacing.screenMargin),
            )
        }
    }
}

/** La durée du tracé, celle d'iOS (`drawDuration`, 950 ms). */
private const val DRAW_DURATION_MS = 950

@Preview(widthDp = 360, heightDp = 640)
@Composable
private fun LaunchViewPreview() {
    LaunchView(developerDetails = "API · http://10.0.2.2:3000 ↪︎ production")
}
