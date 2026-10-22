package com.memobook.app

import android.app.Application
import android.os.Build
import coil3.ImageLoader
import coil3.SingletonImageLoader
import coil3.disk.DiskCache
import coil3.disk.directory
import coil3.memory.MemoryCache
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import com.memobook.feature.AppDependencies
import com.memobook.feature.AppDependenciesHost
import com.memobook.feature.LaunchSwitches
import com.memobook.feature.OnboardingStorage
import com.memobook.feature.PreviewSupport
import com.memobook.feature.RecordingOutboxWorker
import com.memobook.feature.SharedPreferencesAppSettings
import com.memobook.feature.notifications.FirebaseConfiguration
import com.memobook.feature.notifications.FirebasePush
import com.memobook.feature.notifications.PushNotificationPoster
import com.memobook.feature.notifications.PushNotifications
import com.memobook.payments.PlayBillingSubscriptionStore
import com.memobook.payments.StripeCustomerSheetPresenter
import com.memobook.payments.StripePaymentSheetPresenter
import com.memobook.payments.StubPaymentMethodsPresenter
import com.memobook.payments.StubPaymentPresenter
import com.memobook.payments.StubSubscriptionStore
import com.memobook.networking.AndroidConnectivity
import com.memobook.networking.AndroidLogSink
import com.memobook.networking.ApiConfiguration
import com.memobook.networking.ApiError
import com.memobook.networking.KeystoreTokenStore
import com.memobook.networking.MemoBookApiClient
import com.memobook.networking.NetworkLog
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import okhttp3.OkHttpClient
import java.net.URI

/**
 * Le point d'entrée du processus, comme `MemoBookApp.swift` : il lit la
 * configuration de build et assemble [AppDependencies], une fois.
 *
 * **L'assemblage attend la première activité** : les interrupteurs du
 * lancement (`previewSignedIn`…) arrivent avec son intention, et le bac à sable
 * reçoit un autre client que l'app — voir [dependencies].
 */
class MemoBookApplication : Application(), SingletonImageLoader.Factory, AppDependenciesHost {
    private var built: AppDependencies? = null

    /**
     * Pour le vidage de la file en arrière-plan (`RecordingOutboxWorker`). Un
     * processus que WorkManager relance, sans activité, assemble l'app livrée
     * — sans interrupteur de lancement : en Debug, une activité ouverte
     * ensuite dans ce même processus garde ces dépendances-là.
     */
    override val dependencies: AppDependencies
        get() = built ?: dependencies(LaunchSwitches.None)

    /** La portée de l'app entière : ce qui y est lancé survit aux écrans. */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /**
     * Les notifications, construites tôt : le toucher d'une notification arrive
     * avec l'intention qui ouvre l'activité, avant `RootView`.
     */
    val push by lazy {
        PushNotifications.create(this, SharedPreferencesAppSettings(this), BuildConfig.DEBUG, BuildConfig.VERSION_NAME, scope)
    }

    /** Pose la notification d'un message FCM reçu (`MemoBookMessagingService`). */
    val notificationPoster by lazy {
        PushNotificationPoster(this, MainActivity::class.java, R.drawable.ic_launcher_monochrome)
    }

    /** Un seul client HTTP pour l'API et les images : un seul pool de connexions. */
    private val httpClient by lazy { OkHttpClient() }

    override fun onCreate() {
        super.onCreate()
        // Le `#if DEBUG` d'iOS : les messages d'erreur pour développeur ne
        // s'écrivent qu'en Debug.
        if (BuildConfig.DEBUG) ApiError.developerDiagnostics = ApiError.DeveloperDiagnostics(runsInEmulator())
        // Firebase avant tout le reste : un message reçu app fermée relance le
        // processus sans activité, et son service en a besoin. Sans projet
        // (`memobook.firebase.*` vides), rien ne s'initialise et aucun jeton ne part.
        val firebase = FirebaseConfiguration.from(
            applicationId = BuildConfig.FIREBASE_APPLICATION_ID,
            apiKey = BuildConfig.FIREBASE_API_KEY,
            projectId = BuildConfig.FIREBASE_PROJECT_ID,
            gcmSenderId = BuildConfig.FIREBASE_GCM_SENDER_ID,
        )
        if (FirebasePush.initialize(this, firebase)) notificationPoster.createChannel()
    }

