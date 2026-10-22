package com.memobook.feature.tripsettings

import com.memobook.feature.AppDependencies

/**
 * Les personnalisations du carnet, branchées sur le serveur —
 * `bookCustomisationModel(tripId:)` d'`AppDependencies.swift`.
 *
 * `GET /v1/trips/:id/settings` les lit avec le reste des réglages, et leur
 * `PATCH` les écrit une à une.
 */
fun AppDependencies.bookCustomisationModel(tripId: String): BookCustomisationModel = BookCustomisationModel(
    tripId = tripId,
    source = { id -> api.tripSettings(id = id) },
    persist = { id, edit -> api.updateBookCustomisation(tripId = id, edit = edit) },
    // `POST /v1/trips/:id/page-target/rewrite` : réécrire les étapes déjà
    // écrites au nombre de pages cible qu'on vient de changer.
    rewrite = { id -> api.rewritePageTarget(tripId = id) },
    // Les pointillés d'avant le verrou, gardés sur le téléphone : ils doivent
    // survivre à la fermeture de l'écran (Hugo, 02/10/2026).
    rulesMemory = BookRulesMemory.device(settings),
)
