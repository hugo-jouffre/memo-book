package com.memobook.payments

import android.app.Activity
import android.app.Application
import android.os.Bundle
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClient.BillingResponseCode
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.android.billingclient.api.queryProductDetails
import com.android.billingclient.api.queryPurchasesAsync
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.lang.ref.WeakReference
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

// Le jumeau de `MemoBookPayments/SubscriptionStore.swift`. Le catalogue
// (`StoreKitCatalog` sur iOS) est à part : `PlayCatalog.kt`.

/**
 * Un achat Google Play, tel que le serveur le vérifie — le jumeau de
 * `SignedTransaction`, qui porte sur iOS le JWS signé par l'App Store.
 *
 * Ici, c'est le **jeton d'achat** : le serveur le présente à l'API Google Play
 * Developer, qui seule dit ce qu'il vaut (lot B4). L'app ne l'ouvre pas, elle
 * le transmet — avec le produit, parce que l'acquittement d'un abonnement le
 * demande.
 *
 * @property orderId le numéro de commande Google (`GPA.…`), pour le support.
 *   `null` pour un achat en attente.
 */
data class SignedTransaction(
    val purchaseToken: String,
    val productId: String,
    val orderId: String? = null,
)

/**
 * Ce qu'on fait d'une transaction : la remettre au serveur.
 *
 * **Lève si le serveur ne l'a pas prise.** L'achat reste alors non acquitté, et
 * Google Play le rendra au prochain lancement ([SubscriptionStore.deliverUnfinished]) :
 * c'est ce qui rend un achat fait dans un tunnel impossible à perdre.
 *
 * ⚠️ **C'est le serveur qui acquitte, jamais l'app** (lot B4). Google rembourse
 * de lui-même un achat qui n'est pas acquitté sous trois jours : un serveur qui
 * ne répond pas pendant trois jours rend l'argent, il ne garde pas un abonné
 * qu'il ne connaît pas.
 */
typealias TransactionDelivery = suspend (SignedTransaction) -> Unit

/**
 * Le serveur a vu la transaction, et la refuse **pour de bon** : faite depuis
 * un autre compte MemoBook, déjà rattachée ailleurs, ou qu'il ne sait pas
 * vérifier.
 *
 * Sur iOS, la transaction est alors finie. Sur Android, il n'y a rien à finir
 * côté app : l'achat reste non acquitté, et Google le rembourse au bout de trois
 * jours. Le magasin ne la rejoue plus pendant ce lancement-ci. L'achat ne compte
 * pas comme réussi, et l'écran dit pourquoi — c'est le message du serveur.
 */
class TransactionRefused(override val message: String) : Exception(message)

/** Ce qu'un achat rend. */
sealed interface PurchaseOutcome {
    /** Payé, et le serveur l'a appris : l'abonnement est ouvert. */
    data object Subscribed : PurchaseOutcome

    /**
     * Payé chez Google Play, mais le serveur n'a pas répondu. **Ce n'est pas un
     * échec** : l'achat repartira seul, et Google notifiera le serveur de son
     * côté. L'écran se comporte comme pour [Subscribed].
     */
    data object AwaitingServer : PurchaseOutcome

    /**
     * Il faut une validation de plus — l'accord d'un parent (Family Link), ou
     * un paiement en espèces. L'abonnement s'ouvrira quand elle arrivera, par
     * [SubscriptionStore.startListening].
     */
    data object Pending : PurchaseOutcome

    /** La personne a fermé la feuille de Google Play. Un choix, pas une erreur. */
    data object Cancelled : PurchaseOutcome

    data class Failed(val message: String) : PurchaseOutcome
}

enum class RestoreOutcome {
    Restored,
    NothingToRestore,

    /**
     * La personne a refermé la demande de mot de passe de l'App Store. **Jamais
     * rendu sur Android** : Google Play ne demande rien pour relire les achats
     * du compte. Gardé pour que l'écran décompose les mêmes cas sur les deux.
     */
    Cancelled,
}

