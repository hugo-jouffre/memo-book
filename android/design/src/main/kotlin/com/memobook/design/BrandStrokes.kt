package com.memobook.design

import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection

// Les traits dessinés à la main de la marque, repris des vecteurs Figma du
// paywall (nœud `3297:20771`). Jumeau de `BrandStrokes.swift`.
//
// **Ce sont des `Shape`, pas des images.** Un vecteur posé dans une `Image` ne
// sait pas se tracer progressivement ; un `Path`, si — `trimmed(to:)` suffit,
// et c'est exactement l'animation que Figma décrit sur ces nœuds
// (`path-trim`). Les coordonnées viennent telles quelles de l'export,
// rapportées au cadre reçu pour que le trait suive la largeur de l'écran.

/**
 * La part [from]…[to] d'un tracé, de 0 à 1 de sa longueur : le
 * `.trim(from:to:)` de SwiftUI, que Compose n'a pas. Un tracé d'**un seul
 * contour** — c'est le cas du M et des traits de la marque.
 */
fun Path.trimmed(from: Float = 0f, to: Float): Path {
    val start = from.coerceIn(0f, 1f)
    val end = to.coerceIn(0f, 1f)
    if (start <= 0f && end >= 1f) return this
    val segment = Path()
    if (end <= start) return segment
    val measure = PathMeasure()
    measure.setPath(this, false)
    val length = measure.length
    measure.getSegment(start * length, end * length, segment, true)
    return segment
}

/** Le grand trait bleu qui traverse le premier écran du paywall — il descend, fait sa boucle, et repart vers la droite. */
object BrandSquiggleDown : Shape {
    /** Le cadre du tracé dans Figma : 442.362 × 93.6948. */
    val size = Size(442.362f, 93.6948f)

    /** L'épaisseur du trait, en fraction de la hauteur du tracé. */
    const val lineWidthRatio: Float = 12f / 93.6948f

    /** Le tracé, rapporté à [size] (le cadre reçu, pas celui de Figma). */
    fun path(size: Size): Path {
        val w = size.width / this.size.width
        val h = size.height / this.size.height
        return Path().apply {
            moveTo(6.00008f * w, 40.7985f * h)
            cubicTo(6.00008f * w, 40.7985f * h, 66.538f * w, -12.4846f * h, 111.911f * w, 12.824f * h)
            cubicTo(157.284f * w, 38.1326f * h, 134.861f * w, 88.3373f * h, 111.251f * w, 87.6885f * h)
            cubicTo(87.6411f * w, 87.0396f * h, 84.7476f * w, 46.3371f * h, 109.456f * w, 32.0493f * h)
            cubicTo(134.165f * w, 17.7614f * h, 190.013f * w, 72.8536f * h, 261.41f * w, 81.9699f * h)
            cubicTo(332.806f * w, 91.0863f * h, 405.296f * w, 76.8523f * h, 436.362f * w, 80.2933f * h)
        }
    }

    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline =
        Outline.Generic(path(size))
}

/** Le même geste sur le deuxième écran, retourné : la boucle se pose plus haut et le trait remonte. */
object BrandSquiggleUp : Shape {
    /** Le cadre du tracé dans Figma : 430.875 × 139.984. */
    val size = Size(430.875f, 139.984f)

    /** L'épaisseur du trait, en fraction de la hauteur du tracé. */
    const val lineWidthRatio: Float = 12f / 139.984f

    fun path(size: Size): Path {
        val w = size.width / this.size.width
        val h = size.height / this.size.height
        return Path().apply {
            moveTo(6.00041f * w, 6.00041f * h)
            cubicTo(6.00041f * w, 6.00041f * h, 146.586f * w, 19.2322f * h, 191.959f * w, 44.5408f * h)
            cubicTo(237.332f * w, 69.8495f * h, 208.558f * w, 120.11f * h, 182.887f * w, 115.59f * h)
            cubicTo(157.216f * w, 111.07f * h, 155.022f * w, 77.5024f * h, 179.731f * w, 63.2145f * h)
            cubicTo(204.439f * w, 48.9266f * h, 240.232f * w, 47.015f * h, 276.074f * w, 60.3797f * h)
            cubicTo(311.917f * w, 73.7444f * h, 363.682f * w, 114.993f * h, 424.873f * w, 133.983f * h)
        }
    }

    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline =
        Outline.Generic(path(size))
}

/** Le petit trait qui souligne les derniers mots d'un titre, tracé à la main. */
object BrandUnderline : Shape {
    /** Le cadre du tracé dans Figma : 146.645 × 10.4222. */
    val size = Size(146.645f, 10.4222f)

    /** L'épaisseur du trait, en fraction de la hauteur du tracé. */
    const val lineWidthRatio: Float = 4f / 10.4222f

    fun path(size: Size): Path {
        val w = size.width / this.size.width
        val h = size.height / this.size.height
        return Path().apply {
            moveTo(2.00033f * w, 8.42184f * h)
            cubicTo(24.1735f * w, 4.59981f * h, 83.745f * w, -1.51806f * h, 144.645f * w, 4.58676f * h)
        }
    }

    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline =
        Outline.Generic(path(size))
}
