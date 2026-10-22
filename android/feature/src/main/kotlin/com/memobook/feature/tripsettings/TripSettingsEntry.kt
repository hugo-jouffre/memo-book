package com.memobook.feature.tripsettings

import androidx.compose.runtime.Composable
import com.memobook.feature.AppDependencies
import com.memobook.feature.TripSettingsIntent
import com.memobook.feature.TripSettingsSheet
import com.memobook.feature.debug.PortPending

/**
 * Les réglages d'un voyage et leurs feuilles. `opening` : la feuille à ouvrir en arrivant.
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.… }`) et appelle la vue. Sa signature est le
 * contrat avec `RootView` ; tout le reste se porte depuis `TripSettings/TripSettingsView.swift`.
 */
@Composable
fun TripSettingsEntry(dependencies: AppDependencies, tripId: String, opening: TripSettingsSheet?, onIntent: (TripSettingsIntent) -> Unit, onBack: () -> Unit) {
    PortPending("Paramètres du voyage", "TripSettings/TripSettingsView.swift", onBack = onBack)
}
