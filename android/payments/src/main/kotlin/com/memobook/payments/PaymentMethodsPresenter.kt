package com.memobook.payments

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import com.memobook.core.CustomerPaymentKey
import com.stripe.android.PaymentConfiguration
import com.stripe.android.customersheet.CustomerAdapter
import com.stripe.android.customersheet.CustomerEphemeralKey
import com.stripe.android.customersheet.CustomerSheet
import com.stripe.android.customersheet.CustomerSheetResult
import com.stripe.android.customersheet.CustomerSheetResultCallback
import com.stripe.android.customersheet.rememberCustomerSheet
import com.stripe.android.model.PaymentMethod
import com.stripe.android.model.PaymentMethodUpdateParams
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

// Le jumeau de `MemoBookPayments/PaymentMethodsPresenter.swift`.

/**
 * La feuille « Moyens de paiement » du profil : les cartes du compte, telles
 * que Stripe les tient — en ajouter une, en retirer une.
 *
 * **Elle remplace un formulaire fait main** (01/10/2026) : l'app iOS demandait
 * le numéro, l'échéance et le cryptogramme dans ses propres champs, n'en
 * gardait que les quatre derniers chiffres en mémoire, et ne parlait à
 * personne. Un numéro de carte n'a rien à faire dans l'app : ici, c'est Stripe
 * qui le saisit, le vérifie et le garde.
 */
interface PaymentMethodsPresenter {
    /**
     * Ouvre la feuille. Rend un message quand elle n'a pas pu s'ouvrir, `null`
     * sinon — la refermer n'est pas une erreur.
     */
    suspend fun present(
        key: suspend () -> CustomerPaymentKey,
        setupIntent: suspend () -> String,
    ): String?
}

/**
 * La vraie, `CustomerSheet` de Stripe, branchée par une clé éphémère — la voie
 * qu'iOS a prise (les sessions client y sont encore en bêta), et le même
 * serveur pour les deux : `POST /v1/payments/ephemeral-key` et `/setup-intent`.
 *
 * Comme [StripePaymentSheetPresenter], elle ne s'ouvre que posée dans la
 * composition, par [PaymentSheetsHost].
 */
class StripeCustomerSheetPresenter(private val merchantName: String = "MemoBook") : PaymentMethodsPresenter {
    private class Attached(val sheet: CustomerSheet, val context: Context)

    /**
     * L'adaptateur que la feuille garde pour toujours — `rememberCustomerSheet`
     * se souvient de lui —, et qui passe chaque appel à celui de la
     * présentation en cours.
     */
    internal val adapter = PresentationCustomerAdapter()

    private val presenting = Mutex()
    private var attached: Attached? = null
    private var pending: CompletableDeferred<String?>? = null

    override suspend fun present(
        key: suspend () -> CustomerPaymentKey,
        setupIntent: suspend () -> String,
    ): String? = presenting.withLock {
        val customer = try {
            key()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            return error.localizedMessage ?: PaymentError.NoPresenter.errorDescription
        }

        withContext(Dispatchers.Main.immediate) {
            val host = attached ?: return@withContext PaymentError.NoPresenter.errorDescription

            // La clé publique, posée à chaque ouverture depuis la réponse du
            // serveur — comme pour un paiement.
            PaymentConfiguration.init(host.context, customer.publishableKey)

            // **Un adaptateur neuf à chaque ouverture** (22/10/2026). Celui de
            // Stripe garde la clé éphémère trente minutes : un autre compte
            // connecté entre-temps sur le même téléphone aurait vu les cartes
            // du précédent.
            adapter.current = CustomerAdapter.create(
                context = host.context,
                customerEphemeralKeyProvider = {
                    CustomerAdapter.Result.success(
                        CustomerEphemeralKey.create(customer.customerId, customer.ephemeralKeySecret),
                    )
                },
                setupIntentClientSecretProvider = { _ ->
                    try {
                        CustomerAdapter.Result.success(setupIntent())
                    } catch (error: CancellationException) {
                        throw error
                    } catch (error: Exception) {
                        CustomerAdapter.Result.failure(error, error.localizedMessage)
                    }
                },
            )

            host.sheet.configure(
                CustomerSheet.Configuration.builder(merchantName)
                    .headerTextForSelectionScreen("Tes moyens de paiement")
                    .build(),
            )

            val message = CompletableDeferred<String?>()
            pending = message
            try {
                host.sheet.present()
                message.await()
            } finally {
                if (pending === message) pending = null
            }
        }
    }

