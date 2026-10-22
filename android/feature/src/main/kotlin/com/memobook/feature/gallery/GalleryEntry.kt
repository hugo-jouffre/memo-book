package com.memobook.feature.gallery

import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.compose.viewModel
import com.memobook.feature.AppDependencies
import com.memobook.feature.HomeIntent

/**
 * Les carnets de la communauté. Elle **réémet** des intentions de l'accueil.
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`dependencies.galleryModel()`) et appelle la vue. Sa signature est le
 * contrat avec `RootView`.
 */
@Composable
fun GalleryEntry(dependencies: AppDependencies, onIntent: (HomeIntent) -> Unit, onBack: () -> Unit) {
    val model = viewModel { dependencies.galleryModel() }
    GalleryView(model = model, onIntent = onIntent, onBack = onBack)
}
