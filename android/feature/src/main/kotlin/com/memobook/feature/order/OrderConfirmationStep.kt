package com.memobook.feature.order

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.memobook.core.OrderCopy
import com.memobook.design.BrandButton
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandText
import com.memobook.design.ErrorBanner
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.isReduceMotionEnabled
import kotlinx.coroutines.delay

/**
 * Étape 7 — c'est parti. Jumeau de `Order/OrderConfirmationStep.swift`.
 *
 * Elle lit **la commande** et non le brouillon : c'est le serveur qui a le
 * dernier mot sur ce qui a été enregistré, y compris le délai annoncé.
 *
 * Il n'y a pas de flèche de retour utile ici — `OrderStep.allowsGoingBack` la
 * referme sur l'écran plutôt que de ramener au paiement d'une commande déjà
 * passée.
 */
@Composable
internal fun OrderConfirmationStep(
    state: OrderModel.State,
    model: OrderModel,
    onShare: () -> Unit,
    onFinish: () -> Unit,
) {
    val reduceMotion = isReduceMotionEnabled()
    var hasLanded by remember { mutableStateOf(false) }

    /** La feuille qui demande le numéro, quand le compte n'en a pas encore. */
    var isAskingPhone by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        // La pastille se pose une fois, à l'arrivée. Sans ce délai elle
        // apparaîtrait pendant la transition de l'étape et les deux mouvements
        // se marcheraient dessus.
        delay(120)
        hasLanded = true
    }

    OrderStepLayout(
        content = {
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
                OrderConfirmationSeal(isShown = hasLanded || reduceMotion)
                OrderConfirmationHeadline(state)
                OrderDeliveryCard(
                    state,
                    onWhatsApp = {
                        if (state.isSavingWhatsApp) return@OrderDeliveryCard
                        val known = state.suggestedPhoneNumber
                        when {
                            state.wantsWhatsApp -> model.launch { setWhatsAppTracking(phone = null) }
                            known != null -> model.launch { setWhatsAppTracking(phone = known) }
                            else -> isAskingPhone = true
                        }
                    },
                )
                OrderGiftCard()

                state.errorMessage?.let { ErrorBanner(it) }
            }
        },
        actions = {
            BrandButton(
                OrderCopy.Confirmation.share,
                isLoading = state.isPreparingLink,
                fillsWidth = true,
                enabled = !state.isPreparingLink,
                action = onShare,
            )

            BrandButton(
                OrderCopy.Confirmation.home,
                style = BrandButton.Style.Secondary,
                fillsWidth = true,
                action = onFinish,
            )
        },
    )

    BrandSheetHost(isPresented = isAskingPhone, onDismissRequest = { isAskingPhone = false }) {
        OrderWhatsAppSheet(
            suggested = state.suggestedPhoneNumber,
            onConfirm = { phone ->
                isAskingPhone = false
                model.launch { setWhatsAppTracking(phone = phone) }
            },
        )
    }
}

/**
 * La pastille verte et sa coche. Le seul moment de l'app où quelque chose se
 * conclut : elle a le droit de rebondir une fois.
 */
@Composable
private fun OrderConfirmationSeal(isShown: Boolean) {
    val bounce = SwiftMotion.spring<Float>(response = 0.5f, dampingFraction = 0.6f)
    val scale by animateFloatAsState(if (isShown) 1f else 0.4f, bounce, label = "pastille")
    val opacity by animateFloatAsState(if (isShown) 1f else 0f, bounce, label = "pastille-opacité")

    Box(
        Modifier
            .size(66.dp)
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
                // Le ressort dépasse sa cible : l'opacité, elle, s'arrête à 1.
                alpha = opacity.coerceIn(0f, 1f)
            }
            .background(MemoBookColor.accent, CircleShape)
            .clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        Image(
            painterResource(R.drawable.icon_lucide_check),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.action),
            modifier = Modifier.size(26.dp),
        )
    }
}

@Composable
private fun OrderConfirmationHeadline(state: OrderModel.State) {
    Column(
        Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug),
    ) {
        BrandText(OrderCopy.Confirmation.title, MemoBookFont.h1)
        BrandText(state.confirmationDetail, MemoBookFont.body, color = MemoBookColor.inkMuted)
    }
}

/**
 * Ce qui part, quand, et en combien d'exemplaires — et « Être informé par
 * WhatsApp », qui enregistre l'accord et le numéro sur la commande
 * (`POST /v1/orders/:id/whatsapp`). Aucun message ne part encore : le bouton le
 * dit une fois accepté.
 */
