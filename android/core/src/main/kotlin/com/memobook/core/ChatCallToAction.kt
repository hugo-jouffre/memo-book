package com.memobook.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * **L'appel à l'action d'une bulle de MEMO** (03/10/2026) — le bouton posé
 * sous le texte, séparé par un filet, avec « Ignorer » en dessous (maquettes
 * Figma `3653:17090` et, une fois touché, `3653:17213`). Le jumeau de
 * `MemoBookCore/ChatCallToAction.swift`.
 *
 * **C'est le serveur qui le pose**, et le plus souvent l'IA de conversation
 * qui le choisit — dans un catalogue fermé (`services/callsToAction.ts`) : elle
 * propose un identifiant, le code écrit le libellé et l'action. L'app ne
 * décide que de ce qu'elle fait au toucher, d'après [Kind].
 *
 * Distinct d'une [ChatSuggestion] : une puce **dit** quelque chose à MEMO,
 * elle part comme message ; un appel à l'action **ouvre** un écran et
 * n'envoie rien. Et il appartient à une bulle, là où les puces appartiennent
 * au fil.
 */
@Serializable(with = ChatCallToAction.Serializer::class)
data class ChatCallToAction(
    /** L'identifiant du catalogue — `daily_credit_subscribe`, `subscribe`… */
    val id: String,
    val kind: Kind,
    /** Le libellé du bouton, au caractère près. */
    val label: String,
    /** L'en-tête manuscrit de la carte, précédé d'une étoile. */
    val eyebrow: String? = null,
    /** « Ignorer » sous le bouton. */
    val dismissible: Boolean = true,
) {
    /** Ce que l'app fait au toucher. Sur le fil, une simple chaîne. */
    sealed interface Kind {
        val rawValue: String

        /** Ouvrir le paywall. */
        data object Subscribe : Kind { override val rawValue = "subscribe" }

        /** Ouvrir les réglages du voyage. */
        data object OpenTripSettings : Kind { override val rawValue = "open_trip_settings" }

        /** Ouvrir l'aperçu du carnet. */
        data object OpenPreview : Kind { override val rawValue = "open_preview" }

        /** Ouvrir le sélecteur de photos. */
        data object ImportPhotos : Kind { override val rawValue = "import_photos" }

        /** Ouvrir la page de MemoBook dans les réglages du téléphone. */
        data object OpenPhotoSettings : Kind { override val rawValue = "open_photo_settings" }

        /**
         * Demander l'autorisation des notifications — ou, refusée, ouvrir
         * les réglages. **Posé par l'app, jamais par le serveur** : seul le
         * téléphone sait ce que le système a répondu (T246).
         */
        data object EnableNotifications : Kind { override val rawValue = "enable_notifications" }

        /**
         * Une action que le serveur connaît et pas cette version de l'app :
         * **le bouton ne s'affiche pas**, le texte de la bulle reste. Même
         * parti pris que [ChatSuggestion.Intent.Unknown], mais à l'inverse :
         * une puce inconnue peut encore s'envoyer, un bouton inconnu ne
         * mènerait nulle part.
         */
        data class Unknown(override val rawValue: String) : Kind

        /** L'app sait-elle faire quelque chose de ce bouton ? */
        val isSupported: Boolean get() = this !is Unknown

        companion object {
            /** Le `init(rawValue:)` d'iOS : jamais d'échec, l'inconnu devient [Unknown]. */
            fun from(rawValue: String): Kind = when (rawValue) {
                "subscribe" -> Subscribe
                "open_trip_settings" -> OpenTripSettings
                "open_preview" -> OpenPreview
                "import_photos" -> ImportPhotos
                "open_photo_settings" -> OpenPhotoSettings
                "enable_notifications" -> EnableNotifications
                else -> Unknown(rawValue)
            }
        }
    }

    /** `kind` est une chaîne ; `dismissible` absent (ou `null`) vaut `true`, et s'écrit toujours. */
    @Serializable
    @SerialName("com.memobook.core.ChatCallToAction")
    internal class Surrogate(
        val id: String,
        val kind: String,
        val label: String,
        val eyebrow: String? = null,
        val dismissible: Boolean? = null,
    )

    internal object Serializer : ChatSurrogateSerializer<ChatCallToAction, Surrogate>(
        Surrogate.serializer(),
        { Surrogate(it.id, it.kind.rawValue, it.label, it.eyebrow, it.dismissible) },
        { ChatCallToAction(it.id, Kind.from(it.kind), it.label, it.eyebrow, it.dismissible ?: true) },
    )

    companion object {
        /**
         * Celui que l'app pose elle-même sous la bulle « reviens demain » quand
         * elle coupe le micro hors ligne — le même que le serveur
         * (`daily_credit_subscribe`).
         */
        val dailyCreditSubscribe = ChatCallToAction(
            id = "daily_credit_subscribe",
            kind = Kind.Subscribe,
            label = "Raconter sans limite",
            eyebrow = "Crédit du jour épuisé",
        )
    }
}

/**
 * Ce qu'on a fait d'un appel à l'action : rien encore, touché, ou ignoré.
 *
 * **Retenu sur l'appareil**, par identifiant de bulle : c'est l'état d'un
 * geste, pas un fait du récit. Touché, le bouton passe au bleu et « Ignorer »
 * s'en va ; ignoré, les deux s'en vont et la bulle redevient une bulle.
 */
@Serializable
enum class ChatCallToActionState(val rawValue: String) {
    @SerialName("pending") Pending("pending"),
    @SerialName("followed") Followed("followed"),
    @SerialName("dismissed") Dismissed("dismissed"),
}