sealed class SubscriptionStoreError : Exception() {
    /**
     * Le produit n'est pas revenu de Google Play : pas de réseau, pas de Play
     * Store sur l'appareil, ou la Play Console pas prête — abonnement inactif,
     * plan de base non publié, app pas encore installée depuis une piste de
     * test. C'est la panne de configuration la plus courante.
     */
    data object Unavailable : SubscriptionStoreError()

    /** Google Play a rendu un achat qu'on ne sait pas lire comme un abonnement payé. */
    data object Unverified : SubscriptionStoreError()

    /** Le serveur n'a pas pris l'achat restauré. Il repartira seul. */
    data object ServerUnreachable : SubscriptionStoreError()

    val errorDescription: String
        get() = when (this) {
            Unavailable -> "L’abonnement n’est pas disponible pour le moment. Vérifie ta connexion et réessaie."
            Unverified -> "Le Play Store n’a pas pu confirmer cet achat. Aucun abonnement n’a été ouvert."
            ServerUnreachable ->
                "Ton abonnement est bien sur le Play Store, mais notre serveur ne répond pas. Il sera rétabli automatiquement."
        }

    override val message: String get() = errorDescription
}

/**
 * La seule porte par laquelle l'app achète l'abonnement.
 *
 * Une interface et non Google Play Billing directement, pour la même raison que
 * [PaymentPresenter] : les aperçus et le bac à sable ont besoin d'un achat qui
 * n'appelle personne, et le paywall ne doit pas savoir comment on paie.
 */
interface SubscriptionStore {
    /**
     * Le prix tel que Google Play l'affiche dans le pays du compte — « 4,99 € »
     * en France. `null` tant que le produit n'est pas revenu de Google Play.
     */
    suspend fun displayPrice(): String?

    /**
     * La période que ce prix paie, telle qu'elle suit la barre oblique —
     * « mois », « 3 mois », « an ». Lue sur le plan de base (`billingPeriod`),
     * pour que l'écran d'achat ne puisse pas annoncer une autre durée que la
     * feuille de Google Play. `null` tant que le produit n'est pas revenu.
     */
    suspend fun displayPeriod(): String?

    /**
     * Achète l'abonnement. [appAccountToken] est l'identifiant du compte
     * MemoBook, sous le nom qu'il porte sur iOS : il part dans l'achat
     * (`setObfuscatedAccountId`), Google le recopie dans chaque notification,
     * et c'est ce qui permet au serveur de rattacher un renouvellement sans que
     * l'app parle.
     */
    suspend fun purchase(appAccountToken: String?, deliver: TransactionDelivery): PurchaseOutcome

    /**
     * « Restaurer mes achats ». Relit les abonnements que le compte Google
     * tient, puis remet au serveur ce qui est en cours. Lève
     * [SubscriptionStoreError] ou [TransactionRefused].
     */
    suspend fun restore(deliver: TransactionDelivery): RestoreOutcome

    /**
     * Écoute ce qui arrive hors de l'écran d'achat : un achat en attente qui se
     * conclut, un code promo utilisé dans le Play Store, un achat fait sur un
     * autre appareil. À démarrer **au lancement**, sinon ces achats attendent
     * le prochain [deliverUnfinished].
     */
    fun startListening(deliver: TransactionDelivery)

    /** Remet au serveur ce qui n'a pas pu partir — à la connexion, typiquement. */
    suspend fun deliverUnfinished(deliver: TransactionDelivery)

    /**
     * Le renouvellement est-il encore armé chez Google Play ? Lu sur l'appareil,
     * donc juste après que la personne a quitté la page de gestion des
     * abonnements — sans attendre la notification du serveur. `null` quand on
     * ne sait pas.
     */
    suspend fun willAutoRenew(): Boolean?

    /**
     * **Google Play tient-il un abonnement en cours pour ce compte Google ?**
     * Lu sur les achats du compte — sans demander quoi que ce soit à la
     * personne. Un remboursement ou une révocation l'en retirent ; un
     * abonnement suspendu (paiement refusé, « En attente ») n'y est pas. `null`
     * quand on ne sait pas (un aperçu, le bac à sable, pas de Play Store).
     */
    suspend fun hasCurrentEntitlement(): Boolean?
}

