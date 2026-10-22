package com.memobook.feature.chat

import androidx.compose.runtime.Composable
import com.memobook.feature.AppDependencies
import com.memobook.feature.ChatIntent
import com.memobook.feature.debug.PortPending
import com.memobook.feature.recording.RecordingHandoff

/**
 * La conversation avec MEMO. `handoff` : le vocal enregistré depuis l'accueil, déjà parti, que la bulle suit.
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * (`viewModel { dependencies.… }`) et appelle la vue. Sa signature est le
 * contrat avec `RootView` ; tout le reste se porte depuis `Chat/ChatView.swift`.
 */
@Composable
fun ChatEntry(dependencies: AppDependencies, tripId: String, stepId: String?, handoff: RecordingHandoff?, onIntent: (ChatIntent) -> Unit, onBack: () -> Unit) {
    PortPending("Conversation", "Chat/ChatView.swift", onBack = onBack)
}
