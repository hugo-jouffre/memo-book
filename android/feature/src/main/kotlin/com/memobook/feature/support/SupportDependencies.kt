package com.memobook.feature.support

import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import com.memobook.feature.AppDependencies
import com.memobook.feature.LocalSessionViewModelStoreOwner

/**
 * Le support du compte ouvert : le modèle naît branché sur les trois routes du
 * support (T226) — le `support.connect(SupportBackend(api:))` que `RootView`
 * pose sur iOS à chaque compte. Ici, le magasin de la session est vidé quand le
 * compte change : le modèle suivant naît avec l'API du suivant.
 *
 * @param appVersion « 0.1.0 (21) » — voir [SupportDevice.appVersion].
 */
fun AppDependencies.supportModel(appVersion: String?): SupportModel =
    SupportModel(backend = SupportBackend(api, appVersion), appVersion = appVersion)

/**
 * **Le** support de la session : le même modèle d'une porte à l'autre — la
 * destination « Besoin d'aide ? », le paywall —, rangé dans
 * [LocalSessionViewModelStoreOwner] sous la clé `support`. Hors session (un
 * aperçu), le magasin de la destination.
 */
@Composable
fun rememberSessionSupportModel(dependencies: AppDependencies): SupportModel {
    val context = LocalContext.current
    val owner = LocalSessionViewModelStoreOwner.current
        ?: checkNotNull(LocalViewModelStoreOwner.current) { "Le support demande un magasin de modèles." }
    return viewModel(viewModelStoreOwner = owner, key = "support") {
        dependencies.supportModel(SupportDevice.appVersion(context))
    }
}
