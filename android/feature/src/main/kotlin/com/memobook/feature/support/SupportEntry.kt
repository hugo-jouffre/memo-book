package com.memobook.feature.support

import androidx.compose.runtime.Composable
import com.memobook.feature.AppDependencies

/**
 * Le support : FAQ, votes, formulaire. `tripId` : le voyage d'où l'on vient, qui part avec le message (T226).
 *
 * La porte d'entrée de `RootView` vers cet écran. **Un seul modèle de support
 * pour la session** ([rememberSessionSupportModel]) : les votes déjà donnés ne
 * se redemandent pas parce qu'on a refermé l'écran entre-temps, et le paywall
 * ouvre le même.
 */
@Composable
fun SupportEntry(dependencies: AppDependencies, tripId: String?, onBack: () -> Unit) {
    SupportView(rememberSessionSupportModel(dependencies), onBack = onBack, tripId = tripId)
}
