package com.memobook.feature.notifications

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging

// Firebase Cloud Messaging, côté téléphone (lot B3, 22/10/2026) : le jeton, et
// la notification qu'on pose quand un message arrive. Le serveur l'envoie par
// `services/fcm.ts` ; le contrat est dans `docs/notifications.md`.
//
// **Sans le plugin `google-services` ni `google-services.json`** : les quatre
// valeurs du projet Firebase viennent de `android/gradle.properties`
// (`memobook.firebase.*`), comme l'adresse de production, et `FirebaseApp`
// s'initialise à la main. Vides, Firebase n'est pas initialisé, aucun jeton ne
// part, et rien ne plante : l'autorisation, le lien en attente et l'accusé
// d'ouverture marchent sans lui.

/**
 * Les valeurs du projet Firebase, celles que `google-services.json` aurait
 * portées. Aucune n'est un secret — elles partent dans chaque APK, comme le
 * `GoogleService-Info.plist` d'une app iOS.
 */
data class FirebaseConfiguration(
    /** L'identifiant de l'app Android dans Firebase, `1:…:android:…` (`mobilesdk_app_id`). */
    val applicationId: String,
    /** La clé d'API du projet, `AIza…` (`current_key`). */
    val apiKey: String,
    /** `memobook-…` (`project_id`). */
    val projectId: String,
    /** Le numéro du projet (`project_number`), l'expéditeur des messages. */
    val gcmSenderId: String,
) {
    fun options(): FirebaseOptions = FirebaseOptions.Builder()
        .setApplicationId(applicationId)
        .setApiKey(apiKey)
        .setProjectId(projectId)
        .setGcmSenderId(gcmSenderId)
        .build()

    companion object {
        /** `null` dès qu'une valeur manque : Firebase à moitié configuré ne rendrait aucun jeton. */
        fun from(applicationId: String, apiKey: String, projectId: String, gcmSenderId: String): FirebaseConfiguration? {
            val values = listOf(applicationId, apiKey, projectId, gcmSenderId).map(String::trim)
            if (values.any(String::isEmpty)) return null
            return FirebaseConfiguration(values[0], values[1], values[2], values[3])
        }
    }
}

/** L'initialisation de Firebase, une fois par processus. */
object FirebasePush {
    private const val TAG = "FirebasePush"

    /**
     * Initialise Firebase, au démarrage du processus (`Application.onCreate`) :
     * un message reçu app fermée relance le processus sans activité, et le
     * service de messagerie a besoin de Firebase avant toute chose.
     *
     * @return `true` quand Firebase est prêt à donner un jeton.
     */
    fun initialize(context: Context, configuration: FirebaseConfiguration?): Boolean {
        if (configuration == null) return false
        if (FirebaseApp.getApps(context).isNotEmpty()) return true
        return try {
            FirebaseApp.initializeApp(context, configuration.options())
            true
        } catch (error: IllegalStateException) {
            Log.w(TAG, "Firebase non initialisé : ${error.message}")
            false
        }
    }

    fun isReady(context: Context): Boolean = FirebaseApp.getApps(context).isNotEmpty()
}

/**
 * Le jeton de Firebase Cloud Messaging. Il revient ici à la demande
 * ([register]), et par `MemoBookMessagingService.onNewToken` chaque fois que
 * Firebase le change — les deux mènent à [PushNotifications.didRegister].
 *
 * Sans Firebase initialisé ([FirebasePush.isReady]), il ne fait rien.
 */
class FirebasePushTokenSource(private val isReady: () -> Boolean) : PushTokenSource {
    override fun register(onToken: (String) -> Unit) {
        if (!isReady()) return
        try {
            FirebaseMessaging.getInstance().token.addOnSuccessListener { token ->
                if (!token.isNullOrBlank()) onToken(token)
            }
        } catch (error: IllegalStateException) {
            // Firebase s'est retiré entre-temps : pas de jeton, pas d'alerte.
            Log.w("FirebasePush", "Jeton FCM indisponible : ${error.message}")
        }
    }
}

