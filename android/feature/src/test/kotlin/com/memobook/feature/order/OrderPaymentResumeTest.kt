package com.memobook.feature.order

import com.memobook.core.MemoBookJson
import com.memobook.core.NewPrintOrderRequest
import com.memobook.core.OrderContext
import com.memobook.core.OrderPayment
import com.memobook.core.OrderSettlement
import com.memobook.core.OrderStep
import com.memobook.core.PlacedPrintOrder
import com.memobook.core.PrintOrder
import com.memobook.core.ResumedOrderPayment
import com.memobook.payments.PaymentOutcome
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * **« Payer » reprend la commande déjà passée** (01/10/2026). Il en créait une
 * seconde à chaque tapotis — une nouvelle intention, et un second débit. Sans
 * émulateur : le modèle reçoit ses fonctions, comme l'app les lui branche, et
 * on compte ce qu'il appelle. Porté de `OrderPaymentResumeTests.swift`, cas
 * pour cas.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class OrderPaymentResumeTest {
    /** Ce que le modèle a demandé au serveur. */
    private class Calls {
        val submitted = mutableListOf<NewPrintOrderRequest>()
        val resumed = mutableListOf<String>()
        val cancelled = mutableListOf<String>()
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

    private fun model(calls: Calls, sheet: List<PaymentOutcome>): OrderModel {
        val outcomes = ArrayDeque(sheet)
        val ticket = ticket
        return OrderModel(
            memoId = "memo-1",
            submit = { memoId, request ->
                calls.submitted += request
                PlacedPrintOrder(order = PrintOrder.fixture(memoId = memoId, request = request), payment = ticket)
            },
            presentPayment = { outcomes.removeFirstOrNull() ?: PaymentOutcome.Succeeded },
            reloadOrder = null,
            resumePayment = { orderId ->
                calls.resumed += orderId
                val order = PrintOrder.fixture(memoId = "memo-1", request = calls.submitted.last())
                ResumedOrderPayment(order = order, payment = ticket)
            },
            cancelOrder = { orderId ->
                calls.cancelled += orderId
                PrintOrder.fixture(memoId = "memo-1", request = calls.submitted.last())
            },
        )
    }

    /**
     * Apple Pay arrive du serveur, avec le paiement : la feuille d'iOS ne le
     * montre que s'il est là — un serveur sans certificat Apple Pay n'en envoie
     * pas. Le ticket le porte aussi sur Android, où la feuille ne le lit pas :
     * elle lit `googlePayEnabled` (B5), et un ticket sans identifiant paie par
     * carte.
     */
    @Test fun applePayComesFromTheServerWithThePayment() {
        val withApplePay = MemoBookJson.decodeFromString(
            OrderPayment.serializer(),
            """
            {"amountCents":4990,"currency":"eur","clientSecret":"pi_x_secret_y",
            "publishableKey":"pk_test_x","applePayMerchantId":"merchant.com.tonapp.memobook"}
            """.trimIndent(),
        )
        val card = assertIs<OrderSettlement.Card>(withApplePay.settlement, "carte attendue")
        assertEquals("merchant.com.tonapp.memobook", card.ticket.applePayMerchantId)

        val cardsOnly = assertIs<OrderSettlement.Card>(ticket.settlement, "carte attendue")
        assertNull(cardsOnly.ticket.applePayMerchantId)
    }

    /**
     * Google Pay arrive du serveur de la même façon (lot B5) — et un serveur
     * d'avant B5, qui ne l'envoie pas, laisse la feuille aux cartes seules.
     */
    @Test fun googlePayComesFromTheServerWithThePayment() {
        val withGooglePay = MemoBookJson.decodeFromString(
            OrderPayment.serializer(),
            """
            {"amountCents":4990,"currency":"eur","clientSecret":"pi_x_secret_y",
            "publishableKey":"pk_test_x","applePayMerchantId":null,"googlePayEnabled":true}
            """.trimIndent(),
        )
        val card = assertIs<OrderSettlement.Card>(withGooglePay.settlement, "carte attendue")
        assertTrue(card.ticket.googlePayEnabled)

        val olderServer = MemoBookJson.decodeFromString(
            OrderPayment.serializer(),
            """{"amountCents":4990,"currency":"eur","clientSecret":"pi_x_secret_y","publishableKey":"pk_test_x"}""",
        )
        assertFalse(assertIs<OrderSettlement.Card>(olderServer.settlement, "carte attendue").ticket.googlePayEnabled)
    }

    /**
     * « Payer » sur un carnet qu'aucune composition n'a rendu (T224) : le
     * serveur répond `409 no_render`, et l'étape le dit au lieu de ne rien
     * faire. Le jeu d'essai du modèle répond comme le serveur.
     */
    @Test fun payingWithoutARenderSaysSo() = runTest {
        val model = OrderModel(memoId = "memo-1", context = { OrderContext.notComposedFixture })
        model.load()

        model.pay()

        val state = model.state.value
        assertTrue(state.isMissingRender)
        assertNull(state.paymentError, "Ce n'est pas une panne : pas de bandeau d'erreur.")
        assertNotEquals(OrderStep.Confirmation, state.step)
    }

    @Test fun aClosedSheetResumesTheSameOrder() = runTest {
        val calls = Calls()
        val model = model(calls, sheet = listOf(PaymentOutcome.Cancelled, PaymentOutcome.Succeeded))
        model.load()

        model.pay()
        assertEquals(OrderStep.Start, model.state.value.step, "La feuille refermée ne passe pas à la confirmation.")
        model.pay()

        assertEquals(1, calls.submitted.size, "Une seule commande, malgré deux « Payer ».")
        assertEquals(1, calls.resumed.size)
        assertTrue(calls.cancelled.isEmpty())
        assertEquals(OrderStep.Confirmation, model.state.value.step)
    }

    @Test fun aChangedDraftAbandonsTheOldOrderFirst() = runTest {
        val calls = Calls()
        val model = model(calls, sheet = listOf(PaymentOutcome.Cancelled, PaymentOutcome.Succeeded))
        model.load()

        model.pay()
        val first = model.state.value.order?.id
        model.draft = model.draft.copy(copies = 2)
        model.pay()

        assertEquals(2, calls.submitted.size, "Le brouillon a changé : une commande neuve.")
        assertEquals(listOfNotNull(first), calls.cancelled, "L'ancienne rend sa réservation.")
        assertTrue(calls.resumed.isEmpty())
    }
}
