package com.memobook.payments

import com.android.billingclient.api.BillingClient.BillingResponseCode
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Les règles du magasin Google Play, sur la JVM : quelle offre il achète,
 * comment il traduit les issues de Google, et ce qu'il fait d'une remise au
 * serveur qui réussit, échoue ou est refusée. Google Play lui-même est
 * remplacé par [FakePlayBilling].
 */
@OptIn(ExperimentalCoroutinesApi::class)
class PlayBillingSubscriptionStoreTest {
    private val unavailable = SubscriptionStoreError.Unavailable.errorDescription
    private val unverified = SubscriptionStoreError.Unverified.errorDescription

    private fun TestScope.store(billing: FakePlayBilling) = PlayBillingSubscriptionStore(billing, this)

    // MARK: - Le prix et la période

    @Test
    fun thePriceAndPeriodAreReadOnTheMonthlyBasePlan() = runTest {
        val billing = FakePlayBilling()
        val store = store(billing)

        assertEquals("4,99 €", store.displayPrice())
        assertEquals("mois", store.displayPeriod())
        // Le produit n'est demandé qu'une fois à Google Play.
        assertEquals(1, billing.productQueries)
    }

    @Test
    fun aMissingProductLeavesThePriceToTheCatalogue() = runTest {
        val store = store(FakePlayBilling(product = null))

        assertNull(store.displayPrice())
        assertNull(store.displayPeriod())
    }

    @Test
    fun aProductThatDidNotComeBackIsAskedAgain() = runTest {
        val billing = FakePlayBilling(product = null)
        val store = store(billing)
        assertNull(store.displayPrice())

        billing.product = monthlyProduct()
        assertEquals("4,99 €", store.displayPrice())
        assertEquals(2, billing.productQueries)
    }

    // MARK: - L'achat

    @Test
    fun aPurchaseTheServerTakesIsASubscription() = runTest {
        val billing = FakePlayBilling()
        val delivered = mutableListOf<SignedTransaction>()

        val outcome = store(billing).purchase("4f1c2d3e-0000-4000-8000-000000000001") { delivered += it }

        assertEquals(PurchaseOutcome.Subscribed, outcome)
        assertEquals(listOf(SignedTransaction("token-1", PlayCatalog.MONTHLY_SUBSCRIPTION, "GPA.1")), delivered)
        // L'identifiant du compte part dans l'achat, sur le plan de base.
        assertEquals("4f1c2d3e-0000-4000-8000-000000000001", billing.launches.single().accountId)
        assertEquals("monthly-token", billing.launches.single().offer.offerToken)
    }

    @Test
    fun aServerThatDoesNotAnswerLeavesThePurchaseAwaitingIt() = runTest {
        val outcome = store(FakePlayBilling()).purchase(null) { throw IOException("Pas de réseau") }

        assertEquals(PurchaseOutcome.AwaitingServer, outcome)
    }

    @Test
    fun aRefusalFromTheServerFailsWithItsMessage() = runTest {
        val outcome = store(FakePlayBilling()).purchase(null) {
            throw TransactionRefused("Cet achat appartient à un autre compte.")
        }

        assertEquals(PurchaseOutcome.Failed("Cet achat appartient à un autre compte."), outcome)
    }

    @Test
    fun aPendingPurchaseIsNotDelivered() = runTest {
        val billing = FakePlayBilling(
            launchResponse = PlayBillingResponse(BillingResponseCode.OK, listOf(purchase(state = PlayPurchase.State.Pending))),
        )
        val delivered = mutableListOf<SignedTransaction>()

        val outcome = store(billing).purchase(null) { delivered += it }

        assertEquals(PurchaseOutcome.Pending, outcome)
        assertTrue(delivered.isEmpty())
    }

    @Test
    fun closingTheSheetIsACancellation() = runTest {
        val billing = FakePlayBilling(launchResponse = PlayBillingResponse(BillingResponseCode.USER_CANCELED))

        assertEquals(PurchaseOutcome.Cancelled, store(billing).purchase(null) {})
    }

