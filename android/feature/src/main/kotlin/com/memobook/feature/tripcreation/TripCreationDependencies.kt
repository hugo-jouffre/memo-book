package com.memobook.feature.tripcreation

import com.memobook.feature.AppDependencies
import kotlinx.coroutines.flow.map
import com.memobook.feature.chat.NotificationsNudge
import com.memobook.feature.chat.NotificationsPrimer

/**
 * Les six étapes de « Créer un voyage ». Le `tripCreationModel()`
 * d'`AppDependencies.swift`.
 *
 * Deux routes et non une, au début : la seconde servait la flèche de retour,
 * qui ne doit pas créer un second voyage — voir [TripCreationModel]. **Une
 * seule fonction pour les deux, désormais** (01/10/2026) : le voyage part par
 * la file, sous l'identifiant que l'app a tiré, et la création se rejoue sur
 * lui — corriger, c'est la renvoyer. Le code d'accès arrive quand le serveur
 * l'a créé, hors ligne au retour du réseau.
 */
fun AppDependencies.tripCreationModel(): TripCreationModel = TripCreationModel(
    save = { draft ->
        val trip = outbox.saveTrip(draft)
        // Le voyage est créé **sur cet appareil** : sa conversation posera la
        // question des notifications à sa première ouverture, si elle n'a
        // jamais été posée ([NotificationsPrimer]). Revalider le même
        // brouillon ne l'y met pas deux fois.
        NotificationsPrimer.markTripCreated(trip.id, settings)
        trip
    },
    sync = { id -> outbox.tripSync(id) },
    themes = { api.tripThemes() },
    isOffline = outbox.isOnline.map { !it },
    notificationsStepPassed = { NotificationsNudge.markStepPassed(settings) },
)