/**
 * Le vrai Google Play Billing.
 *
 * Un achat n'est jamais acquitté ici : c'est le serveur qui le
 * fait (lot B4), une fois qu'il l'a vérifié. Jusqu'à B4, aucune route ne le
 * prend — et le produit ne doit pas être activé dans la Play Console avant :
 * un produit absent rend [SubscriptionStoreError.Unavailable] **avant** que
 * quiconque paie.
 *
 * Comme le `@MainActor` d'iOS, il s'appelle depuis le fil principal — les
 * modèles d'écran et la portée de l'app y sont ; seule l'ouverture de la
 * feuille de Google Play l'exige vraiment, et elle s'y rend d'elle-même.
 *
 * @param scope la portée de l'app entière : les achats arrivés hors de l'écran
 *   d'achat ([startListening]) y sont remis au serveur.
 * @param productId le produit vendu.
 * @param acceptedProductIds les produits dont on remet les achats.
 */
class PlayBillingSubscriptionStore internal constructor(
    private val billing: PlayBilling,
    private val scope: CoroutineScope,
    private val productId: String = PlayCatalog.MONTHLY_SUBSCRIPTION,
    acceptedProductIds: Set<String> = PlayCatalog.acceptedSubscriptions,
) : SubscriptionStore {

    constructor(
        application: Application,
        scope: CoroutineScope,
        productId: String = PlayCatalog.MONTHLY_SUBSCRIPTION,
        acceptedProductIds: Set<String> = PlayCatalog.acceptedSubscriptions,
    ) : this(GooglePlayBilling(application), scope, productId, acceptedProductIds)

    private val acceptedProductIds: Set<String> = acceptedProductIds + productId
    private val productLock = Mutex()
    private var product: PlayProduct? = null
    private val isListening = AtomicBoolean(false)

    /**
     * Les achats que le serveur a refusés pendant ce lancement. iOS les finit ;
     * ici ils restent chez Google jusqu'au remboursement, et
     * [deliverUnfinished] ne les rejoue pas à chaque connexion.
     */
    private val refusedTokens: MutableSet<String> = ConcurrentHashMap.newKeySet()

    override suspend fun displayPrice(): String? =
        loadProduct()?.let { PlayOffers.basePlan(it.offers) }?.recurringPhase?.formattedPrice

    override suspend fun displayPeriod(): String? =
        loadProduct()?.let { PlayOffers.basePlan(it.offers) }?.recurringPhase?.billingPeriod?.let(PlayOffers::label)

    override suspend fun purchase(appAccountToken: String?, deliver: TransactionDelivery): PurchaseOutcome {
        val product = loadProduct()
            ?: return PurchaseOutcome.Failed(SubscriptionStoreError.Unavailable.errorDescription)
        val offer = PlayOffers.basePlan(product.offers)
            ?: return PurchaseOutcome.Failed(SubscriptionStoreError.Unavailable.errorDescription)

        // La feuille de Google Play se pose sur l'activité au premier plan :
        // sans elle, il n'y a nulle part où l'ouvrir.
        val response = billing.launchPurchase(product, offer, PlayOffers.obfuscatedAccountId(appAccountToken))
            ?: return PurchaseOutcome.Failed(PaymentError.NoPresenter.errorDescription)

        return when (response.code) {
            BillingResponseCode.OK -> outcome(response.purchases, deliver)
            BillingResponseCode.USER_CANCELED -> PurchaseOutcome.Cancelled
            // Le compte Google est déjà abonné — acheté sur un autre appareil,
            // ou depuis un autre compte MemoBook. Comme l'App Store qui répond
            // « Vous êtes déjà abonné » et rend la transaction en cours : on la
            // remet, et le serveur dit à qui elle est.
            BillingResponseCode.ITEM_ALREADY_OWNED -> {
                val owned = billing.subscriptions()
                    ?: return PurchaseOutcome.Failed(SubscriptionStoreError.Unavailable.errorDescription)
                outcome(owned, deliver)
            }
            // Le message de Google (`debugMessage`) est écrit pour le
            // développeur, en anglais : il ne s'affiche pas.
            else -> PurchaseOutcome.Failed(SubscriptionStoreError.Unavailable.errorDescription)
        }
    }

    override suspend fun restore(deliver: TransactionDelivery): RestoreOutcome {
        // Rien à demander ici : Google Play relit les achats du compte sans mot
        // de passe, et sans le geste que l'App Store réserve au bouton.
        val owned = billing.subscriptions() ?: throw SubscriptionStoreError.Unavailable

        var restored = false
        var undelivered = false
        for (purchase in owned) {
            when (val settlement = settle(purchase, deliver)) {
                Settlement.Delivered -> restored = true
                Settlement.Undelivered -> undelivered = true
                is Settlement.Refused -> throw TransactionRefused(settlement.message)
                Settlement.Pending, Settlement.Unverified, Settlement.Ignored -> Unit
            }
        }

        if (restored) return RestoreOutcome.Restored
        if (undelivered) throw SubscriptionStoreError.ServerUnreachable
        return RestoreOutcome.NothingToRestore
    }

    override fun startListening(deliver: TransactionDelivery) {
        if (!isListening.compareAndSet(false, true)) return
        billing.setUpdateHandler { purchases ->
            scope.launch { purchases.forEach { settle(it, deliver) } }
        }
        // `Transaction.updates` rend aussi, au lancement, ce que StoreKit garde
        // de non fini. Google Play n'a pas d'équivalent : on le relit ici.
        scope.launch { deliverUnfinished(deliver) }
    }

    override suspend fun deliverUnfinished(deliver: TransactionDelivery) {
        val owned = billing.subscriptions() ?: return
        // **Non acquitté** : c'est le `Transaction.unfinished` d'iOS. Un achat
        // acquitté, le serveur l'a déjà pris.
        owned
            .filter { !it.isAcknowledged && it.purchaseToken !in refusedTokens }
            .forEach { settle(it, deliver) }
    }

    override suspend fun hasCurrentEntitlement(): Boolean? {
        val owned = billing.subscriptions() ?: return null
        return owned.any { it.state == PlayPurchase.State.Purchased && accepted(it) != null }
    }

    override suspend fun willAutoRenew(): Boolean? {
        val owned = billing.subscriptions() ?: return null
        return owned.firstOrNull { it.state == PlayPurchase.State.Purchased && accepted(it) != null }?.isAutoRenewing
    }

    // MARK: -

    private sealed interface Settlement {
        data object Delivered : Settlement
        data object Undelivered : Settlement
        data object Pending : Settlement
        data object Unverified : Settlement
        data object Ignored : Settlement
        data class Refused(val message: String) : Settlement
    }

    /** Ce que l'écran d'achat apprend des achats qu'une feuille a rendus. */
    private suspend fun outcome(purchases: List<PlayPurchase>, deliver: TransactionDelivery): PurchaseOutcome {
        val purchase = purchases.firstOrNull { accepted(it) != null }
            ?: return PurchaseOutcome.Failed(SubscriptionStoreError.Unverified.errorDescription)
        return when (val settlement = settle(purchase, deliver)) {
            Settlement.Delivered -> PurchaseOutcome.Subscribed
            Settlement.Undelivered -> PurchaseOutcome.AwaitingServer
            Settlement.Pending -> PurchaseOutcome.Pending
            is Settlement.Refused -> PurchaseOutcome.Failed(settlement.message)
            Settlement.Unverified, Settlement.Ignored ->
                PurchaseOutcome.Failed(SubscriptionStoreError.Unverified.errorDescription)
        }
    }

    /**
     * Remet un achat au serveur. **L'app ne l'acquitte jamais** : c'est le
     * serveur qui le fait, une fois qu'il l'a vérifié (lot B4). Acquitter ici,
     * c'est dire à Google qu'on n'en a plus besoin — et un serveur qui n'a rien
     * reçu ne le reverrait jamais.
     */
    private suspend fun settle(purchase: PlayPurchase, deliver: TransactionDelivery): Settlement {
        // L'abonnement mensuel. Un produit inconnu de cette version reste tel
        // quel : une version plus récente saura quoi en faire.
        val product = accepted(purchase) ?: return Settlement.Ignored
        when (purchase.state) {
            // Pas encore payé : le serveur n'a rien à ouvrir. L'achat reviendra
            // par l'écoute quand il se conclura.
            PlayPurchase.State.Pending -> return Settlement.Pending
            PlayPurchase.State.Unspecified -> return Settlement.Unverified
            PlayPurchase.State.Purchased -> Unit
        }

        return try {
            deliver(SignedTransaction(purchase.purchaseToken, product, purchase.orderId))
            Settlement.Delivered
        } catch (error: CancellationException) {
            throw error
        } catch (refusal: TransactionRefused) {
            refusedTokens += purchase.purchaseToken
            Settlement.Refused(refusal.message)
        } catch (_: Exception) {
            Settlement.Undelivered
        }
    }

    private fun accepted(purchase: PlayPurchase): String? = purchase.products.firstOrNull { it in acceptedProductIds }

    private suspend fun loadProduct(): PlayProduct? = productLock.withLock {
        product ?: billing.product(productId)?.also { product = it }
    }
}

