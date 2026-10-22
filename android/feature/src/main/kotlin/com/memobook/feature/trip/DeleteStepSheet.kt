package com.memobook.feature.trip

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.memobook.core.TripStep
import com.memobook.design.BrandButton
import com.memobook.design.BrandSheet
import com.memobook.design.BrandText
import com.memobook.design.ErrorBanner
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing

/**
 * La confirmation avant d'effacer ce qu'on a raconté d'une étape — la croix
 * de son tiroir (T235, Hugo, 06/10/2026 : « même comportement que les cartes
 * de voyage dans l'accueil général »). Jumeau de `Trip/DeleteStepSheet.swift`.
 *
 * **Le dessin de « Supprimer ce voyage »** (`DeleteTripSheet`) : le bouton
 * plein garde, le rouge efface, et le paragraphe dit ce qui part avant qu'on
 * appuie. Une étape peut porter plusieurs souvenirs — un vocal, un texte,
 * des photos : la phrase le dit au pluriel quand c'est le cas, pour qu'on ne
 * croie pas n'effacer que la vignette.
 *
 * À présenter dans un `BrandSheetHost` qui reçoit `dismissDisabled = isDeleting`
 * — le `interactiveDismissDisabled` d'iOS.
 *
 * @param isDeleting l'effacement est parti : le bouton rouge tourne et plus
 *   rien ne se touche — la demande est définitive, elle ne part pas deux fois.
 * @param errorMessage ce que le serveur a répondu si l'effacement a échoué. Il
 *   se lit **dans** la feuille, comme pour un voyage.
 */
@Composable
fun DeleteStepSheet(
    step: TripStep,
    isDeleting: Boolean,
    errorMessage: String?,
    onKeep: () -> Unit,
    onDelete: () -> Unit,
) {
    val count = step.entryIds?.size ?: 0

    BrandSheet(DeleteStepCopy.title(count)) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
            BrandText(
                DeleteStepCopy.body(step.title, count),
                MemoBookFont.body,
                Modifier.fillMaxWidth(),
                color = MemoBookColor.ink,
            )

            if (errorMessage != null) {
                ErrorBanner(errorMessage)
            }

            Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
                BrandButton(DeleteStepCopy.keep(count), fillsWidth = true, enabled = !isDeleting, action = onKeep)

                BrandButton(
                    DeleteStepCopy.confirm,
                    style = BrandButton.Style.Destructive,
                    isLoading = isDeleting,
                    fillsWidth = true,
                    action = onDelete,
                )
            }
        }
    }
}

/**
 * Les mots de la feuille. Pas de maquette : ils suivent ceux de « Supprimer
 * ce voyage » (`BookCopy.Settings.Delete`), au tutoiement.
 */
object DeleteStepCopy {
    fun title(count: Int): String =
        if (count > 1) {
            "Tu es sûr de vouloir supprimer les souvenirs de cette étape ?"
        } else {
            "Tu es sûr de vouloir supprimer ce souvenir ?"
        }

    fun body(step: String, count: Int): String {
        val what = if (count > 1) {
            "Tout ce qui a été raconté pour « $step » — vocaux, textes et photos —"
        } else {
            "Le souvenir de « $step »"
        }
        return "$what sera effacé du carnet, pour toi comme pour tes co-voyageurs. C’est immédiat et sans retour."
    }

    fun keep(count: Int): String = if (count > 1) "Garder ces souvenirs" else "Garder ce souvenir"

    const val confirm = "Supprimer définitivement"

    /** Le libellé de la croix, pour TalkBack et le menu de l'appui long. */
    fun action(step: String): String = "Supprimer les souvenirs de « $step »"

    /** Le mot qui s'efface tout seul, une fois fait. */
    fun done(count: Int): String = if (count > 1) "Souvenirs supprimés." else "Souvenir supprimé."
}

@Preview(locale = "fr-rFR", name = "Supprimer les souvenirs d'une étape", widthDp = 390)
@Composable
private fun DeleteStepSheetPreview() {
    Box(Modifier.background(MemoBookColor.background)) {
        DeleteStepSheet(
            step = TripStep(id = "a", number = 2, entryIds = listOf("e1", "e2")),
            isDeleting = false,
            errorMessage = null,
            onKeep = {},
            onDelete = {},
        )
    }
}
