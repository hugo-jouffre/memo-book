package com.memobook.feature.tripsettings

import com.memobook.core.TripSettings
import com.memobook.feature.AppDependencies
import com.memobook.feature.ContentCache

/**
 * Les réglages d'un voyage, branchés sur le serveur — `tripSettingsModel(tripId:)`
 * d'`AppDependencies.swift`.
 *
 * La lecture passe par le cache (`ContentCache.Slot.TripSettings`) : trente
 * valeurs pour un écran qu'on ouvre pour en changer une, c'est celui qui gagne
 * le plus à s'ouvrir sur ce qu'on avait, et à se relire sans réseau.
 */
fun AppDependencies.tripSettingsModel(tripId: String): TripSettingsModel {
    val slot = ContentCache.Slot.TripSettings(tripId)
    val read = cachedSource(slot) { api.tripSettings(id = tripId) }

    return TripSettingsModel(
        tripId = tripId,
        source = { read() },
        persist = { id, edit -> api.updateTripSettings(id = id, edit = edit) },
        removeCompanion = { id, companionId -> api.removeCompanion(tripId = id, companionId = companionId) },
        resendInvitation = { id, companionId -> api.resendInvitation(tripId = id, companionId = companionId) },
        // La seule sans retour : `DELETE /v1/memos/:id`, que le serveur
        // réserve au propriétaire. L'écran demande confirmation avant.
        delete = { id -> api.deleteMemo(id = id) },
        // `DELETE /v1/trips/:id/chat` : le serveur efface le fil et repose
        // l'ouverture. Propriétaire seul — il refuse (403) à un co-voyageur,
        // et l'écran l'a déjà dit en pâlissant le lien.
        clearConversation = { id -> api.clearChat(tripId = id) },
        cached = cached<TripSettings>(slot),
        themes = { api.tripThemes() },
        // Ce qui a été envoyé et attend la file : le crédit du jour des
        // réglages le compte, comme la conversation et l'accueil — et rien
        // d'autre, ni vocal en cours ni vocal en pause.
        waitingTurns = { outbox.waiting(tripId) },
    )
}