/**
 * Un achat qui n'appelle personne — aperçus et bac à sable.
 *
 * Le résultat est fixé à la construction, comme [StubPaymentPresenter] : un
 * aperçu qui échoue une fois sur deux est un aperçu qu'on ne peut pas relire.
 *
 * @param renewsAfterManagement ce que rend [willAutoRenew]. Dans le bac à sable,
 *   la page de Google Play ne s'ouvre pas : `false` fait comme si la personne y
 *   avait coupé le renouvellement, pour voir la suite.
 */
class StubSubscriptionStore(
    private val outcome: PurchaseOutcome = PurchaseOutcome.Subscribed,
    private val renewsAfterManagement: Boolean? = false,
) : SubscriptionStore {
    /** `null` : l'écran garde le prix du catalogue, celui des maquettes. */
    override suspend fun displayPrice(): String? = null

    /** `null` : l'écran garde la période du catalogue, le mois. */
    override suspend fun displayPeriod(): String? = null

    /**
     * **Un achat réussi passe par la même remise que le vrai** (03/10/2026) :
     * le bac à sable disait « illimité » à l'écran pendant que son double
     * d'API, qui n'avait rien reçu, continuait de compter le crédit du jour et
     * de refuser les tours. L'achat factice part donc au double, qui ouvre
     * l'abonnement chez lui ; un refus s'y lit comme un refus du serveur, une
     * panne comme un serveur muet.
     */
    override suspend fun purchase(appAccountToken: String?, deliver: TransactionDelivery): PurchaseOutcome {
        if (outcome != PurchaseOutcome.Subscribed) return outcome
        return try {
            deliver(SignedTransaction(purchaseToken = "preview", productId = PlayCatalog.MONTHLY_SUBSCRIPTION))
            PurchaseOutcome.Subscribed
        } catch (error: CancellationException) {
            throw error
        } catch (refusal: TransactionRefused) {
            PurchaseOutcome.Failed(refusal.message)
        } catch (_: Exception) {
            PurchaseOutcome.AwaitingServer
        }
    }

    override suspend fun restore(deliver: TransactionDelivery): RestoreOutcome = RestoreOutcome.NothingToRestore

    override fun startListening(deliver: TransactionDelivery) {}

    override suspend fun deliverUnfinished(deliver: TransactionDelivery) {}

    override suspend fun willAutoRenew(): Boolean? = renewsAfterManagement

    /**
     * `null` : le bac à sable n'a pas de Google Play à interroger, et la
     * session garde ce que ses gestes ont dit.
     */
    override suspend fun hasCurrentEntitlement(): Boolean? = null
}

