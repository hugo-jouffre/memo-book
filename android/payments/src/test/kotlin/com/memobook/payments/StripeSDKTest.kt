package com.memobook.payments

import com.memobook.core.PaymentIntentTicket
import com.stripe.android.paymentsheet.PaymentSheet
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Ce que l'app tient du SDK Stripe, et les doubles de ses feuilles. */
@OptIn(ExperimentalCoroutinesApi::class)
class StripeSDKTest {
    // Les feuilles s'ouvrent sur le fil principal.
    @BeforeTest
    fun setUp() = Dispatchers.setMain(UnconfinedTestDispatcher())

    @AfterTest
    fun tearDown() = Dispatchers.resetMain()

    /**
     * La version d'API part avec chaque commande et chaque ouverture des
     * cartes : le serveur la refuse si elle ne se lit pas comme une date
     * (`stripeApiVersionSchema`, `backend/src/services/billing.ts`). Une montée
     * du SDK qui y ajouterait une bêta (`;…`) casserait les cartes enregistrées.
     */
    @Test
    fun theApiVersionIsOneTheServerAccepts() {
        assertTrue(
            Regex("""^\d{4}-\d{2}-\d{2}(\.[a-z]+)?$""").matches(StripeSDK.apiVersion),
            "« ${StripeSDK.apiVersion} »",
        )
    }

    @Test
    fun googlePayFollowsTheModeOfThePublishableKey() {
        assertEquals(PaymentSheet.GooglePayConfiguration.Environment.Test, StripeSDK.googlePayEnvironment("pk_test_123"))
        assertEquals(PaymentSheet.GooglePayConfiguration.Environment.Production, StripeSDK.googlePayEnvironment("pk_live_123"))
    }

    /** Le message de Stripe est relayé tel quel ; sans message, on dit qu'on n'a pas pu ouvrir le paiement. */
    @Test
    fun stripesMessageIsRelayedAsItIs() {
        assertEquals("Ta carte a été refusée.", StripeSDK.message(IllegalStateException("Ta carte a été refusée.")))
        assertEquals(PaymentError.NoPresenter.errorDescription, StripeSDK.message(IllegalStateException()))
        assertEquals("Impossible d’ouvrir le paiement pour le moment. Réessaie.", PaymentError.NoPresenter.message)
    }

    // MARK: - Les feuilles sans hôte

    @Test
    fun aSheetWithoutHostSaysItCannotOpen() = runTest {
        val outcome = StripePaymentSheetPresenter().present(ticket)

        assertEquals(PaymentOutcome.Failed(PaymentError.NoPresenter.errorDescription), outcome)
    }

    /**
     * Google Pay ne paraît dans la feuille que si le ticket le dit (lot B5) :
     * c'est le serveur qui sait si Google a accordé l'accès en production.
     */
    @Test
    fun googlePayFollowsTheTicket() {
        val presenter = StripePaymentSheetPresenter()

        // Un serveur d'avant B5 n'envoie rien : cartes seules.
        assertNull(presenter.googlePay(ticket))
        // Son environnement suit la clé publique (`googlePayEnvironment`, plus haut).
        assertNotNull(presenter.googlePay(ticket.copy(googlePayEnabled = true)))
    }

    @Test
    fun theCardsSheetRelaysTheServersRefusal() = runTest {
        val message = StripeCustomerSheetPresenter().present(
            key = { throw IllegalStateException("Connexion impossible. Vérifie ton réseau et réessaie.") },
            setupIntent = { "seti_secret" },
        )

        assertEquals("Connexion impossible. Vérifie ton réseau et réessaie.", message)
    }

    // MARK: - Les doubles

    @Test
    fun theStubsCallNobody() = runTest {
        assertEquals(PaymentOutcome.Succeeded, StubPaymentPresenter().present(ticket))
        assertEquals(PaymentOutcome.Cancelled, StubPaymentPresenter(PaymentOutcome.Cancelled).present(ticket))
        assertNull(StubPaymentMethodsPresenter().present(key = { error("jamais appelée") }, setupIntent = { "" }))
    }

    private val ticket = PaymentIntentTicket(
        clientSecret = "pi_123_secret_456",
        publishableKey = "pk_test_123",
        amountCents = 10788,
        currency = "eur",
    )
}
