package com.memobook.design

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.StartOffset
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * La place d'une valeur qui n'est pas encore arrivée. Jumeau de `BrandSkeleton.swift`.
 *
 * **Elle ne remplace jamais un écran, seulement une valeur.** La page se
 * dessine tout de suite, et seules les valeurs qui viennent du serveur portent
 * cette barre.
 *
 * Le reflet balaie la barre en boucle — c'est ce mouvement qui la distingue
 * d'un champ désactivé —, sauf sous « Supprimer les animations ».
 *
 * @param width la largeur de la barre ; `null` prend toute la place.
 * @param height la hauteur d'un **bloc** ; `null` garde le corps de texte.
 * @param cornerRadius le rayon d'un bloc ; `null` garde la capsule.
 * @param onDark posée sur une photo ou un aplat sombre : la barre passe en clair.
 */
@Composable
fun BrandSkeleton(
    modifier: Modifier = Modifier,
    width: Dp? = null,
    height: Dp? = null,
    cornerRadius: Dp? = null,
    onDark: Boolean = false,
) {
    // La hauteur suit le corps de texte : la ligne ne saute pas en se remplissant.
    val textHeight = scaled(14.dp)
    val shape = cornerRadius?.let { RoundedCornerShape(it) } ?: RoundedCornerShape(percent = 50)
    // Le noir de la marque à peine posé, pas un gris système.
    val fill = if (onDark) MemoBookColor.onAction.copy(alpha = 0.22f) else MemoBookColor.ink.copy(alpha = 0.09f)
    val sheenColor = if (onDark) MemoBookColor.onAction.copy(alpha = 0.35f) else MemoBookColor.surface.copy(alpha = 0.9f)
    val animates = !isReduceMotionEnabled()

    val transition = rememberInfiniteTransition(label = "skeleton")
    // De -0,6 (le reflet est encore à gauche) à 1 (il est sorti à droite). Une
    // pause entre deux passages : un reflet continu clignote.
    val progress by transition.animateFloat(
        initialValue = -0.6f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(1100, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Restart,
            initialStartOffset = StartOffset(200),
        ),
        label = "sheen",
    )

    androidx.compose.foundation.layout.Box(
        modifier
            .then(if (width != null) Modifier.width(width) else Modifier.fillMaxWidth())
            .height(height ?: textHeight)
            .clip(shape)
            .background(fill)
            .drawWithContent {
                drawContent()
                if (animates) {
                    val bandWidth = size.width * 0.6f
                    val start = size.width * progress
                    drawRect(
                        brush = Brush.horizontalGradient(
                            colors = listOf(Color.Transparent, sheenColor, Color.Transparent),
                            startX = start,
                            endX = start + bandWidth,
                        ),
                        topLeft = Offset(start, 0f),
                        size = androidx.compose.ui.geometry.Size(bandWidth, size.height),
                    )
                }
            }
            .clearAndSetSemantics {},
    )
}

@Preview(name = "Barres d’attente", widthDp = 390)
@Composable
private fun BrandSkeletonPreview() {
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        BrandSkeleton(width = 120.dp)
        BrandSkeleton(width = 180.dp)
        BrandSkeleton()
        Column(
            Modifier
                .fillMaxWidth()
                .background(MemoBookColor.ink, RoundedCornerShape(MemoBookSpacing.cornerRadius))
                .padding(MemoBookSpacing.s),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        ) {
            BrandSkeleton(width = 120.dp, onDark = true)
            BrandSkeleton(width = 180.dp, onDark = true)
        }
    }
}
