package com.memobook.feature.support

import androidx.compose.runtime.Composable
import com.memobook.feature.AppDependencies
import com.memobook.feature.debug.PortPending

/**
 * Le support : FAQ, votes, formulaire. `tripId` : le voyage d'où l'on vient, qui part avec le message (T226).
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.… }`) et appelle la vue. Sa signature est le
 * contrat avec `RootView` ; tout le reste se porte depuis `Support/SupportView.swift`.
 */
@Composable
fun SupportEntry(dependencies: AppDependencies, tripId: String?, onBack: () -> Unit) {
    PortPending("Besoin d’aide ?", "Support/SupportView.swift", onBack = onBack)
}