/**
 * Un message reçu de FCM, tel que le serveur l'écrit (`fcmMessage`, dans
 * `services/fcm.ts`) : **des données seulement**, avec les clés de la charge
 * APNs — `title`, `body`, `link`, `deliveryId`, `threadId`.
 */
data class PushMessageContent(
    val title: String,
    val body: String,
    val link: String?,
    val deliveryId: String?,
    /** Le voyage, ou `memobook` pour les notifications du compte — le `thread-id` d'APNs, gardé pour le jour où l'app regroupera. */
    val threadId: String?,
) {
    /**
     * Les extras de l'intention qui ouvre l'activité au toucher — ceux que
     * [PushNotifications.didOpen] lit.
     */
    val extras: Map<String, String>
        get() = buildMap {
            link?.let { put(PushNotifications.EXTRA_LINK, it) }
            deliveryId?.let { put(PushNotifications.EXTRA_DELIVERY_ID, it) }
        }

    /**
     * Le numéro de la notification dans le centre de notifications : un par
     * envoi, pour qu'une notification n'en remplace pas une autre. Le même
     * envoi reçu deux fois se pose au même endroit.
     */
    val notificationId: Int
        get() = (deliveryId ?: "$title\n$body").hashCode()

    companion object {
        /** `null` quand le message n'a rien à montrer — ni titre, ni texte. */
        fun from(data: Map<String, String>): PushMessageContent? {
            val title = data["title"].orEmpty().trim()
            val body = data["body"].orEmpty().trim()
            if (title.isEmpty() && body.isEmpty()) return null
            return PushMessageContent(
                title = title,
                body = body,
                link = data["link"]?.takeIf(String::isNotBlank),
                deliveryId = data["deliveryId"]?.takeIf(String::isNotBlank),
                threadId = data["threadId"]?.takeIf(String::isNotBlank),
            )
        }
    }
}

/** Le texte du canal, tel que les Paramètres du téléphone le montrent. */
object PushNotificationChannelCopy {
    const val NAME = "MemoBook"
    const val DESCRIPTION = "Les rappels de tes voyages et les nouvelles de tes co-voyageurs."
}

/**
 * Pose la notification d'un message reçu — app fermée comme app ouverte, à la
 * manière du `willPresent` d'iOS, qui montre la bannière même au premier plan.
 *
 * @param activity l'activité que le toucher ouvre, avec les extras du message.
 * @param smallIcon l'icône de la barre d'état, d'une seule couleur.
 */
class PushNotificationPoster(
    private val context: Context,
    private val activity: Class<out Activity>,
    private val smallIcon: Int,
) {
    /** Le canal de l'app — Android 8 et plus n'affichent rien sans lui. Sans effet s'il existe. */
    fun createChannel() {
        val channel = NotificationChannel(CHANNEL_ID, PushNotificationChannelCopy.NAME, NotificationManager.IMPORTANCE_HIGH).apply {
            description = PushNotificationChannelCopy.DESCRIPTION
        }
        context.getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
    }

    fun post(content: PushMessageContent) {
        if (!canPost()) return
        createChannel()

        val intent = Intent(context, activity).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        content.extras.forEach { (key, value) -> intent.putExtra(key, value) }
        // Un code par envoi : deux `PendingIntent` qui ne diffèrent que par
        // leurs extras seraient le même, et le second toucher ouvrirait le
        // lien du premier.
        val pending = PendingIntent.getActivity(
            context,
            content.notificationId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(smallIcon)
            .setContentTitle(content.title.ifEmpty { null })
            .setContentText(content.body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(content.body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()

        try {
            NotificationManagerCompat.from(context).notify(content.notificationId, notification)
        } catch (_: SecurityException) {
            // La permission a été retirée entre la vérification et l'envoi.
        }
    }

    private fun canPost(): Boolean {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    }

    companion object {
        const val CHANNEL_ID = "memobook"
    }
}
