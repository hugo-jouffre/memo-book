package com.memobook.feature.notifications

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/** Ce que l'app lit d'un message FCM, et de la configuration Firebase du build. */
class FirebasePushTest {
    /** Les clés que `services/fcm.ts` écrit — celles de la charge APNs. */
    @Test fun aMessageCarriesTheApnsKeys() {
        val content = PushMessageContent.from(
            mapOf(
                "title" to "Ton voyage à Rome se termine aujourd’hui",
                "body" to "Raconte la dernière journée.",
                "link" to "memobook://trips/t-1/preview",
                "deliveryId" to "envoi-1",
                "threadId" to "t-1",
            ),
        )
        assertEquals(
            PushMessageContent(
                title = "Ton voyage à Rome se termine aujourd’hui",
                body = "Raconte la dernière journée.",
                link = "memobook://trips/t-1/preview",
                deliveryId = "envoi-1",
                threadId = "t-1",
            ),
            content,
        )
    }

    /** Le toucher rouvre l'activité avec les extras que `PushNotifications.didOpen(intent)` lit. */
    @Test fun theTapCarriesTheExtrasDidOpenReads() {
        val content = assertNotNull(PushMessageContent.from(mapOf("title" to "T", "link" to "memobook://paywall", "deliveryId" to "envoi-1")))
        assertEquals(
            mapOf(PushNotifications.EXTRA_LINK to "memobook://paywall", PushNotifications.EXTRA_DELIVERY_ID to "envoi-1"),
            content.extras,
        )
        // Sans lien — une notification du compte —, la clé manque, et `didOpen` lit `null`.
        assertEquals(mapOf(PushNotifications.EXTRA_DELIVERY_ID to "envoi-2"), PushMessageContent.from(mapOf("body" to "B", "deliveryId" to "envoi-2"))?.extras)
    }

    /** Rien à montrer : pas de notification vide. */
    @Test fun anEmptyMessageShowsNothing() {
        assertNull(PushMessageContent.from(emptyMap()))
        assertNull(PushMessageContent.from(mapOf("title" to "  ", "deliveryId" to "envoi-1")))
    }

    /** Un envoi, une notification : deux envois ne se remplacent pas, le même se repose au même endroit. */
    @Test fun eachDeliveryHasItsOwnNotification() {
        val first = PushMessageContent.from(mapOf("title" to "T", "deliveryId" to "envoi-1"))!!
        val second = PushMessageContent.from(mapOf("title" to "T", "deliveryId" to "envoi-2"))!!
        assertNotEquals(first.notificationId, second.notificationId)
        assertEquals(first.notificationId, PushMessageContent.from(mapOf("title" to "Autre", "deliveryId" to "envoi-1"))!!.notificationId)
    }

    /** Une valeur manquante dans `gradle.properties`, et Firebase reste coupé. */
    @Test fun firebaseNeedsAllFourValues() {
        assertNull(FirebaseConfiguration.from("", "", "", ""))
        assertNull(FirebaseConfiguration.from("1:123:android:abc", "AIzaX", "memobook", " "))
        assertEquals(
            FirebaseConfiguration("1:123:android:abc", "AIzaX", "memobook", "123"),
            FirebaseConfiguration.from(" 1:123:android:abc ", "AIzaX", "memobook", "123"),
        )
    }
}
