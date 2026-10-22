package com.memobook.core

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.KeepGeneratedSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.descriptors.element
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import java.math.BigDecimal
import java.net.URI
import java.time.Instant

// Les modèles du premier carnet : appareil, carnet, souvenir, rendu, commande.
// Le jumeau de `MemoBookCore/Models.swift`.

/** Identité de l'appareil, provisoire tant qu'il n'y a pas de comptes. */
@Serializable
data class DeviceRegistration(
    val deviceId: String,
    val token: String,
)

/** Un projet de carnet. */
@Serializable
data class Memo(
    val id: String,
    val title: String,
    val subtitle: String? = null,
    val authors: String? = null,
    val theme: String? = null,
    @Serializable(with = InstantSerializer::class) val startDate: Instant? = null,
    @Serializable(with = InstantSerializer::class) val endDate: Instant? = null,
    val coverPhotoUrl: String? = null,
    @Serializable(with = InstantSerializer::class) val createdAt: Instant,
    @Serializable(with = InstantSerializer::class) val updatedAt: Instant,
)

/** Un carnet tel qu'il apparaît dans la liste d'accueil. */
@Serializable
data class MemoSummary(
    val id: String,
    val title: String,
    val subtitle: String? = null,
    val theme: String? = null,
    val coverPhotoUrl: String? = null,
    @Serializable(with = InstantSerializer::class) val createdAt: Instant,
    val entryCount: Int,
    val latestRender: Render? = null,
)

@Serializable
data class MediaSummary(
    val id: String,
    val mimeType: String,
    val bytes: Int,
    val durationSeconds: Double? = null,
    val cdnUrl: String? = null,
)

/**
 * Un souvenir : un vocal, une note ou une photo.
 *
 * Le texte traverse trois états, et les trois sont conservés :
 * `transcript` (ce qui a été dit), `redactedText` (ce que l'agent de
 * rédaction en a fait) et `editedText` (ce que l'utilisateur a corrigé au
 * clavier). `displayText` applique la hiérarchie — calculé par le serveur
 * pour que la règle ne diverge pas entre les clients.
 *
 * **Décodage tolérant sur les champs de rédaction.** Même raison que
 * [Status.Unknown] : une app déjà installée ne doit pas planter parce que le
 * serveur a changé. Ici c'est l'inverse dans le temps — un serveur plus ancien
 * que l'app, ou une réponse d'un endpoint qui ne renvoie pas encore ces champs,
 * donne un souvenir « en attente de rédaction » plutôt qu'une erreur de
 * décodage ([DecodeIfPresentSerializer]).
 */
@OptIn(ExperimentalSerializationApi::class)
@KeepGeneratedSerializer
@Serializable(with = Entry.Serializer::class)
data class Entry(
    val id: String,
    val memoId: String,
    val kind: EntryKind,
    /** Avancement de la transcription audio. */
    val status: Status,
    val transcript: String? = null,

    /** Avancement de la rédaction, suivi séparément : une transcription
     *  réussie dont la rédaction échoue laisse un souvenir exploitable. */
    val redactionStatus: Status = Status.Pending,
    val redactedText: String? = null,
    val redactionError: String? = null,

    val editedText: String? = null,
    @Serializable(with = InstantSerializer::class) val editedAt: Instant? = null,

    /** « Ça me convient » — le souvenir a été relu et gardé tel quel. Le carnet
     *  se compose avec ou sans ; l'aperçu signale ceux qui ne le sont pas. */
    @Serializable(with = InstantSerializer::class) val validatedAt: Instant? = null,

    /**
     * Le texte à afficher et à éditer. Jamais `null` une fois la
     * transcription passée.
     *
     * Le serveur le calcule ; le repli local (la valeur par défaut, prise aussi
     * quand la clé manque au décodage) applique la même hiérarchie pour que les
     * deux ne puissent pas diverger.
     */
    val displayText: String? = editedText ?: redactedText ?: transcript,

    val suggestedTitle: String? = null,
    val funFact: String? = null,
    val funFactTitle: String? = null,
    val weatherKey: String? = null,

    @Serializable(with = InstantSerializer::class) val capturedAt: Instant,
    val placeLabel: String? = null,
    val error: String? = null,
    val media: MediaSummary? = null,
    @Serializable(with = InstantSerializer::class) val createdAt: Instant,
    /** Ce qui reste des 200 caractères de correction offerts (QA D8,
     *  19/10/2026). `null` pour un serveur d'avant. */
    val freeCorrectionCharactersLeft: Int? = null,
) {
    /** `true` quand l'utilisateur a repris le texte à la main. */
    val isEdited: Boolean get() = editedText != null

    /** `true` tant qu'il reste une étape de traitement en cours sur ce
     *  souvenir — c'est ce que la liste affiche comme « en cours ». */
    val isProcessing: Boolean
        get() = status.isInProgress || (kind != EntryKind.Photo && redactionStatus.isInProgress)

    /** Prêt à entrer dans le carnet : le texte ne bougera plus tout seul. */
    val isReadyForBook: Boolean
        get() = kind == EntryKind.Photo || redactionStatus == Status.Ready || redactionStatus == Status.Failed

    object Serializer : DecodeIfPresentSerializer<Entry>(generatedSerializer())
}

