package com.memobook.feature.covers

import androidx.compose.runtime.Composable
import com.memobook.feature.AppDependencies
import com.memobook.feature.debug.PortPending

/**
 * Les deux textes des plats.
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.… }`) et appelle la vue. Sa signature est le
 * contrat avec `RootView` ; tout le reste se porte depuis `Covers/CoverTextsView.swift`.
 */
@Composable
fun CoverTextsEntry(dependencies: AppDependencies, tripId: String, onBack: () -> Unit) {
    PortPending("Textes de couverture", "Covers/CoverTextsView.swift", onBack = onBack)
}
