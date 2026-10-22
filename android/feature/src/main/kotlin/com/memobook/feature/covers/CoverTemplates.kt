package com.memobook.feature.covers

import androidx.annotation.DrawableRes
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.PathOperation
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.shadow.Shadow as DropShadow
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import com.memobook.core.BookCopy
import com.memobook.core.BookCover
import com.memobook.core.CoverFace
import com.memobook.core.CoverFamily
import com.memobook.core.CoverPhoto
import com.memobook.core.CoverStat
import com.memobook.design.BrandFonts
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.R
import com.memobook.feature.home.TripCoverPlaceholder
import kotlinx.coroutines.launch
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * **Les sept gabarits de couverture**, redessinés d'après les plats de Hugo
 * (`assets/covers`, 08/10/2026 : « recode-les pour qu'ils soient visibles et
 * éditables dans l'app »). Jumeau de `Covers/CoverTemplates.swift`.
 *
 * Chaque gabarit garde **la composition** de la maquette — où tombe le titre,
 * où va la photo, ce qui orne le papier — et y met **ce que le voyageur a
 * choisi** : son titre, sa signature, sa photo, son texte de quatrième, ses
 * chiffres. Rien de la maquette n'y reste écrit : ni « PHILIPPINES », ni la
 * photo des trois amis.
 *
 * - **La signature** (`subtitle` du devant) se lit en deux temps, comme dans
 *   les maquettes : sa première ligne est **qui** — « Maylis, Claire et
 *   Augustin » —, sa dernière **quand** — « Août 2026 ». Chaque gabarit pose
 *   l'une, l'autre ou les deux, là où la maquette les pose.
 * - **Ce qui ne se redessine pas** — la palme, la moto et le globe au trait,
 *   les courbes tracées à la main — est découpé dans le plat de Hugo
 *   (`ios/Tools/import-cover-ornaments.py`) et se pose sur l'aplat que l'app
 *   dessine. Les aquarelles et les timbres de la maquette sont des images **du
 *   voyage de la maquette** : ici, ce sont les photos du voyageur qui en
 *   tiennent la place.
 * - Les mesures sont des **fractions de la largeur** du plat, comme
 *   [CoverPlate]. Et les tailles de texte ne suivent pas la taille de police du
 *   téléphone — c'est l'image d'un objet imprimé (voir [CoverPlate]).
 *
 * Les capitales à empattements de « Par défaut » et d'« Élégant » sont le serif
 * du système, le grotesque épais d'« Aquarelle », d'« Assouline » et de
 * « Travel book » son sans-serif le plus gras — comme sur iOS, qui prend ceux
 * de l'iPhone.
 *
 * ⚠️ **Ce n'est toujours pas le rendu d'impression** : la composition du PDF qui
 * lira ces choix reste à écrire (T223).
 *
 * @param companion le plat d'en face, pour ce que le dos reprend du devant — qui, quand.
 * @param gallery les photos du voyage : les timbres de « Travel book », les
 *   images du récit au dos d'« Aquarelle ». La photo choisie passe toujours en tête.
 */
@Composable
fun CoverTemplate(
    family: CoverFamily,
    face: CoverFace,
    cover: BookCover,
    companion: BookCover?,
    photo: CoverPhoto?,
    gallery: List<CoverPhoto>,
    stats: List<CoverStat>,
    width: Dp,
    titleBadge: (@Composable () -> Unit)? = null,
    subtitleBadge: (@Composable () -> Unit)? = null,
    statsBadge: (@Composable () -> Unit)? = null,
) {
    val m = rememberCoverMetrics(width)
    val reading = remember(cover, companion, face, photo, gallery) { CoverReading(face, cover, companion, photo, gallery) }
    val scope = CoverTemplateScope(m, reading, cover, photo, stats, titleBadge, subtitleBadge, statsBadge)
    Box(Modifier.size(width, width / CoverPlate.ratio)) {
        with(scope) {
            when (family) {
                CoverFamily.Default -> if (face == CoverFace.Front) DefaultFront() else DefaultBack()
                CoverFamily.Watercolor -> if (face == CoverFace.Front) WatercolorFront() else WatercolorBack()
                CoverFamily.Assouline -> if (face == CoverFace.Front) AssoulineFront() else AssoulineBack()
                CoverFamily.Drawing -> if (face == CoverFace.Front) DrawingFront() else DrawingBack()
                CoverFamily.PhotoDrawing -> if (face == CoverFace.Front) PhotoDrawingFront() else PhotoDrawingBack()
                CoverFamily.TravelBook -> if (face == CoverFace.Front) TravelBookFront() else TravelBookBack()
                CoverFamily.Elegant -> if (face == CoverFace.Front) ElegantFront() else ElegantBack()
            }
        }
    }
}

// MARK: - Ce que les gabarits lisent

/** Ce que les gabarits lisent du plat, une fois par plat. */
internal class CoverReading(face: CoverFace, cover: BookCover, companion: BookCover?, photo: CoverPhoto?, gallery: List<CoverPhoto>) {
    /** La signature du devant, ligne par ligne. */
    val signatureLines: List<String> =
        (if (face == CoverFace.Front) cover.subtitle else companion?.subtitle.orEmpty())
            .split("\n")
            .map { it.trim() }
            .filter { it.isNotEmpty() }

    /** Qui : la première ligne de la signature, quand elle en a deux. */
    val authors: String? = if (signatureLines.size > 1) signatureLines.first() else null

    /** Quand : la dernière ligne — la seule, si la signature n'en a qu'une. */
    val `when`: String? = signatureLines.lastOrNull()

    /** Le titre du devant, vu du dos. */
    val frontTitle: String = if (face == CoverFace.Front) cover.title else companion?.title.orEmpty()

    /** Le texte de quatrième, coupé en paragraphes. */
    val backParagraphs: List<String> = cover.subtitle.split("\n\n").map { it.trim() }.filter { it.isNotEmpty() }

    /** Les photos à poser, la choisie d'abord. */
    val photos: List<CoverPhoto> = if (photo == null) gallery else listOf(photo) + gallery.filter { it.id != photo.id }
}

/** Les mesures d'un plat : des fractions de sa largeur, et des tailles de texte qui n'en suivent que la largeur. */
internal class CoverMetrics(val width: Dp, private val density: Density) {
    fun u(fraction: Float): Dp = width * fraction

    fun px(fraction: Float): Float = with(density) { u(fraction).toPx() }

    /** Une taille de texte **fixe** : le dp devient un sp qui ignore la taille de police du téléphone. */
    fun sp(fraction: Float): TextUnit = with(density) { u(fraction).toSp() }

    fun font(family: FontFamily, weight: FontWeight, size: Float) = TextStyle(fontFamily = family, fontWeight = weight, fontSize = sp(size))

    /** Les capitales à empattements de « Par défaut » et d'« Élégant ». */
    fun serif(size: Float, weight: FontWeight = FontWeight.Bold) = font(FontFamily.Serif, weight, size)

    /** Le grotesque épais d'« Aquarelle », d'« Assouline » et de « Travel book ». */
    fun heavy(size: Float) = font(FontFamily.SansSerif, FontWeight.Black, size)

    /** L'écriture à la main de « Dessin » et de « Photo-dessin ». */
    fun hand(size: Float) = font(BrandFonts.gloriaHallelujah, FontWeight.Normal, size)

    fun sans(size: Float) = font(BrandFonts.generalSans, FontWeight.Normal, size)
}

@Composable
internal fun rememberCoverMetrics(width: Dp): CoverMetrics {
    val density = LocalDensity.current
    return remember(width, density) { CoverMetrics(width, density) }
}

/**
 * Un texte du plat, centré par défaut.
 *
 * @param lineSpacing l'interligne ajouté — le `lineSpacing` de SwiftUI, posé
 *   sur l'interligne naturel (×1,2) des polices du plat.
 * @param tracking l'interlettrage, en fraction de largeur déjà résolue.
 * @param minHeight la hauteur que le texte tient même vide, centré dedans — le
 *   `frame(minHeight:)` d'iOS, pour que son crayon ait où se poser.
 */
@Composable
internal fun CoverText(
    text: String,
    style: TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
    maxLines: Int = Int.MAX_VALUE,
    minimumScaleFactor: Float = 1f,
    textAlign: TextAlign = TextAlign.Center,
    lineSpacing: Dp? = null,
    tracking: Dp? = null,
    shadow: Shadow? = null,
    minHeight: Dp? = null,
    contentAlignment: Alignment = Alignment.Center,
) {
    val density = LocalDensity.current
    val resolved = style.copy(
        lineHeight = lineSpacing?.let { (style.fontSize.value * 1.2f + with(density) { it.toSp() }.value).sp } ?: style.lineHeight,
        letterSpacing = tracking?.let { with(density) { it.toSp() } } ?: style.letterSpacing,
        shadow = shadow ?: style.shadow,
    )
    if (minHeight == null) {
        BrandText(text, resolved, modifier, color = color, textAlign = textAlign, maxLines = maxLines, minimumScaleFactor = minimumScaleFactor)
    } else {
        Box(modifier.heightIn(min = minHeight), contentAlignment = contentAlignment) {
            BrandText(text, resolved, color = color, textAlign = textAlign, maxLines = maxLines, minimumScaleFactor = minimumScaleFactor)
        }
    }
}

/** Un bloc, et le crayon de l'écran des textes posé dans son coin — l'`overlay(alignment:)` d'iOS. */
@Composable
internal fun CoverBadged(
    badge: (@Composable () -> Unit)?,
    alignment: Alignment,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    Box(modifier, contentAlignment = Alignment.Center) {
        content()
        if (badge != null) Box(Modifier.align(alignment)) { badge() }
    }
}

/** Le M de la marque, au pied du dos. */
@Composable
internal fun CoverLogo(color: Color, modifier: Modifier) {
    Image(
        painterResource(R.drawable.logo_memobook_creme),
        contentDescription = null,
        colorFilter = ColorFilter.tint(color),
        contentScale = ContentScale.Fit,
        modifier = modifier.clearAndSetSemantics {},
    )
}

/** Un texte qu'on peut ne pas avoir écrit : il tient sa place même vide, pour que son crayon ait où se poser. */
@Composable
private fun CoverPlaceholderFrame(m: CoverMetrics, minHeight: Float) {
    Spacer(
        Modifier
            .fillMaxWidth()
            .heightIn(min = m.u(minHeight)),
    )
}

/** Ce que chaque gabarit lit, pour ne pas le passer à chacun. */
internal class CoverTemplateScope(
    val m: CoverMetrics,
    val reading: CoverReading,
    val cover: BookCover,
    val photo: CoverPhoto?,
    val stats: List<CoverStat>,
    val titleBadge: (@Composable () -> Unit)?,
    val subtitleBadge: (@Composable () -> Unit)?,
    val statsBadge: (@Composable () -> Unit)?,
) {
    val height: Dp get() = m.width / CoverPlate.ratio

    @Composable
    fun Picture(photo: CoverPhoto?, modifier: Modifier, colorFilter: ColorFilter? = null) {
        CoverPhotoImage(photo, seed = photo?.id ?: cover.styleId, modifier = modifier, colorFilter = colorFilter)
    }

    @Composable
    fun Ornament(@DrawableRes image: Int, width: Float, modifier: Modifier = Modifier) {
        Image(
            painterResource(image),
            contentDescription = null,
            contentScale = ContentScale.Fit,
            modifier = modifier
                .width(m.u(width))
                .clearAndSetSemantics {},
        )
    }

    /** Un dessin au trait sur son disque bleu pâle, comme la maquette. */
    @Composable
    fun Drawn(@DrawableRes image: Int, width: Float) {
        val radius = m.px(width * 0.8f) / 2
        val shift = m.px(width * 0.05f)
        Ornament(
            image,
            width,
            Modifier.drawBehind {
                drawCircle(MemoBookColor.outline.copy(alpha = 0.25f), radius = radius, center = center + Offset(shift, 0f))
            },
        )
    }

    /** « Mon voyage en quelques chiffres », dans un cadre arrondi. */
    @Composable
    fun StatsBox(ink: Color, fill: Color?, border: Color) {
        val shape = RoundedCornerShape(m.u(0.04f))
        CoverBadged(statsBadge, Alignment.TopEnd) {
            Column(
                Modifier
                    .then(if (fill != null) Modifier.background(fill, shape) else Modifier)
                    .drawBehind {
                        val line = max(1.dp.toPx(), m.px(0.004f))
                        drawRoundRect(
                            border,
                            topLeft = Offset(line / 2, line / 2),
                            size = Size(size.width - line, size.height - line),
                            cornerRadius = CornerRadius(m.px(0.04f)),
                            style = Stroke(line),
                        )
                    }
                    .padding(m.u(0.035f)),
                verticalArrangement = Arrangement.spacedBy(m.u(0.025f)),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                CoverText(BookCopy.Covers.Stats.heading, m.serif(0.036f, FontWeight.SemiBold), ink)
                Row(horizontalArrangement = Arrangement.spacedBy(m.u(0.025f)), verticalAlignment = Alignment.Top) {
                    stats.forEach { stat ->
                        Column(
                            Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(m.u(0.008f)),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            CoverText(stat.value, m.serif(0.075f, FontWeight.SemiBold), ink, maxLines = 1, minimumScaleFactor = 0.5f)
                            CoverText(stat.label, m.serif(0.028f, FontWeight.Normal), ink, minimumScaleFactor = 0.5f)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Par défaut

    /**
     * La photo pleine page ; le titre en grandes capitales à empattements en
     * haut, la signature en bas, en blanc.
     */
    @Composable
    fun BoxScope.DefaultFront() {
        Picture(photo, Modifier.fillMaxSize())
        // Le blanc se lit sur un ciel clair grâce à ce voile, qui laisse le
        // milieu de la photo intact.
        Box(
            Modifier
                .fillMaxSize()
                .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.35f), Color.Transparent, Color.Transparent, Color.Black.copy(alpha = 0.4f)))),
        )
        Column(
            Modifier
                .fillMaxSize()
                .padding(start = m.u(0.06f), end = m.u(0.06f), top = m.u(0.07f), bottom = m.u(0.08f)),
        ) {
            CoverBadged(titleBadge, Alignment.TopEnd, Modifier.fillMaxWidth()) {
                CoverText(
                    cover.title,
                    m.serif(0.14f),
                    MemoBookColor.paper,
                    Modifier.fillMaxWidth(),
                    maxLines = 2,
                    minimumScaleFactor = 0.4f,
                    shadow = Shadow(Color.Black.copy(alpha = 0.25f), blurRadius = m.px(0.01f)),
                )
            }
            Spacer(Modifier.weight(1f))
            CoverBadged(subtitleBadge, Alignment.BottomEnd, Modifier.fillMaxWidth()) {
                CoverText(
                    cover.subtitle,
                    m.serif(0.05f, FontWeight.Normal),
                    MemoBookColor.paper,
                    Modifier.fillMaxWidth(),
                    maxLines = 3,
                    minimumScaleFactor = 0.6f,
                    shadow = Shadow(Color.Black.copy(alpha = 0.3f), blurRadius = m.px(0.008f)),
                )
            }
        }
    }

    /** Le papier, un filet en pointillés, le trajet, les chiffres, la marque. */
    @Composable
    fun BoxScope.DefaultBack() {
        Box(Modifier.fillMaxSize().background(MemoBookColor.paper))
        Canvas(
            Modifier
                .fillMaxSize()
                .padding(m.u(0.035f)),
        ) {
            val line = max(0.5.dp.toPx(), m.px(0.003f))
            drawRoundRect(
                MemoBookColor.action.copy(alpha = 0.35f),
                topLeft = Offset(line / 2, line / 2),
                size = Size(size.width - line, size.height - line),
                cornerRadius = CornerRadius(m.px(0.01f)),
                style = Stroke(line, pathEffect = PathEffect.dashPathEffect(floatArrayOf(m.px(0.012f), m.px(0.008f)))),
            )
        }
        Column(
            Modifier
                .fillMaxSize()
                .padding(start = m.u(0.1f), end = m.u(0.1f), top = m.u(0.12f), bottom = m.u(0.08f)),
            verticalArrangement = Arrangement.spacedBy(m.u(0.05f)),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Canvas(
                Modifier
                    .size(m.u(0.55f), m.u(0.62f))
                    .clearAndSetSemantics {},
            ) {
                drawPath(
                    CoverShapes.routeSketch(size),
                    MemoBookColor.action.copy(alpha = 0.7f),
                    style = Stroke(
                        max(1.dp.toPx(), m.px(0.006f)),
                        cap = StrokeCap.Round,
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(m.px(0.015f), m.px(0.012f))),
                    ),
                )
                // Les étapes posées sur le trajet : un rond plein, cerné de papier.
                val radius = m.px(0.016f)
                CoverShapes.routeStops.forEach { stop ->
                    val center = Offset(stop.x * size.width, stop.y * size.height)
                    drawCircle(MemoBookColor.action, radius, center)
                    drawCircle(MemoBookColor.paper, radius - radius * 0.2f, center, style = Stroke(radius * 0.4f))
                }
            }
            Spacer(Modifier.weight(1f))
            if (stats.isNotEmpty()) StatsBox(MemoBookColor.ink, fill = null, border = MemoBookColor.action.copy(alpha = 0.6f))
            CoverLogo(MemoBookColor.action, Modifier.height(m.u(0.075f)))
        }
    }

    // MARK: - Aquarelle

    /**
     * Un bandeau crème et son titre noir en capitales épaisses ; dessous, la
     * photo, comme une aquarelle qui se perd dans le papier en bas.
     */
    @Composable
    fun BoxScope.WatercolorFront() {
        Column(Modifier.fillMaxSize().background(MemoBookColor.coverCream)) {
            CoverBadged(
                titleBadge,
                Alignment.TopEnd,
                Modifier
                    .fillMaxWidth()
                    .height(height * 0.17f)
                    .padding(horizontal = m.u(0.05f)),
            ) {
                CoverText(cover.title.uppercase(), m.heavy(0.115f), MemoBookColor.ink, Modifier.fillMaxWidth(), maxLines = 1, minimumScaleFactor = 0.4f)
            }
            Box(
                Modifier
                    .fillMaxWidth()
                    .weight(1f),
            ) {
                Picture(
                    photo,
                    Modifier
                        .fillMaxSize()
                        .clipToBounds()
                        // L'aquarelle de la maquette ne s'arrête pas net : elle
                        // se perd dans le papier. La photo fait de même, en bas.
                        .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                        .drawWithContent {
                            drawContent()
                            drawRect(
                                Brush.verticalGradient(0f to Color.Black, 0.82f to Color.Black, 1f to Color.Transparent),
                                blendMode = BlendMode.DstIn,
                            )
                        },
                    colorFilter = CoverColorFilters.watercolor,
                )
                reading.`when`?.let { date ->
                    CoverText(
                        date,
                        m.heavy(0.04f),
                        MemoBookColor.ink.copy(alpha = 0.8f),
                        Modifier
                            .align(Alignment.BottomEnd)
                            .padding(m.u(0.05f)),
                    )
                }
                if (subtitleBadge != null) Box(Modifier.align(Alignment.BottomEnd)) { subtitleBadge() }
            }
        }
    }

    /**
     * De grandes taches sur le papier ; la date en titre ; le récit en trois
     * temps, chacun avec une image, à gauche puis à droite.
     */
    @Composable
    fun BoxScope.WatercolorBack() {
        Box(Modifier.fillMaxSize().background(MemoBookColor.coverCream))
        Canvas(Modifier.fillMaxSize().clearAndSetSemantics {}) {
            drawPath(CoverShapes.washes(size), MemoBookColor.coverWash)
        }
        Column(
            Modifier
                .fillMaxSize()
                .padding(start = m.u(0.08f), end = m.u(0.08f), top = m.u(0.08f), bottom = m.u(0.06f)),
            verticalArrangement = Arrangement.spacedBy(m.u(0.045f)),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            CoverText(reading.`when` ?: reading.frontTitle, m.heavy(0.055f), MemoBookColor.ink, maxLines = 1, minimumScaleFactor = 0.5f)

            CoverBadged(subtitleBadge, Alignment.TopEnd, Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(m.u(0.05f))) {
                    val paragraphs = reading.backParagraphs.take(3)
                    if (paragraphs.isEmpty()) CoverPlaceholderFrame(m, 0.3f)
                    paragraphs.forEachIndexed { index, paragraph ->
                        val image = reading.photos.takeIf { it.isNotEmpty() }?.let { it[index % it.size] }
                        Row(horizontalArrangement = Arrangement.spacedBy(m.u(0.04f)), verticalAlignment = Alignment.CenterVertically) {
                            if (index % 2 == 0) Vignette(image)
                            CoverText(
                                paragraph,
                                m.sans(0.03f),
                                MemoBookColor.ink,
                                Modifier.weight(1f),
                                minimumScaleFactor = 0.6f,
                                textAlign = TextAlign.Start,
                                lineSpacing = m.u(0.004f),
                            )
                            if (index % 2 == 1) Vignette(image)
                        }
                    }
                }
            }

            Spacer(Modifier.weight(1f))
            CoverLogo(MemoBookColor.separator.copy(alpha = 0.8f), Modifier.height(m.u(0.075f)))
        }
    }

    /** Une image du récit, aux bords adoucis comme une aquarelle collée. */
    @Composable
    private fun Vignette(photo: CoverPhoto?) {
        Picture(
            photo,
            Modifier
                .size(m.u(0.22f), m.u(0.18f))
                .clip(RoundedCornerShape(m.u(0.02f)))
                .alpha(0.95f),
            colorFilter = CoverColorFilters.vignette,
        )
    }

    // MARK: - Assouline

    /** Le bleu de la marque, le titre en grandes capitales vertes, une palme au milieu, l'année en bas. */
    @Composable
    fun BoxScope.AssoulineFront() {
        Column(
            Modifier
                .fillMaxSize()
                .background(MemoBookColor.outline)
                .padding(start = m.u(0.05f), end = m.u(0.05f), top = m.u(0.1f), bottom = m.u(0.06f)),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            CoverBadged(titleBadge, Alignment.TopEnd, Modifier.fillMaxWidth()) {
                CoverText(cover.title.uppercase(), m.heavy(0.12f), MemoBookColor.action, Modifier.fillMaxWidth(), maxLines = 2, minimumScaleFactor = 0.4f)
            }
            Spacer(Modifier.height(m.u(0.03f)))
            Spacer(Modifier.weight(1f))
            Ornament(R.drawable.cover_ornament_palm, 0.72f)
            Spacer(Modifier.height(m.u(0.03f)))
            Spacer(Modifier.weight(1f))
            CoverBadged(subtitleBadge, Alignment.BottomEnd, Modifier.fillMaxWidth()) {
                CoverText(
                    reading.`when`.orEmpty(),
                    m.heavy(0.06f),
                    MemoBookColor.action,
                    Modifier.fillMaxWidth(),
                    maxLines = 1,
                    minimumScaleFactor = 0.5f,
                    minHeight = m.u(0.07f),
                )
            }
        }
    }

    /** Le même bleu : qui a voyagé, en capitales vertes ; le récit, centré ; les chiffres dans un cadre blanc. */
    @Composable
    fun BoxScope.AssoulineBack() {
        Column(
            Modifier
                .fillMaxSize()
                .background(MemoBookColor.outline)
                .padding(start = m.u(0.08f), end = m.u(0.08f), top = m.u(0.1f), bottom = m.u(0.07f)),
            verticalArrangement = Arrangement.spacedBy(m.u(0.04f)),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            CoverText((reading.authors ?: reading.frontTitle).uppercase(), m.heavy(0.055f), MemoBookColor.action, maxLines = 2, minimumScaleFactor = 0.5f)
            CoverBadged(subtitleBadge, Alignment.TopEnd, Modifier.fillMaxWidth()) {
                if (cover.subtitle.isEmpty()) {
                    CoverPlaceholderFrame(m, 0.3f)
                } else {
                    CoverText(
                        cover.subtitle,
                        m.serif(0.03f, FontWeight.Normal),
                        MemoBookColor.ink,
                        Modifier.fillMaxWidth(),
                        minimumScaleFactor = 0.5f,
                        lineSpacing = m.u(0.004f),
                    )
                }
            }
            Spacer(Modifier.weight(1f))
            if (stats.isNotEmpty()) StatsBox(MemoBookColor.ink, fill = MemoBookColor.paper, border = MemoBookColor.ink.copy(alpha = 0.2f))
        }
    }

    // MARK: - Dessin

    /**
     * Le papier crème, des chemins en pointillés aux coins, la moto, le titre à
     * la main, la route, le globe, et qui a voyagé.
     */
    @Composable
    fun BoxScope.DrawingFront() {
        Box(Modifier.fillMaxSize().background(MemoBookColor.coverCream))
        Canvas(Modifier.fillMaxSize().clearAndSetSemantics {}) {
            drawPath(
                CoverShapes.dashedTrails(size),
                MemoBookColor.ink,
                style = Stroke(
                    max(1.dp.toPx(), m.px(0.005f)),
                    cap = StrokeCap.Round,
                    pathEffect = PathEffect.dashPathEffect(floatArrayOf(m.px(0.018f), m.px(0.012f))),
                ),
            )
        }
        Column(
            Modifier
                .fillMaxSize()
                .padding(start = m.u(0.12f), end = m.u(0.12f), top = m.u(0.13f), bottom = m.u(0.07f)),
            verticalArrangement = Arrangement.spacedBy(m.u(0.04f)),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Drawn(R.drawable.cover_ornament_motorbike, 0.34f)
            CoverBadged(titleBadge, Alignment.TopEnd, Modifier.fillMaxWidth()) {
                CoverText(cover.title, m.hand(0.085f), MemoBookColor.ink, Modifier.fillMaxWidth(), maxLines = 3, minimumScaleFactor = 0.5f)
            }
            reading.`when`?.let { date ->
                CoverText(date, m.hand(0.045f), MemoBookColor.ink, maxLines = 1, minimumScaleFactor = 0.5f)
            }
            Ornament(R.drawable.cover_ornament_road, 0.5f)
            Drawn(R.drawable.cover_ornament_globe, 0.2f)
            Spacer(Modifier.weight(1f))
            CoverBadged(subtitleBadge, Alignment.BottomEnd, Modifier.fillMaxWidth()) {
                CoverText(
                    reading.authors.orEmpty(),
                    m.hand(0.035f),
                    MemoBookColor.ink,
                    Modifier.fillMaxWidth(),
                    maxLines = 1,
                    minimumScaleFactor = 0.5f,
                    minHeight = m.u(0.05f),
                )
            }
        }
    }

    /** Un titre à la main souligné, le motard au milieu, et le texte de quatrième, à la main lui aussi. */
    @Composable
    fun BoxScope.DrawingBack() {
        Column(
            Modifier
                .fillMaxSize()
                .background(MemoBookColor.coverCream)
                .padding(start = m.u(0.08f), end = m.u(0.08f), top = m.u(0.12f), bottom = m.u(0.07f)),
            verticalArrangement = Arrangement.spacedBy(m.u(0.05f)),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(horizontalAlignment = Alignment.End) {
                CoverText(BookCopy.Covers.drawingBackHeading, m.hand(0.08f), MemoBookColor.ink, maxLines = 1, minimumScaleFactor = 0.5f)
                Box(
                    Modifier
                        .padding(end = m.u(0.1f))
                        .size(m.u(0.25f), androidx.compose.ui.unit.max(1.5.dp, m.u(0.008f)))
                        .background(MemoBookColor.ink, RoundedCornerShape(percent = 50)),
                )
            }
            Spacer(Modifier.weight(1f))
            Drawn(R.drawable.cover_ornament_rider, 0.42f)
            Spacer(Modifier.weight(1f))
            CoverBadged(subtitleBadge, Alignment.TopEnd, Modifier.fillMaxWidth()) {
                if (cover.subtitle.isEmpty()) {
                    CoverPlaceholderFrame(m, 0.12f)
                } else {
                    CoverText(cover.subtitle, m.hand(0.032f), MemoBookColor.ink, Modifier.fillMaxWidth(), minimumScaleFactor = 0.5f)
                }
            }
        }
    }

    // MARK: - Photo-dessin

    /**
     * La photo pleine page, des courbes de niveau tracées par-dessus, le titre à
     * la main sur un arc ; qui en haut, l'année en bas à droite.
     */
    @Composable
    fun BoxScope.PhotoDrawingFront() {
        Picture(photo, Modifier.fillMaxSize())
        // Sous le titre, comme la maquette : le titre se pose au-dessus des
        // courbes, pas dedans.
        Canvas(
            Modifier
                .align(Alignment.Center)
                .offset(y = m.u(0.26f))
                .size(m.u(0.9f), m.u(0.72f))
                .clearAndSetSemantics {},
        ) {
            drawPath(CoverShapes.contourLines(size), MemoBookColor.coverMint.copy(alpha = 0.9f), style = Stroke(max(1.dp.toPx(), m.px(0.008f))))
        }
        val shadow = Shadow(Color.Black.copy(alpha = 0.18f), blurRadius = m.px(0.006f))
        Column(
            Modifier
                .fillMaxSize()
                .padding(start = m.u(0.06f), end = m.u(0.06f), top = m.u(0.04f), bottom = m.u(0.04f)),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            CoverText(
                reading.authors.orEmpty().uppercase(),
                m.hand(0.05f),
                MemoBookColor.coverMint,
                Modifier.fillMaxWidth(),
                maxLines = 1,
                minimumScaleFactor = 0.5f,
                shadow = shadow,
                minHeight = m.u(0.06f),
            )
            Spacer(Modifier.weight(1f))
            CoverBadged(titleBadge, Alignment.TopEnd) {
                CoverArcText(
                    text = cover.title.uppercase(),
                    style = m.hand(0.17f).copy(shadow = shadow),
                    color = MemoBookColor.coverMint,
                    rise = m.u(0.07f),
                    width = m.u(0.88f),
                )
            }
            Spacer(Modifier.weight(3f))
            CoverBadged(subtitleBadge, Alignment.BottomStart, Modifier.fillMaxWidth()) {
                CoverText(
                    reading.`when`.orEmpty(),
                    m.hand(0.08f),
                    MemoBookColor.coverMint,
                    Modifier.fillMaxWidth(),
                    maxLines = 1,
                    minimumScaleFactor = 0.5f,
                    textAlign = TextAlign.End,
                    shadow = shadow,
                    minHeight = m.u(0.08f),
                    contentAlignment = Alignment.CenterEnd,
                )
            }
        }
    }

    /** L'aplat d'eau claire, les courbes en haut à gauche, un mot à la main au milieu, la marque en bas. */
    @Composable
    fun BoxScope.PhotoDrawingBack() {
        Box(Modifier.fillMaxSize().background(MemoBookColor.coverMint))
        Ornament(R.drawable.cover_ornament_contours, 0.62f, Modifier.align(Alignment.TopStart))
        Column(
            Modifier
                .fillMaxSize()
                // Sous les courbes du coin, jamais dessus.
                .padding(start = m.u(0.1f), end = m.u(0.1f), top = m.u(0.34f), bottom = m.u(0.07f)),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.weight(1f))
            CoverBadged(subtitleBadge, Alignment.TopEnd, Modifier.fillMaxWidth()) {
                if (cover.subtitle.isEmpty()) {
                    CoverPlaceholderFrame(m, 0.15f)
                } else {
                    CoverText(
                        cover.subtitle.uppercase(),
                        m.hand(0.042f),
                        MemoBookColor.action,
                        Modifier.fillMaxWidth(),
                        minimumScaleFactor = 0.5f,
                        lineSpacing = m.u(0.01f),
                    )
                }
            }
            Spacer(Modifier.weight(1f))
            CoverLogo(MemoBookColor.action, Modifier.height(m.u(0.075f)))
        }
    }

    // MARK: - Travel book

    /**
     * Le carnet de bord : le titre et la date en capitales vertes, un tampon,
     * les photos du voyage en timbres, et qui a voyagé en bas.
     */
    @Composable
    fun BoxScope.TravelBookFront() {
        Column(
            Modifier
                .fillMaxSize()
                .background(MemoBookColor.coverCream)
                .padding(start = m.u(0.1f), end = m.u(0.1f), top = m.u(0.1f), bottom = m.u(0.06f)),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(m.u(0.03f)), verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f)) {
                    CoverBadged(titleBadge, Alignment.TopEnd) {
                        CoverText(cover.title.uppercase(), m.heavy(0.07f), MemoBookColor.action, maxLines = 2, minimumScaleFactor = 0.5f, textAlign = TextAlign.Start)
                    }
                    reading.`when`?.let { date ->
                        CoverText(date.uppercase(), m.heavy(0.07f), MemoBookColor.action, maxLines = 1, minimumScaleFactor = 0.5f, textAlign = TextAlign.Start)
                    }
                }
                CoverPostmark(year = reading.`when` ?: cover.title, side = m.u(0.22f))
            }
            Spacer(Modifier.weight(1f))
            StampCollage(Modifier.align(Alignment.CenterHorizontally))
            Spacer(Modifier.weight(1f))
            CoverBadged(subtitleBadge, Alignment.BottomEnd, Modifier.fillMaxWidth()) {
                CoverText(
                    reading.authors.orEmpty().uppercase(),
                    m.heavy(0.055f),
                    MemoBookColor.action,
                    Modifier.fillMaxWidth(),
                    maxLines = 1,
                    minimumScaleFactor = 0.5f,
                    minHeight = m.u(0.06f),
                )
            }
        }
    }

    /** Les timbres : jusqu'à quatre photos du voyage, de travers, bord dentelé, comme le collage de la maquette. */
    @Composable
    private fun StampCollage(modifier: Modifier) {
        val shown = reading.photos.take(4)
        Box(modifier.size(m.u(0.8f), m.u(0.72f)), contentAlignment = Alignment.Center) {
            if (shown.isEmpty()) {
                CoverStamp(null, cover.styleId, m.u(0.4f), Modifier.rotate(-4f))
            }
            shown.forEachIndexed { index, stamp ->
                val place = CoverShapes.stampPlacements[index]
                CoverStamp(
                    stamp,
                    stamp.id,
                    m.u(place.size),
                    Modifier
                        .offset(m.u(place.x), m.u(place.y))
                        .rotate(place.angle),
                )
            }
        }
    }

    /** La photo dans un cadre vert déchiré, la marque dessous. */
    @Composable
    fun BoxScope.TravelBookBack() {
        Column(
            Modifier
                .fillMaxSize()
                .background(MemoBookColor.coverCream)
                .padding(top = m.u(0.12f), bottom = m.u(0.08f)),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.weight(1f))
            Box(Modifier.size(m.u(0.86f), m.u(0.96f))) {
                Picture(photo, Modifier.fillMaxSize().clipToBounds())
                Canvas(Modifier.fillMaxSize().clearAndSetSemantics {}) {
                    drawPath(CoverShapes.roughFrame(size), MemoBookColor.coverForest, style = Stroke(max(2.dp.toPx(), m.px(0.018f))))
                }
            }
            Spacer(Modifier.weight(1f))
            CoverLogo(MemoBookColor.action, Modifier.height(m.u(0.075f)))
        }
    }

    // MARK: - Élégant

    /** Le titre en fines capitales à empattements, la photo comme un tirage, la date dessous. */
    @Composable
    fun BoxScope.ElegantFront() {
        Column(
            Modifier
                .fillMaxSize()
                .background(MemoBookColor.coverCream)
                .padding(start = m.u(0.06f), end = m.u(0.06f), top = m.u(0.08f), bottom = m.u(0.06f)),
            verticalArrangement = Arrangement.spacedBy(m.u(0.05f)),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            CoverBadged(titleBadge, Alignment.TopEnd, Modifier.fillMaxWidth()) {
                CoverText(
                    cover.title.uppercase(),
                    m.serif(0.1f, FontWeight.Normal),
                    MemoBookColor.ink,
                    Modifier.fillMaxWidth(),
                    maxLines = 1,
                    minimumScaleFactor = 0.4f,
                    tracking = m.u(0.004f),
                )
            }
            Picture(photo, Modifier.size(m.u(0.82f), m.u(0.68f)).clipToBounds())
            Spacer(Modifier.weight(1f))
            CoverBadged(subtitleBadge, Alignment.BottomEnd, Modifier.fillMaxWidth()) {
                CoverText(
                    reading.`when`.orEmpty().uppercase(),
                    m.serif(0.04f, FontWeight.Normal),
                    MemoBookColor.ink,
                    Modifier.fillMaxWidth(),
                    maxLines = 1,
                    minimumScaleFactor = 0.5f,
                    tracking = m.u(0.003f),
                    minHeight = m.u(0.05f),
                )
            }
            Spacer(Modifier.weight(1f))
        }
    }

    /** Un paysage en bandeau, quelques lignes à empattements, la marque effacée. */
    @Composable
    fun BoxScope.ElegantBack() {
        Column(
            Modifier
                .fillMaxSize()
                .background(MemoBookColor.coverCream)
                .padding(start = m.u(0.08f), end = m.u(0.08f), top = m.u(0.1f), bottom = m.u(0.07f)),
            verticalArrangement = Arrangement.spacedBy(m.u(0.08f)),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Picture(photo, Modifier.size(m.u(0.84f), m.u(0.26f)).clipToBounds())
            Spacer(Modifier.weight(1f))
            CoverBadged(subtitleBadge, Alignment.TopEnd, Modifier.fillMaxWidth()) {
                if (cover.subtitle.isEmpty()) {
                    CoverPlaceholderFrame(m, 0.2f)
                } else {
                    CoverText(
                        cover.subtitle,
                        m.serif(0.032f, FontWeight.Normal),
                        MemoBookColor.ink,
                        Modifier.fillMaxWidth(),
                        minimumScaleFactor = 0.5f,
                        lineSpacing = m.u(0.006f),
                    )
                }
            }
            Spacer(Modifier.weight(1f))
            CoverLogo(MemoBookColor.separator.copy(alpha = 0.8f), Modifier.height(m.u(0.075f)))
        }
    }
}

