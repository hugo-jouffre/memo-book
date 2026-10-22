package com.memobook.feature.support

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.memobook.core.Faq
import com.memobook.core.FaqEntry
import com.memobook.core.SupportCopy
import com.memobook.core.SupportMessage
import com.memobook.design.BrandButton
import com.memobook.design.BrandSheet
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandText
import com.memobook.design.BrandTextBox
import com.memobook.design.LocalBrandSheetDismiss
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.isReduceMotionEnabled
import com.memobook.design.scaled
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * La feuille du support, en trois temps : une réponse, un formulaire, une
 * confirmation. Jumeau de `Support/SupportSheet.swift`.
 *
 * **Une seule feuille pour les trois**, et c'est une contrainte du design
 * system : on n'empile pas deux [BrandSheet]. « J'ai encore une question »
 * devait pourtant mener au formulaire depuis une réponse — c'est donc une
 * **étape** de la même feuille, comme l'aperçu l'est de la feuille
 * d'abonnement (voir `BookPreviewSheet`).
 *
 * L'avantage n'est pas que théorique : la feuille garde son identité d'un temps
 * à l'autre, donc sa hauteur s'anime au lieu de sauter, et le retour de
 * TalkBack reste celui d'une seule feuille.
 *
 * @param source d'où part le message : le support, ou « Partager mes retours »
 *   du mot des fondateurs (T226).
 * @param tripId le voyage d'où l'on écrit, s'il y en a un.
 */
@Composable
fun SupportSheet(
    model: SupportModel,
    route: SupportSheetRoute,
    source: SupportMessage.Source = SupportMessage.Source.Support,
    tripId: String? = null,
) {
    val state by model.state.collectAsStateWithLifecycle(context = Dispatchers.Main.immediate)
    var step by remember(route) { mutableStateOf(SupportSheetStep.from(route)) }
    var message by rememberSaveable { mutableStateOf("") }
    var isWriting by remember { mutableStateOf(false) }
    val dismiss = LocalBrandSheetDismiss.current
    val reduceMotion = isReduceMotionEnabled()

    // Deux feuilles ouvertes l'une après l'autre ne partagent pas l'état
    // d'envoi de la première : sans ça, la seconde s'ouvrirait sur la
    // confirmation de la précédente.
    DisposableEffect(model) { onDispose { model.resetSending() } }

    BrandSheet(step.title, paragraphs = step.paragraphs) {
        Column(if (reduceMotion) Modifier else Modifier.animateContentSize(SwiftMotion.snappy(0.3f))) {
            when (val current = step) {
                is SupportSheetStep.Answer -> SupportAnswer(
                    entry = current.entry,
                    model = model,
                    state = state,
                    onStillStuck = { step = SupportSheetStep.Contact(about = null) },
                    onUnderstood = dismiss,
                )
                is SupportSheetStep.Contact -> SupportForm(
                    message = message,
                    onMessageChange = { message = it },
                    isWriting = isWriting,
                    onWritingChange = { isWriting = it },
                    sendState = state.sendState,
                    onSend = {
                        isWriting = false
                        // Sur la portée du modèle, comme le `Task` d'iOS : le
                        // message part même si la feuille se referme entre-temps.
                        model.viewModelScope.launch {
                            model.send(message, source = source, topicId = current.about?.id, tripId = tripId)
                            if (model.sendState == SupportModel.SendState.Sent) step = SupportSheetStep.Sent
                        }
                    },
                )
                SupportSheetStep.Sent -> SupportConfirmation()
            }
        }
    }
}

/** Les trois temps de la feuille. */
private sealed interface SupportSheetStep {
    data class Answer(val entry: FaqEntry) : SupportSheetStep

    /**
     * Le formulaire — au sujet d'une question de « Nous contacter », ou sans
     * sujet. Le sujet change le titre et raccourcit le chapeau.
     */
    data class Contact(val about: FaqEntry?) : SupportSheetStep

    data object Sent : SupportSheetStep

    val title: String
        get() = when (this) {
            is Answer -> entry.question
            is Contact -> about?.question ?: SupportCopy.Contact.title
            Sent -> SupportCopy.Contact.confirmation
        }

    /**
     * Le chapeau gris sous le titre. Seul le formulaire en a un : une réponse
     * écrit son texte en pleine encre, plus bas. Ouvert au sujet d'une
     * question, il tient en une phrase.
     */
    val paragraphs: List<String>
        get() = when (this) {
            is Contact -> listOf(about?.let { SupportCopy.Contact.brief(it.id) } ?: SupportCopy.Contact.message)
            else -> emptyList()
        }

    companion object {
        fun from(route: SupportSheetRoute): SupportSheetStep = when (route) {
            is SupportSheetRoute.Answer -> Answer(route.entry)
            is SupportSheetRoute.Contact -> Contact(route.about)
        }
    }
}

// MARK: - Une réponse

@Composable
private fun SupportAnswer(
    entry: FaqEntry,
    model: SupportModel,
    state: SupportModel.State,
    onStillStuck: () -> Unit,
    onUnderstood: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            model.answer(entry).forEach { BrandText(it, MemoBookFont.body) }
        }

        HelpfulVote(entry, model, state)

        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
            BrandButton(SupportCopy.Answer.stillStuck, style = BrandButton.Style.Secondary, fillsWidth = true, action = onStillStuck)
            BrandButton(SupportCopy.Answer.understood, fillsWidth = true, action = onUnderstood)
        }
    }
}

