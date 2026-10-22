package com.memobook.feature.onboarding

import androidx.compose.runtime.Composable
import com.memobook.core.Account
import com.memobook.feature.AppDependencies
import com.memobook.feature.debug.PortPending

/**
 * Les « Dernières questions » d'un compte qui vient d'être ouvert. `onFinished` rend le compte, le prénom peut-être corrigé.
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.… }`) et appelle la vue. Sa signature est le
 * contrat avec `RootView` ; tout le reste se porte depuis `Onboarding/LastQuestionsView.swift`.
 */
@Composable
fun LastQuestionsEntry(dependencies: AppDependencies, account: Account, onFinished: (Account) -> Unit) {
    PortPending("Dernières questions", "Onboarding/LastQuestionsView.swift", actions = listOf("Passer" to { onFinished(account) }))
}
