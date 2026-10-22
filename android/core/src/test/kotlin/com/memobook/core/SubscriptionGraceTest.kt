package com.memobook.core

import java.math.BigDecimal
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * **Le sursis de la période payée.** Un mois commencé est un mois réglé :
 * résilier le 3 ne rend pas les semaines suivantes, donc ça ne referme pas
 * l'illimité non plus (Hugo, 16/09/2026 pour la semaine, règle tenue au passage
 * au mois le 03/10/2026). Mêmes cas que `SubscriptionGraceTests.swift`.
 *
 * Les règles vivent sur [Subscription] et non dans une vue, précisément pour
 * qu'elles se testent sans émulateur — c'est de la date, pas du dessin.
 */
class SubscriptionGraceTest {
    private val today = Instant.ofEpochSecond(1_789_000_000)

    private fun days(count: Long, from: Instant = today): Instant =
        from.atZone(ZoneId.systemDefault()).plusDays(count).toInstant()

    private fun price(raw: String) = BigDecimal(raw)

    private fun decode(json: String): Subscription = MemoBookJson.decodeFromString(Subscription.serializer(), json)

    private fun encode(subscription: Subscription): String =
        MemoBookJson.encodeToString(Subscription.serializer(), subscription)

    private fun decodeTraveller(json: String): Traveller = MemoBookJson.decodeFromString(Traveller.serializer(), json)

    @Test
    fun anActiveSubscriptionGrantsAccess() {
        val subscription = Subscription(price = price("4.99"), isActive = true)
        assertTrue(subscription.grantsAccess(on = today))
        // Actif, il n'y a pas de sursis à annoncer : la phrase des feuilles de
        // résiliation n'a pas lieu d'être tant qu'on n'a pas résilié.
        assertNull(subscription.graceEnd(on = today))
    }

    @Test
    fun aCancelledSubscriptionKeepsItsPaidMonth() {
        val subscription = Subscription(price = price("4.99"), isActive = false, cancelledAt = today, paidThrough = days(20))

        assertTrue(subscription.grantsAccess(on = today))
        assertEquals(days(20), subscription.graceEnd(on = today))
    }

    @Test
    fun theLastDayKeepsTheOldBehaviour() {
        // **Le cas que Hugo a nommément épargné** : « si le dernier jour est
        // aujourd'hui, le processus reste celui d'avant ». Il n'y a pas de sursis
        // à annoncer pour un jour qui est déjà là, et la dernière feuille garde
        // « l'abonnement s'arrête aujourd'hui ».
        val subscription = Subscription(
            price = price("4.99"),
            isActive = false,
            cancelledAt = today,
            // La **même journée**, à quelques heures près : c'est le jour qui
            // compte, pas l'heure.
            paidThrough = today.plusSeconds(6 * 3_600),
        )

        assertFalse(subscription.isWithinPaidPeriod(on = today))
        assertFalse(subscription.grantsAccess(on = today))
        assertNull(subscription.graceEnd(on = today))
    }

    @Test
    fun aPastPeriodGrantsNothing() {
        val subscription = Subscription(price = price("4.99"), isActive = false, cancelledAt = days(-40), paidThrough = days(-2))

        assertFalse(subscription.grantsAccess(on = today))
        assertNull(subscription.graceEnd(on = today))
    }

    @Test
    fun nothingPaidGrantsNothing() {
        // Un compte qui n'a jamais souscrit : `paidThrough` est nul, et on
        // retombe sur le comportement d'avant.
        val subscription = Subscription(price = price("4.99"))
        assertFalse(subscription.grantsAccess(on = today))
    }

    /** Un profil d'ancien abonné : plus d'abonnement actif — exactement l'état de
     *  quelqu'un qui vient de résilier. */
    private fun cancelledProfile(paidThrough: Instant?): TravellerProfile = TravellerProfile(
        fullName = "Margaux Prn",
        subscription = Subscription(price = price("4.99"), isActive = false, cancelledAt = Instant.now(), paidThrough = paidThrough),
    )

    @Test
    fun theProfileFollowsTheAccessAndNotTheFlag() {
        // Le point qui compte : l'illimité se lit sur l'**accès**, pas sur
        // `isActive`. Le refermer le jour du geste rendrait fausse la phrase que
        // la feuille de résiliation vient d'écrire.
        val profile = cancelledProfile(paidThrough = days(4, from = Instant.now()))

        assertTrue(profile.isSubscriber)
        assertTrue(profile.subscription.isUnlimited)
    }

