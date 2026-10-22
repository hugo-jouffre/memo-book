package com.memobook.feature.paywall

import androidx.compose.runtime.staticCompositionLocalOf
import kotlinx.coroutines.delay
import kotlin.time.Duration.Companion.milliseconds

/**
 * Ce que l'offre et la feuille d'abonnement savent faire du store, pour le
 * compte connecté. Jumeau de `Paywall/SubscriptionPurchase.swift` — sur iOS
 * l'App Store, ici Google Play Billing, que le lot de l'argent branche
 * (`AppDependencies.subscriptionPurchase(accountId)`).
 *
 * Des fonctions et non le magasin lui-même : l'écran n'a pas à savoir à qui
 * l'achat est remis, ni sous quel compte. Il demande un achat, et reçoit ce
 * qui s'est passé.
 *
 * @property displayPrice le prix du store, dans le pays du compte. `null` tant
 *   qu'il n'est pas revenu.
 * @property displayPeriod la période que ce prix paie — « mois » —, lue sur le
 *   produit. `null` tant qu'elle n'est pas revenue : l'écran écrit alors celle
 *   de l'offre.
 * @property purchase achète l'abonnement, rattaché au voyage qu'il finance
 *   quand on le sait.
 * @property restore « Restaurer mes achats ».
 * @property willAutoRenew le renouvellement est-il encore armé chez le store.
 * @property deliverUnfinished remet au serveur ce que le store garde encore —
 *   un achat encaissé que le serveur n'a pas reçu ([PurchaseOutcome.AwaitingServer]).
 *   Le profil s'en sert à l'ouverture tant que l'abonnement acheté n'y apparaît
 *   pas (03/10/2026).
 */
class SubscriptionPurchase(
    val displayPrice: suspend () -> String?,
    val displayPeriod: suspend () -> String?,
    val purchase: suspend (memoId: String?) -> PurchaseOutcome,
    val restore: suspend () -> RestoreOutcome,
    val willAutoRenew: suspend () -> Boolean?,
    val deliverUnfinished: suspend () -> Unit = {},
) {
    companion object {
        /**
         * **L'achat qui n'achète rien**, en attendant le vrai store : la porte
         * `memobook://paywall` tant que Google Play Billing n'est pas branché.
         * Le prix et la période restent ceux de l'offre (`null`) ; l'achat
         * rend la main après le temps d'une feuille de store, **comme une
         * feuille refermée** ([PurchaseOutcome.Cancelled]) : rendre
         * « abonné » ferait basculer la session en illimité sans que rien ne
         * soit payé. Et il n'y a rien à restaurer.
         */
        val preview = SubscriptionPurchase(
            displayPrice = { null },
            displayPeriod = { null },
            purchase = {
                delay(600.milliseconds)
                PurchaseOutcome.Cancelled
            },
            restore = { RestoreOutcome.NothingToRestore },
            willAutoRenew = { null },
        )
    }
}

/**
 * L'achat de l'abonnement, pour le compte connecté — posé par `RootView`.
 * `null` dans un aperçu isolé : l'offre s'y comporte comme si l'achat avait
 * réussi.
 */
val LocalSubscriptionPurchase = staticCompositionLocalOf<SubscriptionPurchase?> { null }