    @Test
    fun anErrorFromGooglePlayIsSaidInTheAppsWords() = runTest {
        for (code in listOf(
            BillingResponseCode.ERROR,
            BillingResponseCode.NETWORK_ERROR,
            BillingResponseCode.SERVICE_UNAVAILABLE,
            BillingResponseCode.SERVICE_DISCONNECTED,
            BillingResponseCode.BILLING_UNAVAILABLE,
            BillingResponseCode.ITEM_UNAVAILABLE,
            BillingResponseCode.DEVELOPER_ERROR,
        )) {
            val billing = FakePlayBilling(launchResponse = PlayBillingResponse(code))
            assertEquals(PurchaseOutcome.Failed(unavailable), store(billing).purchase(null) {}, "code $code")
        }
    }

    @Test
    fun aProductThatDidNotComeBackIsNotBought() = runTest {
        val billing = FakePlayBilling(product = null)

        assertEquals(PurchaseOutcome.Failed(unavailable), store(billing).purchase(null) {})
        assertTrue(billing.launches.isEmpty())
    }

    @Test
    fun aProductWithoutABasePlanIsNotBought() = runTest {
        val billing = FakePlayBilling(product = PlayProduct(PlayCatalog.MONTHLY_SUBSCRIPTION, listOf(trialOffer())))

        assertEquals(PurchaseOutcome.Failed(unavailable), store(billing).purchase(null) {})
        assertTrue(billing.launches.isEmpty())
    }

    @Test
    fun noActivityToCarryTheSheetSaysSo() = runTest {
        val billing = FakePlayBilling(launchResponse = null)

        assertEquals(
            PurchaseOutcome.Failed(PaymentError.NoPresenter.errorDescription),
            store(billing).purchase(null) {},
        )
    }

    @Test
    fun anAccountAlreadySubscribedDeliversTheSubscriptionItHolds() = runTest {
        val billing = FakePlayBilling(
            launchResponse = PlayBillingResponse(BillingResponseCode.ITEM_ALREADY_OWNED),
            owned = listOf(purchase(token = "owned", acknowledged = true)),
        )
        val delivered = mutableListOf<String>()

        val outcome = store(billing).purchase(null) { delivered += it.purchaseToken }

        assertEquals(PurchaseOutcome.Subscribed, outcome)
        assertEquals(listOf("owned"), delivered)
    }

    @Test
    fun aPurchaseOfAnotherProductIsNotOurs() = runTest {
        val billing = FakePlayBilling(
            launchResponse = PlayBillingResponse(BillingResponseCode.OK, listOf(purchase(product = "com.memobook.app.other"))),
        )
        val delivered = mutableListOf<SignedTransaction>()

        assertEquals(PurchaseOutcome.Failed(unverified), store(billing).purchase(null) { delivered += it })
        assertTrue(delivered.isEmpty())
    }

    @Test
    fun anAccountIdGooglePlayWouldRefuseDoesNotLeave() = runTest {
        val billing = FakePlayBilling()

        store(billing).purchase("x".repeat(65)) {}

        assertNull(billing.launches.single().accountId)
    }

    // MARK: - Restaurer

    @Test
    fun restoringDeliversWhatTheAccountHolds() = runTest {
        val billing = FakePlayBilling(owned = listOf(purchase(token = "owned", acknowledged = true)))
        val delivered = mutableListOf<String>()

        assertEquals(RestoreOutcome.Restored, store(billing).restore { delivered += it.purchaseToken })
        assertEquals(listOf("owned"), delivered)
    }

    @Test
    fun restoringWithoutSubscriptionHasNothingToRestore() = runTest {
        val billing = FakePlayBilling(owned = listOf(purchase(product = "com.memobook.app.other")))

        assertEquals(RestoreOutcome.NothingToRestore, store(billing).restore {})
    }

