package com.memobook.feature.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.memobook.core.CurrentTrip
import com.memobook.core.OrderTracking
import com.memobook.core.TravellerProfile
import com.memobook.design.BrandButton
import com.memobook.design.BrandSheet
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.R
import com.memobook.design.isAccessibilityTextSize
import com.memobook.design.scaled
import kotlinx.coroutines.launch

/**
 * Où en sont les carnets partis à l'impression. Jumeau de
 * `Profile/OrderTrackingSheet.swift`.
 *
 * Un délai, pas une date : c'est ce que l'imprimeur annonce, et annoncer un
 * jour précis qu'on ne tient pas vaut moins qu'une fourchette honnête.
 *
 * @param ongoingTrip le voyage en cours, s'il y en a un : sans commande, c'est
 *   **lui** que la feuille propose de commander (Hugo, 29/09/2026), plutôt que
 *   d'envoyer planifier un prochain voyage quelqu'un qui en raconte un.
 * @param onPlanTrip ce que fait la carte de l'état vide : aller voir les
 *   carnets de la communauté, comme la maquette l'écrit dessus.
 * @param onOrder « Commander mon carnet » : le tunnel de commande du voyage en cours.
 * @param onOrdersChanged une commande abandonnée vient d'être payée : le profil
 *   se relit, et sa carte passe en livraison.
 * @param finishAbandonedOrder « Finaliser ma commande » —
 *   `dependencies.finishAbandonedOrder(orderId)`, posé par le profil. `null`
 *   en aperçu : le bouton ne s'affiche alors pas, plutôt que de ne rien faire.
 */
@Composable
internal fun OrderTrackingSheet(
    orders: List<OrderTracking>,
    onPlanTrip: () -> Unit,
    ongoingTrip: CurrentTrip? = null,
    onOrder: (CurrentTrip) -> Unit = {},
    onOrdersChanged: () -> Unit = {},
    finishAbandonedOrder: (suspend (String) -> AbandonedOrderPayment.Outcome)? = null,
) {
    // La commande dont le paiement est en train de reprendre. Une à la fois :
    // deux feuilles de Stripe ne s'empilent pas.
    var finishingOrderId by remember { mutableStateOf<String?>(null) }
    var finishError by remember { mutableStateOf<Pair<String, String>?>(null) }
    val scope = rememberCoroutineScope()

    // Reprend le paiement d'une commande abandonnée, sans repasser par le
    // tunnel : elle a déjà son adresse, ses exemplaires et son prix.
    fun finish(order: OrderTracking) {
        val finishAbandonedOrder = finishAbandonedOrder ?: return
        if (finishingOrderId != null) return
        finishingOrderId = order.id
        finishError = null

        scope.launch {
            val outcome = finishAbandonedOrder(order.id)
            finishingOrderId = null
            when (outcome) {
                AbandonedOrderPayment.Outcome.Paid -> onOrdersChanged()
                AbandonedOrderPayment.Outcome.Cancelled -> Unit
                is AbandonedOrderPayment.Outcome.Failed -> finishError = order.id to outcome.message
            }
        }
    }

    BrandSheet("Suivi des commandes") {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
            when {
                orders.isEmpty() && ongoingTrip != null -> OrderInvitation { onOrder(ongoingTrip) }
                // **La maquette existe** — `Modale – Profile PAS de commande`,
                // `3162:34917` : la même carte en pointillés que l'accueil sans
                // voyage à venir, « Commence à planifier ton prochain voyage »,
                // avec son bout de scotch. Rien à inventer, donc : c'est la
                // carte de l'accueil, dont seule la seconde ligne change avec
                // la destination (T22).
                //
                // ⚠️ Le titre de la maquette n'a pas pu être lu (quota MCP) :
                // celui de la ligne reste. Sa seconde ligne écrit « le
                // carnets » ; c'est une coquille, corrigée ici.
                orders.isEmpty() -> UpcomingTripInvite(
                    subtitle = "Clique ici pour voir les carnets de la communauté",
                    onOpen = onPlanTrip,
                )
                else -> orders.forEach { order ->
                    OrderCard(
                        order = order,
                        isFinishing = finishingOrderId == order.id,
                        finishError = finishError?.takeIf { it.first == order.id }?.second,
                        onFinish = if (order.isPaymentAbandoned && finishAbandonedOrder != null) {
                            { finish(order) }
                        } else {
                            null
                        },
                    )
                }
            }
        }
    }
}

