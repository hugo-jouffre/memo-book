package com.memobook.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Statut d'une étape du pipeline, tel que le back-end le renvoie. Le jumeau de
 * `MemoBookCore/Status.swift`.
 *
 * Le cas [Unknown] existe pour qu'un statut ajouté côté serveur ne fasse pas
 * planter une version de l'app déjà installée : elle l'affichera comme « en
 * cours » plutôt que d'échouer au décodage.
 */
@Serializable(with = Status.Serializer::class)
sealed interface Status {
    val rawValue: String

    data object Pending : Status { override val rawValue = "pending" }
    data object Processing : Status { override val rawValue = "processing" }
    data object Ready : Status { override val rawValue = "ready" }
    data object Failed : Status { override val rawValue = "failed" }
    data class Unknown(override val rawValue: String) : Status

    val isTerminal: Boolean get() = this == Ready || this == Failed
    val isInProgress: Boolean get() = !isTerminal

    companion object {
        fun from(raw: String): Status = when (raw) {
            "pending" -> Pending
            "processing" -> Processing
            "ready" -> Ready
            "failed" -> Failed
            else -> Unknown(raw)
        }
    }

    object Serializer : RawValueSerializer<Status>("com.memobook.core.Status", { it.rawValue }, ::from)
}

/** Nature d'un souvenir déposé dans un carnet. */
@Serializable
enum class EntryKind {
    @SerialName("audio") Audio,
    @SerialName("text") Text,
    @SerialName("photo") Photo,
}
