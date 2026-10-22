package com.memobook.feature.home

import androidx.compose.runtime.Composable
import com.memobook.feature.AppDependencies
import com.memobook.feature.HomeIntent
import com.memobook.feature.debug.PortPending

/**
 * L'accueil : les cartes des voyages, le tiroir d'actions, le micro, la boîte hors ligne.
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.… }`) et appelle la vue. Sa signature est le
 * contrat avec `RootView` ; tout le reste se porte depuis `Home/HomeView.swift`.
 */
@Composable
fun HomeEntry(dependencies: AppDependencies, onIntent: (HomeIntent) -> Unit) {
    PortPending("Accueil", "Home/HomeView.swift", actions = listOf("Profil" to { onIntent(HomeIntent.OpenProfile) }, "Créer un voyage" to { onIntent(HomeIntent.CreateTrip) }))
}