// MARK: - Google Play, derrière une façade qu'un test remplace

/**
 * Ce que le magasin demande à Google Play — et rien de plus. Une façade
 * interne pour que les règles du magasin (quelle offre, quelle issue, quand
 * remettre) se testent sur la JVM, sans Play Store : `PlayBillingSubscriptionStoreTest`.
 */
internal interface PlayBilling {
    /** Le produit et ses offres ; `null` quand Google Play ne l'a pas rendu. */
    suspend fun product(productId: String): PlayProduct?

    /**
     * Ouvre la feuille de Google Play et attend qu'elle se referme. `null`
     * quand aucune activité n'est au premier plan pour la porter.
     */
    suspend fun launchPurchase(product: PlayProduct, offer: PlayOffer, obfuscatedAccountId: String?): PlayBillingResponse?

    /** Les abonnements que le compte Google tient ; `null` quand Google Play n'a pas répondu. */
    suspend fun subscriptions(): List<PlayPurchase>?

    /** Ce qui arrive hors d'un achat lancé par l'app. */
    fun setUpdateHandler(handler: (List<PlayPurchase>) -> Unit)
}

/** Une réponse de Google Play : un `BillingResponseCode`, et les achats qu'elle porte. */
internal data class PlayBillingResponse(val code: Int, val purchases: List<PlayPurchase> = emptyList())

