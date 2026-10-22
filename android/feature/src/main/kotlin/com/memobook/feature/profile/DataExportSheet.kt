package com.memobook.feature.profile

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.memobook.core.DataExportReceipt
import com.memobook.design.BrandButton
import com.memobook.design.BrandSheet
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandText
import com.memobook.design.LocalBrandSheetDismiss
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.isReduceMotionEnabled
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * « Exporter mes données » — la feuille qu'ouvre la ligne du bas du profil.
 * Jumeau de `Profile/DataExportSheet.swift`.
 *
 * **Deux temps dans la même feuille**, comme celle du support : la
 * proposition, puis la confirmation. On n'empile pas deux [BrandSheet], et
 * la hauteur s'anime d'un temps à l'autre au lieu de sauter.
 *
 * **Pas de confirmation avant d'envoyer**, contrairement à la suppression du
 * compte : la demande ne détruit rien et ne coûte rien. La feuille dit ce qui
 * va se passer — un lien par e-mail, à l'adresse du compte, valable sept
 * jours — et un seul bouton le fait.
 *
 * Le temps de la demande, la feuille ne se referme pas au glissé : c'est le
 * profil qui le dit à son `BrandSheetHost` (`dismissDisabled`), le
 * `interactiveDismissDisabled` d'iOS.
 *
 * ⚠️ **Aucune maquette Figma** pour cette feuille (relevé le 01/10/2026 : la
 * page App ne montre que la ligne du profil). Elle est faite des pièces des
 * autres feuilles — le chapeau en paragraphes de la résiliation, la coche du
 * support — en attendant d'être dessinée (T241).
 */
@Composable
internal fun DataExportSheet(model: ProfileModel) {
    val state by model.state.collectAsStateWithLifecycle(context = Dispatchers.Main.immediate)
    val dismiss = LocalBrandSheetDismiss.current
    val reduceMotion = isReduceMotionEnabled()
    val animated = if (reduceMotion) Modifier else Modifier.animateContentSize(SwiftMotion.snappy(0.3f))

    // Rouverte plus tard, la feuille repart de la proposition.
    DisposableEffect(model) { onDispose { model.resetDataExport() } }

    when (val export = state.dataExport) {
        is ProfileModel.DataExportState.Sent -> BrandSheet(
            if (export.receipt.alreadyRequested) DataExportCopy.alreadySentTitle else DataExportCopy.sentTitle,
            paragraphs = DataExportCopy.sentParagraphs(export.receipt),
            modifier = animated,
        ) {
            DataExportConfirmation(onUnderstood = dismiss)
        }
        else -> BrandSheet(
            DataExportCopy.title,
            paragraphs = listOf(DataExportCopy.intro, DataExportCopy.contents),
            modifier = animated,
        ) {
            DataExportOffer(
                email = state.profile?.email,
                export = export,
                // Sur la portée du modèle, comme le `Task` d'iOS : la demande
                // va à son terme même si la feuille se referme entre-temps.
                onSend = { model.viewModelScope.launch { model.requestDataExport() } },
            )
        }
    }
}

// MARK: - La proposition

@Composable
private fun DataExportOffer(email: String?, export: ProfileModel.DataExportState, onSend: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
        if (email != null) {
            BrandText(DataExportCopy.destination(email), MemoBookFont.caption, Modifier.fillMaxWidth(), color = MemoBookColor.inkMuted)
        }

        if (export is ProfileModel.DataExportState.Failed) {
            BrandText(export.message, MemoBookFont.caption, Modifier.fillMaxWidth(), color = MemoBookColor.error)
        }

        BrandButton(
            DataExportCopy.send,
            isLoading = export == ProfileModel.DataExportState.Requesting,
            fillsWidth = true,
            action = onSend,
        )
    }
}

// MARK: - La confirmation

/**
 * Le rond et sa coche de la feuille du support (`SupportSheet`), puis
 * « Compris » : le titre et le chapeau ont déjà tout dit.
 */
