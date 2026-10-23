package com.memobook.core

import kotlinx.serialization.Serializable
import java.math.BigDecimal
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale

// Le jumeau de `MemoBookCore/PaymentIntentTicket.swift`.

/**
 * Ce que le serveur donne à l'app pour ouvrir une feuille de paiement.
 *
 * **Rien de secret ici, et c'est le point.** Le `clientSecret` n'ouvre qu'une
 * intention, celle-là et pas une autre ; la clé publique est faite pour partir
 * dans un binaire. La clé secrète, elle, ne quitte jamais le serveur — c'est lui
 * qui a décidé du montant, et l'app ne peut pas le contredire.
 *
 * C'est pour ça que le montant voyage aussi : il ne sert **qu'à l'affichage**.
 * Le débit, lui, est celui que le serveur a posé sur l'intention.
 *
 * @property customerId **le client Stripe du compte, et [ephemeralKeySecret] la
 *   clé qui ouvre ses cartes** — pour un court moment, et pour ce client
 *   seulement. Avec eux, la feuille montre les cartes déjà enregistrées, propose
 *   d'enregistrer la nouvelle, et laisse en retirer une. Absents d'un serveur
 *   plus ancien : la feuille s'ouvre alors sans cartes enregistrées, et on paie
 *   quand même.
 * @property applePayMerchantId **Apple Pay, quand le serveur le dit** :
 *   l'identifiant marchand, posé sur Railway une fois le certificat Apple Pay du
 *   compte Stripe en place. Absent, la feuille montre les cartes seules — mieux
 *   qu'un bouton Apple Pay qui échouerait après Face ID. Propre à iOS.
 * @property googlePayEnabled **Google Pay, quand le serveur le dit** (lot B5,
 *   22/10/2026) : `GOOGLE_PAY_ENABLED` sur Railway, une fois Google Pay activé
 *   sur le compte Stripe et l'accès en production accordé par Google. Absent
 *   d'un serveur plus ancien : faux, et la feuille montre les cartes seules.
 *   Propre à Android — le jumeau de [applePayMerchantId].
 */
@Serializable
data class PaymentIntentTicket(
    val clientSecret: String,
    val publishableKey: String,
    val amountCents: Int,
    val currency: String,
    val customerId: String? = null,
    val ephemeralKeySecret: String? = null,
    val applePayMerchantId: String? = null,
    val googlePayEnabled: Boolean = false,
) {
    /** Le montant tel qu'on l'écrit à l'écran — « 107,88 € » (`fr_FR`, comme iOS). */
    val formattedAmount: String
        get() {
            val euros = BigDecimal(amountCents).divide(BigDecimal(100))
            return try {
                val formatter = NumberFormat.getCurrencyInstance(Locale.FRANCE)
                formatter.currency = Currency.getInstance(currency.uppercase())
                formatter.format(euros)
            } catch (_: IllegalArgumentException) {
                "${euros.toPlainString()} ${currency.uppercase()}"
            }
        }
}

/**
 * Ce qui ouvre la feuille « Moyens de paiement » de Stripe, depuis le profil :
 * le client du compte et une clé éphémère dans la version d'API du SDK.
 */
@Serializable
data class CustomerPaymentKey(
    val customerId: String,
    val ephemeralKeySecret: String,
    val publishableKey: String,
)
