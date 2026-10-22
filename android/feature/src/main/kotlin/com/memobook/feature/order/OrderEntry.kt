package com.memobook.feature.order

import androidx.compose.runtime.Composable
import com.memobook.feature.AppDependencies
import com.memobook.feature.OrderIntent
import com.memobook.feature.debug.PortPending

/**
 * Le tunnel de commande en sept étapes. `email` : où partira la confirmation, `null` sans adresse.
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.… }`) et appelle la vue. Sa signature est le
 * contrat avec `RootView` ; tout le reste se porte depuis `Order/OrderView.swift`.
 */
@Composable
fun OrderEntry(dependencies: AppDependencies, memoId: String, email: String?, onIntent: (OrderIntent) -> Unit, onBack: () -> Unit) {
    PortPending("Commander mon carnet", "Order/OrderView.swift", onBack = onBack)
}