/** Un produit de Google Play et ses offres — le `Product` de StoreKit. */
internal class PlayProduct(
    val productId: String,
    val offers: List<PlayOffer>,
    /** Ce qu'il faut rendre à Google Play pour l'acheter ; `null` dans un test. */
    val details: ProductDetails? = null,
)

/**
 * Une offre d'abonnement : un plan de base (`offerId` nul) ou une offre posée
 * dessus dans la Play Console (essai, réduction).
 */
internal data class PlayOffer(
    val basePlanId: String,
    val offerId: String?,
    val offerToken: String,
    val phases: List<PlayPricingPhase>,
) {
    /** La phase qui se répète tant qu'on ne résilie pas — le prix « normal ». */
    val recurringPhase: PlayPricingPhase? get() = phases.lastOrNull { it.isInfiniteRecurring } ?: phases.lastOrNull()
}

internal data class PlayPricingPhase(
    /** « 4,99 € », écrit par Google Play dans la langue et la devise du compte. */
    val formattedPrice: String,
    /** La période en ISO 8601 : `P1M`, `P3M`, `P1Y`. */
    val billingPeriod: String,
    val isInfiniteRecurring: Boolean,
)

/** Un achat de Google Play, réduit à ce que le magasin lit — le `Transaction` de StoreKit. */
internal data class PlayPurchase(
    val products: List<String>,
    val state: State,
    val purchaseToken: String,
    val orderId: String? = null,
    val isAcknowledged: Boolean = false,
    val isAutoRenewing: Boolean = true,
) {
    enum class State { Purchased, Pending, Unspecified }
}

/** Les règles du catalogue qui ne demandent pas Google Play : testées sur la JVM. */
internal object PlayOffers {
    /**
     * **Le plan de base, jamais une offre** (22/10/2026). L'App Store applique
     * de lui-même une offre d'introduction à qui y a droit ; Google Play rend
     * aussi les offres « déterminées par le développeur » — une offre de
     * reconquête, par exemple — à tout le monde, et laisse l'app décider. En
     * prendre une d'office la donnerait à chacun. MemoBook n'en a pas
     * (`MemoBook.storekit` : `introductoryOffer` nul) ; le jour où elle en a,
     * c'est ici qu'on choisit.
     *
     * Le plan **mensuel** d'abord, si le produit en porte plusieurs : c'est lui
     * que le paywall annonce.
     */
    fun basePlan(offers: List<PlayOffer>): PlayOffer? {
        val basePlans = offers.filter { it.offerId == null }
        return basePlans.firstOrNull { it.recurringPhase?.billingPeriod == "P1M" } ?: basePlans.firstOrNull()
    }

