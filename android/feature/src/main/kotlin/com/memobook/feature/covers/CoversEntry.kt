package com.memobook.feature.covers

import androidx.compose.runtime.Composable
import com.memobook.feature.AppDependencies
import com.memobook.feature.CoversIntent

/**
 * Les deux plats du carnet. Le modèle est **partagé** par les quatre écrans du
 * parcours (`LocalSessionViewModelStoreOwner`) — voir [rememberSessionCoversModel].
 *
 * La porte d'entrée de `RootView` vers cet écran : elle prend le modèle de la
 * session et appelle la vue.
 */
@Composable
fun CoversEntry(dependencies: AppDependencies, tripId: String, onIntent: (CoversIntent) -> Unit, onBack: () -> Unit) {
    val model = rememberSessionCoversModel(dependencies, tripId)
    CoversView(model = model, onIntent = onIntent, onBack = onBack)
}
