package com.memobook.feature.bookpreview

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.core.BookCopy
import com.memobook.design.BrandHeaderAction
import com.memobook.design.BrandScreenHeader
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import kotlin.math.abs

/**
 * L'aperçu **plein cadre** : la page occupe tout ce que l'écran peut lui
 * donner, et le reste se pose dessus. Jumeau de `BookPreview/BookFullScreenView.swift`.
 *
 * Ce n'est pas un écran de plus mais un mode de l'aperçu — d'où le fait qu'il
 * n'ait pas sa propre entrée dans `HomeRoute` : la flèche de retour doit
 * ramener au voyage, pas à la version réduite. C'est le rond `normal_screen`,
 * en haut à gauche de la page, qui revient en arrière. Le geste de retour du
 * système, lui, ramène au voyage, comme la flèche.
 *
 * Trois choses le distinguent du mode réduit, et toutes les trois viennent de
 * la maquette :
 *
 * 1. **La page déborde la marge d'écran.** C'est le seul endroit de l'app où
 *    quelque chose sort de la colonne, et c'est ce qui fait le plein écran.
 * 2. **Les commandes flottent sur la page** au lieu d'être posées dessous.
 * 3. **La bande de miniatures** remplace l'indicateur : en plein écran on saute
 *    d'une page à l'autre, on ne les tourne plus une par une.
 */
@Composable
internal fun BookFullScreenView(model: BookPreviewModel, onShare: () -> Unit, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val state by model.state.collectAsStateWithLifecycle()

    Column(
        modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding(),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        FullScreenHeader(state, onShare, onBack)
        FullScreenPage(model, state, Modifier.weight(1f))
        Filmstrip(model, state)
    }
}

/**
 * Le même en-tête que le mode réduit, au filet près : la maquette lui ajoute
 * une ligne de séparation en bas, parce que la page qui suit monte jusqu'à lui.
 */
@Composable
private fun FullScreenHeader(state: BookPreviewModel.State, onShare: () -> Unit, onBack: () -> Unit) {
    BrandScreenHeader(
        BookCopy.Preview.title,
        onBack = onBack,
        modifier = Modifier
            .drawBehind {
                drawRect(MemoBookColor.hairline, topLeft = Offset(0f, size.height - 1.dp.toPx()))
            }
            .padding(horizontal = MemoBookSpacing.screenMargin)
            .padding(top = MemoBookSpacing.xs),
        subtitle = BookCopy.Preview.subtitle(title = state.preview?.title ?: "", pages = state.sheetCount),
        trailing = { BrandHeaderAction(R.drawable.icon_share_system, BookCopy.Preview.Voice.share, action = onShare) },
    )
}

/**
 * La page, et tout ce qui flotte dessus.
 *
 * Elle occupe la hauteur restante et déborde la marge d'écran des deux côtés —
 * c'est ce que la maquette dessine (420 de large sur un écran de 390). Le
 * débordement passe par une mesure **plus large que la colonne**, recentrée,
 * plutôt que par une largeur en dur : celle-ci aurait figé le dessin à un
 * modèle de téléphone. (Compose n'a pas de marge négative.)
 */
@Composable
private fun FullScreenPage(model: BookPreviewModel, state: BookPreviewModel.State, modifier: Modifier = Modifier) {
    var width by remember { mutableIntStateOf(0) }
    val overflow = with(LocalDensity.current) { (MemoBookSpacing.snug * 2).roundToPx() }

    Box(
        modifier
            .fillMaxWidth()
            .clipToBounds()
            .layout { measurable, constraints ->
                val wide = constraints.maxWidth + overflow
                val placeable = measurable.measure(constraints.copy(minWidth = wide, maxWidth = wide))
                layout(constraints.maxWidth, placeable.height) { placeable.place(-overflow / 2, 0) }
            }
            .onSizeChanged { width = it.width }
            // Le glissé horizontal tourne les pages. C'est le geste qu'on essaie
            // d'abord sur une image plein écran, et le seul qui ne demande pas
            // de viser une commande.
            .pageTurnGesture(model),
    ) {
        Crossfade(
            targetState = state.sheetIndex,
            animationSpec = tween(180, easing = SwiftMotion.easeInOut),
            label = "feuille",
        ) { index ->
            BookSheetFace(model.renderer, state, index, Modifier.fillMaxSize())
        }

        AnimatedVisibility(
            visible = state.isOnConfigurableCover,
            modifier = Modifier.fillMaxSize(),
            enter = fadeIn(tween(200, easing = SwiftMotion.easeInOut)),
            exit = fadeOut(tween(200, easing = SwiftMotion.easeInOut)),
        ) {
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.4f)))
        }

        // Les commandes restent dans la colonne : seule la page déborde.
        Box(Modifier.fillMaxSize().padding(horizontal = MemoBookSpacing.snug)) {
            TopControls(model, state, Modifier.align(Alignment.TopCenter))
            Pager(model, state, Modifier.align(Alignment.BottomCenter))
        }
    }

    LaunchedEffect(state.sheetIndex, width, state.document.generation) {
        model.renderer.prepare(around = state.sheetIndex, width = width)
    }
}