    internal fun attach(sheet: CustomerSheet, context: Context) {
        attached = Attached(sheet, context)
    }

    internal fun detach(sheet: CustomerSheet) {
        if (attached?.sheet === sheet) attached = null
    }

    internal fun onResult(result: CustomerSheetResult) {
        pending?.complete(
            when (result) {
                is CustomerSheetResult.Failed -> StripeSDK.message(result.exception)
                // Choisir une carte, ou refermer : rien à dire.
                else -> null
            },
        )
    }
}

/** Une feuille qui n'appelle personne — aperçus et bac à sable. */
class StubPaymentMethodsPresenter : PaymentMethodsPresenter {
    override suspend fun present(
        key: suspend () -> CustomerPaymentKey,
        setupIntent: suspend () -> String,
    ): String? = null
}

@Composable
internal fun CustomerSheetHost(presenter: StripeCustomerSheetPresenter) {
    val callback = remember(presenter) { CustomerSheetResultCallback(presenter::onResult) }
    val sheet = rememberCustomerSheet(presenter.adapter, callback)
    val context = LocalContext.current.applicationContext
    DisposableEffect(presenter, sheet) {
        presenter.attach(sheet, context)
        onDispose { presenter.detach(sheet) }
    }
}

/**
 * Un `CustomerAdapter` qui passe chaque appel à [current] — celui de la
 * présentation en cours. Avant la première, chaque appel échoue : la feuille
 * ne s'ouvre jamais sans [StripeCustomerSheetPresenter.present], qui le pose.
 */
internal class PresentationCustomerAdapter : CustomerAdapter {
    @Volatile var current: CustomerAdapter? = null

    private fun <T> notReady(): CustomerAdapter.Result<T> =
        CustomerAdapter.Result.failure(IllegalStateException("Aucune présentation en cours."), null)

    override val canCreateSetupIntents: Boolean get() = current?.canCreateSetupIntents ?: false

    override val paymentMethodTypes: List<String>? get() = current?.paymentMethodTypes

    override suspend fun retrievePaymentMethods(): CustomerAdapter.Result<List<PaymentMethod>> =
        current?.retrievePaymentMethods() ?: notReady()

    override suspend fun attachPaymentMethod(paymentMethodId: String): CustomerAdapter.Result<PaymentMethod> =
        current?.attachPaymentMethod(paymentMethodId) ?: notReady()

    override suspend fun detachPaymentMethod(paymentMethodId: String): CustomerAdapter.Result<PaymentMethod> =
        current?.detachPaymentMethod(paymentMethodId) ?: notReady()

    override suspend fun updatePaymentMethod(
        paymentMethodId: String,
        params: PaymentMethodUpdateParams,
    ): CustomerAdapter.Result<PaymentMethod> = current?.updatePaymentMethod(paymentMethodId, params) ?: notReady()

    override suspend fun setSelectedPaymentOption(
        paymentOption: CustomerAdapter.PaymentOption?,
    ): CustomerAdapter.Result<Unit> = current?.setSelectedPaymentOption(paymentOption) ?: notReady()

    override suspend fun retrieveSelectedPaymentOption(): CustomerAdapter.Result<CustomerAdapter.PaymentOption?> =
        current?.retrieveSelectedPaymentOption() ?: notReady()

    override suspend fun setupIntentClientSecretForCustomerAttach(): CustomerAdapter.Result<String> =
        current?.setupIntentClientSecretForCustomerAttach() ?: notReady()
}
