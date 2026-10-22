package com.memobook.feature.auth

import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.compose.viewModel
import com.memobook.core.Account
import com.memobook.feature.AppDependencies

/**
 * Inscription et connexion par e-mail. `resetToken` : le secret d'un lien « Réinitialiser mon mot de passe » ouvert depuis l'e-mail, que l'écran consomme.
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.… }`) et appelle la vue. Sa signature est le
 * contrat avec `RootView` ; tout le reste se porte depuis `Auth/AuthView.swift`.
 */
@Composable
fun AuthEntry(dependencies: AppDependencies, resetToken: String?, onResetTokenConsumed: () -> Unit, onAuthenticated: (Account) -> Unit, onBack: () -> Unit) {
    val model = viewModel { AuthModel(dependencies.api, dependencies.settings) }
    AuthView(
        model = model,
        api = dependencies.api,
        resetToken = resetToken,
        onResetTokenConsumed = onResetTokenConsumed,
        onAuthenticated = onAuthenticated,
        onBack = onBack,
    )
}