/** Le retour au mode réduit, et le compteur de feuilles. */
@Composable
private fun TopControls(model: BookPreviewModel, state: BookPreviewModel.State, modifier: Modifier = Modifier) {
    Row(
        modifier
            .fillMaxWidth()
            .padding(horizontal = MemoBookSpacing.snug)
            .padding(top = MemoBookSpacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BookScreenModeButton(
            R.drawable.icon_normal_screen,
            BookCopy.Preview.Voice.exitFullScreen,
            action = { model.setFullScreen(false) },
        )

        Spacer(Modifier.weight(1f))

        BrandText(
            BookCopy.Preview.sheetIndicator(state.sheetIndex + 1, of = maxOf(state.sheetCount, 1)),
            MemoBookFont.bodySemibold.copy(fontFeatureSettings = "tnum"),
            Modifier
                // Le gris système et non le crème de la marque : la pastille est
                // posée sur une photo dont on ne choisit pas les couleurs, et
                // c'est le matériau qui la rend lisible partout. Relevé sur la
                // maquette (`Grays/Gray 6`). Android n'a pas le verre dépoli
                // d'iOS : le gris 6 à 85 % en tient lieu.
                .background(SystemGray6.copy(alpha = 0.85f), RoundedCornerShape(MemoBookSpacing.snug))
                .padding(horizontal = MemoBookSpacing.xs, vertical = MemoBookSpacing.xs / 2),
            color = MemoBookColor.inkMuted,
        )
    }
}

/** Le `systemGray6` d'iOS, le gris de la maquette sous le compteur de feuilles. */
private val SystemGray6 = Color(0xFFF2F2F7)

/** La barre de pagination posée en bas de la page : trois pastilles bleues sur un voile crème, comme la maquette. */
@Composable
private fun Pager(model: BookPreviewModel, state: BookPreviewModel.State, modifier: Modifier = Modifier) {
    Row(
        modifier
            .fillMaxWidth()
            // Le voile crème de la maquette : la barre doit rester lisible sur
            // une photo pleine page sans la masquer.
            .background(MemoBookColor.background.copy(alpha = 0.7f))
            .padding(horizontal = MemoBookSpacing.s, vertical = MemoBookSpacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        PagerArrow(BookPageArrowDirection.Backward, isEnabled = state.canGoBack, action = model::goBack)
        Spacer(Modifier.weight(1f))

        BrandText(
            BookCopy.Preview.pageIndicator(state.sheetIndex + 1, of = maxOf(state.sheetCount, 1)),
            MemoBookFont.body.copy(fontFeatureSettings = "tnum"),
            Modifier
                .background(MemoBookColor.outline, CircleShape)
                .padding(horizontal = MemoBookSpacing.snug, vertical = MemoBookSpacing.xs),
            color = MemoBookColor.ink,
        )

        Spacer(Modifier.weight(1f))
        PagerArrow(BookPageArrowDirection.Forward, isEnabled = state.canGoForward, action = model::goForward)
    }
}

@Composable
private fun PagerArrow(direction: BookPageArrowDirection, isEnabled: Boolean, action: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val label = if (direction == BookPageArrowDirection.Backward) BookCopy.Preview.Voice.previousPage else BookCopy.Preview.Voice.nextPage
    Box(
        Modifier
            .sizeIn(minWidth = MemoBookSpacing.minimumTapTarget, minHeight = MemoBookSpacing.minimumTapTarget)
            .clickable(interactionSource = interaction, indication = PlainButtonIndication, enabled = isEnabled, role = Role.Button, onClick = action)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .background(MemoBookColor.outline.copy(alpha = if (isEnabled) 1f else 0.5f), CircleShape)
                .padding(horizontal = MemoBookSpacing.snug, vertical = MemoBookSpacing.xs + 1.dp),
        ) {
            Image(
                painter = painterResource(R.drawable.icon_chevron),
                contentDescription = null,
                colorFilter = ColorFilter.tint(MemoBookColor.ink),
                modifier = Modifier
                    .size(MemoBookSpacing.snug)
                    .rotate(if (direction == BookPageArrowDirection.Backward) 180f else 0f),
            )
        }
    }
}

/**
 * Toutes les feuilles du carnet, en petit, pour sauter n'importe où.
 *
 * La feuille courante est **plus haute** que les autres — c'est ce que dessine
 * la maquette (65 contre 59) — et c'est ce qui la désigne sans avoir besoin
 * d'un cadre de sélection.
 *
 * Une `LazyRow` : un carnet de soixante pages ne rend que les miniatures
 * visibles, pas les soixante.
 */
@Composable
private fun Filmstrip(model: BookPreviewModel, state: BookPreviewModel.State) {
    val list = rememberLazyListState()

    LazyRow(
        state = list,
        modifier = Modifier
            .fillMaxWidth()
            .height(CURRENT_THUMBNAIL_HEIGHT),
        contentPadding = PaddingValues(horizontal = MemoBookSpacing.screenMargin),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        items(count = maxOf(state.sheetCount, 0), key = { it }) { index ->
            Thumbnail(model, state, index)
        }
    }

    // La bande suit la page : tourner avec les flèches doit amener la miniature
    // correspondante sous les yeux.
    LaunchedEffect(state.sheetIndex) {
        val layout = list.layoutInfo
        val item = layout.visibleItemsInfo.firstOrNull { it.index == state.sheetIndex }
        val viewport = layout.viewportEndOffset - layout.viewportStartOffset
        if (item != null) {
            list.animateScrollBy((item.offset + item.size / 2 - viewport / 2).toFloat(), SwiftMotion.snappy(0.3f))
        } else if (state.sheetIndex < state.sheetCount) {
            list.animateScrollToItem(state.sheetIndex)
        }
    }
}

private val CURRENT_THUMBNAIL_HEIGHT = 66.dp
private val THUMBNAIL_HEIGHT = 60.dp

@Composable
private fun Thumbnail(model: BookPreviewModel, state: BookPreviewModel.State, index: Int) {
    val isCurrent = index == state.sheetIndex
    val height = if (isCurrent) CURRENT_THUMBNAIL_HEIGHT else THUMBNAIL_HEIGHT
    val shape = RoundedCornerShape(2.dp)
    val interaction = remember { MutableInteractionSource() }

    Box(
        Modifier
            // La cible tactile est plus large que la miniature : une page de
            // 42 dp de large ne se vise pas au doigt (R7).
            .widthIn(min = MemoBookSpacing.minimumTapTarget)
            .clickable(interactionSource = interaction, indication = PlainButtonIndication, role = Role.Button) { model.show(sheet = index) }
            .semantics {
                contentDescription = BookCopy.Preview.pageIndicator(index + 1, of = maxOf(state.sheetCount, 1))
                selected = isCurrent
            },
        contentAlignment = Alignment.Center,
    ) {
        BookSheetFace(
            model.renderer,
            state,
            index,
            Modifier
                .height(height)
                .aspectRatio(state.document.aspectRatio)
                .clip(shape)
                .border(if (isCurrent) 1.5.dp else 1.dp, if (isCurrent) MemoBookColor.action else MemoBookColor.hairline, shape),
        )
    }
}

/**
 * Tourner la page d'un glissé : vers la gauche on avance, vers la droite on
 * revient.
 *
 * Le seuil est franc — 50 dp — et le geste doit rester horizontal : sans ces
 * deux conditions, remonter l'écran d'un doigt un peu de travers changerait de
 * page. Le détecteur horizontal de Compose ne prend le doigt qu'une fois parti
 * à l'horizontale ; le défilement vertical garde le reste.
 */
internal fun Modifier.pageTurnGesture(model: BookPreviewModel): Modifier = pointerInput(model) {
    val threshold = 50.dp.toPx()
    var travelled = 0f
    detectHorizontalDragGestures(
        onDragStart = { travelled = 0f },
        onDragEnd = {
            if (abs(travelled) > threshold) {
                if (travelled < 0) model.goForward() else model.goBack()
            }
        },
        onHorizontalDrag = { change, amount ->
            travelled += amount
            change.consume()
        },
    )
}

