package com.memobook.feature

import com.memobook.core.DailyCredit
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class SubscriptionSessionTest {
    /** Le geste a le dernier mot sur ce que le serveur a dit avant lui… */
    @Test fun aPurchaseWinsOverAnOlderAnswer() {
        val session = SubscriptionSession()
        session.learn(isUnlimited = false, hasSubscribedBefore = false)
        session.record(isSubscribed = true)
        session.learn(isUnlimited = false, hasSubscribedBefore = false)
        assertTrue(session.isUnlimited)
    }

    /** … et seulement jusqu'à ce que le serveur dise la même chose (03/10/2026). */
    @Test fun theGestureStepsBackOnceTheServerAgrees() {
        val session = SubscriptionSession()
        session.record(isSubscribed = true)
        session.learn(isUnlimited = true, hasSubscribedBefore = true)
        session.learn(isUnlimited = false, hasSubscribedBefore = true)
        assertFalse(session.isUnlimited)
    }

    @Test fun anElapsedEndDropsUnlimitedEverywhere() {
        val session = SubscriptionSession()
        val end = Instant.parse("2026-10-06T20:00:00Z")
        session.learn(isUnlimited = true, hasSubscribedBefore = true, endsAt = end)
        session.expireIfDue(now = end.plusSeconds(1))
        assertFalse(session.isUnlimited)
        val credit = DailyCredit(isUnlimited = true)
        assertFalse(session.applied(credit)!!.isUnlimited)
    }

    @Test fun aNewAccountStartsFromNothing() {
        val session = SubscriptionSession()
        session.record(isSubscribed = true)
        session.reset()
        assertFalse(session.isUnlimited)
        assertEquals(PaywallVariant.FirstTime, session.paywallVariant)
    }
}
