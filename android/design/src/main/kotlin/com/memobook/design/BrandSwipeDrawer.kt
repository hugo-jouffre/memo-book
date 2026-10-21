package com.memobook.design

import androidx.annotation.DrawableRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.AnchoredDraggableDefaults
import androidx.compose.foundation.gestures.AnchoredDraggableState
import androidx.compose.foundation.gestures.DraggableAnchors
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.anchoredDraggable
import androidx.compose.foundation.gestures.animateTo
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.snapTo
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import kotlinx.coroutines.launch
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Une action du tiroir d'une carte : son icône, sa couleur et ce qu'elle fait.
 *
 * @param icon une icône du catalogue (`R.drawable.icon_cross`), là où iOS
 *   reçoit son nom.
 * @param label ce que disent le menu de l'appui long et TalkBack.
 * @param id l'identité de l'action ; par défaut, son icône.
 * @param iconScale pour un tracé plus petit que les autres dans sa boîte —
 *   l'imprimante de l'accueil (×1,15).
 */
class BrandSwipeAction(
    @param:DrawableRes val icon: Int,
    val tint: Color,
    val label: String,
    id: String? = null,
    val iconScale: Float = 1f,
    val action: () -> Unit,
) {
    val id: String = id ?: icon.toString()
}

/**
 * Une carte qui glisse vers la gauche pour découvrir ses actions — celles des
 * voyages de l'accueil, des co-voyageurs de « Inviter un proche ». Jumeau de
 * `BrandSwipeDrawer.swift`.
 *
 * **Un glissé horizontal à deux positions d'arrêt, et non un geste qui vole le
 * doigt** (Hugo, 29/09/2026). Sur iOS, le tiroir était un `DragGesture`
 * prioritaire qui sautait d'une frame à chaque geste et volait le défilement
 * vertical — « le scroll vertical est inactif si on commence depuis un
 * voyage » ; il est devenu une `ScrollView` horizontale, qui se verrouille par
 * sens avec la liste qui la porte. Ici, c'est `anchoredDraggable` de
 * Foundation, qui donne les mêmes garanties :
 *
 * - **il ne prend que l'horizontal** : un doigt qui part vers le haut franchit
 *   d'abord le seuil vertical, et c'est la liste qui défile — le tiroir n'a
 *   rien consommé ;
 * - **ses deux arrêts** — la carte en pleine largeur, ou le tiroir — sont des
 *   ancres, et le relâché va à la plus proche selon la position et l'élan, sans
 *   saut : le décalage est lu au placement, pas recomposé ;
 * - **le toucher de la carte ne part pas au bout d'un glissé** : le glissé
 *   consomme le doigt, et le `clickable` de la carte s'annule de lui-même.
 *
 * Les icônes arrivent en quinconce avec le glissé, comme sur iOS. Rien n'est
 * rogné : Compose ne coupe pas ce qui sort du cadre, la carte glisse jusqu'au
 * bord de l'écran et son scotch dépasse en haut — le masque que la
 * `ScrollView` iOS a dû recomposer n'a pas lieu d'être.
 *
 * **L'appui long ouvre un menu dessiné par la marque** — le menu contextuel du
 * système iOS n'a pas d'équivalent en Compose sans Material : une carte crème
 * sous la carte, les gestes en lignes, le rouge pour celui qui défait. Le
 * téléphone vibre à l'ouverture, et le reste du geste est avalé : la carte ne
 * s'ouvre pas au relâché.
 *
 * **TalkBack reçoit les actions sur la carte elle-même** (`customActions`), le
 * rotor de VoiceOver. Compose n'attache une action qu'au nœud qui la porte :
 * c'est pourquoi [content] reçoit un `Modifier`, à poser **sur le nœud que
 * TalkBack sélectionne** — le `clickable` d'une carte-bouton, ou la racine
 * fusionnée (`semantics(mergeDescendants = true)`) d'une ligne qui n'en est pas
 * une. Posé sur un enfant, il donnerait à TalkBack une seconde étape muette.
 * Le tiroir, lui, est caché à TalkBack.
 *
 * ```kotlin
 * BrandSwipeDrawer(actions) { accessibility ->
 *     TripCard(trip, Modifier.then(accessibility).clickable { … })
 * }
 * ```
 */
@Composable
fun BrandSwipeDrawer(
    actions: List<BrandSwipeAction>,
    modifier: Modifier = Modifier,
    content: @Composable (accessibility: Modifier) -> Unit,
) {
    val accessibility = if (actions.isEmpty()) {
        Modifier
    } else {
        Modifier.semantics {
            customActions = actions.map { item ->
                CustomAccessibilityAction(item.label) {
                    item.action()
                    true
                }
            }
        }
    }
    var showsMenu by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current

    Box(
        if (actions.isEmpty()) {
            modifier
        } else {
            modifier.pointerInput(Unit) {
                detectBrandLongPress {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    showsMenu = true
                }
            }
        },
    ) {
        if (actions.isEmpty()) {
            content(accessibility)
        } else {
            SwipeBand(actions) { content(accessibility) }
        }
        if (showsMenu && actions.isNotEmpty()) {
            BrandSwipeMenu(actions, onDismiss = { showsMenu = false })
        }
    }
}

