package com.memobook.design

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Le M de MemoBook, tel qu'il est dessiné dans `Animated Cutout.svg` : un
 * unique trait à bouts ronds, incliné, qui monte, boucle et redescend. Jumeau
 * de `BrandMark.swift`.
 *
 * Le SVG est **recopié courbe par courbe** plutôt qu'importé comme image :
 * c'est ce qui permet de le faire s'écrire au lancement (`Path.trimmed`). Le M
 * plein de l'icône (`brand_mark.xml`) est un autre dessin, une silhouette : il
 * sait s'afficher, pas se tracer.
 *
 * Le tracé se recadre tout seul dans la place qu'on lui donne, épaisseur de
 * trait comprise — un trait déborde de la moitié de son épaisseur de chaque
 * côté, et ce débord est compté ici. Voir [aspectRatio] pour lui donner sa
 * forme, et [lineWidth] pour l'épaisseur à la bonne échelle.
 */
object BrandMark {
    /**
     * La courbe du tracé, celle du fichier de marque
     * (`cubic-bezier(0.884, 0.01, 0.302, 0.99)` dans `Animated Cutout.svg`) :
     * un départ enlevé, une fin qui se pose. C'est ce qui fait que le trait
     * paraît écrit à la main. Sur iOS, `LaunchView` l'écrit en
     * `.timingCurve(…)` ; ici elle a un nom, pour que l'écran de lancement et
     * l'aperçu la partagent.
     */
    val drawingEasing: Easing = CubicBezierEasing(0.884f, 0.01f, 0.302f, 0.99f)

    /**
     * Rapport largeur / hauteur du signe, débord du trait compris. À poser en
     * `Modifier.aspectRatio(BrandMark.aspectRatio)`.
     */
    val aspectRatio: Float get() = designBounds.width / designBounds.height

    /**
     * Hauteur du signe pour une largeur donnée. À utiliser dès qu'on lui pose
     * une largeur : on donne toujours les deux.
     */
    fun height(forWidth: Dp): Dp = forWidth / aspectRatio

    /**
     * Épaisseur du trait une fois le signe recadré dans [fitting]. Le rapport
     * trait / hauteur du dessin d'origine est conservé : le M garde sa graisse
     * à toutes les tailles.
     */
    fun lineWidth(fitting: Size): Float {
        val source = designBounds
        if (source.width <= 0f || source.height <= 0f) return 0f
        return DESIGN_STROKE_WIDTH * min(fitting.width / source.width, fitting.height / source.height)
    }

    /** Le tracé, recadré et centré dans [rect]. C'est le `path(in:)` de la `Shape` iOS. */
    fun path(rect: Rect): Path {
        val path = Path()
        val (start, curves) = fitted(rect) ?: return path
        path.moveTo(start.x, start.y)
        for (curve in curves) {
            path.cubicTo(curve.control1.x, curve.control1.y, curve.control2.x, curve.control2.y, curve.end.x, curve.end.y)
        }
        return path
    }

    // Le tracé d'origine

    /** `stroke-width` du SVG, dans les coordonnées du SVG. */
    private const val DESIGN_STROKE_WIDTH = 164.949f

    internal class Curve(val control1: Offset, val control2: Offset, val end: Offset)

    private val designStart = Offset(27.8559f, 1250.68f)

    /** Le `d` du SVG, courbe par courbe. */
    private val designCurves = listOf(
        Curve(Offset(-11.988f, 985.861f), Offset(-21.4138f, 670.389f), Offset(83.9949f, 429.145f)),
        Curve(Offset(189.404f, 187.901f), Offset(323.854f, -12.0481f), Offset(553.526f, 0.951089f)),
        Curve(Offset(713.14f, 9.98504f), Offset(795.395f, 193.301f), Offset(814.959f, 381.853f)),
        Curve(Offset(817.825f, 409.471f), Offset(819.837f, 442.459f), Offset(820.461f, 476.937f)),
        Curve(Offset(821.707f, 545.777f), Offset(817.418f, 620.558f), Offset(803.333f, 670.389f)),
        Curve(Offset(782.195f, 745.176f), Offset(729.613f, 923.846f), Offset(612.61f, 910.847f)),
        Curve(Offset(495.608f, 897.849f), Offset(514.798f, 699.982f), Offset(542.278f, 618.6f)),
        Curve(Offset(561.06f, 562.975f), Offset(590.781f, 502.855f), Offset(625.3f, 444.913f)),
        Curve(Offset(641.283f, 418.083f), Offset(658.294f, 391.721f), Offset(675.725f, 366.487f)),
        Curve(Offset(826.491f, 148.226f), Offset(1012.33f, 17.8264f), Offset(1180.64f, 0.951176f)),
        Curve(Offset(1348.94f, -15.9241f), Offset(1380.5f, 195.557f), Offset(1375.24f, 332.305f)),
        Curve(Offset(1369.98f, 469.052f), Offset(1354.2f, 600.54f), Offset(1404.17f, 745.176f)),
        Curve(Offset(1454.13f, 889.813f), Offset(1544.59f, 1023.09f), Offset(1630.33f, 1110.71f)),
    )

    /**
     * `transform="translate(-263.854 557.01) rotate(-5.54015)"` du SVG. La
     * rotation s'applique avant la translation, comme en SVG. Une
     * transformation affine se reporte sur les points de contrôle sans changer
     * la courbe : on transforme les points, pas le tracé.
     */
    private fun designTransform(point: Offset): Offset {
        val angle = -5.54015 * Math.PI / 180
        val x = point.x * cos(angle) - point.y * sin(angle)
        val y = point.x * sin(angle) + point.y * cos(angle)
        return Offset((x - 263.854).toFloat(), (y + 557.01).toFloat())
    }

