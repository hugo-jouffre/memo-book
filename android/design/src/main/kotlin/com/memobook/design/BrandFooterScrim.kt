package com.memobook.design

import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.unit.Dp

/**
 * Le voile posé derrière le pied d'un écran — un appel à l'action, une
 * mention — pour que ce qui défile dessous s'y **dissolve**. Jumeau de
 * `BrandFooterScrim.swift`. **Un seul voile pour toute l'app.**
 *
 * - **Il reste translucide** : le pied garde 90 % du crème, jamais 100.
 * - **Il descend jusqu'au bord de la dalle** : poser le pied *sous* la barre
 *   de navigation (son `navigationBarsPadding()` à l'intérieur du voile), pour
 *   que le voile la traverse.
 *
 * Le fondu déborde de [FADE_HEIGHT] au-dessus du pied.
 */
object BrandFooterScrim {
    /** La hauteur du fondu au-dessus du pied : de quoi éteindre un titre en deux lignes. */
    val FADE_HEIGHT: Dp = MemoBookSpacing.xl + MemoBookSpacing.s

    /** Ce que le pied garde du crème. Sous 1, pour laisser deviner ce qui passe. */
    internal const val OPACITY = 0.9f
}

/** Pose le voile de la marque derrière un pied d'écran — voir [BrandFooterScrim]. */
fun Modifier.brandFooterScrim(): Modifier = drawBehind {
    val fade = BrandFooterScrim.FADE_HEIGHT.toPx()
    val veil = MemoBookColor.background.copy(alpha = BrandFooterScrim.OPACITY)
    drawRect(
        brush = Brush.verticalGradient(
            colors = listOf(MemoBookColor.background.copy(alpha = 0f), veil),
            startY = -fade,
            endY = 0f,
        ),
        topLeft = Offset(0f, -fade),
        size = Size(size.width, fade),
    )
    drawRect(veil, size = size)
}
