package com.memobook.feature.legal

import androidx.compose.runtime.Composable
import com.memobook.core.LegalDocument
import com.memobook.feature.LegalIntent

/**
 * Un document légal. Sans « Besoin d'aide ? » hors session (`showsHelp`, T151).
 *
 * La porte d'entrée de `RootView` vers cet écran : il n'a pas de modèle — le
 * texte appartient à l'app — et appelle la vue. Sa signature est le contrat
 * avec `RootView` ; tout le reste se porte depuis `Legal/LegalDocumentView.swift`.
 */
@Composable
fun LegalDocumentEntry(document: LegalDocument, showsHelp: Boolean, onIntent: (LegalIntent) -> Unit, onBack: () -> Unit) {
    LegalDocumentView(document = document, onBack = onBack, showsHelp = showsHelp, onIntent = onIntent)
}
