package com.memobook.design

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.tooling.preview.Preview

/**
 * Le M posé en fond d'écran, au cadrage de la maquette de lancement. Jumeau de
 * `BrandMarkBackdrop.swift`.
 *
 * **Un seul cadrage pour deux écrans.** L'écran de lancement l'utilise pour
 * tracer le signe, l'accueil pour le garder derrière son contenu. Comme les
 * deux passent par cette vue, le M ne bouge pas d'un pixel au moment où l'un
 * remplace l'autre : seule son opacité change, et le passage se lit comme un
 * fondu du signe vers l'arrière-plan plutôt que comme un changement d'écran.
 *
 * Il est **fixe** : posé derrière une liste, il ne défile pas avec elle —
 * c'est un décor, pas un élément de la page. Il prend toute la place qu'on lui
 * donne (sous les barres du système, comme le `ignoresSafeArea` d'iOS, quand
 * l'écran est posé bord à bord), ne prend aucun toucher et ne dit rien à
 * TalkBack.
 *
 * @param progress part du trait déjà tracée. 1 pour un signe entier.
 * @param opacity franche pendant le tracé, discrète une fois le contenu posé —
 *   [BrandMarkBackdrop.drawingOpacity], [BrandMarkBackdrop.restingOpacity].
 * @param scale échelle du signe, pour le faire arriver et se poser.
 */
@Composable
fun BrandMarkBackdrop(progress: Float, opacity: Float, modifier: Modifier = Modifier, scale: Float = 1f) {
    Canvas(
        modifier
            .fillMaxSize()
            .clearAndSetSemantics {},
    ) {
        val width = size.width * BrandMarkBackdrop.OVERSCAN
        val height = width / BrandMark.aspectRatio
        val center = Offset(
            size.width * (0.5f + BrandMarkBackdrop.HORIZONTAL_SHIFT),
            size.height * (0.5f + BrandMarkBackdrop.VERTICAL_SHIFT),
        )
        scale(scale, pivot = center) {
            drawBrandMark(
                progress = progress,
                color = MemoBookColor.outline.copy(alpha = opacity),
                rect = Rect(center - Offset(width / 2, height / 2), Size(width, height)),
            )
        }
    }
}

object BrandMarkBackdrop {
    /** Pendant le tracé : on veut le voir s'écrire. */
    const val drawingOpacity: Float = 0.5f

    /**
     * Une fois l'accueil en place : présent, mais en dessous du contenu, sans
     * concurrencer un titre ni une photo.
     */
    const val restingOpacity: Float = 0.2f

    // Cadrage relevé sur la maquette de lancement. Le signe déborde de
    // l'écran : on n'en voit que le cœur, les deux jambages sortent du cadre.
    // Les décalages sont des fractions de l'écran, pour suivre toutes les
    // tailles de téléphone ; ils amènent la boucle au centre optique, la boîte
    // du tracé penchant vers son long jambage gauche.

    /** Largeur du signe, en largeurs d'écran. */
    internal const val OVERSCAN = 2.0f

    /** Décalage horizontal, en largeurs d'écran. */
    internal const val HORIZONTAL_SHIFT = 0.15f

    /** Décalage vertical, en hauteurs d'écran. */
    internal const val VERTICAL_SHIFT = 0.09f
}

@Preview(locale = "fr-rFR", name = "Le M en fond", widthDp = 390, heightDp = 844)
@Composable
private fun BrandMarkBackdropPreview() {
    Box(
        Modifier
            .fillMaxSize()
            .background(MemoBookColor.background),
    ) {
        BrandMarkBackdrop(progress = 1f, opacity = BrandMarkBackdrop.restingOpacity)
    }
}
