package com.memobook.feature.bookpreview

import android.content.pm.ApplicationInfo
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.viewmodel.compose.viewModel
import com.memobook.feature.AppDependencies
import com.memobook.feature.BookPreviewIntent
import com.memobook.feature.LocalTripsAwaitingServer
import com.memobook.feature.support.rememberSessionSupportModel

/**
 * L'aperçu du carnet : la composition, puis le PDF qu'on feuillette. `opensShare` l'ouvre sur sa feuille de partage.
 *
 * La porte d'entrée de `RootView` vers cet écran : elle construit le modèle
 * ([bookPreviewModel]) et appelle [BookPreviewFlowView]. Trois choses lui
 * viennent de l'app plutôt que de l'écran :
 *
 * - **le cache de l'app**, où le PDF s'écrit pour `PdfRenderer` et pour la
 *   feuille de partage ;
 * - **le `#if DEBUG` d'iOS**, lu à l'exécution : un build Release n'est pas
 *   débogable, et n'ouvre jamais l'aperçu sur des pages blanches ;
 * - **le support de la session** ([rememberSessionSupportModel]), que « Partager
 *   mes retours » du mot des fondateurs ouvre sur son formulaire.
 *
 * Un voyage créé hors ligne que le serveur n'a pas encore reçu
 * ([LocalTripsAwaitingServer], T239) n'a pas de carnet à composer : l'aperçu
 * pâlit et le dit, et la composition part d'elle-même quand le voyage arrive.
 */
@Composable
fun BookPreviewEntry(dependencies: AppDependencies, memoId: String, opensShare: Boolean, onIntent: (BookPreviewIntent) -> Unit, onBack: () -> Unit) {
    val context = LocalContext.current
    val isDebuggable = remember(context) { context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0 }
    val model = viewModel {
        dependencies.bookPreviewModel(memoId, cacheDirectory = context.cacheDir, opensBlankPages = isDebuggable)
    }

    BookPreviewFlowView(
        model = model,
        onIntent = onIntent,
        onBack = onBack,
        opensShare = opensShare,
        support = rememberSessionSupportModel(dependencies),
        isAwaitingServer = memoId in LocalTripsAwaitingServer.current,
    )
}