@Composable
private fun OrderDeliveryCard(state: OrderModel.State, onWhatsApp: () -> Unit) {
    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)
    Row(
        Modifier
            .fillMaxWidth()
            .background(MemoBookColor.surface, shape)
            .border(1.dp, MemoBookColor.hairline, shape)
            .padding(MemoBookSpacing.s),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        verticalAlignment = Alignment.Top,
    ) {
        OrderConfirmationCover(state)

        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2)) {
            // Ce qui se lit d'un tenant ; le bouton du suivi reste une cible à lui.
            Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2)) {
                BrandText(OrderCopy.Confirmation.delivery.uppercase(), MemoBookFont.overline, color = MemoBookColor.inkMuted)

                state.confirmationDays?.let { days ->
                    BrandText(days.deliveryLabel, MemoBookFont.bodySemibold)
                }

                BrandText(state.confirmationSummary, MemoBookFont.label, color = MemoBookColor.inkMuted)
            }

            OrderWhatsAppButton(state, onWhatsApp, Modifier.padding(top = MemoBookSpacing.xs / 2))
        }
    }
}

/**
 * « Être informé par WhatsApp ».
 *
 * Il **bascule** : accepter puis se raviser doit être possible sans quitter
 * l'écran. Un compte qui a déjà son numéro accepte d'un seul geste ; les autres
 * passent par la feuille, qui enregistre le numéro sur le compte au passage.
 */
@Composable
private fun OrderWhatsAppButton(state: OrderModel.State, onWhatsApp: () -> Unit, modifier: Modifier) {
    Column(
        modifier.animateContentSize(SwiftMotion.smooth(0.25f)),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        BrandButton(
            if (state.wantsWhatsApp) OrderCopy.Confirmation.whatsappStop else OrderCopy.Confirmation.whatsapp,
            icon = painterResource(R.drawable.icon_ringtone),
            style = BrandButton.Style.Link,
            size = BrandButton.Size.Small,
            isLoading = state.isSavingWhatsApp,
            action = onWhatsApp,
        )

        // ⚠️ Ce que l'écran ne promet pas : rien ne part encore. Le dire une
        // fois accepté, plutôt que de laisser attendre un message.
        AnimatedVisibility(
            visible = state.wantsWhatsApp,
            enter = fadeIn(SwiftMotion.smooth(0.25f)),
            exit = fadeOut(SwiftMotion.smooth(0.25f)),
        ) {
            BrandText(OrderCopy.Confirmation.whatsappNotLiveYet, MemoBookFont.caption, color = MemoBookColor.inkMuted)
        }
    }
}

/**
 * La couverture du carnet commandé — celle que le serveur a figée avec la
 * commande, et à défaut celle du voyage.
 */
@Composable
private fun OrderConfirmationCover(state: OrderModel.State) {
    val url = state.order?.coverImageUrl ?: state.context?.trip?.coverPhotoUrl
    Box(
        Modifier
            .size(width = 84.dp, height = 98.dp)
            .clip(RoundedCornerShape(MemoBookSpacing.cornerRadius))
            .background(MemoBookColor.beige)
            .clearAndSetSemantics {},
    ) {
        // Le beige tient la place tant que l'image charge, et la remplace si
        // elle ne vient pas.
        if (url != null) {
            AsyncImage(
                model = url.toString(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.matchParentSize(),
            )
        }
    }
}

/**
 * « Envie de l'offrir ? » — l'aplat lime, seul large aplat que porte la marque.
 *
 * Elle **n'est pas un bouton** : recommander se fait depuis le carnet, à tout
 * moment, et c'est exactement ce que la phrase dit. Un bouton ici promettrait
 * un raccourci qui n'existe pas.
 */
@Composable
private fun OrderGiftCard() {
    Row(
        Modifier
            .fillMaxWidth()
            .background(MemoBookColor.accent.copy(alpha = 0.5f), RoundedCornerShape(MemoBookSpacing.largeCornerRadius))
            .padding(MemoBookSpacing.s)
            .semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        verticalAlignment = Alignment.Top,
    ) {
        Box(
            Modifier
                .size(44.dp)
                .background(MemoBookColor.surface.copy(alpha = 0.6f), CircleShape)
                .clearAndSetSemantics {},
            contentAlignment = Alignment.Center,
        ) {
            Image(
                painterResource(R.drawable.icon_lucide_heart),
                contentDescription = null,
                colorFilter = ColorFilter.tint(MemoBookColor.action),
                modifier = Modifier.size(22.dp),
            )
        }

        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            BrandText(OrderCopy.Confirmation.giftTitle, MemoBookFont.bodySemibold)
            BrandText(OrderCopy.Confirmation.giftDetail, MemoBookFont.label, color = MemoBookColor.ink.copy(alpha = 0.7f))
        }
    }
}
