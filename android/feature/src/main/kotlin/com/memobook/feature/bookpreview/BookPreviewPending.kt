package com.memobook.feature.bookpreview

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.lifecycle.ViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

// À brancher : BookPreview/BookPreviewModel.swift, BookPreview/BookPreviewFlowView.swift
// (BookPageStage, BookSheetView, BookPageStepper), BookPreview/BookCompositionPage.swift
// (BookCompositionLoop).
//
// Le lot de l'aperçu porte ces pièces ; `BookPreviewSheet` les emploie sous
// leur nom Swift et leur signature probable. Rien ici ne dessine : la feuille
// montre une page vide en attendant. L'intégrateur supprime ce fichier à la
// fusion, et recale `BookPreviewSheet` sur l'état réel du modèle.

/** Le modèle de l'aperçu — `BookPreviewModel(memoId:)`, servi par le jeu d'essai faute de source. */
class BookPreviewModel(val memoId: String) : ViewModel() {
    enum class Stage { Composing, Preview }

    /**
     * @property documentDidFail le `renderer.didFail` d'iOS : le PDF n'a pas pu
     *   se charger.
     */
    data class State(
        val stage: Stage = Stage.Composing,
        val compositionProgress: Double = 0.0,
        val documentDidFail: Boolean = false,
    )

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    /** Le parcours entier : composer, puis montrer. */
    suspend fun run() = Unit

    suspend fun reloadDocument() = Unit
}

/** La boîte de la page — la même pour la composition et pour le PDF. */
@Composable
fun BookPageStage(content: @Composable () -> Unit) {
    Box(Modifier.fillMaxWidth()) { content() }
}

/** La page qui se monte, puis la suivante. */
@Suppress("UNUSED_PARAMETER")
@Composable
fun BookCompositionLoop(firstPass: Double) = Unit

/** La page regardée, avec ses deux commandes posées dessus. */
@Suppress("UNUSED_PARAMETER")
@Composable
fun BookSheetView(model: BookPreviewModel, onExpand: (() -> Unit)?, onConfigureCovers: (() -> Unit)?) = Unit

/** « ‹ Page 4 / 10 › » — de quoi tourner les pages. */
@Suppress("UNUSED_PARAMETER")
@Composable
fun BookPageStepper(model: BookPreviewModel) = Unit