/** Aucune commande, mais un voyage en cours : le carnet se commande d'ici. */
@Composable
private fun OrderInvitation(onOrder: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2)) {
            BrandText(
                "Aucune commande pour le moment",
                MemoBookFont.bodySemibold,
                Modifier.fillMaxWidth(),
                textAlign = TextAlign.Center,
            )
            BrandText(
                "Ton carnet est en cours d’écriture : commande-le dès que tu es prêt.",
                MemoBookFont.caption,
                Modifier.fillMaxWidth(),
                color = MemoBookColor.inkMuted,
                textAlign = TextAlign.Center,
            )
        }

        BrandButton(
            "Commander mon carnet",
            icon = painterResource(R.drawable.icon_deliver),
            fillsWidth = true,
            action = onOrder,
        )
    }
}

/**
 * Une commande : sa couverture, son délai, et ce qu'elle contient — ou, quand
 * son paiement a été laissé en route, son étiquette et « Finaliser ma
 * commande » (T232).
 *
 * @param onFinish `null` sur une commande en route, ou hors session.
 */
@Composable
private fun OrderCard(order: OrderTracking, isFinishing: Boolean, finishError: String?, onFinish: (() -> Unit)?) {
    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)
    Column(
        Modifier
            .fillMaxWidth()
            .border(1.dp, if (order.isPaymentAbandoned) MemoBookColor.separator else MemoBookColor.action, shape)
            .padding(MemoBookSpacing.xs),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        // Le bouton reste un élément à part : fondu dans la carte, il serait
        // lu sans pouvoir être activé.
        Box(Modifier.semantics(mergeDescendants = true) {}) {
            if (isAccessibilityTextSize()) {
                Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
                    OrderCover(order)
                    OrderText(order, Modifier.padding(horizontal = MemoBookSpacing.xs))
                }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s), verticalAlignment = Alignment.CenterVertically) {
                    OrderCover(order)
                    OrderText(order, Modifier.weight(1f))
                }
            }
        }

        if (onFinish != null) {
            BrandButton(
                "Finaliser ma commande",
                icon = painterResource(R.drawable.icon_cart),
                size = BrandButton.Size.Medium,
                isLoading = isFinishing,
                fillsWidth = true,
                enabled = !isFinishing,
                action = onFinish,
            )
        }

        if (finishError != null) {
            BrandText(finishError, MemoBookFont.caption, Modifier.fillMaxWidth(), color = MemoBookColor.error)
        }
    }
}

@Composable
private fun OrderCover(order: OrderTracking) {
    val side = scaled(72.dp)
    // Pas de photo : l'aplat de marque, comme les couvertures sans image de
    // l'accueil.
    Box(
        Modifier
            .size(side)
            .clip(RoundedCornerShape(MemoBookSpacing.cornerRadius))
            .background(MemoBookColor.outline)
            .clearAndSetSemantics {},
    ) {
        order.coverImageUrl?.let { url ->
            AsyncImage(
                model = url.toString(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(side),
            )
        }
    }
}

@Composable
private fun OrderText(order: OrderTracking, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        if (order.isPaymentAbandoned) {
            // Pas de délai : rien n'est parti. L'étiquette dit pourquoi, le
            // titre dit quel carnet.
            BrandText("Paiement abandonné, commande non finalisée", MemoBookFont.label, color = MemoBookColor.error)
            BrandText(order.tripTitle ?: "Ton carnet", MemoBookFont.heading)
        } else {
            BrandText("Livraison", MemoBookFont.label, color = MemoBookColor.action)
            BrandText("Dans ${order.minimumDays} à ${order.maximumDays} jours", MemoBookFont.heading)
        }

        BrandText(order.contents, MemoBookFont.body, color = MemoBookColor.inkMuted)
    }
}

/**
 * « 2 exemplaires - 50 pages ». L'accord suit le nombre : la maquette ne
 * montre que le pluriel, une commande d'un seul exemplaire existe quand même.
 * Une commande à finaliser dit aussi ce qu'il reste à payer.
 */
private val OrderTracking.contents: String
    get() {
        val copies = if (copies == 1) "1 exemplaire" else "$copies exemplaires"
        val line = "$copies - $pageCount pages"
        val total = total
        if (!isPaymentAbandoned || total == null) return line
        return "$line - ${total.euros}"
    }

@Preview(locale = "fr-rFR", name = "Suivi des commandes", heightDp = 800)
@Composable
private fun OrderTrackingSheetPreview() {
    BrandSheetHost(isPresented = true, onDismissRequest = {}) {
        OrderTrackingSheet(orders = TravellerProfile.fixture.orders, onPlanTrip = {})
    }
}

@Preview(locale = "fr-rFR", name = "Suivi des commandes — aucune", heightDp = 600)
@Composable
private fun OrderTrackingSheetEmptyPreview() {
    BrandSheetHost(isPresented = true, onDismissRequest = {}) {
        OrderTrackingSheet(orders = emptyList(), onPlanTrip = {})
    }
}