    @Test
    fun theProfileClosesOnceThePeriodIsOver() {
        val profile = cancelledProfile(paidThrough = days(-1, from = Instant.now()))

        assertFalse(profile.isSubscriber)
        assertFalse(profile.subscription.isUnlimited)
    }

    // MARK: Le prix à écrire

    @Test
    fun theOfferIsFourNinetyNineAMonth() {
        assertEquals(price("4.99"), Subscription.offer.price)
        assertEquals(Subscription.Interval.Month, Subscription.offer.interval)
        assertEquals("mois", Subscription.offer.periodLabel)
    }

    @Test
    fun displayedPriceIsNeverZero() {
        // Un abonnement à zéro euro n'existe pas : c'est la marque d'un serveur
        // qui n'a pas de ligne à lire. L'app écrivait « 0,00 € ».
        val empty = Subscription(price = BigDecimal.ZERO)
        assertEquals(Subscription.offer.price, empty.displayedPrice)
        assertEquals("mois", empty.periodLabel)

        // Un vrai prix, lui, passe tel quel — avec sa période.
        assertEquals(price("5.99"), Subscription(price = price("5.99")).displayedPrice)
        assertEquals("semaine", Subscription(price = price("1.99"), interval = Subscription.Interval.Week).periodLabel)
    }

    @Test
    fun thePaywallOnlySellsTheMonth() {
        // Un ancien abonné à la semaine garde son tarif dans « Mon abonnement »,
        // mais l'offre qu'on lui présente est la mensuelle.
        assertEquals(price("4.99"), Subscription(price = price("1.99"), interval = Subscription.Interval.Week).offeredPrice)
        assertEquals(price("5.49"), Subscription(price = price("5.49"), interval = Subscription.Interval.Month).offeredPrice)
        assertEquals(price("4.99"), Subscription(price = BigDecimal.ZERO).offeredPrice)

        val nothing: Subscription? = null
        assertEquals(price("4.99"), nothing.offeredPrice)
    }

    // MARK: Le décodage

    @Test
    fun theMonthlyPriceIsRead() {
        val subscription = decode("""{ "price": 4.99, "interval": "month", "weeklyPrice": 4.99, "isActive": true }""")
        assertEquals(price("4.99"), subscription.price)
        assertEquals(Subscription.Interval.Month, subscription.interval)
        assertTrue(subscription.isUnlimited)
    }

    @Test
    fun anOlderServerStillDecodes() {
        // Un serveur d'avant le mois ne sert que `weeklyPrice` : le profil ne
        // doit pas tomber, et sa période est la semaine.
        val subscription = decode("""{ "weeklyPrice": 1.99, "isActive": false }""")
        assertEquals(price("1.99"), subscription.price)
        assertEquals(Subscription.Interval.Week, subscription.interval)
        assertEquals(Subscription.offer.price, subscription.offeredPrice)
    }

    @Test
    fun anUnknownIntervalFallsBackToTheMonth() {
        val subscription = decode("""{ "price": 49.99, "interval": "year", "isActive": true }""")
        assertEquals(Subscription.Interval.Month, subscription.interval)
    }

    @Test
    fun theSubscriptionRoundTripsThroughTheCache() {
        // Le cache disque réencode le profil : il doit se relire tel quel.
        val original = Subscription(
            price = price("4.99"),
            interval = Subscription.Interval.Month,
            isActive = true,
            tripTitle = "Rome entre amis",
            managedByAppStore = true,
        )
        assertEquals(original, decode(encode(original)))
    }

    // MARK: Apple tient l'abonnement (01/10/2026)

    @Test
    fun anAppStoreSubscriptionSaysSo() {
        val subscription = decode("""{ "price": 4.99, "interval": "month", "isActive": true, "managedByAppStore": true }""")
        assertTrue(subscription.managedByAppStore)
    }

    @Test
    fun anOlderServerIsNotTakenForApple() {
        // Sans le champ, la résiliation reste celle d'avant : une route d'ici,
        // pas la feuille du store.
        val subscription = decode("""{ "weeklyPrice": 1.99, "isActive": true }""")
        assertFalse(subscription.managedByAppStore)
    }

    // MARK: Le verdict du serveur (03/10/2026)

    /** Le dernier jour payé, le serveur accorde encore l'illimité jusqu'à l'heure
     *  de `renewsAt` ; le recalcul au jour près dirait non. Le profil suit le
     *  serveur, et ne contredit plus la conversation. */
    @Test
    fun theServedVerdictWinsOnTheLastPaidDay() {
        // Une minute de mois payé devant soi — aujourd'hui, donc : le recalcul au
        // jour près le refuse, le serveur l'accorde.
        val paidThrough = MemoBookDate.format(Instant.now().plusSeconds(60))
        val subscription = decode(
            """{ "price": 4.99, "interval": "month", "isActive": false, """ +
                """"cancelledAt": "2026-10-01T09:00:00.000Z", "paidThrough": "$paidThrough", "isUnlimited": true }""",
        )
        assertEquals(true, subscription.servedIsUnlimited)
        assertTrue(subscription.isUnlimited)
        assertTrue(TravellerProfile(fullName = "Camille", subscription = subscription).isSubscriber)
    }

