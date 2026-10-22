package com.memobook.feature.profile

import androidx.compose.runtime.Composable
import com.memobook.feature.AppDependencies

/**
 * La feuille du nouveau mot de passe, ouverte par un lien de réinitialisation **quand on est déjà entré** (Hugo, 29/09/2026). `token` à `null` : rien n'est présenté.
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.… }`) et appelle la vue. Sa signature est le
 * contrat avec `RootView` ; tout le reste se porte depuis `Profile/PasswordChangeSheet.swift`.
 */
@Composable
fun PasswordResetSheetEntry(dependencies: AppDependencies, token: String?, onDismiss: () -> Unit) {
    if (token == null) return
}
