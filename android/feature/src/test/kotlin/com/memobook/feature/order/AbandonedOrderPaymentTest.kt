package com.memobook.feature.order

import com.memobook.core.NewPrintOrderRequest
import com.memobook.core.OrderCopy
import com.memobook.core.OrderPayment
import com.memobook.core.PrintOrder
import com.memobook.core.PrintOrderStatus
import com.memobook.core.ResumedOrderPayment
import com.memobook.networking.ApiError
import com.memobook.payments.PaymentOutcome
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue
import kotlin.time.Duration

/**
 * **« Finaliser ma commande »** (T232) : la commande abandonnée se reprend par
 * `POST /v1/orders/:id/payment`, sans en passer une seconde. Sans émulateur :
 * on branche les trois fonctions et on regarde ce qui revient. Porté de
 * `AbandonedOrderPaymentTests.swift`, cas pour cas.
 */
class AbandonedOrderPaymentTest {
    private val ticket = OrderPayment(
        amountCents = 3_990,
        currency = "eur",
        clientSecret = "pi_test_secret_test",
        publishableKey = "pk_test_x",
    )

    private fun order(status: PrintOrderStatus): PrintOrder =
        PrintOrder.fixture(memoId = "memo-1", request = NewPrintOrderRequest.previewRequest)
            .copy(id = "order-1", status = status)

    private class Log {
        val resumed = mutableListOf<String>()
        var reloads = 0
    }

    private fun payment(
        log: Log,
        payment: OrderPayment? = ticket,
        sheet: PaymentOutcome = PaymentOutcome.Succeeded,
        failure: Exception? = null,
    ): AbandonedOrderPayment = AbandonedOrderPayment(
        resume = { id ->
            log.resumed += id
            if (failure != null) throw failure
            ResumedOrderPayment(order = order(PrintOrderStatus.Draft), payment = payment)
        },
        present = { sheet },
        reload = {
            log.reloads += 1
            order(if (log.reloads < 2) PrintOrderStatus.Draft else PrintOrderStatus.Submitted)
        },
    ).apply { settlementInterval = Duration.ZERO }

    @Test fun aPaidSheetWaitsForTheServerBeforeSayingPaid() = runTest {
        val log = Log()
        val outcome = payment(log).finish(orderId = "order-1")

        assertEquals(AbandonedOrderPayment.Outcome.Paid, outcome)
        assertEquals(listOf("order-1"), log.resumed, "La commande se reprend, elle ne se repasse pas.")
        assertEquals(2, log.reloads, "Relue jusqu'à ce que le webhook l'ait sortie du brouillon.")
    }

    @Test fun aClosedSheetLeavesTheOrderWaiting() = runTest {
        val log = Log()
        val outcome = payment(log, sheet = PaymentOutcome.Cancelled).finish(orderId = "order-1")

        assertEquals(AbandonedOrderPayment.Outcome.Cancelled, outcome)
        assertEquals(0, log.reloads)
    }

    @Test fun nothingLeftToPayIsPaid() = runTest {
        val log = Log()
        val outcome = payment(log, payment = null).finish(orderId = "order-1")

        assertEquals(AbandonedOrderPayment.Outcome.Paid, outcome)
    }

    @Test fun aRefundedOrderSaysWhatTheServerSays() = runTest {
        val log = Log()
        val refused = ApiError.Server(
            statusCode = 409,
            code = "order_refunded",
            message = "Cette commande a été remboursée : passes-en une nouvelle.",
        )
        val outcome = payment(log, failure = refused).finish(orderId = "order-1")

        val failed = assertIs<AbandonedOrderPayment.Outcome.Failed>(outcome, "Un refus doit se lire : $outcome")
        assertTrue(failed.message.contains("remboursée"))
    }

    @Test fun aServerWithoutStripeKeysSaysSoInsteadOfOpeningAnEmptySheet() = runTest {
        val log = Log()
        val keyless = OrderPayment(amountCents = 3_990, currency = "eur", clientSecret = null, publishableKey = null)
        val outcome = payment(log, payment = keyless).finish(orderId = "order-1")

        assertEquals(AbandonedOrderPayment.Outcome.Failed(OrderCopy.Payment.unavailable), outcome)
    }
}
