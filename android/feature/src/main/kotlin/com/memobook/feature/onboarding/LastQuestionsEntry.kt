package com.memobook.feature.onboarding

import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.compose.viewModel
import com.memobook.core.Account
import com.memobook.feature.AppDependencies

/**
 * Les « Dernières questions » d'un compte qui vient d'être ouvert. `onFinished` rend le compte, le prénom peut-être corrigé.
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.… }`) et appelle la vue. Sa signature est le
 * contrat avec `RootView` ; tout le reste se porte depuis `Onboarding/LastQuestionsView.swift`.
 *
 * Ce qui est validé part **au profil du compte ouvert** — au double d'aperçu
 * sous `previewSignedIn`, dont l'API est celle du bac à sable. Le modèle est
 * rangé sous le compte : un autre compte repart d'un modèle neuf.
 */
@Composable
fun LastQuestionsEntry(dependencies: AppDependencies, account: Account, onFinished: (Account) -> Unit) {
    val model = viewModel(key = "lastQuestions-${account.id}") {
        LastQuestionsModel(account) { edit -> dependencies.api.updateProfile(edit) }
    }
    LastQuestionsView(model, onFinished)
}
