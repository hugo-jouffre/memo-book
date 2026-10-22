package com.memobook.feature.profile

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.feature.AppDependencies

// À brancher : Order/AbandonedOrderPayment.swift et
// `AppDependencies.finishAbandonedOrder(orderId:)` (lot de la commande,
// `order/AbandonedOrderPayment.kt` et `order/OrderDependencies.kt`) ;
// Home/HomeSections.swift (`UpcomingTripInvite`, lot de l'accueil,
// `home/HomeSections.kt`).
//
// Le suivi des commandes emploie ces pièces sous leur nom Swift et la
// signature de leurs lots. L'intégrateur supprime ce fichier à la fusion, et
// importe `com.memobook.feature.order.AbandonedOrderPayment`,
// `com.memobook.feature.order.finishAbandonedOrder` et
// `com.memobook.feature.home.UpcomingTripInvite` dans `OrderTrackingSheet.kt`
// et `ProfileView.kt`.

/** « Finaliser ma commande » — ce que la feuille du suivi doit faire de l'issue. */
class AbandonedOrderPayment {
    sealed interface Outcome {
        /** Payée — ou plus rien à régler. Le suivi relit le profil. */
        data object Paid : Outcome

        /** La feuille de Stripe a été fermée. Ni message ni relecture. */
        data object Cancelled : Outcome

        /** Ce que la personne doit lire. */
        data class Failed(val message: String) : Outcome
    }
}

/** Rouvre le paiement d'une commande abandonnée. En attendant le lot de la commande : rien ne s'ouvre. */
@Suppress("UNUSED_PARAMETER", "UnusedReceiverParameter", "RedundantSuspendModifier")
suspend fun AppDependencies.finishAbandonedOrder(orderId: String): AbandonedOrderPayment.Outcome =
    AbandonedOrderPayment.Outcome.Cancelled

/** La carte en pointillés « Commence à planifier ton prochain voyage » — en attendant son dessin, ses deux lignes. */
@Composable
fun UpcomingTripInvite(
    modifier: Modifier = Modifier,
    subtitle: String = "Clique ici pour ouvrir ton prochain carnet",
    onOpen: () -> Unit,
) {
    Column(
        modifier
            .fillMaxWidth()
            .border(1.dp, MemoBookColor.separator, RoundedCornerShape(MemoBookSpacing.largeCornerRadius))
            .clickable(onClick = onOpen)
            .padding(MemoBookSpacing.s),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        BrandText("Commence à planifier ton prochain voyage", MemoBookFont.bodySemibold)
        BrandText(subtitle, MemoBookFont.label, color = MemoBookColor.inkMuted)
    }
}