/**
 * Correction manuelle d'un souvenir, envoyée en `PATCH`.
 *
 * `editedText` distingue trois cas et le codage doit les préserver :
 * une valeur (nouveau texte), `Some(null)` (revenir à la version proposée),
 * et l'absence de clé (`null` : ne pas toucher au texte). Omettre les `null`
 * ne suffit donc pas — il écraserait le deuxième cas.
 */
@Serializable(with = EntryEdit.Serializer::class)
data class EntryEdit(
    var editedText: Some<String?>? = null,
    var suggestedTitle: Some<String?>? = null,
    var weatherKey: Some<String?>? = null,
) {
    companion object {
        /** Reprend le texte à la main. */
        fun text(value: String): EntryEdit = EntryEdit(editedText = Some(value))

        /** Revient au texte proposé par la rédaction. */
        val revertToRedaction: EntryEdit get() = EntryEdit(editedText = Some(null))
    }

    /** Écrit seulement les clés présentes, et un `null` explicite pour `Some(null)`
     *  — que `explicitNulls = false` de [MemoBookJson] aurait sinon effacé. */
    object Serializer : KSerializer<EntryEdit> {
        override val descriptor: SerialDescriptor = buildClassSerialDescriptor("com.memobook.core.EntryEdit") {
            element<String?>("editedText", isOptional = true)
            element<String?>("suggestedTitle", isOptional = true)
            element<String?>("weatherKey", isOptional = true)
        }

        override fun serialize(encoder: Encoder, value: EntryEdit) {
            val json = encoder as? JsonEncoder
                ?: throw SerializationException("EntryEdit ne s'écrit qu'en JSON")
            json.encodeJsonElement(
                buildJsonObject {
                    value.editedText?.let { put("editedText", it.value?.let(::JsonPrimitive) ?: JsonNull) }
                    value.suggestedTitle?.let { put("suggestedTitle", it.value?.let(::JsonPrimitive) ?: JsonNull) }
                    value.weatherKey?.let { put("weatherKey", it.value?.let(::JsonPrimitive) ?: JsonNull) }
                },
            )
        }

        /** Uniquement `Encodable` sur iOS : ce type ne sert qu'à l'envoi. */
        override fun deserialize(decoder: Decoder): EntryEdit =
            throw SerializationException("EntryEdit ne se décode pas : il ne sert qu'à l'envoi")
    }
}

/** Une génération de carnet. */
@Serializable
data class Render(
    val id: String,
    val memoId: String,
    val status: Status,
    val pdfUrl: String? = null,
    val error: String? = null,
    @Serializable(with = InstantSerializer::class) val createdAt: Instant,
    @Serializable(with = InstantSerializer::class) val updatedAt: Instant,
)

/** Adresse de livraison d'un carnet imprimé. */
@Serializable
data class ShippingAddress(
    var name: String,
    var line1: String,
    var line2: String? = null,
    var postalCode: String,
    var city: String,
    /** Code ISO 3166-1 alpha-2. */
    var country: String,
)

