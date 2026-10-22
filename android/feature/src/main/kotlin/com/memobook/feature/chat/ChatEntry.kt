package com.memobook.feature.chat

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.viewmodel.compose.viewModel
import com.memobook.feature.AppDependencies
import com.memobook.feature.ChatIntent
import com.memobook.feature.recording.RecordingHandoff

/**
 * La conversation avec MEMO. `handoff` : le vocal enregistré depuis l'accueil,
 * déjà parti, que la bulle suit.
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * ([chatModel]) et appelle la vue ([ChatView]). Sa signature est le contrat
 * avec `RootView`.
 *
 * Le micro, le lecteur et la voix se construisent ici, sur le contexte de
 * l'**application** ([ChatAudio]) : le modèle survit à l'activité, il ne doit
 * pas la retenir.
 *
 * Le vocal de l'accueil s'annonce au modèle **avant** son premier chargement —
 * le `model.expect(handoff)` de l'`init` de `ChatView` sur iOS. Le reposer à
 * chaque retour sur l'écran ne double rien : déjà dans le fil, la bulle ne
 * gagne que son fichier.
 */
@Composable
fun ChatEntry(
    dependencies: AppDependencies,
    tripId: String,
    stepId: String?,
    handoff: RecordingHandoff?,
    onIntent: (ChatIntent) -> Unit,
    onBack: () -> Unit,
) {
    val application = LocalContext.current.applicationContext
    val model = viewModel {
        dependencies.chatModel(tripId = tripId, stepId = stepId, audio = ChatAudio(application, application.cacheDir))
    }
    remember(model, handoff) {
        if (handoff != null) model.expect(handoff)
        handoff
    }
    ChatView(
        model = model,
        tripId = tripId,
        onIntent = onIntent,
        onBack = onBack,
        stepId = stepId,
        arrivesWithRecording = handoff != null,
    )
}
