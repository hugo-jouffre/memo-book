package com.memobook.feature.trip

import com.memobook.core.HomeFeed
import com.memobook.core.TripDetail
import com.memobook.feature.AppDependencies
import com.memobook.feature.ContentCache
import com.memobook.networking.ApiError

/**
 * Un voyage ouvert, servi par `GET /v1/trips/:id`. Le `tripModel(id:)`
 * d'`AppDependencies.swift`.
 *
 * Un voyage créé hors ligne n'y est pas encore — le serveur répond par une
 * panne de transport, ou par un 404 tant que la création n'est pas arrivée. Il
 * s'ouvre alors sur ce que l'app en sait : son brouillon.
 */
fun AppDependencies.tripModel(id: String): TripHomeModel {
    // La source est construite **ici**, une fois, parce que le voyage est
    // fixé à la construction du modèle : c'est ce qui permet au cache d'avoir
    // sa case (`Slot.Trip(id)`) sans que le modèle sache qu'il existe.
    val read = cachedSource(ContentCache.Slot.Trip(id)) { api.tripDetail(id) }

    return TripHomeModel(
        tripId = id,
        source = {
            try {
                read()
            } catch (error: kotlinx.coroutines.CancellationException) {
                throw error
            } catch (error: Exception) {
                val waiting = outbox.localTrip(id) ?: throw error
                TripDetail(trip = waiting.trip)
            }
        },
        cached = {
            content.read<TripDetail>(ContentCache.Slot.Trip(id)) ?: outbox.localTrip(id)?.let { TripDetail(trip = it.trip) }
        },
        // Jamais ouvert ici, et hors ligne : la carte de l'accueil gardé
        // (D11). Le modèle ne s'en sert que sur une panne de transport.
        homeCard = { content.read<HomeFeed>(ContentCache.Slot.Home)?.trips?.firstOrNull { it.id == id } },
        validateStep = { tripId, stepId -> api.validateStep(tripId, stepId) },
        // Un souvenir déjà effacé — par un co-voyageur, entre deux lectures —
        // n'est pas un échec : c'est ce qu'on voulait (T235).
        deleteEntry = { entryId ->
            try {
                api.deleteEntry(entryId)
            } catch (error: ApiError) {
                if (error.statusCode != 404) throw error
            }
        },
    )
}
