package com.memobook.feature.tripsettings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import com.memobook.design.BrandButton
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.brandDashedCard
import kotlinx.coroutines.launch

/**
 * Le bac à sable des paramètres du voyage : de quoi voir l'écran pendant que
 * ses valeurs arrivent, sans mauvais réseau. Jumeau de
 * `TripSettings/TripSettingsDebugPanel.swift`.
 *
 * **Il n'existe pas dans l'app livrée.** Sur iOS, le fichier entier est sous
 * `#if DEBUG` ; ici, la porte ne le pose que dans une app déboguable — voir
 * `TripSettingsEntry`.
 *
 * Peu de boutons, et c'est normal : l'écran n'a qu'un état que les maquettes
 * ne dessinent pas — celui où les barres d'attente tiennent la place des
 * valeurs. Le reste se voit en jeu d'essai.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun TripSettingsDebugPanel(model: TripSettingsModel) {
    val scope = rememberCoroutineScope()

    Column(
        Modifier
            .fillMaxWidth()
            .brandDashedCard(color = MemoBookColor.separator)
            .padding(MemoBookSpacing.s),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        BrandText("Bac à sable — absent de l’app livrée", MemoBookFont.caption, color = MemoBookColor.inkMuted)

        DebugRow {
            DebugButton("Barres d’attente", model::debugShowSkeleton)
            DebugButton("Recharger") { scope.launch { model.load() } }
        }

        // Le crédit du jour : le neuf, les 30 dernières secondes, l'épuisé et
        // l'abonné. Le jeu d'essai n'en montre qu'un (un voyage entamé,
        // 3 min 20 devant soi) ; la jauge rouge et la ligne « Illimité » ne se
        // voient qu'ici.
        DebugRow {
            DebugButton("Crédit neuf") { model.debugPlayDailyCredit(TripSettingsModel.DailyCreditDebugState.Fresh) }
            DebugButton("30 s") { model.debugPlayDailyCredit(TripSettingsModel.DailyCreditDebugState.LastSeconds) }
            DebugButton("Épuisé") { model.debugPlayDailyCredit(TripSettingsModel.DailyCreditDebugState.Exhausted) }
            DebugButton("Abonné") { model.debugPlayDailyCredit(TripSettingsModel.DailyCreditDebugState.Unlimited) }
        }

        // De quoi remplir « Co-voyageur(s) » : le jeu d'essai en compte deux,
        // et le tiroir de retrait comme la relance d'invitation demandent d'en
        // avoir plusieurs, dont un en attente.
        DebugRow {
            DebugButton("+ Un co-voyageur", model::debugAddCompanion)
        }
    }
}

/** Une rangée de boutons qui passe à la ligne : quatre boutons ne tiennent pas sur un petit téléphone. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun DebugRow(content: @Composable () -> Unit) {
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) { content() }
}

/** Le bouton « bordé » d'iOS, teinté du vert d'action : le petit bouton doux de la marque. */
@Composable
private fun DebugButton(title: String, action: () -> Unit) {
    BrandButton(title, style = BrandButton.Style.Soft, size = BrandButton.Size.Small, action = action)
}
