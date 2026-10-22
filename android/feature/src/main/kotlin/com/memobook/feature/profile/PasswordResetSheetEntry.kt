package com.memobook.feature.profile

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.design.BrandSheetHost
import com.memobook.feature.AppDependencies

/**
 * La feuille du nouveau mot de passe, ouverte par un lien de réinitialisation **quand on est déjà entré** (Hugo, 29/09/2026). `token` à `null` : rien n'est présenté.
 *
 * La porte d'entrée de `RootView` vers cette feuille : la même que « Modifier
 * mon mot de passe » du profil ([PasswordChangeSheet]), en mode
 * [PasswordChangeModel.Mode.Reset] — le `.brandSheet(item: $signedInResetToken)`
 * de `RootView.swift`. L'adresse n'est pas connue ici : le lien ne la porte
 * pas, et le secret suffit.
 *
 * Un modèle par lien : un second lien ouvre une feuille neuve.
 */
@Composable
fun PasswordResetSheetEntry(dependencies: AppDependencies, token: String?, onDismiss: () -> Unit) {
    val api = dependencies.api
    val model = remember(token) {
        token?.let {
            PasswordChangeModel(
                mode = PasswordChangeModel.Mode.Reset(it),
                email = "",
                reset = { secret, password -> api.resetPassword(secret, password) },
            )
        }
    }
    val isWorking = model?.let { it.state.collectAsStateWithLifecycle().value.isWorking } ?: false

    // Le temps de l'appel, la feuille ne se referme ni au glissé ni au
    // toucher hors d'elle.
    BrandSheetHost(item = model, onDismissRequest = onDismiss, dismissDisabled = isWorking) { shown ->
        PasswordChangeSheet(shown)
    }
}
