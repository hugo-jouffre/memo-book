package com.memobook.feature.chat

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.lifecycle.ViewModel
import com.memobook.core.ChatCallToAction
import com.memobook.core.ChatCallToActionState
import com.memobook.core.ChatCopy
import com.memobook.design.BrandButton
import com.memobook.design.BrandText
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing

// À brancher : Chat/ChatModel.swift, Chat/ChatCallToActionCard.swift, Chat/ChatHeader.swift
// (ChatMetrics).
//
// Le lot de la conversation porte ces pièces ; la bulle des notifications et
// le parcours des photos les emploient sous leur nom Swift et leur signature
// probable. L'intégrateur supprime ce fichier à la fusion.

/** Le modèle de la conversation — ce que la bulle des notifications en lit. */
class ChatModel : ViewModel() {
    /** « Ignorer » sous le bouton d'une bulle : retenu sur l'appareil, par identifiant de bulle. */
    @Suppress("UNUSED_PARAMETER")
    fun dismissCallToAction(messageId: String) = Unit
}

/** La bulle de MEMO qui porte un bouton — en attendant son dessin, le texte et le bouton. */
@Composable
fun ChatCallToActionCard(
    text: String,
    callToAction: ChatCallToAction,
    state: ChatCallToActionState,
    onFollow: () -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
        BrandText(text, MemoBookFont.bubble)
        if (state != ChatCallToActionState.Dismissed) {
            BrandButton(callToAction.label, style = BrandButton.Style.Blue, action = onFollow)
            if (callToAction.dismissible) BrandButton(ChatCopy.CallToAction.dismiss, style = BrandButton.Style.Link, action = onDismiss)
        }
    }
}

/** Les mesures de la conversation. */
object ChatMetrics {
    /** Combien de photos une bulle montre, et combien la photothèque laisse choisir. */
    const val visiblePhotoCount = 6
}
