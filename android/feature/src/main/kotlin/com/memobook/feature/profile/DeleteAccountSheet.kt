package com.memobook.feature.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import com.memobook.design.BrandButton
import com.memobook.design.BrandSheet
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing

/**
 * La confirmation avant de supprimer son compte — **une feuille de l'app**, pas
 * une alerte du système. Jumeau de `DeleteAccountSheet.swift`.
 *
 * Deux modales dans Figma, une seule vue ici : `Modale – Supression de compte
 * (sans voyage)` (`3203:21809`) et `(avec voyage)` (`3206:21854`) ne diffèrent
 * que d'un paragraphe, celui qui propose de **clore le voyage en cours** plutôt
 * que de tout effacer. Hugo, 14/09/2026 (T23).
 *
 * Le texte est celui de la maquette, à deux corrections près, signalées dans
 * la fiche écran : « sont supprimé » s'accorde, et « Co-voyageurs » prend la
 * minuscule que le mot a partout ailleurs dans l'app.
 *
 * ⚠️ Le titre et les libellés des deux boutons n'ont pas pu être lus sur les
 * nœuds (quota MCP) : ce sont ceux qui suivent la logique de la feuille — le
 * bouton plein **garde** le compte, le rouge le supprime. À relire sur la
 * maquette.
 *
 * Le profil la présente dans un `BrandSheetHost`, avec
 * `dismissDisabled = isDeleting` — l'`interactiveDismissDisabled` d'iOS : la
 * demande partie, la feuille ne se referme plus au glissé.
 *
 * @param hasOngoingTrip un voyage est en cours : la feuille propose alors de le
 *   clore plutôt que de tout effacer.
 * @param mentionsSubscription un abonnement App Store va se renouveler : la
 *   feuille rappelle que supprimer le compte ne l'arrête pas. **À lui seul**
 *   (03/10/2026) — le dire à tout le monde demandait à un compte gratuit de
 *   couper un abonnement qu'il n'a pas. Un abonnement Google Play aura sa
 *   phrase avec le lot B4.
 * @param isDeleting la suppression est partie. Le bouton rouge tourne et plus
 *   rien ne se touche : la demande est définitive, elle ne part pas deux fois.
 */
@Composable
internal fun DeleteAccountSheet(
    hasOngoingTrip: Boolean,
    mentionsSubscription: Boolean = true,
    isDeleting: Boolean,
    onKeep: () -> Unit,
    onDelete: () -> Unit,
) {
    BrandSheet(DeleteAccountCopy.title) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
            BrandText(
                DeleteAccountCopy.body(hasOngoingTrip = hasOngoingTrip, mentionsSubscription = mentionsSubscription),
                MemoBookFont.body,
                Modifier.fillMaxWidth(),
            )

            Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
                // Le bouton plein est celui qui **ne détruit rien** : sur une
                // feuille dont l'autre issue est sans retour, l'action la plus
                // visible doit être la plus sûre.
                BrandButton(DeleteAccountCopy.keep, fillsWidth = true, enabled = !isDeleting, action = onKeep)

                BrandButton(
                    DeleteAccountCopy.delete,
                    style = BrandButton.Style.Destructive,
                    isLoading = isDeleting,
                    fillsWidth = true,
                    action = onDelete,
                )
            }
        }
    }
}

/** Les mots de la feuille, tels que Figma les écrit — voir [DeleteAccountSheet]. */
internal object DeleteAccountCopy {
    const val title = "Tu es sûr de vouloir supprimer ton compte MemoBook ?"

    const val erasure =
        "Tes voyages, tes souvenirs et tes carnets seront effacés, ainsi que tes commandes. Les voyages que tu partages restent à tes co-voyageurs, avec les souvenirs que tu y as racontés. C’est immédiat et sans retour."

    /**
     * Pour qui a un abonnement App Store qui va se renouveler — voir
     * `mentionsSubscription`. Il parle de l'iPhone parce que l'abonnement y a
     * été pris, même lu sur Android.
     */
    const val subscriptionWarning =
        "Ton abonnement, lui, se résilie chez Apple : supprimer ton compte ne l’arrête pas, pense à le couper dans les réglages de ton iPhone."

    /** La porte de sortie qui n'existe que s'il y a un voyage en cours à clore. */
    const val closeTripInstead =
        "Tu veux seulement clore ton voyage en cours ? Termine-le : ton compte et tes carnets restent."

    /**
     * Le paragraphe de la feuille : ce qui s'efface, l'abonnement à couper
     * chez Apple s'il y en a un, et la porte de sortie s'il y a un voyage.
     */
    fun body(hasOngoingTrip: Boolean, mentionsSubscription: Boolean): String =
        buildList {
            add(erasure)
            if (mentionsSubscription) add(subscriptionWarning)
            if (hasOngoingTrip) add(closeTripInstead)
        }.joinToString(" ")

    const val keep = "Garder mon compte"
    const val delete = "Supprimer définitivement mon compte"
}

@Preview(locale = "fr-rFR", name = "Suppression — sans voyage", widthDp = 390, heightDp = 640)
@Composable
private fun DeleteAccountSheetPreview() {
    Box(Modifier.fillMaxSize().background(MemoBookColor.background), contentAlignment = Alignment.BottomCenter) {
        DeleteAccountSheet(hasOngoingTrip = false, mentionsSubscription = false, isDeleting = false, onKeep = {}, onDelete = {})
    }
}

@Preview(locale = "fr-rFR", name = "Suppression — avec voyage", widthDp = 390, heightDp = 640)
@Composable
private fun DeleteAccountSheetOngoingTripPreview() {
    Box(Modifier.fillMaxSize().background(MemoBookColor.background), contentAlignment = Alignment.BottomCenter) {
        DeleteAccountSheet(hasOngoingTrip = true, isDeleting = false, onKeep = {}, onDelete = {})
    }
}