// MARK: - La photo d'un plat

/**
 * Une photo de couverture : son image, sinon la trame du voyage. Une image qui
 * ne charge plus redemande des liens neufs (T237) — voir [LocalRefreshCoverPhotos].
 */
@Composable
fun CoverPhotoImage(photo: CoverPhoto?, seed: String, modifier: Modifier = Modifier, colorFilter: ColorFilter? = null) {
    val refresh = LocalRefreshCoverPhotos.current
    val scope = rememberCoroutineScope()
    Box(
        modifier
            .clipToBounds()
            .clearAndSetSemantics {},
    ) {
        // La trame d'abord, la photo par-dessus : elle tient la place tant que
        // la photo charge, et la remplace si elle ne vient pas.
        TripCoverPlaceholder(seed, Modifier.matchParentSize())
        photo?.url?.let { url ->
            AsyncImage(
                model = url,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                colorFilter = colorFilter,
                modifier = Modifier.matchParentSize(),
                onError = { if (refresh != null) scope.launch { refresh() } },
            )
        }
    }
}

/** Les filtres des photos d'« Aquarelle » — la saturation et le contraste de SwiftUI. */
private object CoverColorFilters {
    /** Saturation 1,15, contraste 1,05 : la photo de la maquette, plus vive que nature. */
    val watercolor = ColorFilter.colorMatrix(saturatedContrast(saturation = 1.15f, contrast = 1.05f))

