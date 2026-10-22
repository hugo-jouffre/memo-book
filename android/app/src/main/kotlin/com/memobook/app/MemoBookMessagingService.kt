package com.memobook.app

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.memobook.feature.notifications.PushMessageContent

/**
 * Ce que Firebase Cloud Messaging remet au téléphone (lot B3, 22/10/2026) —
 * le délégué d'`UNUserNotificationCenter` et de
 * `didRegisterForRemoteNotifications` d'iOS, en un.
 *
 * - **Un nouveau jeton** (première installation, données effacées, jeton
 *   tourné) part à [com.memobook.feature.notifications.PushNotifications], qui
 *   le remet au serveur dès qu'une session est là.
 * - **Un message** — toujours de données seulement (`services/fcm.ts`) —
 *   devient une notification posée par l'app, app ouverte comme fermée : son
 *   toucher ouvre [MainActivity] avec `link` et `deliveryId`, que
 *   `PushNotifications.didOpen(intent)` lit.
 */
class MemoBookMessagingService : FirebaseMessagingService() {
    private val memoBook: MemoBookApplication get() = applicationContext as MemoBookApplication

    override fun onNewToken(token: String) {
        memoBook.push.didRegister(token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val content = PushMessageContent.from(message.data) ?: return
        memoBook.notificationPoster.post(content)
    }
}
