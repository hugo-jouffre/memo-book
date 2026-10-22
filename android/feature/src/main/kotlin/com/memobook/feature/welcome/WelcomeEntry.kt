package com.memobook.feature.welcome

import androidx.compose.runtime.Composable
import com.memobook.core.Account
import com.memobook.feature.AppDependencies
import com.memobook.feature.debug.PortPending

/**
 * L'écran d'entrée : les carnets d'exemple, Google, Apple, et « Continuer par e-mail ».
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.… }`) et appelle la vue. Sa signature est le
 * contrat avec `RootView` ; tout le reste se porte depuis `Welcome/WelcomeView.swift`.
 */
@Composable
fun WelcomeEntry(dependencies: AppDependencies, onAuthenticated: (Account) -> Unit, onEmail: () -> Unit, onTermsOfUse: () -> Unit) {
    PortPending("Bienvenue", "Welcome/WelcomeView.swift", actions = listOf("Continuer par e-mail" to onEmail, "Conditions d’utilisation" to onTermsOfUse))
}