    /**
     * « mois », « semaine », « 3 mois », « an » — le mot qui suit « 4,99 €/ ».
     * Lu sur la période ISO 8601 du plan (`P1M`). `null` pour une période qu'on
     * ne sait pas lire : l'écran garde alors celle de l'offre.
     */
    fun label(billingPeriod: String): String? {
        val match = Regex("""^P(\d+)([DWMY])$""").matchEntire(billingPeriod) ?: return null
        val value = match.groupValues[1].toIntOrNull() ?: return null
        return when (match.groupValues[2]) {
            "D" -> if (value == 1) "jour" else "$value jours"
            "W" -> if (value == 1) "semaine" else "$value semaines"
            "M" -> if (value == 1) "mois" else "$value mois"
            "Y" -> if (value == 1) "an" else "$value ans"
            else -> null
        }
    }

    /**
     * L'identifiant du compte tel que Google Play l'accepte : 64 caractères au
     * plus, sinon l'achat échoue sans rien dire. Un identifiant MemoBook (un
     * UUID) en fait 36 ; un autre ne part pas, comme iOS ne garde
     * l'`appAccountToken` que s'il se lit comme un UUID.
     */
    fun obfuscatedAccountId(accountId: String?): String? = accountId?.takeIf { it.isNotBlank() && it.length <= 64 }
}

/** Le vrai Google Play, par `billing-ktx`. */
internal class GooglePlayBilling(application: Application) : PlayBilling {
    private val foreground = ForegroundActivity(application)
    private val connection = Mutex()
    private val launches = Mutex()

    @Volatile private var inFlight: CompletableDeferred<PlayBillingResponse>? = null
    @Volatile private var updateHandler: ((List<PlayPurchase>) -> Unit)? = null

    private val client: BillingClient = BillingClient.newBuilder(application)
        .setListener { result, purchases -> onPurchasesUpdated(result, purchases) }
        // Exigé par la bibliothèque même sans produit unique : un achat
        // d'abonnement peut, lui aussi, attendre un paiement en espèces.
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .enableAutoServiceReconnection()
        .build()

    override suspend fun product(productId: String): PlayProduct? {
        if (!connected()) return null
        val params = QueryProductDetailsParams.newBuilder()
            .setProductList(
                listOf(
                    QueryProductDetailsParams.Product.newBuilder()
                        .setProductId(productId)
                        .setProductType(BillingClient.ProductType.SUBS)
                        .build(),
                ),
            )
            .build()
        val result = client.queryProductDetails(params)
        if (result.billingResult.responseCode != BillingResponseCode.OK) return null
        val details = result.productDetailsList?.firstOrNull { it.productId == productId } ?: return null
        val offers = details.subscriptionOfferDetails.orEmpty().map { offer ->
            PlayOffer(
                basePlanId = offer.basePlanId,
                offerId = offer.offerId,
                offerToken = offer.offerToken,
                phases = offer.pricingPhases.pricingPhaseList.map { phase ->
                    PlayPricingPhase(
                        formattedPrice = phase.formattedPrice,
                        billingPeriod = phase.billingPeriod,
                        isInfiniteRecurring = phase.recurrenceMode == ProductDetails.RecurrenceMode.INFINITE_RECURRING,
                    )
                },
            )
        }
        return PlayProduct(productId, offers, details)
    }

    override suspend fun launchPurchase(
        product: PlayProduct,
        offer: PlayOffer,
        obfuscatedAccountId: String?,
    ): PlayBillingResponse? = launches.withLock {
        val details = product.details ?: return null
        if (!connected()) return PlayBillingResponse(BillingResponseCode.SERVICE_DISCONNECTED)
        val activity = foreground.activity ?: return null

        val params = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(
                listOf(
                    BillingFlowParams.ProductDetailsParams.newBuilder()
                        .setProductDetails(details)
                        .setOfferToken(offer.offerToken)
                        .build(),
                ),
            )
            .apply { if (obfuscatedAccountId != null) setObfuscatedAccountId(obfuscatedAccountId) }
            .build()

        val response = CompletableDeferred<PlayBillingResponse>()
        inFlight = response
        try {
            val started = withContext(Dispatchers.Main.immediate) { client.launchBillingFlow(activity, params) }
            if (started.responseCode != BillingResponseCode.OK) return PlayBillingResponse(started.responseCode)
            response.await()
        } finally {
            inFlight = null
        }
    }

