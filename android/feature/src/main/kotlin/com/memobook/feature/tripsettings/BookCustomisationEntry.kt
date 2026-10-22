package com.memobook.feature.tripsettings

import androidx.compose.runtime.Composable
import com.memobook.feature.AppDependencies
import com.memobook.feature.BookCustomisationIntent
import com.memobook.feature.debug.PortPending

/**
 * Les personnalisations du carnet : ratio, pages, décorations, typos, extras.
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.… }`) et appelle la vue. Sa signature est le
 * contrat avec `RootView` ; tout le reste se porte depuis `TripSettings/BookCustomisationView.swift`.
 */
@Composable
fun BookCustomisationEntry(dependencies: AppDependencies, tripId: String, onIntent: (BookCustomisationIntent) -> Unit, onBack: () -> Unit) {
    PortPending("Style du carnet", "TripSettings/BookCustomisationView.swift", onBack = onBack)
}