/** Les deux positions d'arrêt : la carte calée à gauche, ou son tiroir. */
private enum class Slot { Card, Drawer }

@Composable
private fun SwipeBand(actions: List<BrandSwipeAction>, card: @Composable () -> Unit) {
    val density = LocalDensity.current
    val reduceMotion = isReduceMotionEnabled()
    val scope = rememberCoroutineScope()

    val count = actions.size
    val drawerWidth = MemoBookSpacing.minimumTapTarget * count + MemoBookSpacing.xs * (count + 1)
    val drawerPx = with(density) { drawerWidth.toPx() }
    val openThreshold = with(density) { MemoBookSpacing.xs.toPx() }
    val visibleThreshold = with(density) { 0.5.dp.toPx() }

    val state = remember { AnchoredDraggableState(Slot.Card, anchors(drawerPx)) }
    LaunchedEffect(drawerPx) { state.updateAnchors(anchors(drawerPx)) }

    // De combien la bande a glissé, en pixels : c'est ce qui fait arriver les
    // icônes l'une après l'autre. Lu au dessin et au placement seulement.
    val scrolled = { (-state.offset).takeUnless { it.isNaN() }?.coerceAtLeast(0f) ?: 0f }
    // Le tiroir est là, au moins en partie : ses boutons se touchent.
    val isOpen by remember(openThreshold) { derivedStateOf { scrolled() > openThreshold } }

    fun close() {
        scope.launch {
            if (reduceMotion) state.snapTo(Slot.Card) else state.animateTo(Slot.Card, SwiftMotion.snappy(0.25f))
        }
    }

    Layout(
        content = {
            Box(propagateMinConstraints = true) { card() }
            Row(
                Modifier
                    .padding(horizontal = MemoBookSpacing.xs)
                    // **Fermé, il ne se voit pas**, même dans la marge de
                    // l'écran où la carte glisse : ses icônes n'y attendent pas.
                    .graphicsLayer { alpha = if (scrolled() > visibleThreshold) 1f else 0f }
                    // TalkBack passe par les actions de la carte.
                    .clearAndSetSemantics {},
                horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                actions.forEachIndexed { index, item ->
                    DrawerButton(
                        item = item,
                        enabled = isOpen,
                        // **Elles arrivent avec le glissé, en quinconce** (Hugo,
                        // 17/09/2026) : chaque icône suit la carte avec un
                        // retard qui croît de la première à la dernière. Le
                        // retard est un rapport, pas une durée : pas
                        // d'animation à couper quand on relâche à mi-chemin.
                        lag = { if (reduceMotion) 0f else max(0f, drawerPx - scrolled()) * (0.35f + 0.35f * index) },
                        fade = { 1f - min(1f, max(0f, drawerPx - scrolled()) / max(drawerPx, 1f)) * 0.6f },
                    ) {
                        close()
                        item.action()
                    }
                }
            }
        },
        modifier = Modifier.anchoredDraggable(
            state = state,
            orientation = Orientation.Horizontal,
            flingBehavior = AnchoredDraggableDefaults.flingBehavior(
                state,
                positionalThreshold = { distance -> distance * 0.5f },
                animationSpec = SwiftMotion.snappy(0.25f),
            ),
        ),
    ) { measurables, constraints ->
        // La carte prend exactement la largeur de la bande : c'est ce qui fait
        // du tiroir la seule autre position.
        val cardConstraints = if (constraints.hasBoundedWidth) constraints.copy(minWidth = constraints.maxWidth) else constraints
        val cardPlaceable = measurables[0].measure(cardConstraints)
        val drawerPlaceable = measurables[1].measure(
            Constraints.fixed(drawerPx.roundToInt(), cardPlaceable.height),
        )
        layout(cardPlaceable.width, cardPlaceable.height) {
            val offset = -scrolled().roundToInt()
            cardPlaceable.placeRelative(offset, 0)
            drawerPlaceable.placeRelative(cardPlaceable.width + offset, 0)
        }
    }
}

private fun anchors(drawerPx: Float) = DraggableAnchors {
    Slot.Card at 0f
    Slot.Drawer at -drawerPx
}