// MARK: - Le formulaire

@Composable
private fun SupportForm(
    message: String,
    onMessageChange: (String) -> Unit,
    isWriting: Boolean,
    onWritingChange: (Boolean) -> Unit,
    sendState: SupportModel.SendState,
    onSend: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
        BrandTextBox(
            SupportCopy.Contact.placeholder,
            value = message,
            onValueChange = onMessageChange,
            isFocused = isWriting,
            onFocusChange = onWritingChange,
        )

        if (sendState is SupportModel.SendState.Failed) {
            BrandText(sendState.message, MemoBookFont.caption, color = MemoBookColor.error)
        }

        // Un formulaire vide n'a rien à envoyer, et le bouton le dit en passant
        // au gris plutôt qu'en échouant après coup.
        BrandButton(
            SupportCopy.Contact.send,
            isLoading = sendState == SupportModel.SendState.Sending,
            fillsWidth = true,
            enabled = message.isNotBlank(),
            action = onSend,
        )
    }
}

// MARK: - La confirmation

/**
 * Le rond bleu et sa coche. Rien d'autre : la feuille a déjà dit ce qu'il
 * fallait dire dans son titre.
 *
 * La maquette le dessine en lime ; il est bleu parce que le lime ne parle que de
 * l'abonnement (Hugo, 14/09/2026, T7) et qu'un message envoyé au support n'en
 * parle pas. Le bleu est l'accent de tout le reste.
 */
@Composable
private fun SupportConfirmation() {
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Box(
            Modifier
                .size(66.dp)
                // À moitié, comme la maquette : à pleine intensité, le rond
                // crierait plus fort que le message qu'il confirme.
                .background(MemoBookColor.outline.copy(alpha = 0.5f), CircleShape)
                .clearAndSetSemantics { contentDescription = SupportCopy.Contact.confirmationVoice },
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
}

// MARK: - « Est-ce utile ? »

/**
 * Les deux pouces sous une réponse.
 *
 * C'est **la mesure** que demande la page Notion : « Consultations et clics
 * *cette réponse t'a-t-elle aidé* par identifiant, pour repérer les questions
 * mal formulées et les frictions produit. » Elle porte donc l'identifiant de la
 * question, jamais son texte — c'est l'identifiant qui survit à une réécriture.
 *
 * Une fois le vote passé, les pouces laissent place à un merci : les laisser
 * actifs invite à voter deux fois, et fausserait la mesure qu'ils servent.
 */
@Composable
private fun HelpfulVote(entry: FaqEntry, model: SupportModel, state: SupportModel.State) {
    // Le vote part : les pouces se figent le temps de la réponse.
    val isPending = entry.id in state.pendingVotes
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BrandText(SupportCopy.Answer.helpful, MemoBookFont.label, color = MemoBookColor.inkMuted)
            if (state.votes[entry.id] == null) {
                val vote: (Boolean) -> Unit = { isHelpful -> model.viewModelScope.launch { model.vote(isHelpful, entry) } }
                HelpfulThumb(R.drawable.icon_thumb_up, SupportCopy.Answer.helpfulYes, enabled = !isPending) { vote(true) }
                HelpfulThumb(R.drawable.icon_thumb_down, SupportCopy.Answer.helpfulNo, enabled = !isPending) { vote(false) }
            } else {
                BrandText(SupportCopy.Answer.thanks, MemoBookFont.label, color = MemoBookColor.action)
            }
        }

        // Le vote n'est pas parti : les pouces restent, pour réessayer.
        state.voteFailure?.takeIf { it.questionId == entry.id }?.let { failure ->
            BrandText(failure.message, MemoBookFont.caption, Modifier.fillMaxWidth(), color = MemoBookColor.error)
        }
    }
}

/** Le dessin fait 16, la cible en fait 48 : deux pouces à 16 côte à côte seraient intouchables. */
@Composable
private fun HelpfulThumb(icon: Int, label: String, enabled: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .size(MemoBookSpacing.minimumTapTarget)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = PlainButtonIndication,
                enabled = enabled,
                role = Role.Button,
                onClick = onClick,
            )
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Image(
            painterResource(icon),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.inkMuted),
            modifier = Modifier.size(scaled(16.dp)),
        )
    }
}

@Preview(locale = "fr-rFR", name = "Réponse", heightDp = 800)
@Composable
private fun SupportSheetAnswerPreview() {
    BrandSheetHost(isPresented = true, onDismissRequest = {}) {
        SupportSheet(remember { SupportModel() }, SupportSheetRoute.Answer(Faq.entry("faq.carnet.pages") ?: Faq.discover.entries[0]))
    }
}

@Preview(locale = "fr-rFR", name = "Nous contacter", heightDp = 800)
@Composable
private fun SupportSheetContactPreview() {
    BrandSheetHost(isPresented = true, onDismissRequest = {}) {
        SupportSheet(remember { SupportModel() }, SupportSheetRoute.Contact(about = null))
    }
}

@Preview(locale = "fr-rFR", name = "Réponse — AX3", heightDp = 800, fontScale = 2f)
@Composable
private fun SupportSheetLargePreview() {
    BrandSheetHost(isPresented = true, onDismissRequest = {}) {
        SupportSheet(remember { SupportModel() }, SupportSheetRoute.Answer(Faq.entry("faq.raconter.comment") ?: Faq.tell.entries[0]))
    }
}
