package com.memobook.feature.covers

import androidx.compose.runtime.Composable
import com.memobook.feature.AppDependencies

/**
 * Le carrousel des photos de couverture (`CoverCarouselView(kind: .photo)`), sur
 * le modèle **partagé** du parcours — voir [rememberSessionCoversModel].
 *
 * La porte d'entrée de `RootView` vers cet écran. « Valider » revient en
 * arrière, comme le `dismiss()` d'iOS.
 */
@Composable
fun CoverPhotoEntry(dependencies: AppDependencies, tripId: String, onBack: () -> Unit) {
    val model = rememberSessionCoversModel(dependencies, tripId)
    CoverCarouselView(CoverCarouselView.Kind.Photo, model = model, onDismiss = onBack)
}
