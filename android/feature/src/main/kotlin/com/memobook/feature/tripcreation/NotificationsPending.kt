package com.memobook.feature.tripcreation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import com.memobook.feature.AppSettings

// À brancher : Chat/ChatNotificationsNudge.swift (`NotificationsNudge`) et
// Notifications/PushNotifications.swift (`PushNotifications`,
// `\.pushNotifications`).
//
// Le lot « partage » les porte (`chat/ChatNotificationsNudge.kt`,
// `notifications/PushNotifications.kt`) ; l'étape « Notifications » de la
// création s'en sert sous leurs noms et leurs signatures. Rien ici ne retient
// ni ne demande quoi que ce soit. L'intégrateur supprime ce fichier à la
// fusion et importe `com.memobook.feature.chat.NotificationsNudge`,
// `com.memobook.feature.notifications.LocalPushNotifications` et
// `com.memobook.feature.notifications.rememberNotificationPermissionRequest`
// dans `TripCreationDependencies.kt` et `TripCreationSteps.kt`.

/** Ce que la bulle des notifications retient de l'étape — voir `NotificationsNudge`. */
internal object NotificationsNudge {
    /** L'étape « Notifications » de la création a été traversée — choisie ou passée — sur cet appareil. */
    @Suppress("UNUSED_PARAMETER")
    fun markStepPassed(settings: AppSettings) = Unit
}

/** Les notifications de l'app — `PushNotifications`. */
internal class PushNotifications {
    /** Pose la question, si elle ne l'a jamais été. `true` quand les notifications peuvent arriver. */
    @Suppress("UNUSED_PARAMETER")
    suspend fun requestAuthorization(askSystem: suspend () -> Boolean): Boolean = false
}

/** `null` dans un aperçu, et en attendant le lot : rien n'y demande l'autorisation pour de vrai. */
internal val LocalPushNotifications = staticCompositionLocalOf<PushNotifications?> { null }

/** La fenêtre `POST_NOTIFICATIONS` du système, que seul un écran peut ouvrir. */
@Composable
internal fun rememberNotificationPermissionRequest(): suspend () -> Boolean = remember { suspend { false } }
