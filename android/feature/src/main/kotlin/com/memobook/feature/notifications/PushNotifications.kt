package com.memobook.feature.notifications

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalContext
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.memobook.core.NotificationLink
import com.memobook.core.PushEnvironment
import com.memobook.core.PushProvider
import com.memobook.core.PushTokenRegistration
import com.memobook.feature.AppSettings
import com.memobook.networking.MemoBookApi
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import java.util.TimeZone

/**
 * Les notifications, côté téléphone : **l'autorisation**, **le jeton**, et **le
 * toucher**. Jumeau de `Notifications/PushNotifications.swift`. Les règles —
 * quoi envoyer, quand — sont au serveur (`docs/notifications.md`) ; l'app ne
 * programme aucune notification locale.
 *
 * Un objet **de l'app entière**, et non d'un écran : c'est le service de
 * notifications qui reçoit le jeton, et l'activité qui reçoit le toucher,
 * parfois avant même que `RootView` existe — une notification touchée app
 * fermée ouvre l'app sur elle. Il garde donc ce qu'on lui confie jusqu'à ce que
 * quelqu'un puisse s'en servir :
 *
 * - le jeton part au serveur dès qu'une session est branchée ([connect]) ;
 * - le lien touché attend dans [pendingLink] que l'accueil soit là pour ouvrir
 *   l'écran qu'il désigne.
 *
 * **Le jeton vient de Firebase Cloud Messaging** (lot B3, 22/10/2026), par
 * [PushTokenSource] — [FirebasePushTokenSource] dans l'app, un double dans les
 * tests — et part au serveur avec le fournisseur `fcm`. Le message reçu est
 * posé par `MemoBookMessagingService` ([PushNotificationPoster]). Sans projet
 * Firebase (`memobook.firebase.*` vides), aucun jeton ne vient : l'autorisation,
 * le lien en attente et l'accusé d'ouverture marchent sans lui.
 *
 * L'intégrateur le construit une fois (dans `MemoBookApplication` ou
 * `RootView`, avec [create]), le pose dans [LocalPushNotifications], le branche
 * à chaque session (`connect(api)`, comme le `.task(id: account.id)` d'iOS) et
 * lui passe chaque intention qui ouvre l'activité ([didOpen]).
 */