    /** Les images du récit au dos : saturation 1,1. */
    val vignette = ColorFilter.colorMatrix(saturatedContrast(saturation = 1.1f, contrast = 1f))

    private fun saturatedContrast(saturation: Float, contrast: Float): ColorMatrix {
        val matrix = ColorMatrix().apply { setToSaturation(saturation) }
        // Le contraste pivote autour du gris moyen, comme `.contrast(_:)`.
        val offset = 127.5f * (1 - contrast)
        matrix.timesAssign(
            ColorMatrix(
                floatArrayOf(
                    contrast, 0f, 0f, 0f, offset,
                    0f, contrast, 0f, 0f, offset,
                    0f, 0f, contrast, 0f, offset,
                    0f, 0f, 0f, 1f, 0f,
                ),
            ),
        )
        return matrix
    }
}

// MARK: - Les ornements dessinés

/** Un timbre : la photo sur une marge blanche, le bord dentelé. */
@Composable
private fun CoverStamp(photo: CoverPhoto?, seed: String, side: Dp, modifier: Modifier) {
    val edge = remember(side) { PerforatedEdge(tooth = side * 0.035f) }
    Box(
        modifier
            .size(side)
            .dropShadow(edge, DropShadow(radius = side * 0.03f, color = Color.Black.copy(alpha = 0.18f), offset = DpOffset(0.dp, side * 0.015f)))
            .clip(edge)
            .background(MemoBookColor.paper)
            .padding(side * 0.08f),
    ) {
        CoverPhotoImage(photo, seed, Modifier.fillMaxSize())
    }
}

