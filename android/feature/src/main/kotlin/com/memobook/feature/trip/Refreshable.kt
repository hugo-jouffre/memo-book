package com.memobook.feature.trip

import androidx.compose.animation.core.animate
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import com.memobook.design.ActivitySpinner
import com.memobook.design.DeviceScreen
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookSpacing
import com.memobook.design.SwiftMotion
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/**
 * « Tirer pour rafraîchir » — le `.refreshable` de SwiftUI, que Compose
 * Foundation n'a pas (le sien est dans Material, qu'on n'emploie pas).
 *
 * Posé autour d'un contenu qui défile : un glissé vers le bas, une fois en
 * haut, tire le contenu et découvre la roue d'attente ; relâché au-delà du
 * seuil, il relit ([onRefresh]) et la roue tourne jusqu'à la réponse. En deçà,
 * tout revient en place. Le glissé est pris **après** le défilement
 * (`onPostScroll`) : tant que la page peut remonter, c'est elle qui bouge.
 *
 * ⏳ Écrit ici pour l'écran du voyage ; l'accueil et la galerie en ont le même
 * besoin — à monter dans `:design` quand ils le prendront.
 */
@Composable
internal fun Refreshable(onRefresh: suspend () -> Unit, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()
    val refresh by rememberUpdatedState(onRefresh)
    val threshold = with(density) { 72.dp.toPx() }
    val resting = with(density) { 56.dp.toPx() }
    var pull by remember { mutableFloatStateOf(0f) }
    var isRefreshing by remember { mutableStateOf(false) }

    val connection = remember {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                // Le contenu tiré remonte d'abord, avant que la page ne défile.
                if (isRefreshing || pull <= 0f || available.y >= 0f) return Offset.Zero
                val taken = maxOf(available.y, -pull)
                pull += taken
                return Offset(0f, taken)
            }

            override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
                if (isRefreshing || source != NestedScrollSource.UserInput || available.y <= 0f) return Offset.Zero
                // La moitié du doigt : on sent la résistance, comme sur iOS.
                pull += available.y / 2
                return Offset(0f, available.y)
            }

            override suspend fun onPreFling(available: Velocity): Velocity {
                if (pull <= 0f || isRefreshing) return Velocity.Zero
                if (pull >= threshold) {
                    // La relecture part à côté du geste : le doigt est levé, la
                    // roue tourne jusqu'à la réponse.
                    isRefreshing = true
                    scope.launch {
                        animate(pull, resting, animationSpec = SwiftMotion.smooth(0.3f)) { value, _ -> pull = value }
                        try {
                            refresh()
                        } finally {
                            isRefreshing = false
                            animate(pull, 0f, animationSpec = SwiftMotion.smooth(0.3f)) { value, _ -> pull = value }
                        }
                    }
                } else {
                    animate(pull, 0f, animationSpec = SwiftMotion.smooth(0.3f)) { value, _ -> pull = value }
                }
                return available
            }
        }
    }

    Box(modifier.nestedScroll(connection)) {
        Box(Modifier.graphicsLayer { translationY = pull }) { content() }

        if (pull > 0f || isRefreshing) {
            ActivitySpinner(
                MemoBookColor.ink,
                Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = DeviceScreen.topSafeInset() + MemoBookSpacing.xs)
                    .offset { IntOffset(0, (pull / 2 - with(density) { 9.dp.toPx() }).roundToInt().coerceAtLeast(0)) }
                    .alpha(if (isRefreshing) 1f else (pull / threshold).coerceIn(0f, 1f))
                    .semantics { contentDescription = "Chargement" },
            )
        }
    }
}
