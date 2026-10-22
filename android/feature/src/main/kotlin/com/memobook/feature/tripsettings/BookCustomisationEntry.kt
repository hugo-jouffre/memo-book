package com.memobook.feature.tripsettings

import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.compose.viewModel
import com.memobook.feature.AppDependencies
import com.memobook.feature.BookCustomisationIntent

/**
 * Les personnalisations du carnet : ratio, pages, décorations, typos, extras.
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.bookCustomisationModel(tripId) }`) et appelle la
 * vue. Un modèle par destination, comme sur iOS : `RootView.swift` en fabrique
 * un neuf à chaque ouverture de l'écran.
 */
@Composable
fun BookCustomisationEntry(dependencies: AppDependencies, tripId: String, onIntent: (BookCustomisationIntent) -> Unit, onBack: () -> Unit) {
    val model = viewModel { dependencies.bookCustomisationModel(tripId) }
    BookCustomisationView(model = model, onIntent = onIntent, onBack = onBack)
}
