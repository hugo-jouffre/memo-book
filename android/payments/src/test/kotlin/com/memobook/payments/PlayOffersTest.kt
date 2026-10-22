package com.memobook.payments

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** Le choix de l'offre achetée, et la période écrite après le prix. */
class PlayOffersTest {
    // MARK: - Le plan de base

    @Test
    fun theBasePlanIsBoughtEvenWhenAnOfferIsListed() {
        // Une offre « déterminée par le développeur » revient à tout le monde :
        // la prendre d'office la donnerait à chacun.
        assertEquals("monthly-token", PlayOffers.basePlan(listOf(trialOffer(), monthlyBasePlan()))?.offerToken)
    }

    @Test
    fun theMonthlyBasePlanComesFirst() {
        val yearly = monthlyBasePlan(basePlanId = "yearly", period = "P1Y", price = "49,99 €", token = "yearly-token")

        assertEquals("monthly-token", PlayOffers.basePlan(listOf(yearly, monthlyBasePlan()))?.offerToken)
        assertEquals("yearly-token", PlayOffers.basePlan(listOf(yearly))?.offerToken)
    }

    @Test
    fun withoutABasePlanThereIsNothingToBuy() {
        assertNull(PlayOffers.basePlan(listOf(trialOffer())))
        assertNull(PlayOffers.basePlan(emptyList()))
    }

    @Test
    fun theRecurringPhaseIsTheRegularPrice() {
        assertEquals("4,99 €", trialOffer().recurringPhase?.formattedPrice)
    }

    // MARK: - La période

    @Test
    fun aPeriodOfOneReadsAsItsUnit() {
        assertEquals("mois", PlayOffers.label("P1M"))
        assertEquals("semaine", PlayOffers.label("P1W"))
        assertEquals("an", PlayOffers.label("P1Y"))
        assertEquals("jour", PlayOffers.label("P1D"))
    }

    @Test
    fun aLongerPeriodCarriesItsNumber() {
        assertEquals("3 mois", PlayOffers.label("P3M"))
        assertEquals("4 semaines", PlayOffers.label("P4W"))
        assertEquals("2 ans", PlayOffers.label("P2Y"))
    }

    @Test
    fun aPeriodThatDoesNotReadLeavesTheOffersOwn() {
        assertNull(PlayOffers.label("P1M2W"))
        assertNull(PlayOffers.label("mois"))
        assertNull(PlayOffers.label(""))
    }

    // MARK: - L'identifiant du compte

    @Test
    fun aMemoBookAccountIdLeavesAsItIs() {
        assertEquals(
            "4f1c2d3e-0000-4000-8000-000000000001",
            PlayOffers.obfuscatedAccountId("4f1c2d3e-0000-4000-8000-000000000001"),
        )
    }

    @Test
    fun anIdGooglePlayWouldRefuseDoesNotLeave() {
        assertNull(PlayOffers.obfuscatedAccountId("x".repeat(65)))
        assertNull(PlayOffers.obfuscatedAccountId(" "))
        assertNull(PlayOffers.obfuscatedAccountId(null))
    }
}
