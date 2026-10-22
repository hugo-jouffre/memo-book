package com.memobook.feature.order

import com.memobook.core.NewPrintOrderRequest
import com.memobook.core.OrderCopy
import com.memobook.core.OrderPayment
import com.memobook.core.OrderStep
import com.memobook.core.PlacedPrintOrder
import com.memobook.core.PrintOrder
import com.memobook.core.PrintOrderStatus
import com.memobook.core.ResumedOrderPayment
import com.memobook.payments.PaymentOutcome
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Les garde-fous de l'argent que `OrderModel.swift` porte et que la suite iOS
 * ne rejoue pas : **l'app ne décide jamais qu'une commande est payée**, un
 * serveur sans clés Stripe ne confirme rien, une carte refusée se reprend sur
 * la même commande, et deux « Payer » n'en passent pas deux. Une suite propre à
 * Android, à côté de `OrderPaymentResumeTest` (le portage cas pour cas).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class OrderPaymentGuardTest {
    private class Server {
        val submitted = mutableListOf<NewPrintOrderRequest>()
        val resumed = mutableListOf<String>()
        val presented = mutableListOf<String>()
        var reloads = 0
    }

    private val ticket = OrderPayment(
        amountCents = 4_990,
        currency = "eur",
        clientSecret = "pi_test_secret_test",
        publishableKey = "pk_test_x",
    )

    @BeforeTest fun setUp() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @AfterTest fun tearDown() {
        Dispatchers.resetMain()
    }

    /**
     * @param paidAfter la relecture à partir de laquelle le serveur a appris le
     *   paiement (le webhook) ; `null` : il ne l'apprend jamais.
     */
    private fun model(
        server: Server,
        payment: OrderPayment = ticket,
        sheet: suspend () -> PaymentOutcome = { PaymentOutcome.Succeeded },
        paidAfter: Int? = 2,
        resumedPayment: OrderPayment? = ticket,
    ): OrderModel = OrderModel(
        memoId = "memo-1",
        submit = { memoId, request ->
            server.submitted += request
            PlacedPrintOrder(order = PrintOrder.fixture(memoId = memoId, request = request), payment = payment)
        },
        presentPayment = { ticket ->
            server.presented += ticket.clientSecret
            sheet()
        },
        reloadOrder = { orderId ->
            server.reloads += 1
            val status = if (paidAfter != null && server.reloads >= paidAfter) PrintOrderStatus.Submitted else PrintOrderStatus.Draft
            PrintOrder.fixture(memoId = "memo-1", request = server.submitted.last()).copy(id = orderId, status = status)
        },
        resumePayment = { orderId ->
            server.resumed += orderId
            val order = PrintOrder.fixture(memoId = "memo-1", request = server.submitted.last()).copy(id = orderId)
            ResumedOrderPayment(order = order, payment = resumedPayment)
        },
        cancelOrder = { orderId -> PrintOrder.fixture(memoId = "memo-1", request = server.submitted.last()).copy(id = orderId) },
    )

    private suspend fun TestScope.loaded(model: OrderModel): OrderModel {
        model.load()
        advanceUntilIdle()
        return model
    }

    /**
     * Une feuille qui rend « payé » dit que Stripe a accepté, pas que le
     * serveur l'a appris : la confirmation porte la commande **relue**, sortie
     * du brouillon par le webhook.
     */
    @Test fun aSucceededSheetWaitsForTheServerToSayPaid() = runTest {
        val server = Server()
        val model = loaded(model(server, paidAfter = 2))

        model.pay()

        assertEquals(2, server.reloads, "Relue jusqu'à ce que le serveur la dise payée.")
        assertEquals(PrintOrderStatus.Submitted, model.state.value.order?.status)
        assertEquals(OrderStep.Confirmation, model.state.value.step)
    }

    /**
     * Au bout du budget, la confirmation s'affiche quand même : l'argent est
     * pris, elle est due — et la commande montrée reste celle que le serveur a
     * rendue, en brouillon, jamais une commande que l'app aurait dite payée.
     */
    @Test fun aWebhookThatNeverArrivesStillConfirmsWithoutClaimingPaid() = runTest {
        val server = Server()
        val model = loaded(model(server, paidAfter = null))

        model.pay()

        assertEquals(6, server.reloads, "Six relectures, une par seconde.")
        assertEquals(OrderStep.Confirmation, model.state.value.step)
        assertEquals(PrintOrderStatus.Draft, model.state.value.order?.status)
    }

    /** Un serveur sans clés Stripe : on le dit, sans feuille vide ni confirmation. */
    @Test fun aServerWithoutStripeKeysNeverConfirms() = runTest {
        val server = Server()
        val keyless = OrderPayment(amountCents = 4_990, currency = "eur", clientSecret = "", publishableKey = "")
        val model = loaded(model(server, payment = keyless))

        model.pay()

        assertEquals(OrderCopy.Payment.unavailable, model.state.value.paymentError)
        assertTrue(server.presented.isEmpty(), "Aucune feuille ne s'ouvre sur une clé vide.")
        assertNotEquals(OrderStep.Confirmation, model.state.value.step)
    }

    /** La phrase de Stripe se lit telle quelle, et « Payer » reprend la même commande. */
    @Test fun aRefusedCardSaysWhatStripeSaysAndResumesTheSameOrder() = runTest {
        val server = Server()
        val outcomes = ArrayDeque(listOf(PaymentOutcome.Failed("Ta carte a été refusée."), PaymentOutcome.Succeeded))
        val model = loaded(model(server, sheet = { outcomes.removeFirst() }))

        model.pay()
        assertEquals("Ta carte a été refusée.", model.state.value.paymentError)
        assertNotEquals(OrderStep.Confirmation, model.state.value.step)

        model.pay()
        assertNull(model.state.value.paymentError)
        assertEquals(1, server.submitted.size, "Pas de seconde commande après un refus.")
        assertEquals(1, server.resumed.size)
        assertEquals(OrderStep.Confirmation, model.state.value.step)
    }

    /** Plus rien à régler à la reprise (payée entre-temps) : la confirmation, sans rouvrir de feuille. */
    @Test fun nothingLeftToPayOnResumeConfirmsWithoutASheet() = runTest {
        val server = Server()
        val outcomes = ArrayDeque(listOf(PaymentOutcome.Cancelled))
        val model = loaded(model(server, sheet = { outcomes.removeFirst() }, resumedPayment = null))

        model.pay()
        model.pay()

        assertEquals(1, server.presented.size, "La seconde fois, rien à ouvrir.")
        assertEquals(1, server.submitted.size)
        assertEquals(OrderStep.Confirmation, model.state.value.step)
    }

    /** Deux « Payer » pendant que la feuille est ouverte ne passent qu'une commande. */
    @Test fun aSecondPayWhileSubmittingIsIgnored() = runTest {
        val server = Server()
        val sheetClosed = CompletableDeferred<PaymentOutcome>()
        val model = loaded(model(server, sheet = { sheetClosed.await() }))

        val first = launch { model.pay() }
        runCurrent()
        assertTrue(model.state.value.isSubmitting)
        model.pay()

        sheetClosed.complete(PaymentOutcome.Cancelled)
        first.join()

        assertEquals(1, server.submitted.size)
        assertEquals(1, server.presented.size)
        assertEquals(false, model.state.value.isSubmitting)
    }
}
