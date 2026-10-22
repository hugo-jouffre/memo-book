package com.memobook.feature.tripcreation

import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.compose.viewModel
import com.memobook.feature.AppDependencies
import com.memobook.feature.HomeIntent

/**
 * Les six étapes de « Créer un voyage ». « Commencer ! » réémet `HomeIntent.OpenTrip`.
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * ([tripCreationModel]) et appelle la vue. Le lien d'invitation de la dernière
 * étape part de l'adresse de **production** — un lien de développement ne
 * mènerait nulle part sur le téléphone de l'invité.
 */
@Composable
fun TripCreationEntry(dependencies: AppDependencies, onIntent: (HomeIntent) -> Unit, onBack: () -> Unit) {
    val model = viewModel { dependencies.tripCreationModel() }
    TripCreationView(model, inviteBase = dependencies.productionApiBaseUrl, onIntent = onIntent, onBack = onBack)
}
