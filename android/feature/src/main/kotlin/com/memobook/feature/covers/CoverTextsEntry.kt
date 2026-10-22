package com.memobook.feature.covers

import androidx.compose.runtime.Composable
import com.memobook.feature.AppDependencies

/**
 * Les deux textes des plats, sur le modèle **partagé** du parcours — voir
 * [rememberSessionCoversModel].
 *
 * La porte d'entrée de `RootView` vers cet écran. « Valider » revient en
 * arrière, comme le `dismiss()` d'iOS.
 */
@Composable
fun CoverTextsEntry(dependencies: AppDependencies, tripId: String, onBack: () -> Unit) {
    val model = rememberSessionCoversModel(dependencies, tripId)
    CoverTextsView(model = model, onDismiss = onBack)
}
