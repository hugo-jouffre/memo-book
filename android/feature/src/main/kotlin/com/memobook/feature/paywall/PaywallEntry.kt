package com.memobook.feature.paywall

import androidx.compose.runtime.Composable
import com.memobook.feature.AppDependencies
import com.memobook.feature.debug.PortPending

/**
 * L'offre ouverte par un lien `memobook://paywall`, plein écran, sans écran d'attache.
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.… }`) et appelle la vue. Sa signature est le
 * contrat avec `RootView` ; tout le reste se porte depuis `Paywall/PaywallView.swift`.
 */
@Composable
fun PaywallEntry(dependencies: AppDependencies, onSubscribe: () -> Unit, onDismiss: () -> Unit) {
    PortPending("Abonnement", "Paywall/PaywallView.swift", onBack = onDismiss)
}
