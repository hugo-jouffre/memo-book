package com.memobook.design

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.EaseInOut
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * L'animation qui dit **« ça vient de changer »**. Jumeau de
 * `BrandRefreshFlash.swift` (`.brandRefreshFlash(_:)`) ; ici une enveloppe, parce
 * qu'il lui faut un état et une annonce.
 *
 * Elle sert un cas et un seul : un écran s'est ouvert sur ce qu'on avait en
 * cache, le serveur a répondu autre chose, et la page s'est mise à jour sous
 * les yeux de quelqu'un qui la regardait déjà. Sans elle, la différence entre
 * « rien ne s'est passé » et « trois valeurs viennent de bouger » est
 * invisible — et c'est précisément ce que le cache introduit comme risque.
 *
 * **Un geste, et pas deux.** Un voile clair qui traverse le bloc de gauche à
 * droite — la lumière qu'on passe sur une page qu'on vient de réécrire — et,
 * pour qui ne voit pas, l'annonce « Mis à jour » de TalkBack. Ni rebond, ni
 * changement de couleur, ni son : ce n'est pas une réussite qu'on célèbre,
 * c'est une information qu'on signale.
 *
 * La **pastille** « Mis à jour » qui descendait du haut n'est plus posée par
 * défaut (Hugo, 17/09/2026) : elle prenait trop de place sur le contenu, et le
 * clignotement des chiffres qui changent suffit. Elle reste disponible
 * ([showsBadge]) pour le jour où un changement le mérite.
 *
 * **Rien ne bouge sous « Supprimer les animations »** : le balayage s'éteint,
 * l'annonce reste. C'est l'information qui compte.
 *
 * ```kotlin
 * BrandRefreshFlash(model.freshness.isUpdated) { Column { … } }
 * ```
 *
 * @param isUpdated passe à `true` quand le contenu vient de changer : c'est le
 *   passage à `true` qui joue l'animation, pas la valeur elle-même.
 * @param showsBadge pose aussi la pastille « Mis à jour » en haut du bloc.
 *   Éteinte partout aujourd'hui.
 */
@Composable
fun BrandRefreshFlash(
    isUpdated: Boolean,
    modifier: Modifier = Modifier,
    showsBadge: Boolean = false,
    content: @Composable () -> Unit,
) {
    val reduceMotion = isReduceMotionEnabled()
    // Où en est le balayage, de -1 (hors cadre à gauche) à 1 (hors cadre à droite).
    val sweep = remember { Animatable(-1f) }
    var badgeVisible by remember { mutableStateOf(false) }
    var announcement by remember { mutableStateOf<String?>(null) }
    var lastSeen by remember { mutableStateOf(isUpdated) }
    var plays by remember { mutableIntStateOf(0) }
    // Une portée à elle : quand l'appelant repasse `isUpdated` à `false`, le
    // balayage en cours continue.
    val scope = rememberCoroutineScope()

    LaunchedEffect(isUpdated) {
        val becameUpdated = isUpdated && !lastSeen
        lastSeen = isUpdated
        if (!becameUpdated) return@LaunchedEffect
        val play = ++plays
        if (!reduceMotion) {
            scope.launch {
                sweep.snapTo(-1f)
                sweep.animateTo(1f, tween(900, easing = EaseInOut))
            }
        }
        // Sans pastille, c'est l'annonce qui dit à TalkBack que la page a
        // bougé — une région vivante polie, qui ne coupe pas la lecture en
        // cours. (iOS poste une `AccessibilityNotification.Announcement`.)
        scope.launch {
            announcement = null
            delay(ANNOUNCEMENT_RESET_MS)
            announcement = UPDATED_LABEL
            delay(BADGE_DURATION_MS)
            if (plays == play) announcement = null
        }
        if (showsBadge) {
            scope.launch {
                badgeVisible = true
                delay(BADGE_DURATION_MS)
                if (plays == play) badgeVisible = false
            }
        }
    }

    Box(
        modifier.drawWithContent {
            drawContent()
            // Le voile qui traverse. Il ne teinte rien : c'est du blanc à 35 %,
            // dont les deux bords sont transparents — sur le crème de la
            // marque il se lit comme un reflet, pas comme une couleur. Il ne
            // prend aucun toucher : il est dessiné, pas posé.
            val position = sweep.value
            if (!reduceMotion && position > -1f && position < 1f) {
                val bandWidth = size.width * 0.6f
                val start = position * size.width
                clipRect {
                    drawRect(
                        brush = Brush.horizontalGradient(
                            0f to Color.White.copy(alpha = 0f),
                            0.5f to Color.White.copy(alpha = 0.35f),
                            1f to Color.White.copy(alpha = 0f),
                            startX = start,
                            endX = start + bandWidth,
                        ),
                        topLeft = Offset(start, 0f),
                        size = Size(bandWidth, size.height),
                    )
                }
            }
        },
    ) {
        content()

        Box(
            Modifier
                .matchParentSize()
                .semantics {
                    liveRegion = LiveRegionMode.Polite
                    announcement?.let { contentDescription = it }
                },
        )

        AnimatedVisibility(
            visible = badgeVisible,
            modifier = Modifier.align(Alignment.TopCenter),
            enter = if (reduceMotion) {
                fadeIn(SwiftMotion.snappy(0.3f))
            } else {
                slideInVertically(SwiftMotion.snappy(0.3f)) { -it } + fadeIn(SwiftMotion.snappy(0.3f))
            },
            exit = if (reduceMotion) {
                fadeOut(SwiftMotion.snappy(0.3f))
            } else {
                slideOutVertically(SwiftMotion.snappy(0.3f)) { -it } + fadeOut(SwiftMotion.snappy(0.3f))
            },
        ) {
            val capsule = RoundedCornerShape(percent = 50)
            BrandText(
                UPDATED_LABEL,
                MemoBookFont.overline,
                Modifier
                    .brandShadow(MemoBookShadow.Soft, capsule)
                    .background(MemoBookColor.action, capsule)
                    .padding(horizontal = MemoBookSpacing.s, vertical = MemoBookSpacing.xs / 2)
                    // L'annonce passe par la région vivante, pas par la pastille.
                    .clearAndSetSemantics {},
                color = MemoBookColor.onAction,
            )
        }
    }
}

private const val UPDATED_LABEL = "Mis à jour"

/**
 * Le temps que la pastille reste. Assez pour être lue en levant les yeux,
 * assez court pour ne pas devenir un élément de l'écran.
 */
private const val BADGE_DURATION_MS = 1800L

/** Le temps de vider la région vivante, pour qu'une deuxième mise à jour s'annonce aussi. */
private const val ANNOUNCEMENT_RESET_MS = 100L

@Preview(name = "Mise à jour en direct", widthDp = 390, heightDp = 400)
@Composable
private fun BrandRefreshFlashPreview() {
    var isUpdated by remember { mutableStateOf(false) }
    var days by remember { mutableIntStateOf(12) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(2500)
            days += 1
            isUpdated = true
            delay(100)
            isUpdated = false
        }
    }
    Column(
        Modifier
            .fillMaxSize()
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
    ) {
        BrandRefreshFlash(isUpdated) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .background(MemoBookColor.surface, RoundedCornerShape(MemoBookSpacing.largeCornerRadius))
                    .padding(MemoBookSpacing.s),
                verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
            ) {
                BrandText("Rome et la Dolce Vita", MemoBookFont.cardTitle)
                BrandText("$days jours de voyage", MemoBookFont.body)
            }
        }
    }
}
