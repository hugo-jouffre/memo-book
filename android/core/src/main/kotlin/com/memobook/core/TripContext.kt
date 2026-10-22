package com.memobook.core

import kotlinx.serialization.Serializable

/**
 * Le contexte du voyage, tel que la conversation le montre : la pastille
 * « Contexte du voyage 3/5 » et la fiche qu'elle ouvre. Le jumeau de
 * `MemoBookCore/TripContext.swift`.
 *
 * Avant la première étape, MEMO demande d'où l'on part, à combien, le prénom
 * de chaque compagnon, les dates et le genre de voyage. **Le serveur tient
 * tout** — la liste des lignes, leurs libellés, ce qui compte comme rempli
 * (`backend/src/services/tripContext.ts`, `serializeTripContext`) : une ligne
 * ajoutée là-bas s'affiche ici sans livrer une version.
 *
 * `null` sur `ChatThread.tripContext` tant que le voyageur n'a pas commencé
 * à le raconter.
 */
@Serializable
data class ChatTripContext(
    val status: Status,
    val filledCount: Int,
    val requiredCount: Int,
    val items: List<Item>,
) {
    /** Tolérant au décodage, comme [com.memobook.core.Status] : un état ajouté
     *  côté serveur devient [Unknown]. */
    @Serializable(with = Status.Serializer::class)
    sealed interface Status {
        val rawValue: String

        /** MEMO recueille : chaque tour du voyageur y va. */
        data object Gathering : Status { override val rawValue = "gathering" }
        data object Complete : Status { override val rawValue = "complete" }
        /** « Je compléterai plus tard ». */
        data object Skipped : Status { override val rawValue = "skipped" }
        data class Unknown(override val rawValue: String) : Status

        companion object {
            fun from(raw: String): Status = when (raw) {
                "gathering" -> Gathering
                "complete" -> Complete
                "skipped" -> Skipped
                else -> Unknown(raw)
            }
        }

        object Serializer : RawValueSerializer<Status>("com.memobook.core.ChatTripContext.Status", { it.rawValue }, ::from)
    }

    @Serializable
    data class Item(
        val key: String,
        val label: String,
        /** Ce que MEMO a compris, en clair. `null` tant que la ligne est vide. */
        val value: String?,
        val isRequired: Boolean = true,
        val isFilled: Boolean = value != null,
    ) {
        val id: String get() = key
    }

    /** La pastille ne se montre que pendant le recueil : une fois posé, le
     *  contexte n'a plus rien à réclamer. */
    val isGathering: Boolean get() = status == Status.Gathering

    /** De 0 à 1, pour la jauge de la pastille. */
    val progress: Double
        get() = if (requiredCount > 0) minOf(1.0, filledCount.toDouble() / requiredCount.toDouble()) else 0.0

    companion object {
        /** À mi-chemin : deux lignes sur cinq, pour les aperçus. */
        val fixture = ChatTripContext(
            status = Status.Gathering,
            filledCount = 2,
            requiredCount = 5,
            items = listOf(
                Item(key = "departureCountry", label = "Pays de départ", value = "France"),
                Item(key = "travellerCount", label = "Voyageurs", value = "3, toi compris"),
                Item(key = "companions", label = "Compagnons de route", value = null),
                Item(key = "dates", label = "Dates", value = null),
                Item(key = "tripType", label = "Genre de voyage", value = null),
                Item(key = "itinerary", label = "Itinéraire", value = "Kuala Lumpur, Penang, Langkawi", isRequired = false),
            ),
        )
    }
}