/**
 * Le bord d'un timbre : un rectangle aux dents rondes, découpées tout autour.
 * Les dents sont **retirées** du rectangle — la différence de deux tracés, là
 * où iOS remplit pair-impair : l'ombre suit ainsi le bord dentelé sans déborder.
 */
private class PerforatedEdge(private val tooth: Dp) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline {
        val rect = Path().apply { addRect(Rect(Offset.Zero, size)) }
        val radius = with(density) { tooth.toPx() }
        if (radius <= 0f) return Outline.Generic(rect)
        val teeth = Path()
        val step = radius * 2.6f
        var x = step / 2
        while (x < size.width) {
            teeth.addOval(Rect(Offset(x, 0f), radius))
            teeth.addOval(Rect(Offset(x, size.height), radius))
            x += step
        }
        var y = step / 2
        while (y < size.height) {
            teeth.addOval(Rect(Offset(0f, y), radius))
            teeth.addOval(Rect(Offset(size.width, y), radius))
            y += step
        }
        return Outline.Generic(Path.combine(PathOperation.Difference, rect, teeth))
    }
}

/** Le tampon de « Travel book » : deux cercles, une couronne de points, l'année au milieu, de travers. */
@Composable
private fun CoverPostmark(year: String, side: Dp) {
    val density = LocalDensity.current
    val sidePx = with(density) { side.toPx() }
    Box(
        Modifier
            .size(side)
            .rotate(-12f)
            .alpha(0.85f)
            .clearAndSetSemantics {}
            .drawBehind {
                val outer = max(1.dp.toPx(), sidePx * 0.035f)
                drawCircle(MemoBookColor.coverPostmark, radius = size.minDimension / 2 - outer / 2, style = Stroke(outer))
                val inner = max(0.5.dp.toPx(), sidePx * 0.015f)
                drawCircle(
                    MemoBookColor.coverPostmark,
                    radius = size.minDimension / 2 - sidePx * 0.12f - inner / 2,
                    style = Stroke(inner, pathEffect = PathEffect.dashPathEffect(floatArrayOf(sidePx * 0.02f, sidePx * 0.03f))),
                )
            },
        contentAlignment = Alignment.Center,
    ) {
        BrandText(
            year.uppercase(),
            TextStyle(fontFamily = FontFamily.Serif, fontWeight = FontWeight.ExtraBold, fontSize = with(density) { (side * 0.13f).toSp() }),
            Modifier.padding(side * 0.22f),
            color = MemoBookColor.coverPostmark,
            textAlign = TextAlign.Center,
            maxLines = 2,
            minimumScaleFactor = 0.5f,
        )
    }
}

