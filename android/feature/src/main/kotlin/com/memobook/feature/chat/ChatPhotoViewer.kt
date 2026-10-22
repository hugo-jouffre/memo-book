package com.memobook.feature.chat

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.IntOffset
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import com.memobook.core.ChatCopy
import com.memobook.core.PhotoAttachment
import com.memobook.design.ActivitySpinner
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.isReduceMotionEnabled
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * **Une photo du fil en plein écran** (Hugo, 18/10/2026 : « quand on est dans
 * le chat et qu'on clique sur une photo qu'on a envoyée, elle s'affiche en
 * plein écran »). Jumeau de `ChatPhotoViewer.swift`.
 *
 * On entre par la photo touchée ; on passe aux autres photos de la même bulle
 * d'un glissé latéral — celles que la bulle cachait sous « +N » comprises. Un
 * pincement ou un double appui zoome, un glissé vers le bas referme quand la
 * photo n'est pas zoomée. Le fond est l'encre de la marque, pas un noir pur :
 * la photo reste le seul objet de l'écran. Le retour du système referme, comme
 * le `fullScreenCover` d'iOS ; la barre d'état se cache le temps de regarder.
 *
 * Les images sont relues **à leur taille d'écran** (`ChatModel.fullScreenImage`),
 * la vignette du fil sert d'attente : on ne voit jamais un écran vide.
 */
@Composable
fun ChatPhotoViewer(viewing: ChatPhotoViewing, model: ChatModel, onClose: () -> Unit) {
    val pager = rememberPagerState(initialPage = viewing.index) { viewing.attachments.size }
    var isZoomed by remember { mutableStateOf(false) }
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()
    // Le glissé vers le bas en cours, pour suivre le doigt avant de refermer.
    val dismissOffset = remember { Animatable(0f) }
    val dismissThreshold = with(density) { 140.dp.toPx() }
    val flingThreshold = with(density) { 1_200.dp.toPx() }
    val fadeDistance = with(density) { 600.dp.toPx() }

    BackHandler(onBack = onClose)
    HideStatusBar()
    // Une autre photo a pris la place : celle-ci repart à 1×.
    LaunchedEffect(pager.currentPage) { isZoomed = false }

    Box(Modifier.fillMaxSize()) {
        Box(
            Modifier
                .fillMaxSize()
                .alpha(1f - minOf(0.6f, abs(dismissOffset.value) / fadeDistance))
                .background(MemoBookColor.ink),
        )

        HorizontalPager(
            state = pager,
            userScrollEnabled = !isZoomed,
            modifier = Modifier
                .fillMaxSize()
                .offset { IntOffset(0, dismissOffset.value.roundToInt()) }
                // Vers le bas, la photo suit le doigt ; lâchée assez loin, elle
                // se referme.
                .draggable(
                    orientation = Orientation.Vertical,
                    enabled = !isZoomed,
                    state = rememberDraggableState { delta ->
                        scope.launch { dismissOffset.snapTo(maxOf(0f, dismissOffset.value + delta)) }
                    },
                    onDragStopped = { velocity ->
                        if (dismissOffset.value > dismissThreshold || velocity > flingThreshold) {
                            onClose()
                        } else {
                            dismissOffset.animateTo(0f, SwiftMotion.smooth(0.25f))
                        }
                    },
                ),
            key = { viewing.attachments[it].id },
        ) { page ->
            ZoomablePhoto(
                attachment = viewing.attachments[page],
                model = model,
                isCurrent = page == pager.currentPage,
                onZoomChange = { isZoomed = it },
            )
        }

        ViewerHeader(
            position = pager.currentPage + 1,
            count = viewing.attachments.size,
            isVisible = dismissOffset.value == 0f,
            onClose = onClose,
        )
    }
}