    @Test
    fun restoringWhileTheServerIsDownSaysItWillComeBack() = runTest {
        val billing = FakePlayBilling(owned = listOf(purchase()))

        assertFailsWith<SubscriptionStoreError.ServerUnreachable> { store(billing).restore { throw IOException() } }
    }

    @Test
    fun restoringAPurchaseTheServerRefusesSaysWhy() = runTest {
        val billing = FakePlayBilling(owned = listOf(purchase()))

        val refusal = assertFailsWith<TransactionRefused> {
            store(billing).restore { throw TransactionRefused("Cet abonnement est rattaché à un autre compte.") }
        }
        assertEquals("Cet abonnement est rattaché à un autre compte.", refusal.message)
    }

    @Test
    fun restoringWithoutGooglePlayFails() = runTest {
        val billing = FakePlayBilling(owned = null)

        assertFailsWith<SubscriptionStoreError.Unavailable> { store(billing).restore {} }
    }

    // MARK: - Ce qui n'est pas parti

    @Test
    fun onlyUnacknowledgedPurchasesAreDeliveredAgain() = runTest {
        val billing = FakePlayBilling(
            owned = listOf(
                purchase(token = "acknowledged", acknowledged = true),
                purchase(token = "waiting"),
                purchase(token = "pending", state = PlayPurchase.State.Pending),
            ),
        )
        val delivered = mutableListOf<String>()

        store(billing).deliverUnfinished { delivered += it.purchaseToken }

        assertEquals(listOf("waiting"), delivered)
    }

    @Test
    fun aRefusedPurchaseIsNotReplayedAtEachSignIn() = runTest {
        val billing = FakePlayBilling(owned = listOf(purchase(token = "foreign")))
        val store = store(billing)
        var attempts = 0
        val refusing: TransactionDelivery = {
            attempts += 1
            throw TransactionRefused("Cet achat appartient à un autre compte.")
        }

        store.deliverUnfinished(refusing)
        store.deliverUnfinished(refusing)

        assertEquals(1, attempts)
    }

    @Test
    fun anUndeliveredPurchaseIsTriedAgain() = runTest {
        val billing = FakePlayBilling(owned = listOf(purchase(token = "waiting")))
        val store = store(billing)
        var attempts = 0

        store.deliverUnfinished {
            attempts += 1
            throw IOException()
        }
        store.deliverUnfinished { attempts += 1 }

        assertEquals(2, attempts)
    }

    // MARK: - L'écoute

    @Test
    fun listeningDeliversWhatArrivesOutsideThePaywall() = runTest {
        val billing = FakePlayBilling(owned = emptyList())
        val store = store(billing)
        val delivered = mutableListOf<String>()

        store.startListening { delivered += it.purchaseToken }
        billing.arrive(listOf(purchase(token = "approved-by-a-parent")))
        advanceUntilIdle()

        assertEquals(listOf("approved-by-a-parent"), delivered)
    }

    @Test
    fun listeningAlsoDeliversWhatALaunchBeforeLeftBehind() = runTest {
        val billing = FakePlayBilling(owned = listOf(purchase(token = "left-behind")))
        val delivered = mutableListOf<String>()

        store(billing).startListening { delivered += it.purchaseToken }
        advanceUntilIdle()

        assertEquals(listOf("left-behind"), delivered)
    }

    @Test
    fun listeningTwiceKeepsTheFirstDelivery() = runTest {
        val billing = FakePlayBilling(owned = emptyList())
        val store = store(billing)
        val first = mutableListOf<String>()
        val second = mutableListOf<String>()

        store.startListening { first += it.purchaseToken }
        store.startListening { second += it.purchaseToken }
        billing.arrive(listOf(purchase(token = "renewed")))
        advanceUntilIdle()

        assertEquals(listOf("renewed"), first)
        assertTrue(second.isEmpty())
    }

    // MARK: - Ce que Google Play tient

