package com.memobook.core

import kotlinx.serialization.Serializable
import java.time.Instant

/**
 * Ce que le serveur répond à « Exporter mes données » —
 * `POST /v1/accounts/me/export`. Le jumeau de `MemoBookCore/DataExport.swift`.
 *
 * **La demande ne fabrique rien** : elle envoie par e-mail le lien d'une page
 * où télécharger l'archive, valable sept jours, et c'est en l'ouvrant que
 * l'archive se compose. L'app n'a donc qu'à dire **où** le lien est parti, et
 * **jusqu'à quand** il vaut.
 */
@Serializable
data class DataExportReceipt(
    /** L'adresse du compte — la seule où le lien peut partir : la requête n'en
     *  porte aucune. */
    val email: String,
    @Serializable(with = InstantSerializer::class) val requestedAt: Instant,
    @Serializable(with = InstantSerializer::class) val expiresAt: Instant,

    /** Un e-mail était déjà parti il y a moins de cinq minutes : le serveur
     *  n'en a pas envoyé d'autre. L'écran le dit autrement — l'e-mail est en
     *  route, ou dans les indésirables. */
    val alreadyRequested: Boolean = false,
) {
    companion object {
        /** Ce que l'aperçu et le bac à sable font répondre : un lien parti à
         *  l'instant, valable sept jours. */
        fun fixture(email: String, now: Instant = Instant.now()): DataExportReceipt =
            DataExportReceipt(
                email = email,
                requestedAt = now,
                expiresAt = now.plusSeconds(7L * 24 * 60 * 60),
            )
    }
}
