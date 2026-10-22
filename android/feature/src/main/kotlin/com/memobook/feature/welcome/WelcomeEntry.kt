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
 * L'écran d'entrée : la photo des carnets, Google, Apple, et « S’inscrire avec un e-mail ».
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
    val apple = remember(dependencies) { dependencies.appleEntry() }
    WelcomeView(
        model = model,
        onAuthenticated = onAuthenticated,
        onEmail = onEmail,
        onTermsOfUse = onTermsOfUse,
        googleWebClientId = dependencies.googleWebClientId,
        apple = apple,
        showsTestingMode = isDebuggable,
    )
}

/**
 * L'entrée par Apple sur le web, quand elle est possible : un Services ID, et un
 * serveur où Apple poste sa réponse. Le nom de la route est celui que le lot B2
 * posera ; sans adresse d'API (le bac à sable), pas d'entrée Apple.
 */
private fun AppDependencies.appleEntry(): AppleEntry? {
    val servicesId = appleServicesId ?: return null
    val base = apiConfiguration?.baseUrl ?: return null
    return AppleEntry(servicesId, base.resolve("/v1/auth/apple/callback"))
}
