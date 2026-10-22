package com.memobook.feature.paywall

import com.memobook.feature.PaywallVariant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Le pied de l'offre et la barre des stories. Le premier cas est porté de
 * `ProfileModelTests.testTheOfferPriceNeverBreaks` (recette du 03/10/2026).
 */
class PaywallCopyTest {
    /** « 4,99 € par mois » ne se coupe jamais entre le prix et sa période. */
    @Test fun theOfferPriceNeverBreaks() {
        val renewal = PaywallCopy.offerFootnotePrice(price = "4,99 €", period = "mois")
        assertFalse(renewal.price.contains(" "))
        assertEquals("4,99 € par mois", renewal.price.replace(" ", " "))
        assertEquals("MemoBook illimité pour ", renewal.lead)
        assertEquals(".", renewal.trail)
    }

    /** « chaque mois » ne vaut que pour un abonnement mensuel : la période vient du produit. */
    @Test fun theConditionsFollowTheProductPeriod() {
        assertTrue(PaywallCopy.offerFootnoteDetail("mois").contains("chaque mois"))
        val weekly = PaywallCopy.offerFootnoteDetail("semaine")
        assertTrue(weekly.contains("chaque semaine"))
        assertFalse(weekly.contains("chaque mois"))
    }

    /** La première fois vend le carnet ; au retour, on dit ce qu'on retrouve. */
    @Test fun theOfferTitleFollowsTheVariant() {
        assertEquals("Ce carnet que tu relieras encore " to "dans 30 ans", PaywallVariant.FirstTime.offerTitle)
        assertEquals("Raconte de nouveau " to "sans compter", PaywallVariant.Returning.offerTitle)
        assertEquals(3, PaywallVariant.FirstTime.pageCount)
        assertEquals(2, PaywallVariant.Returning.pageCount)
    }

    /** La barre lit l'heure et calcule sa part : rien n'est en vol, et rien ne dépasse. */
    @Test fun theBarComputesItsShare() {
        val duration = PaywallMetrics.pageDurationMillis
        val running = PaywallFill.Running(sinceMillis = 1_000)
        assertEquals(0.0, running.value(atMillis = 1_000, durationMillis = duration))
        assertEquals(0.5, running.value(atMillis = 1_000 + duration / 2, durationMillis = duration))
        assertEquals(1.0, running.value(atMillis = 1_000 + duration * 2, durationMillis = duration))
        assertEquals(0.0, running.value(atMillis = 0, durationMillis = duration))
        assertEquals(0.3, PaywallFill.Held(0.3).value(atMillis = 99_999, durationMillis = duration))
        assertEquals(1.0, PaywallFill.fraction(sinceMillis = 0, atMillis = 0, durationMillis = 0))
        assertTrue(running.isRunning)
        assertFalse(PaywallFill.Held(1.0).isRunning)
    }

    /** L'achat d'aperçu n'achète rien : il rend la main comme une feuille refermée. */
    @Test fun thePreviewPurchaseBuysNothing() = kotlinx.coroutines.test.runTest {
        assertEquals(PurchaseOutcome.Cancelled, SubscriptionPurchase.preview.purchase(null))
        assertEquals(RestoreOutcome.NothingToRestore, SubscriptionPurchase.preview.restore())
    }
}
