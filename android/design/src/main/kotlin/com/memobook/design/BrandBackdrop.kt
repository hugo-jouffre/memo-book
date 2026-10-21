package com.memobook.design

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import kotlin.math.max

/**
 * Motif de fond de la marque. Jumeau de `BrandBackdrop.swift`. Il déborde
 * volontairement de l'écran ; il est mis à l'échelle pour couvrir n'importe
 * quelle taille de téléphone en gardant le cadrage de la maquette.
 */
@Composable
fun BrandBackdrop(modifier: Modifier = Modifier) {
    val artwork = painterResource(R.drawable.backdrop)
    Canvas(
        modifier
            .fillMaxSize()
            .background(MemoBookColor.background)
            .clipToBounds()
            .clearAndSetSemantics {},
    ) {
        val reference = Size(BrandBackdrop.REFERENCE_WIDTH.dp.toPx(), BrandBackdrop.REFERENCE_HEIGHT.dp.toPx())
        val scale = max(size.width / reference.width, size.height / reference.height)
        val drawn = Size(BrandBackdrop.ARTWORK_WIDTH.dp.toPx() * scale, BrandBackdrop.ARTWORK_HEIGHT.dp.toPx() * scale)
        val center = Offset(
            size.width / 2 + BrandBackdrop.CENTER_X.dp.toPx() * scale,
            size.height / 2 + BrandBackdrop.CENTER_Y.dp.toPx() * scale,
        )
        // Le motif est dessiné à l'horizontale et posé debout dans la
        // maquette. Il tourne autour de son propre centre : celui-ci reste
        // celui du cadre ci-dessus.
        rotate(-90f, pivot = center) {
            translate(center.x - drawn.width / 2, center.y - drawn.height / 2) {
                with(artwork) { draw(drawn) }
            }
        }
    }
}

internal object BrandBackdrop {
    /** Cadre de référence de la maquette. */
    const val REFERENCE_WIDTH = 390f
    const val REFERENCE_HEIGHT = 844f

    /** Taille du SVG, marges de débord comprises. */
    const val ARTWORK_WIDTH = 767.604f
    const val ARTWORK_HEIGHT = 602.933f

    /**
     * Décalage du centre du motif par rapport au centre de l'écran, mesuré
     * dans le cadre de référence.
     */
    const val CENTER_X = 48.67f
    const val CENTER_Y = -21.4f
}
