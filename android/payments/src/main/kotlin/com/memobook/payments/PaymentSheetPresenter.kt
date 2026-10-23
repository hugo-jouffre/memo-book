package com.memobook.payments

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import com.memobook.core.PaymentIntentTicket
import com.stripe.android.PaymentConfiguration
import com.stripe.android.Stripe
import com.stripe.android.paymentsheet.PaymentSheet
import com.stripe.android.paymentsheet.PaymentSheetResult
import com.stripe.android.paymentsheet.PaymentSheetResultCallback
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

// Le jumeau de `MemoBookPayments/PaymentSheetPresenter.swift`.
//
// `PaymentIntentTicket` vit dans `:core` et non ici : c'est un modèle pur, que
// le client réseau décode et que ce module consomme. Le mettre à côté du SDK
// obligerait `:networking` à dépendre de Stripe pour décoder une réponse JSON.

/**
 * La seule porte par laquelle l'app peut déclencher un paiement.
 *
 * Une interface, et non directement le SDK Stripe, pour deux raisons : les
 * aperçus et les tests ont besoin d'un paiement qui n'appelle personne, et le
 * jour où la feuille change — Google Pay natif, un autre prestataire — c'est
 * cette façade qui change, pas les écrans.
 */
interface PaymentPresenter {
    /** Ouvre la feuille, et **attend qu'elle se referme**. */
    suspend fun present(ticket: PaymentIntentTicket): PaymentOutcome
}

/** Ce que l'app doit savoir du SDK Stripe — ce module est le seul à le connaître. */
object StripeSDK {
    /**
     * La version d'API Stripe que pin le SDK de l'app — **« 2020-03-02 » pour
     * stripe-android 23**, quand stripe-ios 24 pin « 2020-08-27 ». Le serveur en
     * a besoin pour créer une clé éphémère que la feuille sache lire : chaque
     * app envoie la sienne (`stripeApiVersion`), et le serveur la suit
     * (`stripeApiVersionSchema`).
     *
     * **Pas de `handle(url)` ici**, contrairement à iOS. Le retour d'un paiement
     * qui sort de l'app (3-D Secure, Klarna…) ne passe pas par
     * `memobook://stripe-redirect` : 3-D Secure 2 s'affiche dans l'app, et une
     * redirection par le navigateur revient par l'activité que le SDK déclare
     * dans son propre manifeste (`stripesdk://payment_return_url/com.memobook.app`).
     * `RootView` n'a rien à lui rendre.
     */
    val apiVersion: String get() = Stripe.API_VERSION

    /**
     * Google Pay en test ou en production, **d'après la clé publique** du
     * ticket : une clé de test n'encaisse rien, et Google Pay en production
     * refuserait de lui donner une vraie carte.
     */
    internal fun googlePayEnvironment(publishableKey: String): PaymentSheet.GooglePayConfiguration.Environment =
        if (publishableKey.startsWith("pk_live_")) {
            PaymentSheet.GooglePayConfiguration.Environment.Production
        } else {
            PaymentSheet.GooglePayConfiguration.Environment.Test
        }

    /** Ce que la feuille de Stripe a rendu, dit dans les mots de l'app. */
    internal fun outcome(result: PaymentSheetResult): PaymentOutcome = when (result) {
        is PaymentSheetResult.Completed -> PaymentOutcome.Succeeded
        is PaymentSheetResult.Canceled -> PaymentOutcome.Cancelled
        is PaymentSheetResult.Failed -> PaymentOutcome.Failed(message(result.error))
    }

    /**
     * Le message de Stripe, relayé tel quel ([PaymentError.Refused]). Une erreur
     * sans message — rare — dit qu'on n'a pas pu ouvrir le paiement.
     */
    internal fun message(error: Throwable): String =
        error.localizedMessage?.takeIf { it.isNotBlank() } ?: PaymentError.NoPresenter.errorDescription
}

/**
 * La vraie feuille Stripe.
 *
 * **Elle ne s'ouvre que posée dans la composition** : sur Android, la feuille
 * s'enregistre auprès de l'activité (`PaymentSheet.Builder(…).build()`), et
 * [PaymentSheetsHost] l'y pose une fois, tout en haut de `RootView`. Sans hôte,
 * [present] rend [PaymentError.NoPresenter].
 *
 * @param merchantName ce qui s'affiche en tête de la feuille, et sur le relevé
 *   bancaire.
 * @param merchantCountryCode le pays du **marchand**, pas du client. `FR` parce
 *   que c'est là qu'est le compte Stripe ; le client, lui, peut payer depuis
 *   n'importe où.
 *
 * **Google Pay vient du serveur, avec chaque paiement** (lot B5, 22/10/2026) —
 * `PaymentIntentTicket.googlePayEnabled`, comme Apple Pay sur iOS
 * (`applePayMerchantId`). Le serveur l'allume (`GOOGLE_PAY_ENABLED`) une fois
 * Google Pay activé dans le tableau de bord Stripe et l'accès en production
 * accordé par la Google Pay & Wallet Console : allumé trop tôt, la feuille
 * montrerait un bouton qui échoue. L'allumer, ou le couper en urgence, est une
 * variable Railway, pas une livraison. Un serveur plus ancien ne l'envoie pas :
 * cartes seules.
 */
