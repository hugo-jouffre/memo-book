package com.memobook.feature.trip

import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.compose.viewModel
import com.memobook.feature.AppDependencies
import com.memobook.feature.TripIntent

/**
 * L'accueil d'un voyage : en-tête, étapes, validation, suppression d'étape.
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * ([tripModel]) et appelle la vue. Le modèle est rangé sous l'identifiant du
 * voyage, dans le magasin de la destination : deux voyages ouverts l'un
 * par-dessus l'autre ont chacun le leur.
 */
@Composable
fun TripHomeEntry(dependencies: AppDependencies, tripId: String, onIntent: (TripIntent) -> Unit, onBack: () -> Unit) {
    val model = viewModel(key = "trip-$tripId") { dependencies.tripModel(tripId) }
    TripHomeView(model, onIntent = onIntent, onBack = onBack)
}
