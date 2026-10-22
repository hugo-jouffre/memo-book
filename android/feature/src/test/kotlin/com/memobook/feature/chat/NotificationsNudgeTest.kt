package com.memobook.feature.chat

import com.memobook.core.ChatCallToAction
import com.memobook.core.ChatCallToActionState
import com.memobook.feature.InMemoryAppSettings
import com.memobook.feature.notifications.NotificationAuthorization
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * T246 : la bulle « Suggestions » des notifications — à qui la montrer, et ce
 * qu'elle propose. Porté de `NotificationsNudgeTests.swift`.
 *
 * Le troisième cas d'iOS traverse aussi `TripCreationModel` (l'étape choisie
 * ou passée) : sa moitié « création » se porte avec le lot du voyage ; ici, ce
 * que la bulle retient de l'étape.
 */
class NotificationsNudgeTest {
    @Test fun shownOnlyAfterTheStepAndWithoutAuthorization() {
        // Jamais traversé l'étape — un co-voyageur venu par un code : rien.
        assertFalse(NotificationsNudge.isShown(hasPassedStep = false, authorization = NotificationAuthorization.NotDetermined, state = ChatCallToActionState.Pending))
        // Passée sans réponse, ou refusée : la bulle.
        assertTrue(NotificationsNudge.isShown(hasPassedStep = true, authorization = NotificationAuthorization.NotDetermined, state = ChatCallToActionState.Pending))
        assertTrue(NotificationsNudge.isShown(hasPassedStep = true, authorization = NotificationAuthorization.Denied, state = ChatCallToActionState.Pending))
        // Autorisé : elle s'en va. (Android n'a pas de « provisoire ».)
        assertFalse(NotificationsNudge.isShown(hasPassedStep = true, authorization = NotificationAuthorization.Authorized, state = ChatCallToActionState.Pending))
        // Ignorée : elle se tait.
        assertFalse(NotificationsNudge.isShown(hasPassedStep = true, authorization = NotificationAuthorization.Denied, state = ChatCallToActionState.Dismissed))
    }

    @Test fun refusedItSendsToTheSettings() {
        assertEquals("Activer dans les Paramètres", NotificationsNudge.callToAction(isDenied = true).label)
        assertEquals("Activer les notifications", NotificationsNudge.callToAction(isDenied = false).label)
        assertEquals(ChatCallToAction.Kind.EnableNotifications, NotificationsNudge.callToAction(isDenied = false).kind)
    }

    @Test fun theStepIsRememberedOnTheDevice() {
        val settings = InMemoryAppSettings()
        assertFalse(NotificationsNudge.hasPassedStep(settings))

        NotificationsNudge.markStepPassed(settings)
        assertTrue(NotificationsNudge.hasPassedStep(settings))
    }
}