    @Test
    fun anActiveSubscriptionIsACurrentEntitlement() = runTest {
        assertEquals(true, store(FakePlayBilling(owned = listOf(purchase()))).hasCurrentEntitlement())
        assertEquals(false, store(FakePlayBilling(owned = emptyList())).hasCurrentEntitlement())
        assertEquals(
            false,
            store(FakePlayBilling(owned = listOf(purchase(state = PlayPurchase.State.Pending)))).hasCurrentEntitlement(),
        )
        assertNull(store(FakePlayBilling(owned = null)).hasCurrentEntitlement())
    }

    @Test
    fun theRenewalIsReadOnTheSubscription() = runTest {
        assertEquals(false, store(FakePlayBilling(owned = listOf(purchase(autoRenewing = false)))).willAutoRenew())
        assertEquals(true, store(FakePlayBilling(owned = listOf(purchase()))).willAutoRenew())
        assertNull(store(FakePlayBilling(owned = emptyList())).willAutoRenew())
        assertNull(store(FakePlayBilling(owned = null)).willAutoRenew())
    }
}

// MARK: - Le faux Google Play

internal fun monthlyBasePlan(
    basePlanId: String = "monthly",
    period: String = "P1M",
    price: String = "4,99 €",
    token: String = "monthly-token",
) = PlayOffer(
    basePlanId = basePlanId,
    offerId = null,
    offerToken = token,
    phases = listOf(PlayPricingPhase(price, period, isInfiniteRecurring = true)),
)

internal fun trialOffer() = PlayOffer(
    basePlanId = "monthly",
    offerId = "winback",
    offerToken = "winback-token",
    phases = listOf(
        PlayPricingPhase("Gratuit", "P1W", isInfiniteRecurring = false),
        PlayPricingPhase("4,99 €", "P1M", isInfiniteRecurring = true),
    ),
)

internal fun monthlyProduct() = PlayProduct(PlayCatalog.MONTHLY_SUBSCRIPTION, listOf(trialOffer(), monthlyBasePlan()))

internal fun purchase(
    token: String = "token-1",
    product: String = PlayCatalog.MONTHLY_SUBSCRIPTION,
    state: PlayPurchase.State = PlayPurchase.State.Purchased,
    acknowledged: Boolean = false,
    autoRenewing: Boolean = true,
) = PlayPurchase(
    products = listOf(product),
    state = state,
    purchaseToken = token,
    orderId = if (state == PlayPurchase.State.Purchased) "GPA.1" else null,
    isAcknowledged = acknowledged,
    isAutoRenewing = autoRenewing,
)

internal class FakePlayBilling(
    var product: PlayProduct? = monthlyProduct(),
    var launchResponse: PlayBillingResponse? = PlayBillingResponse(BillingResponseCode.OK, listOf(purchase())),
    var owned: List<PlayPurchase>? = emptyList(),
) : PlayBilling {
    data class Launch(val offer: PlayOffer, val accountId: String?)

    var productQueries = 0
    val launches = mutableListOf<Launch>()
    private var handler: ((List<PlayPurchase>) -> Unit)? = null

    override suspend fun product(productId: String): PlayProduct? {
        productQueries += 1
        return product?.takeIf { it.productId == productId }
    }

    override suspend fun launchPurchase(
        product: PlayProduct,
        offer: PlayOffer,
        obfuscatedAccountId: String?,
    ): PlayBillingResponse? {
        launches += Launch(offer, obfuscatedAccountId)
        return launchResponse
    }

    override suspend fun subscriptions(): List<PlayPurchase>? = owned

    override fun setUpdateHandler(handler: (List<PlayPurchase>) -> Unit) {
        this.handler = handler
    }

    /** Un achat arrive par l'écouteur de Google Play, hors de toute feuille ouverte par l'app. */
    fun arrive(purchases: List<PlayPurchase>) {
        handler?.invoke(purchases)
    }
}
