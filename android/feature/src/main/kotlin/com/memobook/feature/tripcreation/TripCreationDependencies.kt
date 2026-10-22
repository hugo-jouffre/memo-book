package com.memobook.feature.tripcreation

import com.memobook.feature.AppDependencies
import kotlinx.coroutines.flow.map

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
    save = { draft -> outbox.saveTrip(draft) },
    sync = { id -> outbox.tripSync(id) },
    themes = { api.tripThemes() },
    isOffline = outbox.isOnline.map { !it },
    notificationsStepPassed = { NotificationsNudge.markStepPassed(settings) },
)
