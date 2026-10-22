package com.memobook.feature.notifications

import com.memobook.core.NotificationLink
import com.memobook.core.PushEnvironment
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Ce qu'Android répond, et ce que l'app en fait avant qu'une session soit là. */
class PushNotificationsTest {
    private class FakePermission(var answer: NotificationAuthorization) : NotificationPermission {
        var asked = 0
        override fun current() = answer
        override fun markAsked() {
            asked += 1
        }
    }

    private class FakeTokens : PushTokenSource {
        var registrations = 0
        override fun register(onToken: (String) -> Unit) {
            registrations += 1
        }
    }

    /** Avant Android 13, permises d'office ; depuis, la permission les ouvre, et un refus ne se repose pas. */
    @Test fun theSystemAnswers() {
        assertEquals(NotificationAuthorization.Authorized, NotificationAuthorization.resolve(32, isPermissionGranted = false, areNotificationsEnabled = true, hasAsked = false))
        assertEquals(NotificationAuthorization.Denied, NotificationAuthorization.resolve(32, isPermissionGranted = false, areNotificationsEnabled = false, hasAsked = false))
        assertEquals(NotificationAuthorization.NotDetermined, NotificationAuthorization.resolve(33, isPermissionGranted = false, areNotificationsEnabled = false, hasAsked = false))
        assertEquals(NotificationAuthorization.Denied, NotificationAuthorization.resolve(33, isPermissionGranted = false, areNotificationsEnabled = false, hasAsked = true))
        assertEquals(NotificationAuthorization.Authorized, NotificationAuthorization.resolve(34, isPermissionGranted = true, areNotificationsEnabled = true, hasAsked = true))
        // Accordée, puis coupée dans les Paramètres : refusée.
        assertEquals(NotificationAuthorization.Denied, NotificationAuthorization.resolve(34, isPermissionGranted = true, areNotificationsEnabled = false, hasAsked = true))
        assertTrue(NotificationAuthorization.Authorized.allowsDelivery)
        assertFalse(NotificationAuthorization.NotDetermined.allowsDelivery)
    }

    /** La question ne se pose qu'une fois ; la réponse connue, on ne la repose pas. */
    @Test fun theQuestionIsAskedOnce() = runTest {
        val permission = FakePermission(NotificationAuthorization.NotDetermined)
        val tokens = FakeTokens()
        val push = PushNotifications(permission, tokens, PushEnvironment.Sandbox, appVersion = null, scope = this)
        var shown = 0

        val granted = push.requestAuthorization {
            shown += 1
            permission.answer = NotificationAuthorization.Authorized
            true
        }
        assertTrue(granted)
        assertEquals(1, shown)
        assertEquals(1, permission.asked)
        assertEquals(1, tokens.registrations)

        permission.answer = NotificationAuthorization.Denied
        assertFalse(push.requestAuthorization { shown += 1; true })
        assertEquals(1, shown, "Un refus se corrige dans les Paramètres, il ne se redemande pas.")
    }

    /** Une notification touchée avant la session : son lien attend l'accueil. */
    @Test fun aTappedLinkWaitsForTheHome() {
        val push = PushNotifications(FakePermission(NotificationAuthorization.Authorized), FakeTokens(), PushEnvironment.Sandbox, appVersion = null, scope = TestScope())
        push.didOpen(link = "memobook://paywall", deliveryId = "envoi-1")
        assertEquals(NotificationLink.Paywall, push.pendingLink)

        push.disconnect()
        assertNull(push.pendingLink)
    }
}
