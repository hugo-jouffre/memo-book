package com.memobook.feature.tripsettings

import android.content.pm.ApplicationInfo
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.viewmodel.compose.viewModel
import com.memobook.feature.AppDependencies
import com.memobook.feature.TripSettingsIntent
import com.memobook.feature.TripSettingsSheet
import com.memobook.feature.support.LocalSupportModel
import com.memobook.feature.support.rememberSessionSupportModel

/**
 * Les réglages d'un voyage et leurs feuilles. `opening` : la feuille à ouvrir en arrivant.
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.tripSettingsModel(tripId) }`) et appelle la vue.
 * Elle pose aussi, pour le paywall que la feuille du crédit du jour ouvre, le
 * support **de la session** (« Besoin d'aide ? » l'ouvre par-dessus l'offre),
 * et dit à la vue si l'app est déboguable — le `#if DEBUG` du bac à sable.
 *
 * Après la suppression du voyage, la vue remonte
 * [TripSettingsIntent.TripDeleted] : `RootView` vide la pile.
 */
@Composable
fun TripSettingsEntry(dependencies: AppDependencies, tripId: String, opening: TripSettingsSheet?, onIntent: (TripSettingsIntent) -> Unit, onBack: () -> Unit) {
    val model = viewModel { dependencies.tripSettingsModel(tripId) }
    val context = LocalContext.current
    val isDebuggable = remember(context) { context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0 }
    val support = LocalSupportModel.current ?: rememberSessionSupportModel(dependencies)

    CompositionLocalProvider(LocalSupportModel provides support) {
        TripSettingsView(
            model = model,
            onIntent = onIntent,
            onBack = onBack,
            opening = opening,
            inviteBase = dependencies.productionApiBaseUrl,
            showsDebugPanel = isDebuggable,
        )
    }
}