/**
 * Un titre posé **sur un arc**, comme « PHILIPPINES » sur la photo de
 * « Photo-dessin » : chaque lettre monte puis redescend, et penche avec la
 * courbe. Le mot rapetisse — jusqu'au tiers de sa taille — pour tenir dans
 * [width], comme le `minimumScaleFactor(0.3)` d'iOS.
 *
 * @param rise de combien le milieu du mot monte au-dessus de ses extrémités.
 */
@Composable
private fun CoverArcText(text: String, style: TextStyle, color: Color, rise: Dp, width: Dp) {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val letters = remember(text) { text.map { it.toString() } }
    val natural = remember(letters, style) { letters.sumOf { measurer.measure(it, style, maxLines = 1).size.width } }
    val available = with(density) { width.toPx() }
    val scale = if (natural > available && natural > 0) max(0.3f, available / natural) else 1f
    val fitted = style.copy(color = color, fontSize = style.fontSize * scale)
    val count = max(letters.size - 1, 1)
    Row(
        Modifier
            .width(width)
            .padding(top = rise)
            .clearAndSetSemantics { contentDescription = text },
        horizontalArrangement = Arrangement.Center,
    ) {
        letters.forEachIndexed { index, letter ->
            // De -1 (première lettre) à 1 (dernière) : la parabole d'un arc.
            val position = index.toFloat() / count * 2 - 1
            BasicText(
                letter,
                Modifier
                    .offset(y = -rise * (1 - position * position))
                    .rotate(position * 14f),
                style = fitted,
                maxLines = 1,
                softWrap = false,
            )
        }
    }
}

