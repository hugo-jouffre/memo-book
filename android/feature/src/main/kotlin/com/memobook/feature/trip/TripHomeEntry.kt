package com.memobook.feature.trip

import androidx.compose.runtime.Composable
import com.memobook.feature.AppDependencies
import com.memobook.feature.TripIntent
import com.memobook.feature.debug.PortPending

/**
 * L'accueil d'un voyage : en-tête, étapes, validation, suppression d'étape.
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.… }`) et appelle la vue. Sa signature est le
 * contrat avec `RootView` ; tout le reste se porte depuis `Trip/TripHomeView.swift`.
 */
@Composable
fun TripHomeEntry(dependencies: AppDependencies, tripId: String, onIntent: (TripIntent) -> Unit, onBack: () -> Unit) {
    PortPending("Voyage", "Trip/TripHomeView.swift", onBack = onBack, actions = listOf("Raconter" to { onIntent(TripIntent.TellMore(tripId)) }))
}
