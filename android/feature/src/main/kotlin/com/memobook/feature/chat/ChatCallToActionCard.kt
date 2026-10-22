package com.memobook.feature.chat

import androidx.annotation.DrawableRes
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.snap
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.memobook.core.ChatAuthor
import com.memobook.core.ChatCallToAction
import com.memobook.core.ChatCallToActionState
import com.memobook.core.ChatCopy
import com.memobook.core.DailyCreditCopy
import com.memobook.design.BrandChatBubble
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.isReduceMotionEnabled
import com.memobook.design.scaled
import com.memobook.feature.AppSettings
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json

/**
 * **La carte d'une bulle de MEMO qui porte un bouton** — [ChatCallToAction]
 * (maquettes `3653:17090` et, une fois touchée, `3653:17213` ; 03/10/2026).
 * Jumeau de `ChatCallToActionCard.swift`.
 *
 * C'est une bulle de MEMO comme les autres — [BrandChatBubble], sa queue, son
 * blanc —, avec trois choses de plus, de haut en bas :
 *
 * 1. **l'en-tête manuscrit**, « ✦ » et l'[ChatCallToAction.eyebrow] en
 *    [MemoBookFont.handwriting] vert : MEMO annote sa propre bulle, comme on
 *    écrit un mot dans la marge du carnet ;
 * 2. sous le texte et un filet, **la ligne d'action**, centrée, icône et
 *    libellé en vert d'action ;
 * 3. sous un second filet, **« Ignorer »**, centré, en gris — si le bouton se
 *    laisse ignorer.
 *
 * **Touchée**, l'action s'exécute, la ligne passe au bleu du texte
 * ([MemoBookColor.blueText]) et « Ignorer » s'en va : on voit ce qu'on a déjà
 * ouvert, et on peut y retourner. **Ignorée**, l'en-tête, la ligne et
 * « Ignorer » s'en vont : la bulle redevient une bulle. L'état se retient sur
 * l'appareil, par bulle ([ChatCallToActionMemory]).
 *
 * **Réutilisable tel quel** : elle ne sait rien de l'abonnement ni des photos.
 * Le bouton est décrit par [ChatCallToAction] ; ce qu'il ouvre, c'est l'écran
 * qui le décide (`ChatView`). Un [ChatCallToAction.Kind.Unknown] ne montre pas
 * de bouton, ni « s'abonner » à un abonné : `ChatModel.showsCallToAction` le
 * dit avant qu'on la pose.
 */
@Composable
fun ChatCallToActionCard(
    text: String,
    callToAction: ChatCallToAction,
    state: ChatCallToActionState,
    onFollow: () -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val reduceMotion = isReduceMotionEnabled()
    val iconSide = scaled(20.dp)

    BrandChatBubble(ChatAuthor.Memo, modifier) {
        Column(
            Modifier.animateContentSize(if (reduceMotion) snap() else SwiftMotion.smooth(0.25f)),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        ) {
            val eyebrow = callToAction.eyebrow
            if (state != ChatCallToActionState.Dismissed && !eyebrow.isNullOrEmpty()) {
                CallToActionHeader(eyebrow)
            }

            BrandText(text, MemoBookFont.bubble)

            AnimatedVisibility(
                visible = state != ChatCallToActionState.Dismissed,
                enter = fadeIn(if (reduceMotion) snap() else SwiftMotion.smooth(0.25f)),
                exit = fadeOut(if (reduceMotion) snap() else SwiftMotion.smooth(0.25f)),
            ) {
                Column {
                    Rule()
                    ActionRow(callToAction, state, iconSide, onFollow)
                    if (callToAction.dismissible && state == ChatCallToActionState.Pending) {
                        Rule()
                        DismissRow(onDismiss)
                    }
                }
            }
        }
    }
}

/** « ✦ Crédit du jour épuisé », à la main, en vert. */
@Composable
private fun CallToActionHeader(eyebrow: String) {
    Row(
        Modifier.semantics(mergeDescendants = true) { contentDescription = eyebrow },
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BrandText(ChatCopy.CallToAction.star, MemoBookFont.label, Modifier.clearAndSetSemantics {}, color = MemoBookColor.action)
        BrandText(eyebrow, MemoBookFont.handwriting, color = MemoBookColor.action)
    }
}

/** Le filet qui sépare le texte de ce qu'on peut en faire. */
@Composable
private fun Rule() {
    androidx.compose.foundation.layout.Box(
        Modifier
            .fillMaxWidth()
            .height(1.dp)
            .background(MemoBookColor.hairline)
            .clearAndSetSemantics {},
    )
}

/** La ligne d'action : verte tant qu'elle n'a pas servi, bleue ensuite. */
@Composable
private fun ActionRow(
    callToAction: ChatCallToAction,
    state: ChatCallToActionState,
    iconSide: androidx.compose.ui.unit.Dp,
    onFollow: () -> Unit,
) {
    val tint = if (state == ChatCallToActionState.Followed) MemoBookColor.blueText else MemoBookColor.action
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = MemoBookSpacing.minimumTapTarget)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = PlainButtonIndication,
                role = Role.Button,
                onClick = onFollow,
            )
            .semantics(mergeDescendants = true) {
                contentDescription = callToAction.label
                if (state == ChatCallToActionState.Followed) stateDescription = ChatCopy.CallToAction.followed
            },
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(
            painter = painterResource(ChatCallToActionCard.icon(callToAction.kind)),
            contentDescription = null,
            colorFilter = ColorFilter.tint(tint),
            modifier = Modifier.size(iconSide),
        )
        BrandText(
            callToAction.label,
            MemoBookFont.bubbleAction,
            Modifier.clearAndSetSemantics {},
            color = tint,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun DismissRow(onDismiss: () -> Unit) {
    BrandText(
        ChatCopy.CallToAction.dismiss,
        MemoBookFont.bubble,
        Modifier
            .fillMaxWidth()
            .heightIn(min = MemoBookSpacing.minimumTapTarget)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = PlainButtonIndication,
                role = Role.Button,
                onClick = onDismiss,
            )
            .padding(vertical = MemoBookSpacing.snug),
        color = MemoBookColor.inkMuted,
        textAlign = TextAlign.Center,
    )
}