/** Les tracés des gabarits, rapportés au cadre reçu. */
internal object CoverShapes {
    /** Une place du collage de « Travel book » : décalage et côté en fractions de largeur, angle en degrés. */
    data class StampPlacement(val x: Float, val y: Float, val size: Float, val angle: Float)

    val stampPlacements = listOf(
        StampPlacement(-0.17f, -0.12f, 0.34f, -7f),
        StampPlacement(0.14f, -0.15f, 0.36f, 3f),
        StampPlacement(-0.15f, 0.17f, 0.3f, 4f),
        StampPlacement(0.17f, 0.13f, 0.32f, -5f),
    )

    /**
     * Le trajet du dos « Par défaut » : une route en pointillés qui serpente du
     * haut vers le bas. La maquette dessine la carte du pays visité ; elle
     * viendra du gabarit d'impression, qui connaît les étapes (`carte.js`).
     */
    val routeStops = listOf(
        Offset(0.42f, 0.05f), Offset(0.62f, 0.28f), Offset(0.3f, 0.5f), Offset(0.58f, 0.72f), Offset(0.78f, 0.94f),
    )

    fun routeSketch(size: Size): Path = Path().apply {
        val points = routeStops.map { Offset(it.x * size.width, it.y * size.height) }
        moveTo(points.first().x, points.first().y)
        points.zipWithNext { previous, next ->
            quadraticTo((previous.x + next.x) / 2 + size.width * 0.12f, (previous.y + next.y) / 2, next.x, next.y)
        }
    }

