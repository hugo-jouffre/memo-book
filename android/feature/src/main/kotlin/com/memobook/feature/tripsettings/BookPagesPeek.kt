package com.memobook.feature.tripsettings

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookSpacing
import com.memobook.design.SwiftMotion
import com.memobook.design.isReduceMotionEnabled
import java.net.URI
import com.memobook.feature.bookpreview.BookSheetImage
import com.memobook.feature.bookpreview.BookPageRenderer

/**
 * Deux pages du carnet, l'une sur l'autre, un peu de travers — ce qu'on
 * regarde pendant qu'on règle ce qui les change. Jumeau de
 * `TripSettings/BookPagesPeek.swift`.
 *
 * **En tête de l'écran des personnalisations, elles ne sont plus que le papier
 * nu** qui attend l'aperçu de personnalisation (02/10/2026, voir
 * [BookCustomisationPreviewView]) : le temps que l'image arrive, ou quand elle
 * n'arrive pas. Elles y étaient arrivées le 29/09/2026 (V3 de la maquette,
 * `3595:23801`), et flottaient avant au-dessus des feuilles de réglage, ce qui
 * reste possible — voir [BookPagesPeekOverlay] — pour une feuille qui en aurait
 * besoin.
 *
 * **Sans carnet composé, deux feuilles de papier nues** : la maquette dessine
 * toujours ses deux pages, et un bloc qui disparaît ferait sauter les pastilles
 * et tout le contenu sous elles. Le papier vide dit « il n'y a rien encore », là
 * où deux rectangles blancs *à la place d'un rendu* se liraient comme un rendu
 * raté — c'est la nuance qui décidait, avant, de ne rien montrer.
 *
 * Les deux pages sont les premières du PDF du dernier rendu prêt
 * (`TripSettings.bookPdfUrl`), par le même moteur que l'aperçu.
 *
 * @param pdfUrl le PDF du carnet composé, ou rien.
 * @param size la taille du bloc. Celle de la maquette V3 par défaut : la largeur
 *   de l'écran, et 17.5 rem de haut (280).
 * @param clearance de combien le bloc descend sous son cadre — la réserve
 *   au-dessus d'une feuille, où la poignée passe. Zéro en tête d'écran.
 */
@Composable
internal fun BookPagesPeek(
    pdfUrl: URI?,
    modifier: Modifier = Modifier,
    size: DpSize = BookPagesPeek.headerSize,
    clearance: Dp = 0.dp,
) {
    val context = LocalContext.current
    val renderer = remember(context) { BookPageRenderer(context.cacheDir) }
    var document by remember(renderer) { mutableStateOf(renderer.document) }
    DisposableEffect(renderer) { onDispose { renderer.close() } }
    LaunchedEffect(pdfUrl) {
        val url = pdfUrl ?: return@LaunchedEffect
        document = renderer.load(url.toString())
    }

    // Elles respirent : deux points de haut en bas, lentement. Assez pour dire
    // qu'on regarde un objet, pas une capture.
    val reduceMotion = isReduceMotionEnabled()
    val floating = rememberInfiniteTransition(label = "pages qui flottent")
    val drift by floating.animateFloat(
        initialValue = 2f,
        targetValue = if (reduceMotion) 2f else -2f,
        animationSpec = infiniteRepeatable(tween(3_000, easing = SwiftMotion.easeInOut), RepeatMode.Reverse),
        label = "dérive",
    )

    Box(
        modifier
            .size(size)
            .offset(y = clearance + drift.dp)
            // Décor, et rien d'autre : l'écran sous ces pages dit ce qu'il
            // règle, et TalkBack n'a pas à s'arrêter sur deux images muettes.
            .clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        Page(renderer, document, index = 1, size, Modifier.offset(x = size.width * -0.18f, y = size.height * -0.07f).rotate(BookPagesPeek.backTilt))
        Page(renderer, document, index = 0, size, Modifier.offset(x = size.width * 0.16f, y = size.height * 0.06f).rotate(BookPagesPeek.frontTilt))
    }
}

@Composable
private fun BoxScope.Page(renderer: BookPageRenderer, document: BookPageRenderer.Document, index: Int, size: DpSize, modifier: Modifier) {
    // 80 % de la hauteur du bloc : 223 sur 280, comme la maquette.
    val height = size.height * 0.8f
    val shape = RoundedCornerShape(MemoBookSpacing.xs - 2.dp)

    // Le papier nu tant qu'il n'y a rien à rendre : `BookSheetImage` le dessine
    // lui-même quand le moteur n'a pas de page.
    BookSheetImage(
        renderer,
        document,
        index,
        modifier
            .align(Alignment.Center)
            .width(height * document.aspectRatio)
            .height(height)
            .dropShadow(shape, Shadow(radius = 5.dp, color = Color.Black.copy(alpha = 0.25f), offset = DpOffset(0.dp, 5.dp)))
            .clip(shape)
            .border(2.dp, MemoBookColor.onAction, shape),
    )
}

/** Les mesures des deux pages, en tête d'écran et au-dessus d'une feuille. */
internal object BookPagesPeek {
    /** La taille au-dessus d'une feuille : celle d'avant le 29/09. */
    val sheetSize = DpSize(250.dp, 190.dp)

    /** La taille en tête de l'écran des personnalisations (`3595:23806`). */
    val headerSize = DpSize(358.dp, 280.dp)

    /**
     * Ce que la feuille réserve au-dessus d'elle pour les pages : leur hauteur
     * et un peu d'air, pour que la poignée ne les touche pas.
     */
    val sheetInset: Dp get() = sheetSize.height + MemoBookSpacing.xs

    /** Sous la poignée d'une feuille, pas dessus. */
    val sheetClearance: Dp = MemoBookSpacing.xs * 2 + 5.dp

    /** Les deux inclinaisons de la maquette : celle de derrière penche à gauche, celle de devant à droite. */
    const val backTilt = -6.24f
    const val frontTilt = 10.39f
}

/**
 * Pose les deux pages du carnet au-dessus d'une feuille — le
 * `.bookPagesPeek(pdfUrl:isVisible:)` d'iOS, devenu une enveloppe. Rien sans
 * PDF : au-dessus d'une feuille, deux pages vides se liraient comme un rendu
 * raté.
 */
@Composable
internal fun BookPagesPeekOverlay(pdfUrl: URI?, modifier: Modifier = Modifier, isVisible: Boolean = true, content: @Composable () -> Unit) {
    Box(modifier) {
        content()
        if (isVisible && pdfUrl != null) {
            BookPagesPeek(
                pdfUrl,
                Modifier.align(Alignment.TopCenter),
                size = BookPagesPeek.sheetSize,
                clearance = BookPagesPeek.sheetClearance,
            )
        }
    }
}
