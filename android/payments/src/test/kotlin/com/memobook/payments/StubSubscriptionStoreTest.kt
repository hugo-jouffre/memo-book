package com.memobook.payments

import kotlinx.coroutines.test.runTest
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Le double du bac à sable — porté de `ProfileModelTests.testASandboxPurchaseIsDeliveredLikeARealOne`
 * (03/10/2026), où il est essayé depuis le profil.
 */
class StubSubscriptionStoreTest {
    /**
     * L'achat du bac à sable passe par la même remise que le vrai : le double
     * d'API l'apprend, et cesse de compter.
     */
    @Test
    fun aSandboxPurchaseIsDeliveredLikeARealOne() = runTest {
        val store = StubSubscriptionStore()
        val received = mutableListOf<String>()

        val outcome = store.purchase(appAccountToken = null) { received += it.purchaseToken }
        assertEquals(PurchaseOutcome.Subscribed, outcome)
        assertEquals(listOf("preview"), received)

        val refused = store.purchase(appAccountToken = null) {
            throw TransactionRefused("Cet achat appartient à un autre compte.")
        }
        assertEquals(PurchaseOutcome.Failed("Cet achat appartient à un autre compte."), refused)

        val unreachable = store.purchase(appAccountToken = null) { throw IOException("Délai dépassé") }
        assertEquals(PurchaseOutcome.AwaitingServer, unreachable)
    }

    /** Un autre résultat que l'abonnement est rendu tel quel, sans rien remettre. */
    @Test
    fun aFixedOutcomeIsReturnedWithoutDelivery() = runTest {
        val store = StubSubscriptionStore(outcome = PurchaseOutcome.Cancelled)
        val received = mutableListOf<SignedTransaction>()

        assertEquals(PurchaseOutcome.Cancelled, store.purchase(appAccountToken = null) { received += it })
        assertTrue(received.isEmpty())
    }
}
