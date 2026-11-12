package com.memobook.design

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.delay

/**
 * **Le message qui passe** : une phrase qui s'affiche, se lit, et s'en va
 * toute seule (Hugo, 10/11/2026 — « un popup temporaire de 3 sec devrait
 * indiquer "Tu as rejoint le voyage de X" »). Jumeau de `BrandToast.swift`.
 *
 * C'est **le** composant de ce rôle, et il se distingue de ses voisins :
 *
 * - [BrandNotice] reste tant que la cause reste — il explique un état ;
 * - `ErrorBanner` demande un geste — réessayer, écrire au support ;
 * - celui-ci **ne demande rien**. Il confirme ce qui vient d'arriver, puis il
 *   libère l'écran. Rien ne doit en dépendre : ce qu'il dit est déjà vrai
 *   ailleurs — le voyage est dans la liste, la page est ouverte.
 */
@Composable
fun BrandToast(message: String, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)
    BrandText(
        message,
        MemoBookFont.bodySemibold,
        color = MemoBookColor.ink,
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = MemoBookSpacing.screenMargin)
            .brandShadow(MemoBookShadow.Soft, shape)
            .background(MemoBookColor.surface, shape)
            .clip(shape)
            .border(1.dp, MemoBookColor.hairline, shape)
            .padding(horizontal = MemoBookSpacing.s, vertical = MemoBookSpacing.snug)
            // Une phrase qui s'en va toute seule doit être **lue** par
            // TalkBack au moment où elle arrive : sans ça, elle n'existe pas
            // pour qui ne voit pas l'écran. C'est le `.accessibilityAddTraits`
            // d'iOS, en plus explicite.
            .semantics { liveRegion = LiveRegionMode.Polite },
    )
}

/**
 * Combien de temps un message reste sous les yeux. Trois secondes : le temps
 * de lire une phrase, et pas celui de s'y habituer (Hugo, 10/11/2026).
 */
val BRAND_TOAST_DURATION: Duration = 3.seconds

/**
 * Pose un message fugitif en haut de l'écran : il s'efface seul au bout de
 * [duration], et remettre la valeur à `null` l'efface tout de suite.
 *
 * Le `.brandToast(_:)` d'iOS est un modificateur ; ici c'est un composable
 * d'enveloppe, Compose n'ayant pas d'`overlay` posé par modificateur.
 */
@Composable
fun BrandToastHost(
    message: String?,
    onDismiss: () -> Unit,
    duration: Duration = BRAND_TOAST_DURATION,
    modifier: Modifier = Modifier,
) {
    val reduceMotion = isReduceMotionEnabled()

    // `LaunchedEffect(message)` : un second message qui arrive avant la fin du
    // premier **relance** l'attente au lieu de la laisser emporter les deux.
    LaunchedEffect(message) {
        if (message == null) return@LaunchedEffect
        delay(duration)
        onDismiss()
    }

    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
        AnimatedVisibility(
            visible = message != null,
            enter = if (reduceMotion) fadeIn() else fadeIn() + slideInVertically { -it },
            exit = if (reduceMotion) fadeOut() else fadeOut() + slideOutVertically { -it },
        ) {
            BrandToast(message.orEmpty())
        }
    }
}

@Preview(locale = "fr-rFR", name = "Message fugitif", widthDp = 390, heightDp = 160)
@Composable
private fun BrandToastPreview() {
    Box(Modifier.background(MemoBookColor.background).padding(vertical = MemoBookSpacing.m)) {
        BrandToast("Tu as rejoint le voyage de Fanny ; il est ajouté à tes voyages.")
    }
}