@Stable
class PushNotifications(
    private val permission: NotificationPermission,
    private val tokens: PushTokenSource,
    private val environment: PushEnvironment,
    private val appVersion: String?,
    private val scope: CoroutineScope,
) {
    /**
     * Ce qu'Android a répondu à la demande d'autorisation. [NotificationAuthorization.NotDetermined]
     * tant qu'on ne l'a pas posée — la feuille « Notifications » s'en sert pour
     * dire que tout est coupé dans les Paramètres.
     */
    var authorization: NotificationAuthorization by mutableStateOf(NotificationAuthorization.NotDetermined)
        private set

    /**
     * Le lien de la notification qu'on vient de toucher, en attendant que
     * `RootView` l'ouvre. Remis à `null` par celui qui l'a consommé.
     */
    var pendingLink: NotificationLink? by mutableStateOf(null)

    /** Le dernier jeton que le service de notifications a donné. */
    private var deviceToken: String? = null

    /** L'API de la session ouverte, ou `null` hors session — rien ne part alors. */
    private var api: MemoBookApi? = null

    /**
     * Le jeton déjà remis **à cette session**. Une nouvelle session le renvoie :
     * le serveur l'a oublié avec la précédente.
     */
    private var deliveredToken: String? = null

    /**
     * Les notifications touchées avant qu'une session soit là pour le dire au
     * serveur — app fermée, le toucher arrive avant la relecture de la session.
     * Elles partent à [connect].
     */
    private val unreportedOpenings = mutableListOf<String>()

    // MARK: - La session

    /**
     * Une session s'ouvre : on la retient, et on demande le jeton si
     * l'autorisation est déjà donnée — **sans jamais poser la question ici**.
     * La question se pose au bon moment, à l'étape « Notifications » de la
     * création d'un voyage, ou depuis la bulle de la conversation
     * ([requestAuthorization]).
     */
    suspend fun connect(api: MemoBookApi) {
        this.api = api
        deliveredToken = null
        refreshAuthorization()
        if (authorization.allowsDelivery) tokens.register(::didRegister)
        val openings = unreportedOpenings.toList()
        unreportedOpenings.clear()
        openings.forEach(::reportOpening)
        deliverToken()
    }

    /**
     * La session se ferme. Le serveur oublie le jeton avec elle ; l'app, elle,
     * garde le jeton pour la personne suivante.
     */
    fun disconnect() {
        api = null
        deliveredToken = null
        pendingLink = null
    }

    // MARK: - L'autorisation

    /**
     * Relit ce qu'Android a retenu — la personne a pu tout couper dans les
     * Paramètres entre deux ouvertures. À appeler à l'ouverture d'un écran qui
     * en parle, et au retour au premier plan.
     */
    fun refreshAuthorization() {
        authorization = permission.current()
    }

    /**
     * **Pose la question**, si elle ne l'a jamais été, puis s'inscrit auprès du
     * service de notifications. Sans effet quand la réponse est déjà connue :
     * un refus se corrige dans les Paramètres.
     *
     * Android 13 et plus demandent la permission `POST_NOTIFICATIONS`, par la
     * fenêtre du système — [askSystem], qu'un écran obtient de
     * [rememberNotificationPermissionRequest]. Avant Android 13, les
     * notifications sont permises d'office, et il n'y a rien à demander.
     *
     * @return `true` quand les notifications peuvent arriver.
     */
    suspend fun requestAuthorization(askSystem: suspend () -> Boolean): Boolean {
        refreshAuthorization()
        if (authorization == NotificationAuthorization.NotDetermined) {
            permission.markAsked()
            askSystem()
            refreshAuthorization()
        }
        if (!authorization.allowsDelivery) return false
        tokens.register(::didRegister)
        return true
    }

    // MARK: - Ce que le système transmet

    /** Le service de notifications a donné un jeton — à chaque lancement, et chaque fois qu'il change. */
    fun didRegister(token: String) {
        deviceToken = token
        scope.launch { deliverToken() }
    }

    /**
     * On a touché une notification : on retient où elle mène, et on dit au
     * serveur qu'elle a été ouverte.
     */
    fun didOpen(link: String?, deliveryId: String?) {
        NotificationLink.from(link)?.let { pendingLink = it }
        if (deliveryId == null) return
        if (api == null) unreportedOpenings += deliveryId else reportOpening(deliveryId)
    }

    /**
     * L'intention qui ouvre l'activité, quand elle vient d'une notification
     * touchée : les mêmes clés que la charge d'iOS (`link`, `deliveryId`).
     *
     * @return `true` si l'intention venait d'une notification.
     */
    fun didOpen(intent: Intent?): Boolean {
        intent ?: return false
        val link = intent.getStringExtra(EXTRA_LINK)
        val deliveryId = intent.getStringExtra(EXTRA_DELIVERY_ID)
        if (link == null && deliveryId == null) return false
        didOpen(link, deliveryId)
        return true
    }

    private fun reportOpening(deliveryId: String) {
        val api = api ?: return
        scope.launch {
            try {
                api.markNotificationOpened(deliveryId)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                // Un accusé perdu ne se rattrape pas, et ne mérite pas d'alerte.
            }
        }
    }

    // MARK: - Le jeton, au serveur

    private suspend fun deliverToken() {
        val api = api ?: return
        val token = deviceToken ?: return
        if (token == deliveredToken) return

        val registration = PushTokenRegistration(
            token = token,
            environment = environment,
            timeZone = TimeZone.getDefault().id,
            appVersion = appVersion,
            provider = PushProvider.Fcm,
        )
        try {
            api.registerPushToken(registration)
            deliveredToken = token
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            // Rien à dire à l'écran : on réessaiera à la prochaine entrée dans
            // l'app. Une notification manquée vaut mieux qu'une alerte.
        }
    }

    companion object {
        /** Le lien d'une notification touchée, dans l'intention qui ouvre l'activité. */
        const val EXTRA_LINK = "link"

        /** L'identifiant de l'envoi, pour l'accusé d'ouverture (`POST /v1/notifications/:id/opened`). */
        const val EXTRA_DELIVERY_ID = "deliveryId"

        /** Les notifications de l'app, sur le téléphone — l'objet que l'app construit une fois. */
        fun create(
            context: Context,
            settings: AppSettings,
            isDebug: Boolean,
            appVersion: String?,
            scope: CoroutineScope,
        ): PushNotifications = PushNotifications(
            permission = AndroidNotificationPermission(context.applicationContext, settings),
            tokens = FirebasePushTokenSource { FirebasePush.isReady(context) },
            environment = PushEnvironment.current(isDebug),
            appVersion = appVersion,
            scope = scope,
        )

        /**
         * La page des notifications de MemoBook dans les Paramètres du
         * téléphone : un refus ne se corrige que là.
         */
        fun openSystemSettings(context: Context) {
            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            runCatching { context.startActivity(intent) }
        }
    }
}

/**
 * Ce qu'Android laisse passer — l'`UNAuthorizationStatus` d'iOS, réduit à ce
 * qu'Android sait dire.
 */
