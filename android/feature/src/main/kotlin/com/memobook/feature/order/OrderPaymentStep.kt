package com.memobook.feature.order

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.memobook.core.OrderCopy
import com.memobook.design.BrandButton
import com.memobook.design.BrandNotice
import com.memobook.design.BrandText
import com.memobook.design.ErrorBanner
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.SwiftMotion
import kotlinx.coroutines.delay

/**
 * Étape 6 — par quoi on paie, où ça va, et combien. Jumeau de
 * `Order/OrderPaymentStep.swift`.
 *
 * « Payer » enregistre la commande en brouillon **puis ouvre la feuille
 * Stripe**, et ne passe à la confirmation qu'une fois le paiement accepté.
 * Voir `OrderModel.pay`, qui tient les chemins possibles.
 *
 * **Le moyen de paiement se choisit dans la feuille de Stripe** (01/10/2026).
 * L'étape affichait une carte dessinée et une feuille de choix — cartes
 * fabriquées par l'app, Apple Pay —, et rien de ce choix n'arrivait à Stripe.
 * La feuille, elle, montre les cartes enregistrées du compte, en accepte une
 * nouvelle, et propose Google Pay quand `:payments` l'allume — sur iOS, Apple
 * Pay quand l'identifiant marchand est posé.
 *
 * @param onPay « Payer » — `OrderModel.pay`, lancé par l'écran.
 */
@Composable
internal fun OrderPaymentStep(state: OrderModel.State, onPay: () -> Unit) {
    // La notice « aucun rendu » à amener sous les yeux quand elle apparaît : en
    // très grand texte, elle tombe sous le pli, et le geste semblerait encore
    // ne rien faire.
    val missingRenderNotice = remember { BringIntoViewRequester() }
    LaunchedEffect(state.isMissingRender) {
        if (!state.isMissingRender) return@LaunchedEffect
        // Une fois la notice posée : elle arrive en glissant.
        delay(NOTICE_REVEAL_DELAY_MS)
        missingRenderNotice.bringIntoView()
    }

    OrderStepLayout(
        content = {
            OrderSectionHeader(OrderCopy.Payment.title)

            // Le moyen de paiement.
            BrandNotice(OrderCopy.Payment.inStripeSheet)

            OrderPaymentAddress(state)

            OrderPriceRow(OrderCopy.Payment.total, amount = state.quote?.total, isProminent = true)

            state.paymentError?.let { ErrorBanner(it) }

            // « Payer » sans carnet composé (T224) : la cause et la sortie, en
            // réponse au geste — rien n'a raté, d'où l'information et non le
            // bandeau d'erreur. Voir `OrderModel.State.isMissingRender`.
            AnimatedVisibility(
                visible = state.isMissingRender,
                enter = fadeIn(SwiftMotion.snappy(0.25f)) + slideInVertically(SwiftMotion.snappy(0.25f)) { it / 2 },
                exit = fadeOut(SwiftMotion.snappy(0.25f)),
            ) {
                BrandNotice(
                    OrderCopy.Payment.noRender,
                    Modifier.bringIntoViewRequester(missingRenderNotice),
                    tone = BrandNotice.Tone.Information,
                )
            }
        },
        actions = {
            BrandButton(
                OrderCopy.Payment.cta,
                isLoading = state.isSubmitting,
                fillsWidth = true,
                enabled = state.canContinue && !state.isSubmitting,
                action = onPay,
            )
        },
    )
}

private const val NOTICE_REVEAL_DELAY_MS = 280L

// MARK: L'adresse

@Composable
private fun OrderPaymentAddress(state: OrderModel.State) {
    val shape = RoundedCornerShape(MemoBookSpacing.controlCornerRadius)
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
        BrandText(OrderCopy.Payment.address, MemoBookFont.h2)

        Column(
            Modifier
                .fillMaxWidth()
                .background(MemoBookColor.surface, shape)
                .border(1.dp, MemoBookColor.hairline, shape)
                .padding(MemoBookSpacing.s)
                .semantics(mergeDescendants = true) {},
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            BrandText(state.draft.shipping.name, MemoBookFont.bodySemibold)
            BrandText(formattedAddress(state), MemoBookFont.body, color = MemoBookColor.inkMuted)
        }
    }
}

/**
 * « 7 Rue Simon Fryd, Lyon, FRANCE 69007 ». Le pays s'écrit en toutes lettres
 * — le code ISO est ce que la base garde, pas ce qui se lit.
 */
private fun formattedAddress(state: OrderModel.State): String {
    val shipping = state.draft.shipping
    val country = state.context?.countries
        ?.firstOrNull { it.code == shipping.country }
        ?.name ?: shipping.country

    return listOfNotNull(shipping.line1, shipping.line2, shipping.city, "$country ${shipping.postalCode}")
        .filter { it.isNotBlank() }
        .joinToString(", ")
}
