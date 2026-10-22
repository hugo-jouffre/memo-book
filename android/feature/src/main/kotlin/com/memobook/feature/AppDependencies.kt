package com.memobook.feature

import com.memobook.core.Account
import com.memobook.feature.chat.ChatTransport
import com.memobook.networking.ApiConfiguration
import com.memobook.networking.ApiError
import com.memobook.networking.Connectivity
import com.memobook.networking.MemoBookApi
import com.memobook.recording.PendingRecordingStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.KSerializer
import kotlinx.serialization.serializer
import java.io.File
import java.time.Instant
import java.net.URI
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.MutableStateFlow
import com.memobook.feature.notifications.PushNotifications
import com.memobook.feature.paywall.SubscriptionPurchase
import com.memobook.payments.TransactionRefused
import com.memobook.payments.TransactionDelivery
import com.memobook.payments.SubscriptionStore
import com.memobook.payments.StubSubscriptionStore
import com.memobook.payments.StubPaymentPresenter
import com.memobook.payments.StubPaymentMethodsPresenter
import com.memobook.payments.StripeSDK
import com.memobook.payments.PaymentPresenter
import com.memobook.payments.PaymentMethodsPresenter

/**
 * Les dépendances que les écrans partagent. Un seul point d'assemblage, comme
 * `AppDependencies.swift` : construit une fois par `MemoBookApplication`, puis
 * descendu aux écrans. Pas de singleton, pas de framework d'injection.
 *
 * **L'enregistrement de l'appareil n'est pas une condition de démarrage.** Il
 * est **paresseux** : il se déclenche au premier appel réseau qui en a besoin,
 * et son échec est l'erreur de cet appel-là, pas un mur devant l'app.
 *
 * ### Les modèles branchés sur l'API
 *
 * Chaque écran reçoit une **source**, une fonction qui rend son contenu. Sur
 * iOS, les fabriques (`homeModel()`, `tripModel(id:)`…) sont des méthodes de
 * cette classe ; ici ce sont des **fonctions d'extension**, chacune dans le
 * paquet de son écran (`home/HomeDependencies.kt`…) : un écran porté n'a pas à
 * rouvrir ce fichier. Elles lisent [api], [content] et [cachedSource], internes
 * au module.
 *
 * @param api le client d'API — le vrai, ou `PreviewApi` sous `previewSignedIn`.
 * @param apiConfiguration l'adresse que le client vise, pour la ligne de
 *   développeur de l'écran de lancement. `null` dans le bac à sable.
 * @param cacheDirectory où [ContentCache] écrit — `cacheDir` dans l'app.
 * @param filesDirectory où dorment ce qui n'existe nulle part ailleurs : les
 *   vocaux et les voyages en attente — `filesDir` dans l'app.
 * @param scope la portée de l'app entière : ce qui y est lancé survit aux
 *   écrans (la file des envois, l'enregistrement de l'appareil).
 * @param googleWebClientId l'identifiant client **web** de Google — l'audience
 *   des jetons que « Continuer avec Google » rend, le `GIDClientID` d'iOS côté
 *   serveur. `null` tant qu'il n'existe pas : le bouton ne s'affiche pas.
 * @param scheduleBackgroundFlush planifie le vidage de la file **app fermée** —
 *   au retour du réseau (`null`), ou à la recharge du crédit du jour :
 *   `RecordingOutboxWorker.scheduler(context)` dans l'app, rien dans un test
 *   ou un aperçu. Voir [RecordingOutboxWorker].
 */
