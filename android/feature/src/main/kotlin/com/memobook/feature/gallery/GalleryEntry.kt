package com.memobook.feature.gallery

import androidx.compose.runtime.Composable
import com.memobook.feature.AppDependencies
import com.memobook.feature.HomeIntent
import com.memobook.feature.debug.PortPending

/**
 * Les carnets de la communauté. Elle **réémet** des intentions de l'accueil.
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.… }`) et appelle la vue. Sa signature est le
 * contrat avec `RootView` ; tout le reste se porte depuis `Gallery/GalleryView.swift`.
 */
@Composable
fun GalleryEntry(dependencies: AppDependencies, onIntent: (HomeIntent) -> Unit, onBack: () -> Unit) {
    PortPending("Galerie", "Gallery/GalleryView.swift", onBack = onBack)
}