@Composable
private fun DataExportConfirmation(onUnderstood: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            // Les mesures de la coche du support : 66 et 28.
            Box(
                Modifier
                    .size(66.dp)
                    .background(MemoBookColor.outline.copy(alpha = 0.5f), CircleShape)
                    .clearAndSetSemantics { contentDescription = DataExportCopy.confirmationVoice },
                contentAlignment = Alignment.Center,
            ) {
                Image(
                    painterResource(R.drawable.icon_lucide_check),
                    contentDescription = null,
                    colorFilter = ColorFilter.tint(MemoBookColor.ink),
                    modifier = Modifier.size(28.dp),
                )
            }
        }

        BrandButton(DataExportCopy.understood, fillsWidth = true, action = onUnderstood)
    }
}

/** Les mots de la feuille. Sans maquette : à relire avec elle (T241). */
internal object DataExportCopy {
    const val title = "Exporter mes données"

    const val intro =
        "On t’envoie par e-mail un lien pour télécharger une copie de tout ce que MemoBook garde de toi."

    /**
     * La même phrase que l'e-mail et la page de téléchargement
     * (`DATA_EXPORT_CONTENTS`, `backend/src/services/mailTemplates.ts`).
     */
    const val contents =
        "Dans l’archive : ton compte, tes voyages et leurs récits, chaque souvenir tel que tu l’as raconté et tel que MEMO l’a écrit, tes photos et tes vocaux d’origine, tes carnets en PDF, tes commandes et ton abonnement."

    fun destination(email: String): String = "Le lien partira à $email. Il sera valable sept jours."

    const val send = "M’envoyer le lien"

    const val sentTitle = "Regarde ta boîte mail"
    const val alreadySentTitle = "Ton e-mail est déjà en route"

    fun sentParagraphs(receipt: DataExportReceipt, zone: ZoneId = ZoneId.systemDefault()): List<String> {
        val first = if (receipt.alreadyRequested) {
            "Un lien est parti à ${receipt.email} à ${time(receipt.requestedAt, zone)}. Il peut mettre quelques minutes à arriver."
        } else {
            "Le lien est parti à ${receipt.email}. Il est valable jusqu’au ${day(receipt.expiresAt, zone)}."
        }
        return listOf(first, "Rien dans ta boîte d’ici quelques minutes ? Regarde dans tes indésirables.")
    }

    const val understood = "Compris"
    const val confirmationVoice = "Lien envoyé"

    /** Le 404 d'un serveur qui ne connaît pas encore la route. */
    const val notYetAvailable =
        "L’export de tes données n’est pas encore ouvert sur notre serveur. Réessaie un peu plus tard."

    private val french = Locale.FRANCE

    /** « mercredi 8 octobre » — et « 1er », que le format ne sait pas écrire. */
    fun day(date: Instant, zone: ZoneId = ZoneId.systemDefault()): String =
        DateTimeFormatter.ofPattern("EEEE d MMMM", french).format(date.atZone(zone))
            .replace(Regex("(^|\\s)1(\\s)"), "$11er$2")

    /** « 15 h 02 ». */
    fun time(date: Instant, zone: ZoneId = ZoneId.systemDefault()): String =
        DateTimeFormatter.ofPattern("HH:mm", french).format(date.atZone(zone)).replace(":", " h ")
}

@Preview(locale = "fr-rFR", name = "Export — proposition", heightDp = 700)
@Composable
private fun DataExportSheetOfferPreview() {
    val model = remember { ProfileModel() }
    BrandSheetHost(isPresented = true, onDismissRequest = {}) { DataExportSheet(model) }
}

@Preview(locale = "fr-rFR", name = "Export — envoyé", heightDp = 700)
@Composable
private fun DataExportSheetSentPreview() {
    val model = remember { ProfileModel() }
    LaunchedEffect(model) {
        model.load()
        model.requestDataExport()
    }
    BrandSheetHost(isPresented = true, onDismissRequest = {}) { DataExportSheet(model) }
}
