package com.memobook.feature.home

import android.content.pm.ApplicationInfo
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.viewmodel.compose.viewModel
import com.memobook.feature.AppDependencies
import com.memobook.feature.HomeIntent
import com.memobook.feature.support.LocalSupportModel
import com.memobook.feature.support.rememberSessionSupportModel

/**
 * L'accueil : les cartes des voyages, le tiroir d'actions, le micro, la boîte hors ligne.
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`dependencies.homeModel()`) et appelle la vue. Sa signature est le contrat
 * avec `RootView`.
 *
 * Elle pose aussi, pour le paywall que l'alerte de fin d'abonnement ouvre, le
 * support **de la session** — « Besoin d'aide ? » l'ouvre par-dessus l'offre,
 * comme depuis le profil.
 */
@Composable
fun HomeEntry(dependencies: AppDependencies, onIntent: (HomeIntent) -> Unit) {
    val model = viewModel { dependencies.homeModel() }
    val context = LocalContext.current
    // Le `#if DEBUG` d'iOS, lu à l'exécution : un build Release n'est pas
    // débogable, et le bac à sable de l'accueil n'y existe pas.
    val isDebuggable = remember(context) { context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0 }
    val support = LocalSupportModel.current ?: rememberSessionSupportModel(dependencies)

    CompositionLocalProvider(LocalSupportModel provides support) {
        HomeView(model = model, onIntent = onIntent, showsSandbox = isDebuggable)
    }
}
