package com.memobook.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject

// Le jumeau de `MemoBookCore/OrderPayment.swift`.

/**
 * Ce que le serveur rend quand une commande est enregistrée : la commande, et
 * par quel chemin elle se règle.
 *
 * **Deux objets et non un**, parce qu'ils ne vivent pas au même rythme. La
 * commande est un enregistrement durable, qu'on relira demain dans l'historique
 * du carnet. Le paiement est un aller-retour qui ne vaut que pour cette
 * minute-là : son `clientSecret` n'ouvre qu'une intention, et une fois la
 * feuille fermée il ne sert plus à rien. Les séparer ici garantit qu'aucun
 * écran ne pourra ranger l'un à côté de l'autre et garder le second.
 */
@Serializable(with = PlacedPrintOrder.Serializer::class)
data class PlacedPrintOrder(val order: PrintOrder, val payment: OrderPayment) {
    /**
     * La commande occupe la racine de la réponse et `payment` est une clé à côté
     * d'elle : on lit donc le même objet sous ses deux formes. Redéclarer les
     * vingt champs de [PrintOrder] pour les aplatir ici ferait deux listes à
     * tenir d'accord, et c'est celle qu'on oublie.
     */
    object Serializer : KSerializer<PlacedPrintOrder> {
        override val descriptor: SerialDescriptor = buildClassSerialDescriptor("com.memobook.core.PlacedPrintOrder")

        override fun deserialize(decoder: Decoder): PlacedPrintOrder {
            val (json, root) = decoder.rootObject()
            val payment = root["payment"] ?: throw SerializationException("Champ manquant : payment")
            return PlacedPrintOrder(
                order = json.decodeFromJsonElement(PrintOrder.serializer(), root),
                payment = json.decodeFromJsonElement(OrderPayment.serializer(), payment),
            )
        }

        override fun serialize(encoder: Encoder, value: PlacedPrintOrder) {
            encoder.encodeOrderAtRoot(value.order, value.payment)
        }
    }
}

/**
 * La reprise du paiement d'une commande déjà passée —
 * `POST /v1/orders/:id/payment`. La commande à la racine, comme
 * [PlacedPrintOrder] ; [payment] est nul quand il n'y a plus rien à régler :
 * payée, en cours, ou plus un brouillon. L'app relit alors la commande.
 */
@Serializable(with = ResumedOrderPayment.Serializer::class)
data class ResumedOrderPayment(val order: PrintOrder, val payment: OrderPayment?) {
    object Serializer : KSerializer<ResumedOrderPayment> {
        override val descriptor: SerialDescriptor =
            buildClassSerialDescriptor("com.memobook.core.ResumedOrderPayment")

        override fun deserialize(decoder: Decoder): ResumedOrderPayment {
            val (json, root) = decoder.rootObject()
            return ResumedOrderPayment(
                order = json.decodeFromJsonElement(PrintOrder.serializer(), root),
                payment = root["payment"]?.takeUnless { it is JsonNull }
                    ?.let { json.decodeFromJsonElement(OrderPayment.serializer(), it) },
            )
        }

        override fun serialize(encoder: Encoder, value: ResumedOrderPayment) {
            encoder.encodeOrderAtRoot(value.order, value.payment)
        }
    }
}

private fun Decoder.rootObject(): Pair<kotlinx.serialization.json.Json, JsonObject> {
    val json = this as? JsonDecoder ?: throw SerializationException("Une commande ne se lit qu'en JSON")
    return json.json to json.decodeJsonElement().jsonObject
}

/** Le chemin inverse, pour qu'un test ou un double puisse écrire la réponse du serveur. */
private fun Encoder.encodeOrderAtRoot(order: PrintOrder, payment: OrderPayment?) {
    val json = this as? JsonEncoder ?: throw SerializationException("Une commande ne s'écrit qu'en JSON")
    val fields = json.json.encodeToJsonElement(PrintOrder.serializer(), order).jsonObject.toMutableMap()
    if (payment != null) fields["payment"] = json.json.encodeToJsonElement(OrderPayment.serializer(), payment)
    json.encodeJsonElement(JsonObject(fields))
}

/**
 * Comment une commande se règle — la réponse du serveur, telle quelle.
 *
 * On ne la lit jamais champ par champ depuis un écran : [settlement] en tire la
 * seule question qui se pose, « faut-il ouvrir une feuille de paiement, et avec
 * quoi ». C'est ce qui évite qu'un écran conclue « rien à payer » d'un
 * `clientSecret` absent, alors que son absence peut aussi vouloir dire que le
 * serveur est mal configuré.
 *
 * **Plus de `paidFromWallet`** (Hugo, 06/10/2026, T230) : la cagnotte qui
 * pouvait tout couvrir est partie, et avec elle la commande réglée sans feuille.
 * Une commande se paie par Stripe, toujours.
 *
 * @property amountCents ce qui est à régler par carte.
 * @property clientSecret absent, comme [publishableKey], seulement quand le
 *   serveur n'a pas ses clés Stripe — voir [OrderSettlement.Unavailable].
 * @property customerId les cartes du compte, pour la feuille — voir [PaymentIntentTicket].
 * @property applePayMerchantId Apple Pay, quand le serveur le propose — voir [PaymentIntentTicket].
 */
@Serializable
data class OrderPayment(
    val amountCents: Int,
    val currency: String,
    val clientSecret: String? = null,
    val publishableKey: String? = null,
    val customerId: String? = null,
    val ephemeralKeySecret: String? = null,
    val applePayMerchantId: String? = null,
) {
    /** Ce qu'il reste à faire pour que la commande soit payée. */
    val settlement: OrderSettlement
        get() {
            // Une chaîne vide, et pas seulement `null` : côté serveur,
            // `STRIPE_PUBLISHABLE_KEY` vaut `""` quand elle n'est pas configurée,
            // et c'est cette valeur-là qui arrive jusqu'ici. Une feuille montée
            // sur une clé vide échoue au moment de payer, après l'authentification.
            if (clientSecret.isNullOrEmpty() || publishableKey.isNullOrEmpty()) {
                return OrderSettlement.Unavailable
            }
            return OrderSettlement.Card(
                PaymentIntentTicket(
                    clientSecret = clientSecret,
                    publishableKey = publishableKey,
                    amountCents = amountCents,
                    currency = currency,
                    customerId = customerId,
                    ephemeralKeySecret = ephemeralKeySecret,
                    applePayMerchantId = applePayMerchantId,
                ),
            )
        }
}

/** Par où passe le règlement d'une commande. */
sealed interface OrderSettlement {
    /** Il reste à payer, et voici de quoi ouvrir la feuille. */
    data class Card(val ticket: PaymentIntentTicket) : OrderSettlement

    /**
     * Il reste à payer, et le serveur n'a pas donné de quoi le faire.
     *
     * **Un cas de configuration, pas un cas d'usage.** Il n'arrive que si
     * `STRIPE_SECRET_KEY` ou `STRIPE_PUBLISHABLE_KEY` manquent à l'API déployée.
     * La commande existe alors en brouillon et n'est pas payée : il faut le
     * dire, et surtout ne pas afficher une confirmation.
     */
    data object Unavailable : OrderSettlement
}
