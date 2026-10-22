package com.memobook.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant

/**
 * Un message à l'équipe — `POST /v1/support/messages` (contrat du 06/10/2026,
 * point 4, T226). Le jumeau de `MemoBookCore/SupportMessage.swift`.
 *
 * « Envoyer » du support attendait 600 ms puis disait « envoyé », et rien ne
 * partait (Hugo, 06/10/2026). Le formulaire de « Nous contacter » et
 * « Partager mes retours » du mot des fondateurs passent désormais par ici ;
 * [source] dit lequel des deux. Ne sert qu'à l'envoi.
 */
@Serializable
data class SupportMessage(
    var source: Source,
    /** La question de « Nous contacter » qui a ouvert le formulaire
     *  (`FaqEntry.id`), `null` pour le formulaire seul. */
    var topicId: String? = null,
    var message: String,
    /** Le voyage d'où l'on écrit, s'il y en a un. Le serveur ignore un voyage
     *  qu'il ne voit pas. */
    var tripId: String? = null,
    /** « 0.1.0 (21) ». */
    var appVersion: String? = null,
    /** L'appareil, sans rien des souvenirs — ce que la mention sous le champ
     *  promet. */
    var diagnostics: SupportDiagnostics? = null,
) {
    /** D'où part le message. */
    @Serializable
    enum class Source(val rawValue: String) {
        /** « Écris à notre équipe », et les deux questions de « Nous contacter ». */
        @SerialName("support") Support("support"),

        /** « Partager mes retours », dans le mot des fondateurs. */
        @SerialName("founders_note") FoundersNote("founders_note"),
    }
}

/** Le diagnostic technique joint à un message : le système, le modèle et la
 *  langue de l'appareil. Rien d'autre. */
@Serializable
data class SupportDiagnostics(
    var osVersion: String,
    var deviceModel: String,
    var locale: String,
)

/** Un vote « Est-ce utile ? » — `PUT /v1/support/faq-votes/:questionId` et
 *  `GET /v1/support/faq-votes`. Un par compte et par question : revoter
 *  remplace. */
@Serializable
data class FaqVote(
    val questionId: String,
    val isHelpful: Boolean,
    @Serializable(with = InstantSerializer::class) val updatedAt: Instant? = null,
)