    /**
     * Les dépendances de ce lancement-ci, construites au premier appel.
     * **Le raccourci `previewSignedIn` reçoit le jeu d'essai**, et pas seulement
     * un compte inventé. Sans effet en Release : les interrupteurs n'y sont pas lus.
     */
    fun dependencies(switches: LaunchSwitches): AppDependencies = built ?: build(switches).also { built = it }

    private fun build(switches: LaunchSwitches): AppDependencies {
        val settings = SharedPreferencesAppSettings(this)
        val session = KeystoreTokenStore(this, account = "session-token")
        OnboardingStorage.resetIfRequested(switches, settings) { session.clear() }

        val configuration = if (switches.previewSignedIn) null else fromBuildConfiguration()
        val api = if (configuration == null) {
            PreviewSupport.api(switches)
        } else {
            MemoBookApiClient(
                configuration = configuration,
                tokenStore = KeystoreTokenStore(this, account = "device-token"),
                sessionStore = session,
                httpClient = httpClient,
                networkLog = if (BuildConfig.DEBUG) NetworkLog(AndroidLogSink()) else null,
            )
        }
        return AppDependencies(
            api = api,
            apiConfiguration = configuration,
            connectivity = AndroidConnectivity(this, scope),
            settings = settings,
            switches = switches,
            cacheDirectory = cacheDir,
            filesDirectory = filesDir,
            scope = scope,
            // Vides dans `gradle.properties` tant que leurs clients n'existent
            // pas : le bouton du fournisseur ne s'affiche pas.
            googleWebClientId = BuildConfig.GOOGLE_WEB_CLIENT_ID.ifBlank { null },
            appleServicesId = BuildConfig.APPLE_SERVICES_ID.ifBlank { null },
            scheduleBackgroundFlush = RecordingOutboxWorker.scheduler(this),
            // Le bac à sable ne paie rien : ses doubles n'appellent personne.
            payments = if (switches.previewSignedIn) StubPaymentPresenter() else StripePaymentSheetPresenter(),
            subscriptions = if (switches.previewSignedIn) StubSubscriptionStore() else PlayBillingSubscriptionStore(this, scope),
            paymentMethods = if (switches.previewSignedIn) StubPaymentMethodsPresenter() else StripeCustomerSheetPresenter(),
            productionApiBaseUrl = runCatching { URI(BuildConfig.PRODUCTION_API_BASE_URL) }.getOrNull(),
            push = if (switches.previewSignedIn) null else push,
        )
    }

    /**
     * **Les photos sans réseau** (Hugo, 08/10/2026) : toutes les images de
     * l'app passent par Coil, avec un cache disque de 256 Mo — le cache d'URL
     * d'iOS, agrandi pour qu'une photo de profil y tienne.
     */
    override fun newImageLoader(context: android.content.Context): ImageLoader =
        ImageLoader.Builder(context)
            .components { add(OkHttpNetworkFetcherFactory(callFactory = { httpClient })) }
            .memoryCache { MemoryCache.Builder().maxSizeBytes(32L * 1024 * 1024).build() }
            .diskCache { DiskCache.Builder().directory(cacheDir.resolve("images")).maxSizeBytes(256L * 1024 * 1024).build() }
            .build()

    /**
     * L'adresse de ce build pour cet appareil. Repli local dans l'émulateur
     * seulement, arrêt net partout ailleurs (`APIConfiguration.fromBuildConfiguration`, iOS).
     */
    private fun fromBuildConfiguration(): ApiConfiguration =
        ApiConfiguration.effective(
            configured = ApiConfiguration.parse(BuildConfig.API_BASE_URL),
            productionFallback = ApiConfiguration.parse(BuildConfig.PRODUCTION_API_BASE_URL),
            runsInEmulator = runsInEmulator(),
        ) ?: error("Aucune adresse d'API lisible dans ce build : voir android/gradle.properties.")

    /** L'émulateur d'Android Studio — le « simulateur » de ce côté-ci. */
    private fun runsInEmulator(): Boolean =
        Build.HARDWARE in setOf("ranchu", "goldfish") ||
            Build.PRODUCT.startsWith("sdk") ||
            Build.FINGERPRINT.startsWith("generic")
}