class StripePaymentSheetPresenter(
    private val merchantName: String = "MemoBook",
    private val merchantCountryCode: String = "FR",
) : PaymentPresenter {
    private class Attached(val sheet: PaymentSheet, val context: Context)

    private val presenting = Mutex()
    private var attached: Attached? = null
    private var pending: CompletableDeferred<PaymentOutcome>? = null

    override suspend fun present(ticket: PaymentIntentTicket): PaymentOutcome = presenting.withLock {
        withContext(Dispatchers.Main.immediate) {
            val host = attached ?: return@withContext PaymentOutcome.Failed(PaymentError.NoPresenter.errorDescription)

            // La clé publique est posée **à chaque paiement**, depuis la réponse
            // du serveur, et non figée dans le binaire. Changer de compte Stripe
            // — ou passer de test à production — devient une variable
            // d'environnement côté serveur, pas une livraison sur le Play Store.
            PaymentConfiguration.init(host.context, ticket.publishableKey)

            val outcome = CompletableDeferred<PaymentOutcome>()
            pending = outcome
            try {
                host.sheet.presentWithPaymentIntent(ticket.clientSecret, configuration(ticket))
                outcome.await()
            } finally {
                if (pending === outcome) pending = null
            }
        }
    }

    private fun configuration(ticket: PaymentIntentTicket): PaymentSheet.Configuration {
        val builder = PaymentSheet.Configuration.Builder(merchantName)

        // **Les cartes du compte.** Avec le client et sa clé éphémère, la
        // feuille montre les cartes déjà enregistrées, propose « Enregistrer
        // pour la prochaine fois », et laisse en retirer une — tout ce que
        // l'app faisait semblant de faire avec son propre formulaire. Sans eux
        // (un serveur plus ancien), on paie quand même, carte saisie.
        val customerId = ticket.customerId
        val ephemeralKey = ticket.ephemeralKeySecret
        if (customerId != null && ephemeralKey != null) {
            builder.customer(PaymentSheet.CustomerConfiguration(customerId, ephemeralKey))
        }

        googlePay(ticket)?.let(builder::googlePay)
        return builder.build()
    }

    /** Google Pay pour ce paiement, ou rien si le ticket ne l'allume pas. */
    internal fun googlePay(ticket: PaymentIntentTicket): PaymentSheet.GooglePayConfiguration? =
        if (ticket.googlePayEnabled) {
            PaymentSheet.GooglePayConfiguration(
                environment = StripeSDK.googlePayEnvironment(ticket.publishableKey),
                countryCode = merchantCountryCode,
                currencyCode = ticket.currency.uppercase(),
            )
        } else {
            null
        }

    internal fun attach(sheet: PaymentSheet, context: Context) {
        attached = Attached(sheet, context)
    }

    internal fun detach(sheet: PaymentSheet) {
        if (attached?.sheet === sheet) attached = null
    }

    /**
     * L'issue de la feuille. Une rotation pendant le paiement recrée l'hôte : le
     * SDK rend alors l'issue à la nouvelle feuille, qui la transmet ici, où
     * l'appel de [present] l'attend toujours.
     */
    internal fun onResult(result: PaymentSheetResult) {
        pending?.complete(StripeSDK.outcome(result))
    }
}

/**
 * Un paiement qui n'appelle personne — aperçus et tests.
 *
 * Le résultat est **fixé à la construction** plutôt que tiré au hasard : un
 * aperçu qui échoue une fois sur deux est un aperçu qu'on ne peut pas relire.
 */
class StubPaymentPresenter(private val outcome: PaymentOutcome = PaymentOutcome.Succeeded) : PaymentPresenter {
    override suspend fun present(ticket: PaymentIntentTicket): PaymentOutcome = outcome
}

/**
 * **Les feuilles de Stripe, posées une fois tout en haut de l'app** — dans
 * `RootView`, hors de toute condition et hors des `NavDisplay`. Elles
 * s'enregistrent auprès de l'activité et de son `ViewModelStore` : posées dans
 * une destination, elles disparaîtraient avec elle, et un paiement ouvert
 * depuis un autre écran n'aurait plus de feuille.
 *
 * Ne dessine rien. Avec les doubles ([StubPaymentPresenter],
 * [StubPaymentMethodsPresenter]), ne fait rien non plus : un aperçu ne peut pas
 * ouvrir une feuille, même par accident.
 */
@Composable
fun PaymentSheetsHost(payments: PaymentPresenter, paymentMethods: PaymentMethodsPresenter) {
    if (payments is StripePaymentSheetPresenter) PaymentSheetHost(payments)
    if (paymentMethods is StripeCustomerSheetPresenter) CustomerSheetHost(paymentMethods)
}

@Composable
private fun PaymentSheetHost(presenter: StripePaymentSheetPresenter) {
    val callback = remember(presenter) { PaymentSheetResultCallback(presenter::onResult) }
    val sheet = remember(callback) { PaymentSheet.Builder(callback) }.build()
    val context = LocalContext.current.applicationContext
    DisposableEffect(presenter, sheet) {
        presenter.attach(sheet, context)
        onDispose { presenter.detach(sheet) }
    }
}