class AppDependencies(
    val api: MemoBookApi,
    val apiConfiguration: ApiConfiguration?,
    val connectivity: Connectivity,
    val settings: AppSettings,
    val switches: LaunchSwitches,
    cacheDirectory: File,
    val filesDirectory: File,
    val scope: CoroutineScope,
    val googleWebClientId: String? = null,
    scheduleBackgroundFlush: (Instant?) -> Unit = {},
    /**
     * Qui ouvre une feuille de paiement — la feuille Stripe, ou un double qui
     * n'appelle personne (aperçus, bac à sable, tests).
     */
    val payments: PaymentPresenter = StubPaymentPresenter(),
    /**
     * Qui achète l'abonnement — Google Play, ou un double. **À part de
     * [payments], et pour de bon** : l'abonnement est un service numérique,
     * Google impose sa facturation, et le faire passer par Stripe ferait
     * refuser l'app (règlement « Paiements » de Google Play).
     */
    val subscriptions: SubscriptionStore = StubSubscriptionStore(),
    /** Qui ouvre la feuille « Moyens de paiement » de Stripe, depuis le profil. */
    val paymentMethods: PaymentMethodsPresenter = StubPaymentMethodsPresenter(),
    /**
     * L'adresse de **production**, même dans un build de développement : le
     * lien d'invitation d'un co-voyageur (`InviteLink.url`) doit mener quelque
     * part sur le téléphone de l'invité. `null` dans un test.
     */
    val productionApiBaseUrl: URI? = null,
    /**
     * Les notifications de l'app — le jeton, l'autorisation, le toucher.
     * **Jamais dans le bac à sable** : il n'a pas de session à qui remettre un
     * jeton. `null` dans un test ou un aperçu.
     */
    val push: PushNotifications? = null,
) {
    /**
     * Ce que l'app garde du serveur sur l'appareil — voir [ContentCache].
     * **Deux usages pour une seule pièce** : relire hors ligne, et ouvrir vite.
     */
    internal val content = ContentCache(File(cacheDirectory, "memobook-content"))

    /**
     * La file de départ des vocaux. Elle vit **ici** et non dans un écran : un
     * souvenir raconté dans un tunnel doit repartir tout seul au retour du
     * réseau, quel que soit l'écran affiché à ce moment-là — et même si on
     * n'est jamais revenu sur l'accueil depuis. Sur Android, même app fermée
     * ([RecordingOutboxWorker]).
     *
     * Tout ce qu'on dit part par la file, et la file parle à la conversation
     * (`POST /v1/trips/:id/chat`) : le vocal de l'accueil est un tour comme un
     * autre, avec l'identifiant de sa bulle. Le serveur relit la durée dans le
     * fichier et la décompte du crédit du jour où le tour **arrive** ; un refus
     * faute de crédit le garde sur le disque jusqu'à la recharge (03/10/2026).
     *
     * Les voyages créés hors ligne passent par elle aussi, et **avant** ce
     * qu'on y raconte : la création se rejoue sur l'identifiant que l'app a
     * tiré (`POST /v1/trips`), celui que les tours en attente portent.
     *
     * Les deux files dorment dans [filesDirectory] : ce qui n'existe nulle part
     * ailleurs ne va jamais dans un cache.
     */
    val outbox: RecordingOutbox = RecordingOutbox(
        store = PendingRecordingStore.inLibrary(filesDirectory),
        trips = PendingTripStore.inLibrary(filesDirectory),
        connectivity = connectivity,
        send = { turn, tripId -> ChatTransport.sendNow(turn, tripId, api) },
        createTrip = { draft -> api.createTrip(draft) },
        scope = scope,
        onPending = scheduleBackgroundFlush,
    ).also {
        // Au démarrage, et pas à l'ouverture d'un écran : c'est ce qui permet
        // de savoir qu'on est hors ligne **avant** de dessiner l'accueil, et de
        // repartir avec ce qu'un lancement précédent avait laissé en file.
        it.start()
    }

    /** Le bac à sable : le jeu d'essai, aucun jeton, aucun appel qui aboutisse. */
    val isPreviewingSignedIn: Boolean get() = switches.previewSignedIn

    private val registrationLock = Mutex()
    private var registration: Deferred<Unit>? = null

    /**
     * Efface ce que l'app garde du compte qui s'en va. À appeler à la
     * déconnexion : les voyages de quelqu'un ne doivent pas apparaître, même
     * une demi-seconde, devant la personne suivante.
     *
     * **Les vocaux en attente, eux, restent.** Ce sont des souvenirs que
     * personne n'a encore lus : si le même compte revient, ils repartent ; si
     * c'en est un autre, le serveur les refuse et la file le dit. Les jeter
     * serait le seul geste irréversible du lot.
     */
    suspend fun forgetAccountContent() {
        content.clearAll()
        accountForgetters.forEach { it() }
        // Les voyages créés hors ligne restent sur le disque, comme les
        // vocaux : ils ne se montrent plus, et ne partent plus, tant que leur
        // compte n'est pas revenu.
        outbox.setAccount(null)
    }

    /**
     * Ce que d'autres pièces doivent oublier avec le compte — le dernier crédit
     * du jour de chaque conversation, la file qui change de compte. Elles s'y
     * inscrivent en se construisant, au lieu que ce fichier les connaisse toutes.
     */
    private val accountForgetters = mutableListOf<suspend () -> Unit>()
    private val accountRememberers = mutableListOf<suspend (Account) -> Unit>()

    fun onForgetAccount(action: suspend () -> Unit) {
        accountForgetters += action
    }

    fun onRememberAccount(action: suspend (Account) -> Unit) {
        accountRememberers += action
    }

    /**
     * Relit la session gardée — voir [SessionRestore]. Une session refusée
     * emporte ce qu'on gardait du compte, comme une déconnexion.
     */
    suspend fun restoreSession(): SessionRestore {
        val restore = SessionRestore.resolve(
            verify = { api.currentAccount() },
            isStillStored = { api.hasStoredSession() },
            remembered = { content.read<Account>(ContentCache.Slot.Account) },
        )
        if (restore == SessionRestore.Closed) forgetAccountContent()
        return restore
    }

    /** Garde le compte de la session ouverte, pour rouvrir l'app le jour où le serveur ne répond pas. */
    suspend fun rememberAccount(account: Account) {
        content.write(ContentCache.Slot.Account, account)
        accountRememberers.forEach { it(account) }
        // Ses voyages créés hors ligne réapparaissent, et partent s'il y a du
        // réseau.
        outbox.setAccount(account.id)
    }

    // MARK: - Ce que `RootView` dit à la file

    /**
     * **Le retour au premier plan** — à appeler par `RootView` à chaque
     * `ON_RESUME`, comme le `.onChange(of: scenePhase)` d'iOS : « ce qui n'a
     * pas eu le temps de partir repart au retour dans l'app ». Le moniteur
     * réseau ne dit rien quand c'est le serveur, et non le réseau, qui
     * manquait. Sans effet quand la file est vide.
     */
    suspend fun flushOutboxOnForeground() {
        outbox.flush()
    }

    /**
     * **L'illimité libère la file** (03/10/2026) — à appeler par `RootView`
     * quand la session passe en illimité ou que le serveur le confirme : un
     * achat, une restauration, un abonnement pris sur un autre appareil et que
     * l'accueil vient d'apprendre. Ce qui attendait le crédit de demain ou
     * l'illimité repart tout de suite, au lieu d'attendre minuit. Une seconde
     * fois quand **le serveur** le confirme : juste après l'achat, il peut ne
     * pas le savoir encore, et refuser de nouveau. La session ne connaît pas la
     * file, ni la file la session : c'est dans `RootView`, où vivent les deux,
     * qu'on les relie.
     */
    suspend fun releaseCreditHolds() {
        outbox.releaseCreditHolds()
    }

    /**
     * Le vidage que [RecordingOutboxWorker] demande, app fermée. Un processus
     * que WorkManager vient de lancer n'a pas encore rouvert la session : le
     * dernier compte gardé ([rememberAccount]) rend ses voyages créés hors
     * ligne à la file, pour qu'ils partent eux aussi.
     *
     * @return il reste quelque chose qui attend le réseau — le travail repassera.
     */
    internal suspend fun flushOutboxInBackground(): Boolean {
        if (outbox.accountId == null) content.read<Account>(ContentCache.Slot.Account)?.let { outbox.setAccount(it.id) }
        outbox.flush()
        return outbox.pending.value > 0 || outbox.localTrips.value.isNotEmpty()
    }

    /**
     * Garantit que l'appareil est enregistré avant un appel réseau. Idempotent,
     * et rejouable : après une panne réseau, l'appel suivant retente au lieu de
     * rester bloqué sur l'échec précédent.
     */
    suspend fun ensureRegistered() {
        // L'essai en cours ou réussi se partage ; un essai raté se jette, et
        // l'appel suivant en relance un.
        registrationLock.withLock { registration }?.let { previous ->
            try {
                return previous.await()
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                registrationLock.withLock { if (registration === previous) registration = null }
            }
        }
        val task = registrationLock.withLock {
            registration ?: scope.async { api.ensureDeviceRegistered() }.also { registration = it }
        }
        task.await()
    }

    /**
     * Enveloppe une lecture réseau du cache : elle **recopie** ce qui arrive,
     * et **relit** ce qu'elle avait si le transport échoue.
     *
     * **On ne se replie que sur une panne de transport.** Un 500 ou un 404
     * sont des réponses : les cacher derrière un contenu périmé, c'est masquer
     * une panne du serveur.
     */
    internal fun <Value> cachedSource(
        slot: ContentCache.Slot,
        serializer: KSerializer<Value>,
        fetch: suspend () -> Value,
    ): suspend () -> Value = {
        try {
            fetch().also { content.write(slot, it, serializer) }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            if ((error as? ApiError)?.isTransport != true) throw error
            content.read(slot, serializer) ?: throw error
        }
    }

    internal inline fun <reified Value> cachedSource(
        slot: ContentCache.Slot,
        noinline fetch: suspend () -> Value,
    ): suspend () -> Value = cachedSource(slot, serializer<Value>(), fetch)

    /** Ce qu'on avait pour [slot], pour le `cached` d'un modèle. */
    internal inline fun <reified Value> cached(slot: ContentCache.Slot): CachedValue<Value> = { content.read<Value>(slot) }

    // MARK: - L'argent

    private val deliveredTransactionCount = MutableStateFlow(0)

    /**
     * Combien d'achats Google Play **remis hors du paywall** le serveur a
     * acceptés : un achat en attente qui se conclut, un code promo, un achat
     * qu'un lancement précédent n'avait pas pu remettre. `RootView` relit
     * l'accueil à chaque fois.
     */
    val deliveredTransactions: StateFlow<Int> = deliveredTransactionCount.asStateFlow()

    init {
        // **Au lancement, et pas à l'ouverture du paywall** : un achat en
        // attente, un code promo arrivent quand ils veulent.
        subscriptions.startListening(countingDelivery())
    }

    private fun countingDelivery(): TransactionDelivery {
        val deliver = deliveringTransaction(api, memoId = null)
        return { signed ->
            deliver(signed)
            deliveredTransactionCount.update { it + 1 }
        }
    }

    /** Remet au serveur ce que Google Play garde de non acquitté — à la connexion, et au retour dans l'app. */
    suspend fun deliverUnfinishedTransactions() {
        subscriptions.deliverUnfinished(countingDelivery())
    }

    /** Ce que Google Play tient pour ce compte Google — voir [SubscriptionStore.hasCurrentEntitlement]. */
    suspend fun hasCurrentEntitlement(): Boolean? = subscriptions.hasCurrentEntitlement()

    /**
     * Ce que l'offre sait faire du store, pour **ce** compte — posé par
     * `RootView` une fois connecté. L'identifiant du compte part dans l'achat
     * (`setObfuscatedAccountId`) : c'est lui qui permet au serveur de rattacher
     * chaque renouvellement.
     */
    fun subscriptionPurchase(accountId: String): SubscriptionPurchase = SubscriptionPurchase(
        displayPrice = { subscriptions.displayPrice() },
        displayPeriod = { subscriptions.displayPeriod() },
        purchase = { memoId -> subscriptions.purchase(accountId, deliveringTransaction(api, memoId)) },
        restore = { subscriptions.restore(deliveringTransaction(api, memoId = null)) },
        willAutoRenew = { subscriptions.willAutoRenew() },
        deliverUnfinished = { subscriptions.deliverUnfinished(deliveringTransaction(api, memoId = null)) },
    )

    /**
     * Ouvre la feuille « Moyens de paiement » de Stripe — les cartes du compte.
     * Rend un message si elle n'a pas pu s'ouvrir.
     */
    suspend fun managePaymentMethods(): String? =
        paymentMethods.present(
            key = { api.paymentMethodsKey(stripeApiVersion = StripeSDK.apiVersion) },
            setupIntent = { api.paymentMethodsSetupIntent() },
        )

    companion object {
        /**
         * Remet un achat Google Play au serveur. **Un refus définitif devient
         * [TransactionRefused]** : un achat fait depuis un autre compte MemoBook
         * (403), un abonnement déjà rattaché ailleurs (409), un jeton que le
         * serveur ne sait pas vérifier (400). Tout le reste lève tel quel, et
         * l'achat reste non acquitté pour la prochaine fois.
         *
         * ⏳ Lot B4 : tant que la route n'existe pas, le serveur répond 404 et
         * l'achat n'est pas acquitté — le produit ne s'active donc pas dans la
         * Play Console avant elle.
         */
        internal fun deliveringTransaction(api: MemoBookApi, memoId: String?): TransactionDelivery = { signed ->
            try {
                api.syncGooglePlayPurchase(purchaseToken = signed.purchaseToken, productId = signed.productId, memoId = memoId)
            } catch (error: ApiError.Server) {
                if (error.statusCode in setOf(400, 403, 409)) throw TransactionRefused(error.message)
                throw error
            }
        }
    }
}
