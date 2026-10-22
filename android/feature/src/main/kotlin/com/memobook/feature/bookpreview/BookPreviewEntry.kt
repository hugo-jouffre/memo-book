package com.memobook.feature.bookpreview

import androidx.compose.runtime.Composable
import com.memobook.feature.AppDependencies
import com.memobook.feature.BookPreviewIntent
import com.memobook.feature.debug.PortPending

/**
 * L'aperçu du carnet : la composition, puis le PDF qu'on feuillette. `opensShare` l'ouvre sur sa feuille de partage.
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.… }`) et appelle la vue. Sa signature est le
 * contrat avec `RootView` ; tout le reste se porte depuis `BookPreview/BookPreviewFlowView.swift`.
 */
@Composable
fun BookPreviewEntry(dependencies: AppDependencies, memoId: String, opensShare: Boolean, onIntent: (BookPreviewIntent) -> Unit, onBack: () -> Unit) {
    PortPending("Aperçu du carnet", "BookPreview/BookPreviewFlowView.swift", onBack = onBack, actions = listOf("Commander ce carnet" to { onIntent(BookPreviewIntent.Order) }))
}
