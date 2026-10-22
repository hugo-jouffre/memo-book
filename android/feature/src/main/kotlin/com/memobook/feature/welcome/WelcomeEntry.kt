package com.memobook.feature.welcome

import android.content.pm.ApplicationInfo
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.viewmodel.compose.viewModel
import com.memobook.core.Account
import com.memobook.feature.AppDependencies
import com.memobook.feature.auth.AppleSignInService
import com.memobook.feature.auth.AppleWebReturn
import com.memobook.feature.auth.AuthModel

/**
 * L'écran d'entrée : la photo des carnets, Google, Apple, et « S’inscrire avec un e-mail ».
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.… }`) et appelle la vue. Sa signature est le
 * contrat avec `RootView` ; tout le reste se porte depuis `Welcome/WelcomeView.swift`.
 */
@Composable
fun WelcomeEntry(
    dependencies: AppDependencies,
    onAuthenticated: (Account) -> Unit,
    onEmail: () -> Unit,
    onTermsOfUse: () -> Unit,
    appleReturn: AppleWebReturn? = null,
    onAppleReturnConsumed: () -> Unit = {},
) {
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
        appleReturn = appleReturn,
        onAppleReturnConsumed = onAppleReturnConsumed,
        showsTestingMode = isDebuggable,
    )
}

/**
 * L'entrée par Apple sur le web, quand elle est possible : un Services ID, et le
 * serveur où Apple poste sa réponse. **Toujours celui de production**, même en
 * Debug : Apple n'accepte que l'adresse de retour déclarée sur le Services ID.
 * Le jeton, lui, part ensuite vers le serveur de l'app (le Mac en Debug), qui
 * doit connaître le même `APPLE_SERVICES_ID`. Sans adresse d'API (le bac à
 * sable), pas d'entrée Apple.
 */
private fun AppDependencies.appleEntry(): AppleEntry? {
    val servicesId = appleServicesId ?: return null
    if (apiConfiguration == null) return null
    val redirect = AppleSignInService.redirectUri(productionApiBaseUrl) ?: return null
    return AppleEntry(servicesId, redirect)
}
