package com.memobook.feature.bookpreview

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.memobook.core.BookCopy
import com.memobook.design.BrandButton
import com.memobook.design.BrandSheet
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandSkeleton
import com.memobook.design.ErrorBanner
import com.memobook.design.MemoBookSpacing
import com.memobook.design.SwiftMotion
import kotlinx.coroutines.launch

/**
 * « Prévisualisation » : le carnet qu'on feuillette, **sans quitter l'offre**.
 * Jumeau de `BookPreview/BookPreviewSheet.swift`.
 *
 * C'est ce qu'ouvre la pastille « Voir un aperçu » du paywall — la feuille
 * d'abonnement en portait une aussi, partie avec sa page « Comment ça
 * fonctionne ? » (03/10/2026). Une feuille et non un écran poussé, et c'est
 * tout le sujet : quelqu'un à qui l'on est en train de proposer un abonnement
 * veut voir ce qu'il achète, puis **revenir à l'offre**. Un écran poussé
 * l'aurait sorti du parcours de vente, et la flèche de retour ne l'y aurait pas
 * ramené au même endroit.
 *
 * Elle réutilise les pièces de l'aperçu — [BookPageStage], [BookSheetView],
 * [BookPageStepper] — plutôt que d'en redessiner de plus petites. C'est la même
 * page et le même geste ; en refaire une version « pour la feuille » aurait
 * donné deux aperçus à tenir d'accord, et celui de la feuille aurait vieilli le
 * premier.
 *
 * @param memoId le carnet à montrer. `null` — le cas d'un compte qui n'a pas
 *   encore de voyage en cours — ouvre le jeu d'essai : la feuille existe pour
 *   **montrer à quoi ça ressemble**, et un aperçu vide ne vendrait rien.
 * @param onBack le retour à l'étape d'où l'on vient. `null` quand la feuille
 *   est présentée seule — le paywall la referme par son geste de feuille, il
 *   n'y a rien derrière elle.
 */
@Composable
fun BookPreviewSheet(memoId: String?, onBack: (() -> Unit)? = null) {
    val id = memoId ?: "preview"
    val model = viewModel(key = "bookPreviewSheet.$id") { BookPreviewModel(memoId = id) }
    val state by model.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    BrandSheet(BookCopy.Preview.sheetTitle) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            BookPageStage {
                AnimatedContent(
                    targetState = state.stage,
                    transitionSpec = { fadeIn(SwiftMotion.smooth(0.3f)) togetherWith fadeOut(SwiftMotion.smooth(0.3f)) },
                    label = "étape",
                ) { stage ->
                    when (stage) {
                        // La même attente que l'écran de l'aperçu : la page qui
                        // se monte, puis la suivante (08/10/2026).
                        BookPreviewModel.Stage.Composing -> BookCompositionLoop(firstPass = state.compositionProgress)
                        // Pas de plein écran depuis la feuille : il faudrait en
                        // sortir pour y entrer, et on ne reviendrait pas à
                        // l'offre. La commande est donc absente, et non
                        // désactivée — un bouton qui ne fait rien est pire que
                        // pas de bouton. Même chose pour « Configurer » : les
                        // couvertures sont un écran, et la feuille n'a pas de
                        // pile où le poser.
                        BookPreviewModel.Stage.Preview -> BookSheetView(model, onExpand = null, onConfigureCovers = null)
                    }
                }
            }

            // L'indicateur de pages attend que la page soit montée : le montrer
            // pendant la composition annoncerait des pages qu'on ne peut pas
            // encore tourner.
            if (state.stage == BookPreviewModel.Stage.Preview) {
                BookPageStepper(model)
            } else {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .padding(vertical = MemoBookSpacing.snug),
                    contentAlignment = Alignment.Center,
                ) { BrandSkeleton(width = 96.dp) }
            }

            if (state.documentDidFail) {
                ErrorBanner(BookCopy.Preview.loadFailed, retry = { scope.launch { model.reloadDocument() } })
            }

            if (onBack != null) {
                BrandButton(
                    BookCopy.Preview.backToOffer,
                    modifier = Modifier.padding(top = MemoBookSpacing.xs),
                    style = BrandButton.Style.Secondary,
                    fillsWidth = true,
                    action = onBack,
                )
            }
        }
    }

    // La composition se joue **aussi ici** : la page se monte sous les yeux
    // avant de se laisser feuilleter, exactement comme sur l'écran d'aperçu.
    // C'est ce que la maquette du paywall montre, et c'est ce qui donne envie de
    // tourner la page.
    LaunchedEffect(model) { model.run() }
}

@Preview(locale = "fr-rFR", name = "Feuille de prévisualisation", heightDp = 800)
@Composable
private fun BookPreviewSheetPreview() {
    BrandSheetHost(isPresented = true, onDismissRequest = {}) {
        BookPreviewSheet(memoId = null)
    }
}