    private val transformedStart = designTransform(designStart)
    private val transformedCurves = designCurves.map {
        Curve(designTransform(it.control1), designTransform(it.control2), designTransform(it.end))
    }

    /**
     * Boîte du tracé, élargie de la demi-épaisseur du trait de chaque côté.
     * C'est elle, et pas la boîte du tracé nu, qui définit le cadrage : sans
     * ça les bouts ronds seraient rognés.
     *
     * La boîte **exacte** des courbes, calculée ici plutôt que demandée à
     * `Path.getBounds()` : celle d'Android peut englober les points de
     * contrôle, et le M serait cadré trop large. C'est le `boundingRect` de
     * Core Graphics, et `BrandMarkTest` le vérifie au centième.
     */
    internal val designBounds: Rect = run {
        var bounds = Rect(transformedStart, transformedStart)
        var from = transformedStart
        for (curve in transformedCurves) {
            val curveBounds = cubicBounds(from, curve)
            bounds = Rect(
                min(bounds.left, curveBounds.left),
                min(bounds.top, curveBounds.top),
                max(bounds.right, curveBounds.right),
                max(bounds.bottom, curveBounds.bottom),
            )
            from = curve.end
        }
        bounds.inflate(DESIGN_STROKE_WIDTH / 2)
    }

    /** Le départ et les courbes, recadrés dans [rect] — `null` si le dessin n'a pas d'aire. */
    private fun fitted(rect: Rect): Pair<Offset, List<Curve>>? {
        val source = designBounds
        if (source.width <= 0f || source.height <= 0f) return null
        val scale = min(rect.width / source.width, rect.height / source.height)
        val drawn = Size(source.width * scale, source.height * scale)
        val origin = Offset(rect.left + (rect.width - drawn.width) / 2, rect.top + (rect.height - drawn.height) / 2)
        fun place(point: Offset) = (point - source.topLeft) * scale + origin
        return place(transformedStart) to transformedCurves.map { Curve(place(it.control1), place(it.control2), place(it.end)) }
    }

    /** La boîte exacte d'une cubique : ses deux bouts, et ses extrémums où la dérivée s'annule. */
    private fun cubicBounds(from: Offset, curve: Curve): Rect {
        val xs = cubicExtremes(from.x, curve.control1.x, curve.control2.x, curve.end.x)
        val ys = cubicExtremes(from.y, curve.control1.y, curve.control2.y, curve.end.y)
        return Rect(xs.first, ys.first, xs.second, ys.second)
    }

    private fun cubicExtremes(p0: Float, p1: Float, p2: Float, p3: Float): Pair<Float, Float> {
        val a = 3.0 * (-p0 + 3 * p1 - 3 * p2 + p3)
        val b = 6.0 * (p0 - 2 * p1 + p2)
        val c = 3.0 * (p1 - p0)
        val roots = mutableListOf<Double>()
        if (kotlin.math.abs(a) < 1e-9) {
            if (kotlin.math.abs(b) > 1e-9) roots += -c / b
        } else {
            val discriminant = b * b - 4 * a * c
            if (discriminant >= 0) {
                val root = sqrt(discriminant)
                roots += (-b + root) / (2 * a)
                roots += (-b - root) / (2 * a)
            }
        }
        var low = min(p0, p3).toDouble()
        var high = max(p0, p3).toDouble()
        for (t in roots) {
            if (t <= 0.0 || t >= 1.0) continue
            val u = 1 - t
            val value = u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
            low = min(low, value)
            high = max(high, value)
        }
        return low.toFloat() to high.toFloat()
    }
}

/**
 * Le M en train de s'écrire. [progress] est la part du trait déjà tracée : 0
 * ne montre rien, 1 montre le signe entier.
 *
 * La vue ne s'anime pas toute seule — c'est l'appelant qui fait varier
 * [progress] (un `Animatable` sur [BrandMark.drawingEasing]), pour rester
 * maître du moment et de la courbe. Voir `LaunchView`.
 */
@Composable
fun BrandMarkDrawing(progress: Float, modifier: Modifier = Modifier, color: Color = MemoBookColor.outline) {
    Canvas(
        modifier
            .aspectRatio(BrandMark.aspectRatio)
            .clearAndSetSemantics {},
    ) {
        drawBrandMark(progress, color, Rect(Offset.Zero, size))
    }
}

/**
 * Trace la part [progress] du M dans [rect], à l'épaisseur qui lui revient.
 * Partagé avec [BrandMarkBackdrop], qui le pose en débord de l'écran.
 */
internal fun DrawScope.drawBrandMark(progress: Float, color: Color, rect: Rect) {
    if (progress <= 0f) return
    drawPath(
        path = BrandMark.path(rect).trimmed(to = progress),
        color = color,
        style = Stroke(width = BrandMark.lineWidth(rect.size), cap = StrokeCap.Round, join = StrokeJoin.Round),
    )
}

@Preview(locale = "fr-rFR", name = "Le M, tracé", widthDp = 390, heightDp = 500)
@Composable
private fun BrandMarkDrawingPreview() {
    val progress = remember { Animatable(0f) }
    LaunchedEffect(Unit) { progress.animateTo(1f, tween(950, easing = BrandMark.drawingEasing)) }
    BrandMarkDrawing(
        progress = progress.value,
        modifier = Modifier
            .fillMaxSize()
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.m),
    )
}