object ChatCallToActionCard {
    /**
     * L'icône de la ligne d'action, par genre de bouton. Celle de « Modifier
     * l’autorisation » est celle de la maquette ; les autres reprennent l'icône
     * que l'app montre déjà pour la même destination.
     */
    @DrawableRes
    fun icon(kind: ChatCallToAction.Kind): Int = when (kind) {
        ChatCallToAction.Kind.Subscribe -> R.drawable.icon_lucide_sparkles
        ChatCallToAction.Kind.OpenTripSettings -> R.drawable.icon_settings
        ChatCallToAction.Kind.OpenPreview -> R.drawable.icon_book
        ChatCallToAction.Kind.ImportPhotos -> R.drawable.icon_lucide_camera
        ChatCallToAction.Kind.OpenPhotoSettings -> R.drawable.icon_picture_frame
        ChatCallToAction.Kind.EnableNotifications -> R.drawable.icon_ringtone
        is ChatCallToAction.Kind.Unknown -> R.drawable.icon_arrow_right
    }
}

/**
 * Ce qu'on a fait des boutons posés sous les bulles de MEMO, **retenu sur
 * l'appareil** — touché ou ignoré, par identifiant de bulle. Jumeau de
 * `ChatCallToActionMemory` (`ChatCallToActionCard.swift`).
 *
 * Sur l'appareil et non sur le serveur : c'est l'état d'un geste, pas un fait
 * du récit, et un co-voyageur qui ignore « Raconter sans limite » ne l'ignore
 * pas pour les autres. Seuls les gestes s'écrivent — une bulle sans trace est
 * en attente —, ce qui garde la liste à quelques lignes par voyage.
 *
 * Le dictionnaire d'iOS (`UserDefaults.dictionary(forKey:)`) s'écrit ici en
 * JSON sous la même clé : [AppSettings] ne garde que des chaînes et des
 * booléens.
 *
 * @param settings les réglages de l'appareil — `null` pour rien sur le disque
 *   (les aperçus et les tests, [inMemory]).
 */
class ChatCallToActionMemory(private val settings: AppSettings?) {
    private val states: MutableMap<String, String> =
        settings?.getString(KEY)?.let(::decode)?.toMutableMap() ?: mutableMapOf()

    fun state(messageId: String): ChatCallToActionState {
        val raw = states[messageId] ?: return ChatCallToActionState.Pending
        return ChatCallToActionState.entries.firstOrNull { it.rawValue == raw } ?: ChatCallToActionState.Pending
    }

    fun remember(state: ChatCallToActionState, messageId: String) {
        states[messageId] = state.rawValue
        settings?.putString(KEY, encode(states))
    }

    companion object {
        /** La clé dans les réglages de l'appareil. */
        const val KEY = "memobook.chat.callToActionStates"

        /** Rien sur le disque — les aperçus et les tests. */
        fun inMemory(): ChatCallToActionMemory = ChatCallToActionMemory(settings = null)

        private val format = MapSerializer(String.serializer(), String.serializer())

        private fun decode(raw: String): Map<String, String>? = runCatching { Json.decodeFromString(format, raw) }.getOrNull()

        private fun encode(states: Map<String, String>): String = Json.encodeToString(format, states)
    }
}

// MARK: - Aperçus

@Preview(locale = "fr-rFR", name = "Carte d’appel à l’action — ses trois états", widthDp = 390, heightDp = 900)
@Composable
private fun ChatCallToActionCardPreview() {
    Column(
        Modifier
            .background(MemoBookColor.background)
            .verticalScroll(rememberScrollState())
            .padding(MemoBookSpacing.snug),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        ChatCallToActionCard(
            text = DailyCreditCopy.exhaustedMessage,
            callToAction = ChatCallToAction.dailyCreditSubscribe,
            state = ChatCallToActionState.Pending,
            onFollow = {},
            onDismiss = {},
        )
        ChatCallToActionCard(
            text = DailyCreditCopy.exhaustedMessage,
            callToAction = ChatCallToAction.dailyCreditSubscribe,
            state = ChatCallToActionState.Followed,
            onFollow = {},
            onDismiss = {},
        )
        ChatCallToActionCard(
            text = DailyCreditCopy.exhaustedMessage,
            callToAction = ChatCallToAction.dailyCreditSubscribe,
            state = ChatCallToActionState.Dismissed,
            onFollow = {},
            onDismiss = {},
        )
        ChatCallToActionCard(
            text = ChatFixtureCopy.limitedPhotosMessage,
            callToAction = ChatFixtureCopy.limitedPhotosCallToAction,
            state = ChatCallToActionState.Pending,
            onFollow = {},
            onDismiss = {},
        )
    }
}
