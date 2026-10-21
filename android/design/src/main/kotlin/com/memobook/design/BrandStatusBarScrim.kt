package com.memobook.design

import androidx.compose.animation.core.EaseInOut
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.max
import androidx.compose.ui.unit.min

/**
 * Le voile posé sous la barre d'état — l'heure, la batterie, la caméra — pour
 * que ce qui défile dessous s'y **dissolve** au lieu de passer sous les
 * chiffres. Jumeau de `BrandStatusBarScrim.swift`.
 *
 * Sans lui, le texte d'un écran qui défile venait se lire à travers l'heure
 * (T210). Hugo l'a voulu **sur tous les écrans**, photos pleine page comprises,
 * et « de la hauteur de la barre d'état, dégradé sur le bord inférieur »
 * (06/10/2026). **Sauf l'accueil d'un voyage** (08/10/2026) : sa photo pleine
 * page reprend le haut de l'écran, et le dégradé crème s'y lisait comme une
 * bande étrange.
 *
 * C'est donc le frère de [BrandFooterScrim], retourné, et il en reprend les
 * deux règles :
 *
 * - **Il reste translucide** — le même crème à 90 % : on voit passer ce qui
 *   défile, on ne le lit plus.
 * - **Il ne dépasse pas la barre d'état.** Le fondu est pris *dans* sa
 *   hauteur, sur son bord bas, et non ajouté dessous : au repos, l'en-tête d'un
 *   écran commence juste sous l'heure, et un fondu qui déborderait pâlirait sa
 *   flèche de retour.
 *
 * Il se pose **une fois**, à la racine (l'enveloppe ci-dessous) : tous les
 * écrans de l'app sont dans la même pile, et une feuille de la marque s'arrête
 * bien avant la barre d'état. Seul un écran présenté en plein écran (le
 * paywall) doit le reposer chez lui.
 *
 * @param height la hauteur de la barre d'état — [DeviceScreen.topSafeInset].
 */
@Composable
fun BrandStatusBarScrim(height: Dp, modifier: Modifier = Modifier) {
    val fade = BrandStatusBarScrim.fadeHeight(height)
    val veil = MemoBookColor.background.copy(alpha = BrandFooterScrim.OPACITY)
    // Aucun toucher : le voile n'a pas de geste, ce qui est dessous les garde.
    Column(
        modifier
            .fillMaxWidth()
            .clearAndSetSemantics {},
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(max(0.dp, height - fade))
                .background(veil),
        )
        Box(
            Modifier
                .fillMaxWidth()
                .height(fade)
                .background(Brush.verticalGradient(listOf(veil, MemoBookColor.background.copy(alpha = 0f)))),
        )
    }
}

/**
 * Pose le voile de la barre d'état par-dessus [content] — le
 * `.brandStatusBarScrim(isVisible:)` d'iOS. À poser sur la racine d'un écran
 * qui occupe tout l'écran, bord à bord, pas sur chaque écran d'une pile.
 *
 * La hauteur se lit sur la barre d'état du système : 24 dp environ, davantage
 * sous une découpe de caméra, rien quand la barre est cachée.
 *
 * @param isVisible faux sous un écran dont la photo monte, pleine page,
 *   jusque sous l'heure — l'accueil d'un voyage (Hugo, 08/10/2026). Le voile
 *   s'y efface en fondu, et revient de même à l'écran suivant.
 */
@Composable
fun BrandStatusBarScrim(modifier: Modifier = Modifier, isVisible: Boolean = true, content: @Composable () -> Unit) {
    val opacity by animateFloatAsState(if (isVisible) 1f else 0f, tween(250, easing = EaseInOut), label = "scrim")
    Box(modifier) {
        content()
        BrandStatusBarScrim(
            height = DeviceScreen.topSafeInset(),
            modifier = Modifier
                .align(Alignment.TopCenter)
                .graphicsLayer { alpha = opacity },
        )
    }
}

object BrandStatusBarScrim {
    /**
     * La hauteur du fondu, au plus. Sous une découpe de caméra, l'heure reste
     * sous l'aplat ; sous une barre courte, le fondu se réduit à proportion
     * ([fadeHeight]) pour ne pas l'atteindre.
     */
    val maximumFadeHeight: Dp = MemoBookSpacing.s

    /** Le fondu pour une barre de [height] : au plus [maximumFadeHeight], au plus un tiers de la barre. */
    fun fadeHeight(height: Dp): Dp = max(0.dp, min(maximumFadeHeight, height / 3))
}

@Preview(name = "Voile de la barre d’état", widthDp = 390, heightDp = 600)
@Composable
private fun BrandStatusBarScrimPreview() {
    BrandStatusBarScrim(Modifier.background(MemoBookColor.background)) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = MemoBookSpacing.screenMargin),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        ) {
            repeat(30) { index ->
                BrandText("Ligne $index — le texte passe sous l’heure sans s’y lire", MemoBookFont.body)
            }
        }
    }
}