@Composable
private fun ViewerHeader(position: Int, count: Int, isVisible: Boolean, onClose: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .safeDrawingPadding()
            .padding(horizontal = MemoBookSpacing.screenMargin)
            .padding(top = MemoBookSpacing.xs)
            .alpha(if (isVisible) 1f else 0f),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(MemoBookSpacing.minimumTapTarget)
                .background(MemoBookColor.ink.copy(alpha = 0.4f), CircleShape)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = PlainButtonIndication,
                    role = Role.Button,
                    onClick = onClose,
                )
                .semantics { contentDescription = ChatCopy.PhotoViewer.close },
            contentAlignment = Alignment.Center,
        ) {
            Image(
                painter = painterResource(R.drawable.icon_lucide_close),
                contentDescription = null,
                colorFilter = ColorFilter.tint(MemoBookColor.paper),
                modifier = Modifier.size(20.dp),
            )
        }

        Spacer(Modifier.weight(1f))

        if (count > 1) {
            BrandText(
                ChatCopy.PhotoViewer.position(position, of = count),
                MemoBookFont.caption,
                Modifier
                    .background(MemoBookColor.ink.copy(alpha = 0.4f), RoundedCornerShape(percent = 50))
                    .padding(horizontal = MemoBookSpacing.s, vertical = MemoBookSpacing.xs),
                color = MemoBookColor.paper,
            )
        }
    }
}

/**
 * Une photo qui se zoome : pincement de 1× à 4×, double appui pour basculer
 * entre 1× et 2,5×, glissé pour se promener dans la photo zoomée. Un seul
 * doigt sur une photo à 1× n'est pas à elle : il tourne les pages, ou referme.
 */
@Composable
private fun ZoomablePhoto(attachment: PhotoAttachment, model: ChatModel, isCurrent: Boolean, onZoomChange: (Boolean) -> Unit) {
    val url = attachment.displayUrl
    var full by remember(url) { mutableStateOf<ImageBitmap?>(null) }
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    val reduceMotion = isReduceMotionEnabled()
    val shownScale by animateFloatAsState(scale, if (reduceMotion) androidx.compose.animation.core.snap() else SwiftMotion.smooth(0.25f), label = "zoom")

    fun reset() {
        scale = 1f
        offset = Offset.Zero
        onZoomChange(false)
    }

    LaunchedEffect(url) {
        url ?: return@LaunchedEffect
        model.loadImage(url)
        full = model.fullScreenImage(url)
    }
    // Quittée, la photo repart à 1×.
    LaunchedEffect(isCurrent) { if (!isCurrent && scale != 1f) reset() }

    val thumbnail = url?.let { chatImage(model, it) }
    val shown = full ?: thumbnail

    Box(
        Modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                detectTapGestures(
                    onDoubleTap = {
                        if (scale > 1f) {
                            reset()
                        } else {
                            scale = 2.5f
                            onZoomChange(true)
                        }
                    },
                )
            }
            .pointerInput(Unit) {
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false)
                    do {
                        val event = awaitPointerEvent()
                        val fingers = event.changes.count { it.pressed }
                        if (fingers >= 2 || scale > 1f) {
                            scale = (scale * event.calculateZoom()).coerceIn(1f, 4f)
                            offset = if (scale > 1f) offset + event.calculatePan() else Offset.Zero
                            onZoomChange(scale > 1f)
                            event.changes.forEach { if (it.positionChanged()) it.consume() }
                        }
                    } while (event.changes.any { it.pressed })
                    if (scale <= 1.02f && scale != 1f) reset()
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        if (shown != null) {
            Image(
                bitmap = shown,
                contentDescription = ChatCopy.PhotoViewer.photo,
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .fillMaxSize()
                    .graphicsLayer {
                        scaleX = shownScale
                        scaleY = shownScale
                        translationX = offset.x
                        translationY = offset.y
                    },
            )
        } else {
            ActivitySpinner(MemoBookColor.paper)
        }
    }
}

/** La barre d'état se cache le temps du plein écran — le `.statusBarHidden()` d'iOS — et revient en partant. */
@Composable
private fun HideStatusBar() {
    val view = LocalView.current
    val activity = LocalContext.current.findActivity()
    DisposableEffect(activity, view) {
        val window = activity?.window ?: return@DisposableEffect onDispose {}
        val controller = WindowCompat.getInsetsController(window, view)
        controller.hide(WindowInsetsCompat.Type.statusBars())
        onDispose { controller.show(WindowInsetsCompat.Type.statusBars()) }
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