    /** Les chemins en pointillés qui sortent des coins du devant « Dessin ». */
    fun dashedTrails(size: Size): Path {
        val w = size.width
        val h = size.height
        return Path().apply {
            // En haut, de gauche vers le milieu, qui remonte.
            moveTo(0f, h * 0.03f)
            cubicTo(w * 0.3f, 0f, w * 0.55f, h * 0.12f, w * 0.58f, 0f)
            // En haut à droite.
            moveTo(w * 0.9f, 0f)
            quadraticTo(w * 0.95f, h * 0.06f, w, h * 0.08f)
            // À gauche, qui descend jusqu'en bas.
            moveTo(0f, h * 0.61f)
            cubicTo(w * 0.12f, h * 0.7f, w * 0.17f, h * 0.85f, w * 0.15f, h)
            // À droite, qui remonte de bas en haut.
            moveTo(w * 0.82f, h)
            cubicTo(w * 0.78f, h * 0.86f, w * 0.92f, h * 0.8f, w, h * 0.73f)
        }
    }

    /** Les courbes de niveau tracées sur la photo de « Photo-dessin » : quatre contours emboîtés, d'une même forme qui se rétrécit. */
    fun contourLines(size: Size): Path = Path().apply {
        repeat(4) { ring ->
            val inset = ring * 0.11f
            val frame = Rect(
                left = size.width * inset / 2,
                top = size.height * inset / 2,
                right = size.width - size.width * inset / 2,
                bottom = size.height - size.height * inset / 2,
            )
            addPath(blob(frame))
        }
    }

