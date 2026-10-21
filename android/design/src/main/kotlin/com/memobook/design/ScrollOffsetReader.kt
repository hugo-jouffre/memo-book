package com.memobook.design

import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.interaction.DragInteraction
import androidx.compose.foundation.interaction.InteractionSource
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import kotlinx.coroutines.launch

// Le jumeau de `ScrollOffsetReader.swift` (`.brandScrollOffset(_:)`).
//
// ⚠️ Sur iOS, la mesure passe par l'`UIScrollView` elle-même, observée, et
// **pas par un `GeometryReader`** : la conversation en posait un en fond de sa
// liste paresseuse, et lire le cadre de la liste la faisait se replacer, ce
// qui déplaçait le défilement, ce qui la faisait se replacer — l'app à 100 %
// d'un cœur, conversation ouverte et personne ne la touchant (recette du
// 30/09/2026). Ici, même règle, et Compose la rend simple : on lit l'**état**
// de la liste (`ScrollState`, `LazyListState`), jamais sa mise en page. Rien
// ne se redemande, rien ne boucle.
//
// Compose n'a pas de liste « englobante » à aller chercher depuis le contenu :
// c'est l'écran qui passe l'état de sa liste, celui qu'il a déjà en main.

/**
 * Dit de combien une colonne défilante a défilé.
 *
 * @param onChange le haut du contenu par rapport au haut du cadre, **négatif**
 *   quand on descend vers la fin ; ce qui reste à défiler **sous** l'écran
 *   (`bottomGap`, zéro tout en bas) ; et **si c'est le doigt** qui fait défiler
 *   — pendant le glissé ou l'élan qui le suit. Une liste qui se cale en bas à
 *   l'ouverture, un `animateScrollTo` à l'arrivée d'un message bougent aussi
 *   le contenu, et ce ne sont pas des gestes.
 */
@Composable
fun BrandScrollOffset(state: ScrollState, onChange: (top: Dp, bottomGap: Dp, byUser: Boolean) -> Unit) {
    ObserveScroll(
        interactions = state.interactionSource,
        isScrolling = { state.isScrollInProgress },
        measure = { -state.value.toFloat() to (state.maxValue - state.value).toFloat() },
        onChange = onChange,
    )
}

/**
 * Dit de combien une liste paresseuse a défilé — la conversation.
 *
 * Une liste paresseuse ne connaît que les lignes qu'elle a mesurées : le haut
 * est exact tant que la première ligne est à l'écran, puis **estimé** à partir
 * de la hauteur moyenne des lignes visibles ; `bottomGap` est exact dès que la
 * dernière ligne est à l'écran — c'est là qu'on en a besoin, pour savoir si
 * l'on est en bas. Une liste dans le sens de lecture : pas de `reverseLayout`.
 * Mêmes paramètres que pour une colonne.
 */
@Composable
fun BrandScrollOffset(state: LazyListState, onChange: (top: Dp, bottomGap: Dp, byUser: Boolean) -> Unit) {
    ObserveScroll(
        interactions = state.interactionSource,
        isScrolling = { state.isScrollInProgress },
        measure = { lazyListOffsets(state) },
        onChange = onChange,
    )
}

private fun lazyListOffsets(state: LazyListState): Pair<Float, Float> {
    val info = state.layoutInfo
    val visible = info.visibleItemsInfo
    if (visible.isEmpty()) return 0f to 0f
    val last = visible.last()
    // Une ligne et son espacement, en moyenne sur ce qui est à l'écran.
    val averageSize = visible.sumOf { it.size + info.mainAxisItemSpacing }.toFloat() / visible.size
    val top = -(state.firstVisibleItemIndex * averageSize + state.firstVisibleItemScrollOffset)
    // Ce qui dépasse sous le bas visible — la marge du bas comprise : c'est la
    // barre d'envoi qui la pose.
    val hiddenBelow = (info.totalItemsCount - 1 - last.index) * averageSize
    val bottomGap = last.offset + last.size + info.afterContentPadding - info.viewportEndOffset + hiddenBelow
    return top to bottomGap
}

/**
 * Le « c'est le doigt » : un glissé a commencé, et le défilement qui le suit
 * — l'élan — lui appartient jusqu'à l'arrêt. Un défilement qui démarre sans
 * glissé est celui du programme.
 */
@Composable
private fun ObserveScroll(
    interactions: InteractionSource,
    isScrolling: () -> Boolean,
    measure: () -> Pair<Float, Float>,
    onChange: (top: Dp, bottomGap: Dp, byUser: Boolean) -> Unit,
) {
    val density = LocalDensity.current
    val latest by rememberUpdatedState(onChange)
    LaunchedEffect(interactions, density) {
        var dragging = false
        var userDriven = false
        launch {
            interactions.interactions.collect { interaction ->
                when (interaction) {
                    is DragInteraction.Start -> {
                        dragging = true
                        userDriven = true
                    }
                    is DragInteraction.Stop, is DragInteraction.Cancel -> dragging = false
                }
            }
        }
        snapshotFlow { measure() to isScrolling() }.collect { (offsets, scrolling) ->
            if (!scrolling && !dragging) userDriven = false
            latest(offsets.first.toDp(density), offsets.second.toDp(density), userDriven && (scrolling || dragging))
        }
    }
}

private fun Float.toDp(density: Density): Dp = with(density) { this@toDp.toDp() }