@Serializable
enum class PrintOrderStatus(val rawValue: String) {
    @SerialName("draft") Draft("draft"),
    @SerialName("submitted") Submitted("submitted"),
    @SerialName("in_production") InProduction("in_production"),
    @SerialName("shipped") Shipped("shipped"),
    @SerialName("cancelled") Cancelled("cancelled"),
}

/** Une commande de carnet imprimé, passée sur un rendu précis. */
@Serializable
data class PrintOrder(
    val id: String,
    val memoId: String,
    /** Le rendu commandé est figé : c'est exactement le PDF prévisualisé. */
    val renderId: String,
    val status: PrintOrderStatus,
    val copies: Int,
    val shippingSpeed: ShippingSpeed = ShippingSpeed.Standard,
    val shipping: ShippingAddress,

    /** Ce que l'écran de confirmation annonce. Figés avec la commande : c'est
     *  le livre qui est parti à l'impression, pas celui d'aujourd'hui. */
    val pageCount: Int? = null,
    @Serializable(with = UriSerializer::class) val coverImageUrl: URI? = null,
    val estimatedMinDays: Int? = null,
    val estimatedMaxDays: Int? = null,

    /** Le net payé. `null` sur les commandes d'avant la tarification — à lire
     *  comme « pas de montant à afficher », jamais comme zéro. */
    @Serializable(with = BigDecimalSerializer::class) val total: BigDecimal? = null,

    /** Les options, exemplaire par exemplaire, dans l'ordre des rangs. */
    val copyOptions: List<PrintedCopyOptions> = emptyList(),

    /** Le suivi par WhatsApp, et le numéro à prévenir. Le second ne vaut jamais
     *  `null` quand le premier est vrai : une promesse sans destinataire n'a pas
     *  de sens, et c'est le serveur qui le garantit. */
    val notifyByWhatsApp: Boolean = false,
    val whatsappPhone: String? = null,

    val trackingUrl: String? = null,
    val error: String? = null,
    @Serializable(with = InstantSerializer::class) val createdAt: Instant,
    @Serializable(with = InstantSerializer::class) val updatedAt: Instant,
) {
    /** Le délai annoncé, quand l'imprimeur en a donné un. */
    val estimatedDays: DayRange?
        get() {
            val min = estimatedMinDays ?: return null
            val max = estimatedMaxDays ?: return null
            return DayRange(min = min, max = max)
        }
}

/** Un carnet avec tout son contenu — la réponse de `GET /v1/memos/:id`. */
@Serializable
data class MemoDetail(
    val id: String,
    val title: String,
    val subtitle: String? = null,
    val authors: String? = null,
    val theme: String? = null,
    @Serializable(with = InstantSerializer::class) val startDate: Instant? = null,
    @Serializable(with = InstantSerializer::class) val endDate: Instant? = null,
    val coverPhotoUrl: String? = null,
    @Serializable(with = InstantSerializer::class) val createdAt: Instant,
    @Serializable(with = InstantSerializer::class) val updatedAt: Instant,
    val entries: List<Entry> = emptyList(),
    val renders: List<Render> = emptyList(),
) {
    /** La génération la plus récente, celle que l'écran de statut suit. */
    val latestRender: Render? get() = renders.firstOrNull()
}

/** Paramètres de création d'un carnet. */
@Serializable
data class NewMemo(
    var title: String,
    var subtitle: String? = null,
    var authors: String? = null,
    var theme: String? = null,
    @Serializable(with = InstantSerializer::class) var startDate: Instant? = null,
    @Serializable(with = InstantSerializer::class) var endDate: Instant? = null,
)

/**
 * Une note écrite, envoyée telle quelle sans transcription.
 *
 * Ne sert qu'à l'envoi : `kind` n'est pas un paramètre, il vaut toujours
 * [EntryKind.Text] et part toujours dans le corps.
 */
@Serializable
data class NewTextEntry(
    var transcript: String,
    @Serializable(with = InstantSerializer::class) var capturedAt: Instant = Instant.now(),
    var placeLabel: String? = null,
) {
    val kind: EntryKind = EntryKind.Text
}