    /** Délai de grâce de facturation du store (`past_due`) : `isActive` est faux
     *  et rien n'est résilié, mais le serveur accorde l'illimité. */
    @Test
    fun aBillingGracePeriodStaysUnlimited() {
        val subscription = decode("""{ "price": 4.99, "interval": "month", "isActive": false, "isUnlimited": true }""")
        assertTrue(subscription.isUnlimited)
        assertNull(subscription.cancelledAt)
    }

    /** Un geste fait dans l'app retouche l'abonnement sur place : le verdict
     *  servi avant lui ne vaut plus, et le recalcul reprend la main. */
    @Test
    fun aLocalGestureDropsTheServedVerdict() {
        var subscription = Subscription(price = price("4.99"), isActive = true, servedIsUnlimited = true)

        subscription = subscription.updating(isActive = true)
        assertEquals(true, subscription.servedIsUnlimited, "Rien n'a changé : le verdict tient.")

        subscription = subscription.updating(isActive = false)
        assertNull(subscription.servedIsUnlimited)
        assertFalse(subscription.isUnlimited, "Ni actif ni mois payé : plus d'illimité.")

        var paid = Subscription(price = price("4.99"), servedIsUnlimited = false)
        paid = paid.updating(paidThrough = Instant.now().plus(Duration.ofDays(10)))
        assertNull(paid.servedIsUnlimited)
        assertTrue(paid.isUnlimited, "Dix jours payés devant soi : l'illimité.")
    }

    @Test
    fun anOlderServerFallsBackOnTheDay() {
        val subscription = decode("""{ "price": 4.99, "interval": "month", "isActive": true }""")
        assertNull(subscription.servedIsUnlimited)
        assertTrue(subscription.isUnlimited)
    }

    @Test
    fun theServedVerdictRoundTripsThroughTheCache() {
        val original = Subscription(price = price("4.99"), isActive = false, servedIsUnlimited = true)
        val decoded = decode(encode(original))
        assertEquals(true, decoded.servedIsUnlimited)
        assertEquals(original, decoded)
    }

    /** Mis en cache pendant le mois payé, relu hors ligne une fois ce mois passé :
     *  le « oui » du serveur ne vaut plus, l'illimité se referme comme le serveur
     *  l'aurait refermé. */
    @Test
    fun aServedVerdictExpiresWithItsPaidPeriod() {
        val paidThrough = MemoBookDate.format(Instant.now().minus(Duration.ofDays(2)))
        val served = decode(
            """{ "price": 4.99, "interval": "month", "isActive": false, """ +
                """"cancelledAt": "2026-10-01T09:00:00.000Z", "paidThrough": "$paidThrough", "isUnlimited": true }""",
        )
        val cached = decode(encode(served))
        assertEquals(true, cached.servedIsUnlimited, "Le verdict voyage avec le cache…")
        assertFalse(cached.isUnlimited, "… mais ne survit pas à sa période.")
        assertFalse(TravellerProfile(fullName = "Camille", subscription = cached).isSubscriber)

        // La veille de la fin, il tenait.
        assertTrue(cached.isUnlimited(at = Instant.now().minus(Duration.ofDays(3))))
    }

    /** Les phrases de la résiliation disent la période **payée** : la semaine
     *  d'un ancien abonné hebdomadaire, le mois sinon. */
    @Test
    fun thePaidIntervalFollowsThePrice() {
        assertEquals(Subscription.Interval.Week, Subscription(price = price("1.99"), interval = Subscription.Interval.Week).paidInterval)
        assertEquals(Subscription.Interval.Month, Subscription(price = price("4.99")).paidInterval)
        assertEquals(Subscription.Interval.Month, Subscription(price = BigDecimal.ZERO, interval = Subscription.Interval.Week).paidInterval)
        assertEquals("semaine", Subscription(price = price("1.99"), interval = Subscription.Interval.Week).periodLabel)
    }

    // MARK: L'accueil

