package com.memobook.feature.tripcreation

import androidx.compose.runtime.Composable
import com.memobook.feature.AppDependencies
import com.memobook.feature.HomeIntent
import com.memobook.feature.debug.PortPending

/**
 * Les six étapes de « Créer un voyage ». « Commencer ! » réémet `HomeIntent.OpenTrip`.
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.… }`) et appelle la vue. Sa signature est le
 * contrat avec `RootView` ; tout le reste se porte depuis `TripCreation/TripCreationView.swift`.
 */
@Composable
fun TripCreationEntry(dependencies: AppDependencies, onIntent: (HomeIntent) -> Unit, onBack: () -> Unit) {
    PortPending("Créer un voyage", "TripCreation/TripCreationView.swift", onBack = onBack)
}
