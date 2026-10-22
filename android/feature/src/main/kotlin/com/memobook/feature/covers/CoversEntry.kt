package com.memobook.feature.covers

import androidx.compose.runtime.Composable
import com.memobook.feature.AppDependencies
import com.memobook.feature.CoversIntent
import com.memobook.feature.debug.PortPending

/**
 * Les deux plats du carnet. Le modèle est **partagé** par les quatre écrans du parcours (`LocalSessionViewModelStoreOwner`).
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.… }`) et appelle la vue. Sa signature est le
 * contrat avec `RootView` ; tout le reste se porte depuis `Covers/CoversView.swift`.
 */
@Composable
fun CoversEntry(dependencies: AppDependencies, tripId: String, onIntent: (CoversIntent) -> Unit, onBack: () -> Unit) {
    PortPending("Couvertures", "Covers/CoversView.swift", onBack = onBack)
}