enum class NotificationAuthorization {
    /** La question n'a jamais été posée : « Activer les notifications » la pose. */
    NotDetermined,

    /** Refusées, ou coupées dans les Paramètres : seule la page du système les rouvre. */
    Denied,

    Authorized,
    ;

    /** Android laissera passer ce qu'on enverra. Android n'a pas de « provisoire » : autorisé, c'est tout. */
    val allowsDelivery: Boolean get() = this == Authorized

    companion object {
        /**
         * Ce que valent les réponses du système.
         *
         * - **Avant Android 13**, les notifications sont permises d'office :
         *   elles ne sont refusées que si la personne les a coupées.
         * - **Depuis Android 13**, la permission `POST_NOTIFICATIONS` les
         *   ouvre. Jamais demandée, la question reste à poser ; demandée et pas
         *   accordée, c'est un refus — comme sur iOS, on ne la repose pas, la
         *   bulle mène aux Paramètres. (Android laisserait la redemander une
         *   fois ; iOS non, et les deux apps se tiennent à la même règle.)
         *
         * @param hasAsked l'app a déjà posé la question sur cet appareil.
         */
        fun resolve(
            sdkInt: Int,
            isPermissionGranted: Boolean,
            areNotificationsEnabled: Boolean,
            hasAsked: Boolean,
        ): NotificationAuthorization = when {
            sdkInt < Build.VERSION_CODES.TIRAMISU -> if (areNotificationsEnabled) Authorized else Denied
            isPermissionGranted -> if (areNotificationsEnabled) Authorized else Denied
            hasAsked -> Denied
            else -> NotDetermined
        }
    }
}

/** Où se lit — et se retient — l'autorisation. Une interface, pour que [PushNotifications] se teste sur la JVM. */
interface NotificationPermission {
    fun current(): NotificationAuthorization

    /** La question vient d'être posée : on ne la reposera plus. */
    fun markAsked()
}

/** L'autorisation du téléphone. Que la question ait été posée se retient dans les réglages de l'app. */
class AndroidNotificationPermission(private val context: Context, private val settings: AppSettings) : NotificationPermission {
    override fun current(): NotificationAuthorization = NotificationAuthorization.resolve(
        sdkInt = Build.VERSION.SDK_INT,
        isPermissionGranted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED,
        areNotificationsEnabled = NotificationManagerCompat.from(context).areNotificationsEnabled(),
        hasAsked = settings.getBoolean(ASKED_KEY),
    )

    override fun markAsked() {
        settings.putBoolean(ASKED_KEY, true)
    }

    private companion object {
        const val ASKED_KEY = "memobook.notifications.permissionAsked"
    }
}

/**
 * Ce qui donne le jeton de l'appareil au téléphone — le
 * `registerForRemoteNotifications()` d'iOS et le délégué qui reçoit le jeton.
 */
interface PushTokenSource {
    /**
     * Demande le jeton au service de notifications. Il revient par [onToken],
     * tout de suite ou plus tard — et de nouveau chaque fois qu'il change.
     */
    fun register(onToken: (String) -> Unit)
}

/**
 * Pose la question d'Android 13 — la fenêtre `POST_NOTIFICATIONS` du système —
 * et rend sa réponse. Avant Android 13, rien à demander : elle rend ce que le
 * téléphone permet déjà. À passer à [PushNotifications.requestAuthorization].
 *
 * Une fonction d'écran : la fenêtre du système s'ouvre depuis l'activité, par
 * un lanceur que seul un écran peut inscrire.
 */
@Composable
fun rememberNotificationPermissionRequest(): suspend () -> Boolean {
    val context = LocalContext.current
    val waiting = remember { PermissionAnswer() }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        waiting.deliver(granted)
    }
    return remember(context, launcher) {
        suspend {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                NotificationManagerCompat.from(context).areNotificationsEnabled()
            } else {
                val answer = waiting.expect()
                launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
                answer.await()
            }
        }
    }
}

/** La réponse attendue de la fenêtre du système. */
private class PermissionAnswer {
    private var pending: CompletableDeferred<Boolean>? = null

    fun expect(): CompletableDeferred<Boolean> = CompletableDeferred<Boolean>().also {
        pending?.complete(false)
        pending = it
    }

    fun deliver(granted: Boolean) {
        pending?.complete(granted)
        pending = null
    }
}

/**
 * Les notifications de l'app, pour les écrans qui en parlent — la feuille
 * « Notifications », l'étape du même nom à la création d'un voyage, la bulle de
 * la conversation. `null` dans un aperçu : rien n'y demande l'autorisation pour
 * de vrai.
 */
val LocalPushNotifications = staticCompositionLocalOf<PushNotifications?> { null }