@Composable
private fun DrawerButton(
    item: BrandSwipeAction,
    enabled: Boolean,
    lag: () -> Float,
    fade: () -> Float,
    onClick: () -> Unit,
) {
    Box(
        Modifier
            .graphicsLayer {
                translationX = lag()
                alpha = fade()
            }
            .size(MemoBookSpacing.minimumTapTarget)
            .border(1.dp, item.tint, CircleShape)
            .clickable(interactionSource = null, indication = null, enabled = enabled, role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Image(
            painter = painterResource(item.icon),
            contentDescription = null,
            colorFilter = ColorFilter.tint(item.tint),
            modifier = Modifier.size(MemoBookSpacing.sectionGap * item.iconScale),
        )
    }
}

/**
 * L'appui long, sans voler le toucher de la carte : il écoute **avant** elle
 * (`Initial`) et ne prend rien tant que le délai n'est pas écoulé. Un doigt qui
 * bouge ou que la liste prend annule tout ; passé le délai, le reste du geste
 * est consommé, et la carte ne s'ouvre pas au relâché.
 */
private suspend fun PointerInputScope.detectBrandLongPress(onLongPress: () -> Unit) {
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
        val released = withTimeoutOrNull(viewConfiguration.longPressTimeoutMillis) {
            var waiting = true
            while (waiting) {
                val change = awaitPointerEvent(PointerEventPass.Final).changes.firstOrNull { it.id == down.id }
                waiting = change != null && change.pressed && !change.isConsumed &&
                    (change.position - down.position).getDistance() <= viewConfiguration.touchSlop
            }
            true
        }
        if (released == null) {
            onLongPress()
            do {
                val event = awaitPointerEvent(PointerEventPass.Initial)
                event.changes.forEach { it.consume() }
            } while (event.changes.any { it.pressed })
        }
    }
}

/**
 * Le menu de l'appui long. Sur iOS, c'est celui du système, qui soulève la
 * carte et floute l'écran ; ici, une carte de la marque posée sous la carte
 * (ou au-dessus, faute de place), les gestes en lignes, sans flou.
 */
@Composable
private fun BrandSwipeMenu(actions: List<BrandSwipeAction>, onDismiss: () -> Unit) {
    val gap = with(LocalDensity.current) { MemoBookSpacing.xs.roundToPx() }
    val position = remember(gap) { MenuPosition(gap) }
    val shape = RoundedCornerShape(MemoBookSpacing.cornerRadius)
    Popup(popupPositionProvider = position, onDismissRequest = onDismiss, properties = PopupProperties(focusable = true)) {
        Column(
            Modifier
                .width(IntrinsicSize.Max)
                .brandShadow(MemoBookShadow.Raised, shape)
                .background(MemoBookColor.surface, shape)
                .clip(shape),
        ) {
            actions.forEachIndexed { index, item ->
                if (index > 0) {
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .height(1.dp)
                            .background(MemoBookColor.hairline),
                    )
                }
                Row(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = MemoBookSpacing.minimumTapTarget)
                        .clickable(role = Role.Button) {
                            onDismiss()
                            item.action()
                        }
                        .padding(horizontal = MemoBookSpacing.s),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    BrandText(
                        item.label,
                        MemoBookFont.body,
                        // Le geste qui défait porte le rouge, comme le rôle
                        // `destructive` du menu iOS.
                        color = if (item.tint == MemoBookColor.error) MemoBookColor.error else MemoBookColor.ink,
                    )
                }
            }
        }
    }
}

/** Sous la carte, calé sur son bord droit ; au-dessus quand la place manque en bas. */
private class MenuPosition(private val gap: Int) : PopupPositionProvider {
    override fun calculatePosition(
        anchorBounds: IntRect,
        windowSize: IntSize,
        layoutDirection: LayoutDirection,
        popupContentSize: IntSize,
    ): IntOffset {
        val x = (anchorBounds.right - popupContentSize.width)
            .coerceIn(gap, max(gap, windowSize.width - popupContentSize.width - gap))
        val below = anchorBounds.bottom + gap
        val y = if (below + popupContentSize.height <= windowSize.height - gap) {
            below
        } else {
            max(gap, anchorBounds.top - gap - popupContentSize.height)
        }
        return IntOffset(x, y)
    }
}

@Preview(name = "Tiroir d’actions", widthDp = 390)
@Composable
private fun BrandSwipeDrawerPreview() {
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        BrandSwipeDrawer(
            actions = listOf(
                BrandSwipeAction(R.drawable.icon_cross, MemoBookColor.error, "Supprimer") {},
                BrandSwipeAction(R.drawable.icon_share_system, MemoBookColor.action, "Partager") {},
                BrandSwipeAction(R.drawable.icon_printer, MemoBookColor.action, "Prévisualiser") {},
            ),
        ) { accessibility ->
            BrandText(
                "Glisse-moi vers la gauche",
                MemoBookFont.body,
                Modifier
                    .then(accessibility)
                    .fillMaxWidth()
                    .background(MemoBookColor.surface, RoundedCornerShape(MemoBookSpacing.largeCornerRadius))
                    .padding(MemoBookSpacing.s),
            )
        }
    }
}