    @Test
    fun theTripEndReminderIsReadFromTheHome() {
        val traveller = decodeTraveller("""{ "id": "t", "firstName": "Camille", "subscriptionOutlivesTrip": true }""")
        assertTrue(traveller.subscriptionOutlivesTrip)

        // Et un serveur qui ne le sert pas ne rappelle rien à personne.
        assertFalse(decodeTraveller("""{ "id": "t", "firstName": "Camille" }""").subscriptionOutlivesTrip)
    }

    @Test
    fun theHomeSaysWhoIsUnlimited() {
        val traveller = decodeTraveller(
            """{ "id": "t", "firstName": "Camille", "isUnlimited": true, "hasSubscribedBefore": true }""",
        )
        assertTrue(traveller.isUnlimited)
        assertTrue(traveller.hasSubscribedBefore)

        // Un serveur plus ancien : personne n'est illimité, et le paywall ouvre
        // sur la découverte. Les anciens champs d'étapes s'ignorent.
        val decoded = decodeTraveller("""{ "id": "t", "firstName": "Camille", "offeredSteps": 3, "remainingSteps": 0 }""")
        assertFalse(decoded.isUnlimited)
        assertFalse(decoded.hasSubscribedBefore)
    }

    // MARK: L'état tranché par le serveur (contrat du 06/10/2026, point 11)

    private fun decodedSubscription(fields: String): Subscription =
        decode("""{ "price": 4.99, "interval": "month", "isActive": false, $fields}""")

    /** Renouvellement coupé : abonné jusqu'à la date de fin, puis plus du tout —
     *  même lu dans le cache, sans relecture (Hugo, 06/10/2026). */
    @Test
    fun anEndingSubscriptionStopsAtItsDate() {
        val end = days(10)
        val subscription = decodedSubscription(
            """"isUnlimited": true, "state": "ending", "autoRenews": false, "endsAt": "$end"""",
        )

        assertEquals(Subscription.State.Ending, subscription.servedState)
        assertTrue(subscription.isUnlimited(at = today))
        assertNotNull(subscription.unlimitedUntil(at = today))
        assertTrue(subscription.isCancelled)
        assertFalse(subscription.isInBillingRetry)

        assertFalse(subscription.isUnlimited(at = days(11)))
        assertNull(subscription.unlimitedUntil(at = days(11)))
    }

    /** Un renouvellement coupé chez le store, sans `cancelledAt` : la lecture
     *  d'avant y voyait un prélèvement raté. L'état du serveur tranche. */
    @Test
    fun theServedStateIsNotMistakenForABillingRetry() {
        val ending = decodedSubscription(""""isUnlimited": true, "state": "ending"""")
        assertFalse(ending.isInBillingRetry)

        val grace = decodedSubscription(""""isUnlimited": true, "state": "grace"""")
        assertTrue(grace.isInBillingRetry)
        assertTrue(grace.isUnlimited(at = today))
        assertFalse(grace.isCancelled)
    }

    @Test
    fun anEndedOrRefundedSubscriptionGrantsNothing() {
        // Un remboursement : `ended`, même si une période payée traînait.
        val ended = decodedSubscription(""""isUnlimited": false, "state": "ended", "paidThrough": "2030-01-01T00:00:00Z"""")
        assertFalse(ended.isUnlimited(at = today))
        assertNull(ended.unlimitedUntil(at = today))
    }

    /** Une valeur inconnue de cette version ne fait pas tomber le profil : la
     *  lecture d'avant répond. */
    @Test
    fun anUnknownStateFallsBackToTheFlags() {
        val subscription = decodedSubscription(""""isUnlimited": true, "state": "paused"""")
        assertNull(subscription.servedState)
        assertTrue(subscription.isUnlimited(at = today))
    }

    /** Un geste local (résilier dans l'app) retouche l'abonnement : l'état servi
     *  avant lui ne vaut plus. */
    @Test
    fun aGestureForgetsTheServedState() {
        var subscription = decodedSubscription(""""isUnlimited": true, "state": "active"""")
        assertEquals(Subscription.State.Active, subscription.servedState)
        subscription = subscription.updating(isActive = true)
        assertNull(subscription.servedState)
    }

    @Test
    fun theHomeSaysWhenTheUnlimitedEnds() {
        val traveller = decodeTraveller(
            """{ "id": "t", "firstName": "Camille", "isUnlimited": true, "subscriptionState": "ending", "subscriptionEndsAt": "2030-01-01T00:00:00Z" }""",
        )
        assertEquals(Subscription.State.Ending, traveller.subscriptionState)
        assertNotNull(traveller.unlimitedUntil)

        val active = """{ "id": "t", "firstName": "Camille", "isUnlimited": true, "subscriptionState": "active" }"""
        assertNull(decodeTraveller(active).unlimitedUntil)
    }
}
