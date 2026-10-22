package com.memobook.feature.profile

import androidx.compose.runtime.Composable
import com.memobook.feature.AppDependencies
import com.memobook.feature.ProfileIntent
import com.memobook.feature.debug.PortPending

/**
 * Le profil et ses feuilles. `opensSubscription` : « Mon abonnement » ouvert en arrivant (`HomeRoute.ManageSubscription`).
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.… }`) et appelle la vue. Sa signature est le
 * contrat avec `RootView` ; tout le reste se porte depuis `Profile/ProfileView.swift`.
 */
@Composable
fun ProfileEntry(dependencies: AppDependencies, opensSubscription: Boolean, onSignOut: () -> Unit, onIntent: (ProfileIntent) -> Unit, onBack: () -> Unit) {
    PortPending("Profil", "Profile/ProfileView.swift", onBack = onBack, actions = listOf("Se déconnecter" to onSignOut))
}
