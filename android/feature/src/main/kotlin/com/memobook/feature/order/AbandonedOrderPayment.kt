package com.memobook.feature.order

import com.memobook.core.OrderCopy
import com.memobook.core.OrderSettlement
import com.memobook.core.PaymentIntentTicket
import com.memobook.core.PrintOrder
import com.memobook.core.PrintOrderStatus
import com.memobook.core.ResumedOrderPayment
import com.memobook.payments.PaymentOutcome
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/**
 * « Finaliser ma commande », depuis Profil › Suivi des commandes (T232).
 * Jumeau de `Order/AbandonedOrderPayment.swift`.
 *
 * Une commande au paiement abandonné se **reprend**, elle ne se repasse pas :
 * `POST /v1/orders/:id/payment` la rouvre avec une nouvelle intention Stripe,
 * au prix figé à la commande — même quand le ménage des 24 h l'avait fermée.
 * Rouvrir le tunnel aurait fait ressaisir l'adresse et les exemplaires d'une
 * commande qui les a déjà, et en aurait passé une seconde.
 *
 * Comme [OrderModel], il ne connaît ni l'API ni le SDK : trois fonctions, que
 * [finishAbandonedOrder] branche.
 */
class AbandonedOrderPayment(
    private val resume: suspend (String) -> ResumedOrderPayment,
    private val present: suspend (PaymentIntentTicket) -> PaymentOutcome,
    private val reload: (suspend (String) -> PrintOrder)? = null,
) {
    /** Ce que la feuille du suivi doit en faire. */
    sealed interface Outcome {
        /**
         * Payée — ou plus rien à régler. Le suivi relit le profil : la carte
         * passe en livraison.
         */
        data object Paid : Outcome

        /**
         * La feuille de Stripe a été fermée. Ni message ni relecture : la
         * commande attend toujours, le bouton aussi.
         */
        data object Cancelled : Outcome

        /** Ce que la personne doit lire. */
        data class Failed(val message: String) : Outcome
    }

    /**
     * Une seconde entre deux relectures, six fois au plus — le même budget que
     * la confirmation du tunnel ([OrderModel]).
     */
    internal var settlementAttempts = 6
    internal var settlementInterval: Duration = 1.seconds

    suspend fun finish(orderId: String): Outcome {
        val resumed = try {
            resume(orderId)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            // `409 order_refunded` arrive avec sa phrase : la commande a été
            // payée puis remboursée, il faut en passer une autre. Le serveur la
            // dit mieux que nous.
            return Outcome.Failed(OrderModel.describe(error))
        }

        // `payment: null` : payée entre-temps, ou un paiement déjà en cours.
        // Rien à ouvrir — le profil relu dira où elle en est.
        val payment = resumed.payment ?: return Outcome.Paid

        return when (val settlement = payment.settlement) {
            OrderSettlement.Unavailable -> Outcome.Failed(OrderCopy.Payment.unavailable)

            is OrderSettlement.Card -> when (val outcome = present(settlement.ticket)) {
                PaymentOutcome.Cancelled -> Outcome.Cancelled
                is PaymentOutcome.Failed -> Outcome.Failed(outcome.message)
                PaymentOutcome.Succeeded -> {
                    // La feuille dit que Stripe a accepté, pas que le serveur
                    // l'a appris : on attend le webhook avant de relire le
                    // profil, sans quoi la carte resterait « abandonnée » sur un
                    // paiement réussi.
                    waitUntilSettled(orderId)
                    Outcome.Paid
                }
            }
        }
    }

    private suspend fun waitUntilSettled(orderId: String) {
        val reload = reload ?: return
        repeat(settlementAttempts) {
            delay(settlementInterval)
            val fresh = try {
                reload(orderId)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                null
            }
            if (fresh != null && fresh.status != PrintOrderStatus.Draft) return
        }
    }
}
