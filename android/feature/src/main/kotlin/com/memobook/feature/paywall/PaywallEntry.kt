package com.memobook.feature.paywall

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import com.memobook.core.Subscription
import com.memobook.feature.AppDependencies
import com.memobook.feature.LocalSubscriptionSession
import com.memobook.feature.PaywallVariant
import com.memobook.feature.support.LocalSupportModel
import com.memobook.feature.support.rememberSessionSupportModel

/**
 * L'offre ouverte par un lien `memobook://paywall`, plein écran, sans écran
 * d'attache — le `fullScreenCover(isPresented: $showsNotificationPaywall)` du
 * `RootView` d'iOS : l'offre du moment, dans la version que la session connaît.
 *
 * La porte d'entrée de `RootView` vers cet écran. Elle pose pour le paywall le
 * support **de la session** (« Besoin d'aide ? » l'ouvre par-dessus l'offre), et
 * l'achat du compte — **en attendant le vrai store** (Google Play Billing, lot
 * de l'argent), celui de l'aperçu, qui n'achète rien.
 */
@Composable
fun PaywallEntry(dependencies: AppDependencies, onSubscribe: () -> Unit, onDismiss: () -> Unit) {
    val support = LocalSupportModel.current ?: rememberSessionSupportModel(dependencies)
    CompositionLocalProvider(LocalSupportModel provides support) {
        PaywallView(
            subscription = Subscription.offer,
            onSubscribe = onSubscribe,
            onDismiss = onDismiss,
            variant = LocalSubscriptionSession.current?.paywallVariant ?: PaywallVariant.FirstTime,
            subscriptionPurchase = LocalSubscriptionPurchase.current ?: SubscriptionPurchase.preview,
        )
    }
}
