package com.memobook.feature.legal

import androidx.compose.runtime.Composable
import com.memobook.core.LegalDocument
import com.memobook.feature.AppDependencies
import com.memobook.feature.LegalIntent
import com.memobook.feature.debug.PortPending

/**
 * Un document légal. Sans « Besoin d'aide ? » hors session (`showsHelp`, T151).
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.… }`) et appelle la vue. Sa signature est le
 * contrat avec `RootView` ; tout le reste se porte depuis `Legal/LegalDocumentView.swift`.
 */
@Composable
fun LegalDocumentEntry(document: LegalDocument, showsHelp: Boolean, onIntent: (LegalIntent) -> Unit, onBack: () -> Unit) {
    PortPending("Document légal", "Legal/LegalDocumentView.swift", onBack = onBack)
}