    override suspend fun subscriptions(): List<PlayPurchase>? {
        if (!connected()) return null
        val params = QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.SUBS).build()
        val result = client.queryPurchasesAsync(params)
        if (result.billingResult.responseCode != BillingResponseCode.OK) return null
        return result.purchasesList.map(::playPurchase)
    }

    override fun setUpdateHandler(handler: (List<PlayPurchase>) -> Unit) {
        updateHandler = handler
    }

    /**
     * Le seul écouteur de la bibliothèque : il reçoit l'issue de la feuille
     * ouverte par l'app **et** ce qui arrive d'ailleurs. L'une va à l'achat en
     * cours, l'autre à l'écoute.
     */
    private fun onPurchasesUpdated(result: BillingResult, purchases: List<Purchase>?) {
        val response = PlayBillingResponse(result.responseCode, purchases.orEmpty().map(::playPurchase))
        val launch = inFlight
        if (launch != null && !launch.isCompleted) {
            launch.complete(response)
            return
        }
        if (response.code == BillingResponseCode.OK && response.purchases.isNotEmpty()) {
            updateHandler?.invoke(response.purchases)
        }
    }

    /**
     * Ouvre la connexion au Play Store si elle ne l'est pas. La bibliothèque la
     * rouvre ensuite d'elle-même (`enableAutoServiceReconnection`). Quinze
     * secondes au plus : un Play Store qui ne répond pas ne doit pas laisser
     * l'écran d'achat tourner pour toujours.
     */
    private suspend fun connected(): Boolean {
        if (client.isReady) return true
        return connection.withLock {
            if (client.isReady) return@withLock true
            val setup = CompletableDeferred<Boolean>()
            client.startConnection(
                object : BillingClientStateListener {
                    override fun onBillingSetupFinished(result: BillingResult) {
                        setup.complete(result.responseCode == BillingResponseCode.OK)
                    }

                    override fun onBillingServiceDisconnected() {
                        setup.complete(false)
                    }
                },
            )
            withTimeoutOrNull(15_000) { setup.await() } ?: false
        }
    }

    private fun playPurchase(purchase: Purchase) = PlayPurchase(
        products = purchase.products,
        state = when (purchase.purchaseState) {
            Purchase.PurchaseState.PURCHASED -> PlayPurchase.State.Purchased
            Purchase.PurchaseState.PENDING -> PlayPurchase.State.Pending
            else -> PlayPurchase.State.Unspecified
        },
        purchaseToken = purchase.purchaseToken,
        orderId = purchase.orderId,
        isAcknowledged = purchase.isAcknowledged,
        isAutoRenewing = purchase.isAutoRenewing,
    )
}

/**
 * L'activité au premier plan, celle qui peut porter la feuille de Google Play —
 * le `activeScene()` d'iOS. Le paywall demande un achat sans tenir d'activité :
 * on la suit ici, depuis l'application, plutôt que de la faire descendre.
 */
internal class ForegroundActivity(application: Application) : Application.ActivityLifecycleCallbacks {
    @Volatile private var current: WeakReference<Activity>? = null

    init {
        application.registerActivityLifecycleCallbacks(this)
    }

    val activity: Activity? get() = current?.get()?.takeUnless { it.isFinishing || it.isDestroyed }

    override fun onActivityResumed(activity: Activity) {
        current = WeakReference(activity)
    }

    override fun onActivityDestroyed(activity: Activity) {
        if (current?.get() === activity) current = null
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}

    override fun onActivityStarted(activity: Activity) {}

    override fun onActivityPaused(activity: Activity) {}

    override fun onActivityStopped(activity: Activity) {}

    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
}
