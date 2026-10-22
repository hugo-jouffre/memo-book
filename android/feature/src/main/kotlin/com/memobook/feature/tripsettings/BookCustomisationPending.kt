package com.memobook.feature.tripsettings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import com.memobook.design.MemoBookColor
import java.io.File

// Les pièces du lot de l'aperçu que `BookPagesPeek` emploie, sous leur nom
// Swift et la signature qu'elles ont dans ce lot (`bookpreview/BookPageRenderer.kt`).
// Rien ici ne rend de PDF : les deux pages restent le papier nu, ce qu'elles
// sont de toute façon en tête des personnalisations. **L'intégrateur supprime
// ce fichier à la fusion** et importe les vraies depuis
// `com.memobook.feature.bookpreview`.

// MARK: - À brancher : BookPreview/BookPageRenderer.swift (lot de l'aperçu)

/** Le PDF du carnet, et ses pages rendues à la demande. Ici, un document qui ne s'ouvre jamais. */
internal class BookPageRenderer(@Suppress("unused") private val directory: File) {
    /** Ce que l'écran sait du document — la même forme que la vraie. */
    data class Document(
        val sheetCount: Int = 0,
        val didFail: Boolean = false,
        val aspectRatio: Float = 1f / 1.414f,
        val generation: Int = 0,
    )

    var document: Document = Document()
        private set

    @Suppress("RedundantSuspendModifier", "UNUSED_PARAMETER")
    suspend fun load(url: String): Document = document

    fun close() = Unit
}

/** Une feuille du carnet, rendue depuis le PDF. Ici, le papier nu. */
@Composable
internal fun BookSheetImage(
    @Suppress("UNUSED_PARAMETER") renderer: BookPageRenderer,
    @Suppress("UNUSED_PARAMETER") document: BookPageRenderer.Document,
    @Suppress("UNUSED_PARAMETER") index: Int,
    modifier: Modifier = Modifier,
    showsPlaceholder: Boolean = true,
) {
    Box(modifier.clearAndSetSemantics {}.then(if (showsPlaceholder) Modifier.background(MemoBookColor.paper) else Modifier))
}
