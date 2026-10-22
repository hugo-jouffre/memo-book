package com.memobook.feature.covers

import androidx.compose.runtime.Composable
import com.memobook.feature.AppDependencies
import com.memobook.feature.debug.PortPending

/**
 * Le carrousel des styles de couverture (`CoverCarouselView(kind: .style)`).
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.… }`) et appelle la vue. Sa signature est le
 * contrat avec `RootView` ; tout le reste se porte depuis `Covers/CoverCarouselView.swift`.
 */
@Composable
fun CoverStyleEntry(dependencies: AppDependencies, tripId: String, onBack: () -> Unit) {
    PortPending("Style de couverture", "Covers/CoverCarouselView.swift", onBack = onBack)
}
