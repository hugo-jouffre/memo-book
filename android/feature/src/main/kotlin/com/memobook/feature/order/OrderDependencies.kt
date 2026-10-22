package com.memobook.feature.order

import com.memobook.feature.AppDependencies
import com.memobook.payments.StripeSDK

// Les fabriques du tunnel de commande — les `orderModel(memoId:email:)` et
// `finishAbandonedOrder(orderId:)` d'`AppDependencies.swift`.

/**
 * Le tunnel de commande, **entièrement servi par le serveur** — c'est ce qui
 * le distingue de l'accueil, du profil ou du voyage, qui s'ouvrent sur le cache.
 * Les commandes ne s'y gardent pas : c'est de l'argent, et un état périmé est
 * pire qu'un état absent.
 *
 * Quatre routes : `GET /v1/memos/:id/order-context` ouvre les sept étapes d'un
 * seul appel, `POST /v1/memos/:id/orders/quote` compte le récapitulatif,
 * `POST /v1/memos/:id/orders` enregistre **et rend de quoi payer**, et
 * `GET /v1/orders/:id` relit ce que le webhook a conclu.
 *
 * La commande naît en `draft` et n'en sort que sur retour de Stripe au
 * serveur : `presentPayment` ouvre la feuille, `reloadOrder` attend le
 * verdict. **L'app ne décide jamais qu'une commande est payée.**
 *
 * Google Pay, quand il est allumé, est un réglage de la feuille ([payments],
 * `StripePaymentSheetPresenter`) et non du tunnel : là où iOS lit
 * `applePayMerchantId` sur le ticket, la feuille d'Android l'ignore.
 *
 * @param email l'adresse à laquelle la confirmation partira, pour la dernière
 *   phrase de l'écran de confirmation. `null` quand le compte n'en a pas — la
 *   phrase s'abrège alors au lieu de promettre un envoi sans destinataire.
 */
fun AppDependencies.orderModel(memoId: String, email: String? = null): OrderModel =
    OrderModel(
        memoId = memoId,
        email = email,
        context = { id -> api.orderContext(id) },
        quote = { id, copies, speed -> api.orderQuote(memoId = id, copies = copies, shippingSpeed = speed) },
        submit = { id, request ->
            // La version du SDK Stripe part avec la commande : c'est elle qui
            // fait revenir une clé éphémère, et donc les cartes du compte dans
            // la feuille.
            api.createPrintOrder(memoId = id, order = request.copy(stripeApiVersion = StripeSDK.apiVersion))
        },
        // Le lien et le suivi WhatsApp de la confirmation n'étaient pas
        // branchés : la confirmation partageait un lien fabriqué par l'app, qui
        // ne menait nulle part.
        shareLink = { id -> api.bookShareLink(id) },
        setWhatsApp = { orderId, phone -> api.setOrderWhatsApp(orderId = orderId, phone = phone) },
        presentPayment = { ticket -> payments.present(ticket) },
        reloadOrder = { orderId -> api.printOrder(orderId) },
        resumePayment = { orderId -> api.resumePrintOrderPayment(orderId, StripeSDK.apiVersion) },
        cancelOrder = { orderId -> api.cancelPrintOrder(orderId) },
    )

/**
 * « Finaliser ma commande » du suivi des commandes (T232) : rouvre le paiement
 * d'une commande abandonnée, `POST /v1/orders/:id/payment`, et ouvre la feuille
 * de Stripe sur la nouvelle intention. Le suivi des commandes du profil
 * l'appelle ; dans le bac à sable, le double rend une commande sans rien à
 * régler, donc payée.
 */
suspend fun AppDependencies.finishAbandonedOrder(orderId: String): AbandonedOrderPayment.Outcome =
    AbandonedOrderPayment(
        resume = { id -> api.resumePrintOrderPayment(id, StripeSDK.apiVersion) },
        present = { ticket -> payments.present(ticket) },
        reload = { id -> api.printOrder(id) },
    ).finish(orderId)
