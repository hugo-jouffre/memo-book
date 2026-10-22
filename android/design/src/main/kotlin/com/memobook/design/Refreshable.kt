package com.memobook.design

import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.animate
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * **Tirer pour rafraîchir** — le `.refreshable` de SwiftUI, que Compose
 * Foundation n'a pas : celui d'Android vit dans Material, qu'on n'emploie pas.
 * Comme [BrandText] ou [ActivitySpinner], une pièce du système et non de la
 * marque, écrite une fois.
 *
 * Le contenu qui défile déjà tout en haut **descend sous le doigt**, à moitié
 * de sa course — la résistance d'iOS —, et découvre la roue. Relâché au-delà
 * du seuil, il reste ouvert le temps de [onRefresh], puis remonte ; en deçà, il
 * remonte tout de suite. Un défilement vers le haut pendant qu'il est tiré le
 * referme d'abord, au lieu de faire défiler la liste sous lui.
 *
 * **TalkBack ne tire pas** : l'action « Actualiser » est posée sur le contenu,
 * où le geste à trois doigts de VoiceOver la cherche sur iOS.
 *
 * ```kotlin
 * Refreshable(onRefresh = { model.load() }, indicatorTop = DeviceScreen.topSafeInset()) {
 *     Column(Modifier.verticalScroll(rememberScrollState())) { … }
 * }
 * ```
 *
 * @param onRefresh la relecture. La roue tourne jusqu'à son retour.
 * @param indicatorTop où la roue se pose quand le contenu est tiré — sous la
 *   barre d'état d'un écran qui passe dessous.
 */
@Composable
fun Refreshable(
    onRefresh: suspend () -> Unit,
    modifier: Modifier = Modifier,
    indicatorTop: Dp = 0.dp,
    content: @Composable BoxScope.() -> Unit,
) {
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()
    val refresh by rememberUpdatedState(onRefresh)
    val threshold = with(density) { RefreshableMetrics.threshold.toPx() }
    val resting = with(density) { RefreshableMetrics.restingOffset.toPx() }
    val pull = remember(threshold, resting) { RefreshPull(scope, threshold, resting) { refresh() } }

    Box(
        modifier
            .nestedScroll(pull)
            .semantics {
                customActions = listOf(
                    CustomAccessibilityAction(RefreshableMetrics.accessibilityLabel) {
                        pull.refreshNow()
                        true
                    },
                )
            },
    ) {
        Box(Modifier.graphicsLayer { translationY = pull.offset }) {
            content()
        }

        // La roue, au-dessus du contenu qu'elle découvre : elle paraît à mesure
        // qu'on tire, et tourne pendant la relecture.
        if (pull.offset > 0f || pull.isRefreshing) {
            ActivitySpinner(
                color = MemoBookColor.inkMuted,
                size = 22.dp,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = indicatorTop)
                    .graphicsLayer {
                        val revealed = (pull.offset / threshold).coerceIn(0f, 1f)
                        alpha = if (pull.isRefreshing) 1f else revealed
                        translationY = pull.offset / 2 - with(density) { 11.dp.toPx() }
                    }
                    .clearAndSetSemantics {},
            )
        }
    }
}

/** Les mesures du geste. */
internal object RefreshableMetrics {
    /** Ce qu'il faut tirer pour que le relâché relise. */
    val threshold: Dp = 72.dp

    /** Où le contenu attend pendant la relecture : de quoi voir la roue. */
    val restingOffset: Dp = 52.dp

    /** La résistance du geste : le contenu suit le doigt à moitié. */
    const val RESISTANCE = 0.5f

    const val accessibilityLabel = "Actualiser"
}

/** L'état du geste : de combien le contenu est descendu, et s'il relit. */
private class RefreshPull(
    private val scope: CoroutineScope,
    private val threshold: Float,
    private val resting: Float,
    private val onRefresh: suspend () -> Unit,
) : NestedScrollConnection {
    /** En pixels. Posé à chaque pas du doigt, sans attendre une image. */
    var offset by mutableFloatStateOf(0f)
        private set

    var isRefreshing by mutableStateOf(false)
        private set

    override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
        // Le contenu est tiré et le doigt remonte : on le referme avant de faire
        // défiler la liste.
        if (source != NestedScrollSource.UserInput || available.y >= 0f || offset <= 0f || isRefreshing) return Offset.Zero
        val next = (offset + available.y).coerceAtLeast(0f)
        val consumed = next - offset
        offset = next
        return Offset(0f, consumed)
    }

    override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
        // La liste est en haut et le doigt descend encore : c'est le contenu qui
        // descend, avec résistance.
        if (source != NestedScrollSource.UserInput || available.y <= 0f || isRefreshing) return Offset.Zero
        offset += available.y * RefreshableMetrics.RESISTANCE
        return Offset(0f, available.y)
    }

    override suspend fun onPreFling(available: Velocity): Velocity {
        if (offset <= 0f || isRefreshing) return Velocity.Zero
        if (offset >= threshold) run() else settle(0f, SwiftMotion.smooth(0.3f))
        // Le lancer est avalé : le contenu ne part pas en défilement en
        // remontant.
        return available
    }

    /** L'action de TalkBack : relire sans tirer. */
    fun refreshNow() {
        if (isRefreshing) return
        scope.launch { run() }
    }

    private suspend fun run() {
        isRefreshing = true
        settle(resting, SwiftMotion.smooth(0.25f))
        try {
            onRefresh()
        } finally {
            isRefreshing = false
            settle(0f, SwiftMotion.smooth(0.3f))
        }
    }

    private suspend fun settle(target: Float, spec: AnimationSpec<Float>) {
        animate(initialValue = offset, targetValue = target, animationSpec = spec) { value, _ -> offset = value }
    }
}