    private fun blob(rect: Rect): Path {
        val w = rect.width
        val h = rect.height
        val x = rect.left
        val y = rect.top
        return Path().apply {
            moveTo(x + w * 0.08f, y + h * 0.35f)
            cubicTo(x + w * 0.1f, y + h * 0.05f, x + w * 0.4f, y, x + w * 0.62f, y + h * 0.02f)
            cubicTo(x + w * 0.85f, y + h * 0.05f, x + w, y + h * 0.25f, x + w, y + h * 0.5f)
            cubicTo(x + w, y + h * 0.8f, x + w * 0.7f, y + h, x + w * 0.4f, y + h)
            cubicTo(x + w * 0.1f, y + h, x, y + h * 0.6f, x + w * 0.08f, y + h * 0.35f)
        }
    }

    /** Les grandes taches du dos « Aquarelle ». */
    fun washes(size: Size): Path {
        val w = size.width
        val h = size.height
        return Path().apply {
            addOval(Rect(Offset(-w * 0.25f, h * 0.18f), Size(w * 0.8f, h * 0.32f)))
            addOval(Rect(Offset(w * 0.45f, h * 0.42f), Size(w * 0.85f, h * 0.28f)))
            addOval(Rect(Offset(-w * 0.1f, h * 0.72f), Size(w * 0.7f, h * 0.25f)))
        }
    }

    /**
     * Le cadre déchiré du dos de « Travel book » : un rectangle dont le bord
     * tremble, toujours de la même façon — un bruit fixe, pas un hasard, le
     * même que sur iOS.
     */
    fun roughFrame(size: Size): Path {
        val jitter = min(size.width, size.height) * 0.008f
        val steps = 48
        fun wobble(index: Int): Float {
            val value = sin(index * 12.9898) * 43_758.5453
            return ((value - floor(value) - 0.5) * 2 * jitter).toFloat()
        }
        val corners = listOf(Offset(0f, 0f), Offset(size.width, 0f), Offset(size.width, size.height), Offset(0f, size.height))
        var index = 0
        return Path().apply {
            for (side in 0 until 4) {
                val start = corners[side]
                val end = corners[(side + 1) % 4]
                for (step in 0 until steps) {
                    val t = step.toFloat() / steps
                    val px = start.x + (end.x - start.x) * t + if (side % 2 == 1) wobble(index) else 0f
                    val py = start.y + (end.y - start.y) * t + if (side % 2 == 0) wobble(index) else 0f
                    if (side == 0 && step == 0) moveTo(px, py) else lineTo(px, py)
                    index += 1
                }
            }
            close()
        }
    }
}
