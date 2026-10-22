package com.memobook.feature.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.memobook.core.BookCopy
import com.memobook.design.BrandButton
import com.memobook.design.BrandSheet
import com.memobook.design.BrandText
import com.memobook.design.ErrorBanner
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing

// À brancher : TripSettings/TripSettingsSheets.swift (`DeleteTripSheet`).
//
// La confirmation avant de supprimer un voyage vit avec les feuilles des
// réglages du voyage, que leur lot porte. L'accueil l'ouvre depuis le tiroir
// d'une carte : la voici sous son nom et sa signature, réduite à son dessin, le
// temps que la vraie arrive. L'intégrateur supprime ce fichier à la fusion.

/**
 * La confirmation avant de supprimer un voyage — le bouton plein garde, le
 * rouge supprime, et le paragraphe dit ce qui part avant qu'on appuie. À
 * présenter dans un `BrandSheetHost` avec `dismissDisabled = isDeleting`.
 *
 * @param tripName le nom du voyage, s'il est arrivé.
 * @param isDeleting la suppression est partie : le bouton rouge tourne.
 * @param errorMessage ce que le serveur a répondu si la suppression a échoué —
 *   il se lit **dans** la feuille.
 */
@Composable
internal fun DeleteTripSheet(
    tripName: String?,
    isDeleting: Boolean,
    errorMessage: String?,
    onKeep: () -> Unit,
    onDelete: () -> Unit,
) {
    BrandSheet(BookCopy.Settings.Delete.title) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
            BrandText(BookCopy.Settings.Delete.body(trip = tripName), MemoBookFont.body, Modifier.fillMaxWidth())

            if (errorMessage != null) ErrorBanner(errorMessage)

            Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
                BrandButton(BookCopy.Settings.Delete.keep, fillsWidth = true, enabled = !isDeleting, action = onKeep)
                BrandButton(
                    BookCopy.Settings.Delete.confirm,
                    style = BrandButton.Style.Destructive,
                    isLoading = isDeleting,
                    fillsWidth = true,
                    action = onDelete,
                )
            }
        }
    }
}
