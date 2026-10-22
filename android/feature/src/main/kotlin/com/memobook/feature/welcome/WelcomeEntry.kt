package com.memobook.feature.welcome

import android.content.pm.ApplicationInfo
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.viewmodel.compose.viewModel
import com.memobook.core.Account
import com.memobook.feature.AppDependencies
import com.memobook.feature.auth.AuthModel

/**
 * L'écran d'entrée : la photo des carnets, Google, et « S’inscrire avec un e-mail ».
 * Pas d'Apple sur Android — voir [WelcomeView].
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.… }`) et appelle la vue. Sa signature est le
 * contrat avec `RootView` ; tout le reste se porte depuis `Welcome/WelcomeView.swift`.
 */
@Composable
fun WelcomeEntry(dependencies: AppDependencies, onAuthenticated: (Account) -> Unit, onEmail: () -> Unit, onTermsOfUse: () -> Unit) {
    val model = viewModel { AuthModel(dependencies.api, dependencies.settings) }
    val context = LocalContext.current
    // Le `#if DEBUG` d'iOS, lu à l'exécution : un build Release n'est pas débogable.
    val isDebuggable = remember(context) { context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0 }
    WelcomeView(
        model = model,
        onAuthenticated = onAuthenticated,
        onEmail = onEmail,
        onTermsOfUse = onTermsOfUse,
        googleWebClientId = dependencies.googleWebClientId,
        showsTestingMode = isDebuggable,
    )
}
