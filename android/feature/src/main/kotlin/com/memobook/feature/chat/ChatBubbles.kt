package com.memobook.feature.chat

import androidx.annotation.DrawableRes
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.slideInHorizontally
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.core.ChatAuthor
import com.memobook.core.ChatCallToAction
import com.memobook.core.ChatCallToActionState
import com.memobook.core.ChatCopy
import com.memobook.core.ChatDelivery
import com.memobook.core.ChatMessage
import com.memobook.core.ChatMessageBody
import com.memobook.core.DailyCreditCopy
import com.memobook.core.PhotoAttachment
import com.memobook.core.TranscriptCard
import com.memobook.core.VoiceNote
import com.memobook.design.ActivitySpinner
import com.memobook.design.BrandAlert
import com.memobook.design.BrandChatBubble
import com.memobook.design.BrandMark
import com.memobook.design.BrandMarkDrawing
import com.memobook.design.BrandText
import com.memobook.design.BrandWaveform
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.isAccessibilityTextSize
import com.memobook.design.isReduceMotionEnabled
import com.memobook.design.scaled
import com.memobook.feature.home.TripCoverPlaceholder
import kotlinx.coroutines.delay
import java.net.URI
import kotlin.math.max

/**
 * Ce que la rangée d'un message lit du modèle, réuni une fois par la vue —
 * l'observation fine de l'`@Observable` d'iOS, où chaque bulle ne relit que
 * ce qu'elle montre. Une valeur : la rangée ne se redessine que si elle change.
 *
 * @property isReading la voix lit ce message à voix haute.
 * @property isCopied la coche d'une copie, pendant une seconde.
 * @property callToActionState ce qu'on a fait du bouton de la bulle.
 * @property showsCallToAction le bouton se montre — voir `ChatModel.showsCallToAction`.
 * @property portrait la photo ou les initiales de qui a parlé, pour un vocal.
 */
data class ChatRowState(
    val isReading: Boolean = false,
    val isCopied: Boolean = false,
    val callToActionState: ChatCallToActionState = ChatCallToActionState.Pending,
    val showsCallToAction: Boolean = false,
    val portrait: ChatPortrait? = null,
    val levels: List<Double> = emptyList(),
)

/**
 * Une réplique du fil : la bulle, et les deux commandes posées à côté d'elle.
 * Jumeau de `ChatMessageRow` (`ChatBubbles.swift`).
 *
 * **Le côté est la seule question posée.** L'auteur décide de l'alignement, de
 * la couleur, du sens de la queue et de la nature des commandes — écouter et
 * copier ce que MEMO a dit, corriger et copier ce qu'on a dit soi-même. Tout le
 * reste est commun, et c'est pour ça qu'il n'y a qu'une rangée et pas deux.
 *
 * @param onCallToAction ce que fait le bouton posé sous une bulle de MEMO —
 *   [ChatCallToAction]. C'est l'écran qui ouvre ce qu'il ouvre (le paywall, les
 *   réglages du voyage, l'aperçu…) ; la rangée ne fait que transmettre.
 */
@Composable
fun ChatMessageRow(
    message: ChatMessage,
    model: ChatModel,
    row: ChatRowState,
    isExpanded: Boolean,
    onToggleExpansion: () -> Unit,
    modifier: Modifier = Modifier,
    onCallToAction: (ChatCallToAction) -> Unit = {},
) {
    val isTraveller = message.author.isTraveller
    Column(
        modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2),
        horizontalAlignment = if (isTraveller) Alignment.End else Alignment.Start,
    ) {
        AuthorCaption(message)
        BubbleAndActions(message, model, row, isExpanded, onToggleExpansion, onCallToAction)
        DeliveryNotice(message, model, onCallToAction)
        DeliveryTicksIfOwn(message)
    }
}

/**
 * Le prénom de l'autre voyageur, au-dessus de sa bulle, dans un fil à
 * plusieurs. **Seulement si le serveur l'a mis** : il sait qui lit, qui parle,
 * et s'ils sont plusieurs — la vue affiche, elle ne raisonne pas
 * (`docs/conversation.md` § 2).
 */
@Composable
private fun AuthorCaption(message: ChatMessage) {
    val name = message.authorName
    if (name.isNullOrEmpty()) return
    BrandText(
        name,
        MemoBookFont.caption,
        Modifier
            .padding(horizontal = MemoBookSpacing.snug)
            .semantics { contentDescription = "$name :" },
        color = MemoBookColor.inkMuted,
    )
}

/**
 * La bulle et ses commandes.
 *
 * En taille de texte accessible, les commandes passent **sous** la bulle :
 * deux cibles de 3 rem qui grandissent avec le corps ne laisseraient plus
 * qu'un mot par ligne au texte.
 */
@Composable
private fun BubbleAndActions(
    message: ChatMessage,
    model: ChatModel,
    row: ChatRowState,
    isExpanded: Boolean,
    onToggleExpansion: () -> Unit,
    onCallToAction: (ChatCallToAction) -> Unit,
) {
    val isTraveller = message.author.isTraveller
    val actions = actions(message)
    val bubble: @Composable () -> Unit = { Bubble(message, model, row, isExpanded, onToggleExpansion, onCallToAction) }
    val buttons: @Composable () -> Unit = {
        actions.forEach { action ->
            ChatActionButton(
                action = action,
                isActive = action == ChatMessageAction.ReadAloud && row.isReading,
                isConfirmed = action == ChatMessageAction.Copy && row.isCopied,
            ) {
                when (action) {
                    ChatMessageAction.ReadAloud -> model.toggleReading(message)
                    ChatMessageAction.Copy -> model.copy(message)
                    ChatMessageAction.Edit -> model.edit(message)
                }
            }
        }
    }

    if (isAccessibilityTextSize()) {
        Column(
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2),
            horizontalAlignment = if (isTraveller) Alignment.End else Alignment.Start,
        ) {
            bubble()
            if (actions.isNotEmpty()) Row { buttons() }
        }
    } else {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            if (isTraveller) {
                Spacer(Modifier.weight(1f))
                buttons()
            }
            bubble()
            if (!isTraveller) {
                buttons()
                Spacer(Modifier.weight(1f))
            }
        }
    }
}

/**
 * Ce que chaque auteur permet de faire de son message.
 *
 * Rien sous un vocal : il n'y a pas de texte à copier ni à faire lire, et son
 * bouton de lecture est déjà dans la bulle.
 */
private fun actions(message: ChatMessage): List<ChatMessageAction> {
    if (message.spokenText == null) return emptyList()
    return if (message.author.isTraveller) {
        listOf(ChatMessageAction.Edit, ChatMessageAction.Copy)
    } else {
        listOf(ChatMessageAction.ReadAloud, ChatMessageAction.Copy)
    }
}

/**
 * « En cours d'envoi » se voit : la bulle est là, un peu en retrait, et prend
 * sa pleine couleur quand le serveur l'a — tout de suite en ligne, à la sortie
 * du tunnel sinon (`docs/conversation.md` § 9). Ni roue ni libellé : la bulle
 * d'un texte dit dans le métro ne doit pas avoir l'air cassée, juste pas
 * encore arrivée. TalkBack le dit en toutes lettres.
 *
 * Une bulle qui attend le crédit de demain, ou l'illimité, reste en retrait de
 * la même façon : elle n'est pas partie non plus. C'est la mention dessous qui
 * dit pourquoi — voir [DeliveryNotice].
 */
@Composable
private fun Bubble(
    message: ChatMessage,
    model: ChatModel,
    row: ChatRowState,
    isExpanded: Boolean,
    onToggleExpansion: () -> Unit,
    onCallToAction: (ChatCallToAction) -> Unit,
) {
    val delivery = message.delivery
    val isWaiting = delivery == ChatDelivery.Sending || delivery.isWaitingForCredit || delivery.isWaitingForUnlimited
    val opacity by animateFloatAsState(if (isWaiting) 0.6f else 1f, SwiftMotion.smooth(0.3f), label = "waiting")
    val hint = when {
        delivery.isWaitingForCredit -> ChatCopy.Voice.leavesTomorrow
        delivery.isWaitingForUnlimited -> ChatCopy.Voice.tooLongForADay
        delivery == ChatDelivery.Sending -> ChatCopy.Voice.sending
        else -> null
    }

    Box(
        Modifier
            .alpha(opacity)
            .semantics { if (hint != null) stateDescription = hint },
    ) {
        BubbleBody(message, model, row, isExpanded, onToggleExpansion, onCallToAction)
    }
}

@Composable
private fun BubbleBody(
    message: ChatMessage,
    model: ChatModel,
    row: ChatRowState,
    isExpanded: Boolean,
    onToggleExpansion: () -> Unit,
    onCallToAction: (ChatCallToAction) -> Unit,
) {
    when (val body = message.body) {
        is ChatMessageBody.Text -> {
            val callToAction = message.callToAction
            if (!message.author.isTraveller && row.showsCallToAction && callToAction != null) {
                // Une bulle de MEMO qui porte un bouton se dessine en carte.
                ChatCallToActionCard(
                    text = body.value,
                    callToAction = callToAction,
                    state = row.callToActionState,
                    onFollow = {
                        model.followCallToAction(message.id)
                        onCallToAction(callToAction)
                    },
                    onDismiss = { model.dismissCallToAction(message.id) },
                )
            } else {
                BrandChatBubble(message.author, Modifier.semantics(mergeDescendants = true) {}) {
                    BrandText(body.value, MemoBookFont.bubble)
                }
            }
        }
        is ChatMessageBody.Voice -> ChatVoiceBubble(body.note, message.author, row.portrait, model, row.levels)
        is ChatMessageBody.Transcript -> ChatTranscriptBubble(body.card, isExpanded, onToggleExpansion)
        is ChatMessageBody.Photos -> ChatPhotosBubble(body.attachments, message.author, model)
    }
}

/**
 * « Non envoyé », sous la bulle qui n'est pas passée. La bulle reste : perdre
 * le message serait perdre ce qu'il racontait.
 *
 * **« Partira demain »**, en gris et sans « Réessayer », sous une bulle que le
 * serveur a refusée faute de crédit du jour (Hugo, 03/10/2026) : elle attend
 * sur le téléphone et repart toute seule à la recharge. Un « Réessayer » rouge
 * ferait renvoyer en boucle vers le même refus.
 *
 * **« Trop long pour une journée · Passer en illimité »** sous une bulle qui
 * coûte plus qu'une journée entière de crédit (03/10/2026) : demain ne la
 * ferait pas passer, l'illimité si. Gris comme « Partira demain », l'offre
 * soulignée en vert d'action ; le toucher ouvre le paywall, et la bulle part
 * dès que le compte raconte sans limite. **« Supprimer »** à côté, en gris :
 * sans abonnement, c'est la seule autre sortie — après confirmation, le tour
 * quitte le téléphone et la bulle le fil.
 */
@Composable
private fun DeliveryNotice(message: ChatMessage, model: ChatModel, onCallToAction: (ChatCallToAction) -> Unit) {
    val delivery = message.delivery
    when {
        delivery.isWaitingForCredit -> BrandText(
            ChatCopy.leavesTomorrow,
            MemoBookFont.caption,
            Modifier
                .padding(horizontal = MemoBookSpacing.snug)
                .clearAndSetSemantics {},
            color = MemoBookColor.inkMuted,
        )
        delivery.isWaitingForUnlimited -> WaitingForUnlimitedNotice(message, model, onCallToAction)
        delivery.hasFailed -> BasicText(
            buildAnnotatedString {
                append(ChatCopy.notSent)
                append(" ")
                withStyle(SpanStyle(textDecoration = TextDecoration.Underline)) { append(ChatCopy.retry) }
            },
            Modifier
                .padding(horizontal = MemoBookSpacing.snug)
                .heightIn(min = MemoBookSpacing.minimumTapTarget)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = PlainButtonIndication,
                    role = Role.Button,
                    onClick = model::retry,
                )
                .clearAndSetSemantics {
                    contentDescription = "${ChatCopy.notSent}. ${ChatCopy.retry}"
                    role = Role.Button
                    onClick { model.retry(); true }
                }
                .padding(vertical = MemoBookSpacing.snug),
            style = MemoBookFont.caption.copy(color = MemoBookColor.error),
        )
    }
}

@Composable
private fun WaitingForUnlimitedNotice(message: ChatMessage, model: ChatModel, onCallToAction: (ChatCallToAction) -> Unit) {
    var confirmsDiscard by remember { mutableStateOf(false) }
    val stacks = isAccessibilityTextSize()

    val offer: @Composable () -> Unit = {
        // Une seule phrase, qui se replie en très grand texte au lieu de couper
        // trois morceaux côte à côte.
        BasicText(
            buildAnnotatedString {
                withStyle(SpanStyle(color = MemoBookColor.inkMuted)) { append(ChatCopy.tooLongForADay + " · ") }
                withStyle(SpanStyle(color = MemoBookColor.action, textDecoration = TextDecoration.Underline)) {
                    append(DailyCreditCopy.unlimitedCallToAction)
                }
            },
            Modifier
                .heightIn(min = MemoBookSpacing.minimumTapTarget)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = PlainButtonIndication,
                    role = Role.Button,
                ) { onCallToAction(ChatCallToAction.dailyCreditSubscribe) }
                .clearAndSetSemantics {
                    contentDescription = "${ChatCopy.tooLongForADay}. ${DailyCreditCopy.unlimitedCallToAction}"
                    role = Role.Button
                    onClick(label = ChatCopy.Credit.exhaustedHint) { onCallToAction(ChatCallToAction.dailyCreditSubscribe); true }
                }
                .padding(vertical = MemoBookSpacing.snug),
            style = MemoBookFont.caption.copy(textAlign = TextAlign.End),
        )
    }
    val discard: @Composable () -> Unit = {
        BasicText(
            buildAnnotatedString {
                if (!stacks) append("· ")
                withStyle(SpanStyle(textDecoration = TextDecoration.Underline)) { append(ChatCopy.DiscardWaiting.action) }
            },
            Modifier
                .heightIn(min = MemoBookSpacing.minimumTapTarget)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = PlainButtonIndication,
                    role = Role.Button,
                ) { confirmsDiscard = true }
                .clearAndSetSemantics {
                    contentDescription = ChatCopy.DiscardWaiting.action
                    role = Role.Button
                    onClick(label = ChatCopy.DiscardWaiting.hint) { confirmsDiscard = true; true }
                }
                .padding(vertical = MemoBookSpacing.snug),
            style = MemoBookFont.caption.copy(color = MemoBookColor.inkMuted),
        )
    }

    // Côte à côte ; l'un sous l'autre en très grand texte, où deux cibles sur
    // une ligne ne laisseraient qu'un mot par ligne.
    if (stacks) {
        Column(Modifier.padding(horizontal = MemoBookSpacing.snug), horizontalAlignment = Alignment.End) {
            offer()
            discard()
        }
    } else {
        Row(
            Modifier.padding(horizontal = MemoBookSpacing.snug),
            horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            offer()
            discard()
        }
    }

    // Le `confirmationDialog` d'iOS : deux issues, le titre et la phrase.
    BrandAlert(
        isPresented = confirmsDiscard,
        title = if (message.body is ChatMessageBody.Voice) ChatCopy.DiscardWaiting.voiceTitle else ChatCopy.DiscardWaiting.textTitle,
        message = ChatCopy.DiscardWaiting.body,
        actions = listOf(
            BrandAlert.Action(ChatCopy.DiscardWaiting.confirm, BrandAlert.Role.Destructive) {
                confirmsDiscard = false
                model.discardWaitingTurn(message.id)
            },
            BrandAlert.Action(ChatCopy.DiscardWaiting.keep, BrandAlert.Role.Cancel) { confirmsDiscard = false },
        ),
        onDismissRequest = { confirmsDiscard = false },
    )
}

/**
 * **Les coches, à la manière de WhatsApp** (Hugo, 08/10/2026), sous les
 * messages qu'on a dits soi-même : une coche grise, il est **gardé sur le
 * téléphone** — dans la file, il partira tout seul ; deux, il est **arrivé
 * chez nous**, et la retranscription a commencé.
 *
 * Rien sous une bulle qui attend le crédit ou l'illimité, ni sous un échec : la
 * mention dessous ([DeliveryNotice]) dit déjà où il en est, et une coche à côté
 * se contredirait avec elle. Rien sous les bulles d'un co-voyageur : ce n'est
 * pas notre envoi.
 */
@Composable
private fun DeliveryTicksIfOwn(message: ChatMessage) {
    if (!message.author.isTraveller || message.authorName != null) return
    when (message.delivery) {
        ChatDelivery.Sending -> ChatDeliveryTicks(isDelivered = false, Modifier.padding(horizontal = MemoBookSpacing.snug))
        ChatDelivery.Sent -> ChatDeliveryTicks(isDelivered = true, Modifier.padding(horizontal = MemoBookSpacing.snug))
        is ChatDelivery.Failed, is ChatDelivery.WaitingForCredit, ChatDelivery.WaitingForUnlimited -> Unit
    }
}

/**
 * Une coche ou deux, sous un message à soi. Jumeau de `ChatDeliveryTicks`.
 *
 * Grises dans les deux cas, comme les commandes à côté des bulles : elles
 * renseignent, elles ne demandent rien. La seconde arrive en glissant sous la
 * première, de la largeur d'un trait : c'est ce mouvement qui se remarque quand
 * le réseau revient.
 */
@Composable
fun ChatDeliveryTicks(isDelivered: Boolean, modifier: Modifier = Modifier) {
    val side = scaled(13.dp)
    val reduceMotion = isReduceMotionEnabled()
    Box(
        modifier
            .animateContentSize(if (reduceMotion) snap() else SwiftMotion.snappy(0.3f))
            .clearAndSetSemantics {
                contentDescription = if (isDelivered) ChatCopy.Voice.delivered else ChatCopy.Voice.storedOnPhone
            },
    ) {
        Tick(side)
        AnimatedVisibility(
            visible = isDelivered,
            modifier = Modifier.padding(start = side * 0.45f),
            enter = if (reduceMotion) fadeIn(snap()) else slideInHorizontally(SwiftMotion.snappy(0.3f)) { -it / 2 } + fadeIn(),
            exit = fadeOut(snap()),
        ) {
            Tick(side)
        }
    }
}

@Composable
private fun Tick(side: Dp) {
    Image(
        painter = painterResource(R.drawable.icon_lucide_check),
        contentDescription = null,
        colorFilter = ColorFilter.tint(MemoBookColor.inkMuted),
        modifier = Modifier.size(side),
    )
}

/** Ce qu'on peut faire d'un message. Jumeau de `ChatMessageAction`. */
enum class ChatMessageAction {
    ReadAloud,
    Copy,
    Edit,
    ;

    /**
     * ⚠️ Trois icônes **Lucide**, faute d'équivalent dans le jeu de marque —
     * voir `assets/icons/lucide/README.md`. Le préfixe du nom d'asset est là
     * pour que la dette se voie d'ici, et le jour où Clara les dessine, c'est
     * cette ligne-là qui change.
     */
    @get:DrawableRes
    val icon: Int
        get() = when (this) {
            ReadAloud -> R.drawable.icon_lucide_speaker
            Copy -> R.drawable.icon_lucide_copy
            Edit -> R.drawable.icon_pen
        }

    val label: String
        get() = when (this) {
            ReadAloud -> ChatCopy.Voice.readAloud
            Copy -> ChatCopy.Voice.copy
            Edit -> ChatCopy.Voice.edit
        }
}

/**
 * Une commande posée à côté d'une bulle : une icône discrète dans une cible de
 * 3 rem. Jumeau de `ChatActionButton`.
 *
 * Grise et non colorée : ce sont des services rendus au message, pas des
 * actions de l'écran. La seule qui s'allume est la lecture à voix haute, parce
 * qu'elle a un état — quelque chose est en train de parler.
 *
 * **Toutes à la taille du crayon** (Hugo, 08/10/2026 : « un peu plus petites et
 * discrètes, le crayon garde sa taille, les autres descendent à la sienne »).
 * Le crayon du jeu de marque n'encre que 70 % de sa boîte de 24 ; les icônes
 * Lucide, 92 %. À boîte égale, copier et écouter paraissaient donc un tiers
 * plus gros. Elles se dessinent dans une boîte plus petite, et les quatre ont
 * la même encre. La cible, elle, reste de 3 rem : plus discret ne veut pas dire
 * plus difficile à toucher.
 *
 * @param isConfirmed le geste vient d'aboutir. Vrai une seconde après une copie
 *   — voir `ChatModel.copiedMessageId`.
 */
@Composable
private fun ChatActionButton(action: ChatMessageAction, isActive: Boolean, isConfirmed: Boolean, perform: () -> Unit) {
    val reduceMotion = isReduceMotionEnabled()
    // La boîte du crayon, inchangée ; celle des icônes Lucide, ramenée de 92 %
    // à 70 % d'encre.
    val penSide = scaled(MemoBookSpacing.sectionGap)
    val lucideSide = scaled(MemoBookSpacing.sectionGap * 0.76f)

    // Ce que le bouton montre : la coche s'il vient de servir, l'arrêt s'il
    // parle, son icône sinon. Seul le crayon vient du jeu de marque.
    val icon = when {
        isConfirmed -> R.drawable.icon_lucide_check
        isActive -> R.drawable.icon_lucide_stop
        else -> action.icon
    }
    val side = if (icon == R.drawable.icon_pen) penSide else lucideSide
    // Au repos, un cran sous le gris du texte secondaire : elles se devinent à
    // côté de la bulle sans lui disputer le regard.
    val tint = when {
        isConfirmed -> MemoBookColor.valid
        isActive -> MemoBookColor.action
        else -> MemoBookColor.inkMuted.copy(alpha = MemoBookColor.inkMuted.alpha * 0.75f)
    }
    // La coche **remplace** l'icône, elle ne s'ajoute pas à côté : c'est la
    // même commande qui répond, et rien ne bouge autour. Elle arrive avec un
    // petit sursaut, parce qu'un simple fondu se rate quand on regarde ailleurs
    // une demi-seconde.
    val scale by animateFloatAsState(
        if (isConfirmed && !reduceMotion) 1.18f else 1f,
        if (reduceMotion) snap() else SwiftMotion.spring(response = 0.28f, dampingFraction = 0.5f),
        label = "confirmed",
    )

    Box(
        Modifier
            .size(MemoBookSpacing.minimumTapTarget)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = PlainButtonIndication,
                role = Role.Button,
                onClick = perform,
            )
            .semantics {
                contentDescription = if (isActive) ChatCopy.Voice.stopReading else action.label
                // TalkBack n'a pas de coche à regarder : il faut le lui dire.
                if (isConfirmed) stateDescription = ChatCopy.Voice.copied
            },
        contentAlignment = Alignment.Center,
    ) {
        Image(
            painter = painterResource(icon),
            contentDescription = null,
            colorFilter = ColorFilter.tint(tint),
            modifier = Modifier
                .size(side)
                .scale(scale),
        )
    }
}

// MARK: - Les photos

/**
 * Des photos jointes : une grande si elle est seule, une grille sinon. Jumeau
 * de `ChatPhotosBubble`.
 *
 * ⚠️ **Aucune bulle de photo n'est dessinée dans la maquette.** Celle-ci est
 * écrite pour que l'ajout de photos — que la maquette propose, elle, en puce et
 * en bouton — mène quelque part. Elle reprend la bulle et le rayon de vignette
 * de l'app, et rien d'autre n'est inventé. À faire dessiner — voir T60.
 *
 * Deux colonnes, jamais plus : à trois, une vignette tombe sous la largeur d'un
 * pouce sur un petit téléphone. Des rangées et non une grille paresseuse : la
 * bulle vit déjà dans la liste du fil, qui ne se laisse pas imbriquer.
 */
@Composable
fun ChatPhotosBubble(attachments: List<PhotoAttachment>, author: ChatAuthor, model: ChatModel) {
    val thumbnail = scaled(76.dp)
    val shown = attachments.take(ChatMetrics.visiblePhotoCount)
    val hidden = max(0, attachments.size - ChatMetrics.visiblePhotoCount)

    BrandChatBubble(
        author,
        Modifier.clearAndSetSemantics {
            contentDescription = ChatCopy.Voice.photos(count = attachments.size)
            role = Role.Button
            onClick(label = ChatCopy.PhotoViewer.hint) { model.viewPhotos(attachments, 0); true }
        },
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2)) {
            if (attachments.size == 1) {
                ChatPhoto(attachments[0], index = 0, side = thumbnail * 2.4f, attachments = attachments, model = model)
            } else {
                shown.chunked(2).forEachIndexed { rowIndex, pair ->
                    Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2)) {
                        pair.forEachIndexed { column, attachment ->
                            ChatPhoto(
                                attachment,
                                index = rowIndex * 2 + column,
                                side = thumbnail * 1.4f,
                                attachments = attachments,
                                model = model,
                                modifier = Modifier.weight(1f),
                            )
                        }
                        if (pair.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
            }

            if (hidden > 0) BrandText("+$hidden", MemoBookFont.caption)
        }
    }
}

/**
 * Une vignette : le fichier local tant qu'il est là, sinon le média du serveur
 * — **avec la session**, par le modèle. Un `AsyncImage` n'envoyait pas
 * d'en-tête et `/v1/entries/:id/media` le refusait (T206).
 *
 * Touchée, elle s'ouvre en plein écran ([ChatPhotoViewer]), avec les autres
 * photos de la bulle à portée de glissé.
 */
@Composable
private fun ChatPhoto(
    attachment: PhotoAttachment,
    index: Int,
    side: Dp,
    attachments: List<PhotoAttachment>,
    model: ChatModel,
    modifier: Modifier = Modifier,
) {
    val url = attachment.displayUrl
    val shape = RoundedCornerShape(MemoBookSpacing.snug)
    LaunchedEffect(url) { url?.let(model::loadImage) }

    Box(
        modifier
            .fillMaxWidth()
            .height(side)
            .clip(shape)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { model.viewPhotos(attachments, index) },
    ) {
        val image = url?.let { chatImage(model, it) }
        if (image != null) {
            Image(image, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
        } else {
            // La même trame que les vignettes d'étape : une image qui charge ne
            // doit pas laisser un trou de la couleur du fond.
            TripCoverPlaceholder(seed = attachment.id, modifier = Modifier.matchParentSize())
        }
    }
}

/** L'image d'une adresse, telle que le modèle l'a chargée — seule l'arrivée de **celle-ci** redessine qui la lit. */
@Composable
internal fun chatImage(model: ChatModel, url: URI): ImageBitmap? {
    val image by model.image(url).collectAsStateWithLifecycle()
    return image
}

// MARK: - Le vocal

/**
 * Un vocal : de quoi le jouer, sa forme d'onde, sa durée, et le signe de celui
 * qui l'a dit. Jumeau de `ChatVoiceBubble`.
 *
 * La forme d'onde est **celle du vocal**, pas un motif : les niveaux ont été
 * relevés pendant l'enregistrement. Un dessin décoratif, identique d'un vocal à
 * l'autre, dirait quelque chose de faux sur ce qui a été raconté.
 *
 * Le bouton, l'onde et la signature partagent **le même axe**, et le chrono
 * pend sous l'onde (Hugo, 30/09/2026, maquette `3627:31695`). C'est l'onde, et
 * non le bloc onde + chrono, qui se centre sur la bulle : c'est ce que Clara
 * reprochait le 17/09 à la version en deux lignes, dont l'onde remontait
 * au-dessus du milieu. L'`alignmentGuide` d'iOS est ici un `alignBy`.
 *
 * @param portrait la photo ou les initiales de celui qui a parlé. `null` : le M
 *   de MEMO.
 * @param levels le relevé du serveur, ou celui relu dans le fichier quand le
 *   vocal est arrivé sans — voir `ChatModel.deriveLevelsIfNeeded`.
 */
@Composable
fun ChatVoiceBubble(note: VoiceNote, author: ChatAuthor, portrait: ChatPortrait?, model: ChatModel, levels: List<Double>) {
    val player by model.player.state.collectAsStateWithLifecycle()
    val isPlaying = player.playingId == note.id
    val glyph = scaled(MemoBookSpacing.sectionGap)
    val markSide = scaled(MemoBookSpacing.xl + 8.dp)
    val density = LocalDensity.current
    val trackHalf = with(density) { (MemoBookSpacing.m / 2).roundToPx() }

    LaunchedEffect(note.id) { model.deriveLevelsIfNeeded(note) }

    BrandChatBubble(
        author,
        Modifier.clearAndSetSemantics {
            contentDescription = ChatCopy.Voice.voiceNote(duration = note.duration.chatSpokenDurationLabel)
            role = Role.Button
            onClick { model.togglePlayback(note); true }
        },
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
            Box(
                Modifier
                    .alignBy { it.measuredHeight / 2 }
                    .sizeIn(minWidth = MemoBookSpacing.minimumTapTarget, minHeight = MemoBookSpacing.minimumTapTarget)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = PlainButtonIndication,
                        role = Role.Button,
                    ) { model.togglePlayback(note) },
                contentAlignment = Alignment.Center,
            ) {
                Image(
                    painter = painterResource(if (isPlaying) R.drawable.icon_lucide_pause else R.drawable.icon_lucide_play),
                    contentDescription = null,
                    colorFilter = ColorFilter.tint(MemoBookColor.ink),
                    modifier = Modifier.size(glyph),
                )
            }

            Column(
                Modifier
                    .alignBy { trackHalf }
                    .weight(1f)
                    .widthIn(min = MemoBookSpacing.xl * 2),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                VoiceTrack(levels, progress = if (isPlaying) player.progress else 0.0)
                // Le chrono compte **en avançant** pendant la lecture, et
                // affiche la durée totale au repos : c'est ce que fait un
                // lecteur, et c'est ce qu'on cherche des yeux dans les deux cas.
                BrandText(
                    (if (isPlaying) player.elapsed else note.duration).chatDurationLabel,
                    MemoBookFont.caption.copy(fontFeatureSettings = "tnum"),
                    maxLines = 1,
                )
            }

            // Le vocal est signé par celui qui l'a dit : son portrait — sa
            // photo, ou ses initiales comme sur son profil (Clara, 26/09/2026).
            // Le rond vert au M de la marque ne signe plus que MEMO.
            if (!isAccessibilityTextSize()) {
                VoiceSignature(portrait, model, markSide, Modifier.alignBy { it.measuredHeight / 2 })
            }
        }
    }
}

/** L'onde, et la tête de lecture posée dessus : le point de la maquette, au début de l'onde au repos, qui avance avec la lecture. */
@Composable
private fun VoiceTrack(levels: List<Double>, progress: Double) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        BrandWaveform(levels = levels, progress = progress, tint = MemoBookColor.inkMuted, playedTint = MemoBookColor.ink)
        val dot = MemoBookSpacing.snug
        Box(
            Modifier
                .align(Alignment.CenterStart)
                .offset(x = (maxWidth - dot) * progress.toFloat().coerceIn(0f, 1f))
                .size(dot)
                .background(MemoBookColor.ink, CircleShape),
        )
    }
}

@Composable
private fun VoiceSignature(portrait: ChatPortrait?, model: ChatModel, side: Dp, modifier: Modifier = Modifier) {
    Box(modifier.clearAndSetSemantics {}) {
        if (portrait != null) {
            val url = portrait.url
            LaunchedEffect(url) { url?.let(model::loadImage) }
            ChatPortraitDisc(portrait, image = url?.let { chatImage(model, it) }, side = side)
        } else {
            // Un tracé et non une image : le M du dépôt se met à l'échelle sans
            // se pixelliser.
            Box(
                Modifier
                    .size(side)
                    .background(MemoBookColor.action, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                BrandMarkDrawing(
                    progress = 1f,
                    color = MemoBookColor.onAction,
                    modifier = Modifier
                        .width(side * 0.55f)
                        .height(BrandMark.height(forWidth = side * 0.55f)),
                )
            }
        }
        // Le micro, **en pastille** sur le bord bas du rond (Clara,
        // 26/09/2026 — « mieux intégré ») : un disque du fond de la bulle qui
        // le détoure, et le glyphe vert dedans. Il se lit comme un badge du
        // portrait, et non plus comme une icône posée à côté.
        MicBadge(side * 0.42f, Modifier.align(Alignment.BottomStart))
    }
}

/**
 * La pastille du micro : un disque du papier de la marque, cerclé comme le
 * portrait, et le glyphe vert dedans — le badge d'une photo, pas une icône de
 * plus dans la bulle.
 */
@Composable
private fun MicBadge(side: Dp, modifier: Modifier = Modifier) {
    Box(
        modifier
            .offset(x = -side * 0.3f, y = side * 0.12f)
            .size(side)
            .background(MemoBookColor.surface, CircleShape)
            .border(1.dp, MemoBookColor.hairline, CircleShape)
            .padding(side * 0.2f),
    ) {
        Image(
            painter = painterResource(R.drawable.icon_mic),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.action),
            modifier = Modifier.matchParentSize(),
        )
    }
}

/**
 * Le portrait d'une bulle de vocal : la photo, ou les initiales **comme sur la
 * page de profil** — le même bleu d'aplat, l'encre. Un cerne du papier de la
 * marque le détache : sans lui, le rond bleu se fondait dans la bulle bleue du
 * voyageur, et il ne restait que deux lettres qui flottaient. Jumeau de
 * `ChatPortraitDisc`.
 *
 * La photo arrive **déjà chargée**, par `ChatModel.loadImage` : un
 * `AsyncImage` ici repartait de zéro à chaque recomposition du fil, et restait
 * sur les initiales dès qu'une requête était annulée.
 */
@Composable
fun ChatPortraitDisc(portrait: ChatPortrait, image: ImageBitmap?, side: Dp, modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(side)
            .background(MemoBookColor.outline, CircleShape)
            .clip(CircleShape)
            .border(2.dp, MemoBookColor.surface, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        if (image != null) {
            Image(image, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
        } else {
            BrandText(
                portrait.initials,
                MemoBookFont.cardTitle,
                Modifier.padding(horizontal = 4.dp),
                maxLines = 1,
                minimumScaleFactor = 0.5f,
            )
        }
    }
}

/** Qui a dit un vocal, pour son rond : une photo quand il y en a une, des initiales sinon. */
data class ChatPortrait(val url: URI?, val initials: String)

// MARK: - La retranscription

/**
 * La fiche « Retranscription étape N » : ce que MEMO a compris d'un vocal.
 * Jumeau de `ChatTranscriptBubble`.
 *
 * Elle a la forme d'une **fiche** et non d'une réplique, parce qu'elle n'est
 * pas de la même nature : on la relit, on la corrige, elle finira dans le
 * carnet. D'où l'intitulé, la date, et la note de pied qui dit d'où vient le
 * texte.
 */
@Composable
fun ChatTranscriptBubble(card: TranscriptCard, isExpanded: Boolean, onToggleExpansion: () -> Unit) {
    val stage = ChatTranscriptBubble.stage(card)
    val reduceMotion = isReduceMotionEnabled()

    BrandChatBubble(
        ChatAuthor.Memo,
        Modifier.semantics(mergeDescendants = true) { contentDescription = ChatTranscriptBubble.accessibilityText(card, stage) },
    ) {
        // Le texte qui passe du brut au rédigé, la coche qui arrive : un fondu,
        // pas un saut.
        Column(
            Modifier.animateContentSize(if (reduceMotion) snap() else SwiftMotion.smooth(0.3f)),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug),
        ) {
            TranscriptHeading(card)
            TranscriptBody(card, stage, isExpanded, onToggleExpansion)
            val footnote = card.footnote
            if (footnote != null && stage == ChatTranscriptBubble.Stage.Ready) {
                BrandText(footnote, MemoBookFont.caption, Modifier.clearAndSetSemantics {}, color = MemoBookColor.inkMuted)
            }
        }
    }
}

object ChatTranscriptBubble {
    /** Combien de lignes la fiche montre avant « Voir plus ». Sept : de quoi juger si la transcription est juste, sans que la fiche mange l'écran. */
    const val collapsedLineLimit = 7

    /**
     * À partir de combien de caractères la fiche propose de se déplier.
     *
     * Un seuil et non une mesure : la mesurer demanderait de rendre le texte
     * deux fois à chaque image de défilement. Sept lignes d'environ
     * trente-cinq signes à la largeur d'une bulle — le compte est approché
     * **par le haut**, pour qu'un « Voir plus » qui ne montre rien de plus ne
     * puisse pas arriver.
     */
    val expandableLength: Int = (collapsedLineLimit * 35 * 1.15).toInt()

    /**
     * Les trois temps de la fiche — `docs/conversation.md` § 5. Une fiche sans
     * texte écoute encore, quel que soit son temps : le moteur local n'en pose
     * pas.
     */
    enum class Stage { Listening, Writing, Ready, Failed }

    fun stage(card: TranscriptCard): Stage {
        if (card.text == null) return Stage.Listening
        return when (card.phase) {
            TranscriptCard.Phase.Listening -> Stage.Listening
            TranscriptCard.Phase.Writing -> Stage.Writing
            TranscriptCard.Phase.Failed -> Stage.Failed
            TranscriptCard.Phase.Ready, is TranscriptCard.Phase.Unknown -> Stage.Ready
        }
    }

    fun accessibilityText(card: TranscriptCard, stage: Stage): String {
        val day = ChatCopy.Voice.transcript(title = card.title, day = card.capturedAt.chatFullDayLabel)
        val state = when (stage) {
            Stage.Listening -> ChatCopy.transcriptPending
            Stage.Writing -> "${ChatCopy.transcriptWriting} ${card.text.orEmpty()}"
            Stage.Failed -> "${ChatCopy.transcriptFailed} ${card.text.orEmpty()}"
            Stage.Ready -> listOfNotNull(card.heading, card.text).joinToString(". ")
        }
        val validated = if (card.isValidated) " ${ChatCopy.Voice.validated}." else ""
        return "$day. $state$validated"
    }
}

@Composable
private fun TranscriptHeading(card: TranscriptCard) {
    val glyph = scaled(MemoBookSpacing.snug)
    Column(Modifier.clearAndSetSemantics {}, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            // L'intitulé est **écrit à la main** — Gloria Hallelujah, comme la
            // maquette, et comme les titres du carnet (T54).
            Glyph(R.drawable.icon_lucide_sparkles, glyph, MemoBookColor.action)
            BrandText(card.title, MemoBookFont.handwriting, Modifier.padding(start = MemoBookSpacing.xs), color = MemoBookColor.action)
            // « Ça me convient » a été dit : une coche discrète, dans le vert
            // d'action, à la place de rien — la fiche ne change pas de forme
            // pour le dire. Son écart vit avec elle.
            AnimatedVisibility(card.isValidated, enter = scaleIn() + fadeIn(), exit = fadeOut()) {
                Box(Modifier.padding(start = MemoBookSpacing.xs)) { Glyph(R.drawable.icon_lucide_check, glyph, MemoBookColor.action) }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug), verticalAlignment = Alignment.CenterVertically) {
            Glyph(R.drawable.icon_lucide_calendar, glyph, MemoBookColor.ink)
            BrandText(card.capturedAt.chatDayLabel, MemoBookFont.caption)
            card.placeLabel?.let { BrandText(it, MemoBookFont.caption, color = MemoBookColor.inkMuted, maxLines = 1) }
        }
    }
}

@Composable
private fun Glyph(@DrawableRes icon: Int, side: Dp, tint: Color) {
    Image(painterResource(icon), contentDescription = null, colorFilter = ColorFilter.tint(tint), modifier = Modifier.size(side))
}

/**
 * Le récit, ou ce qui le remplace tant qu'il n'est pas revenu.
 *
 * La fiche s'affiche **avant** la transcription, avec ce qu'on sait déjà — la
 * date, le lieu, la durée. Cacher une information réelle derrière une attente
 * donnerait l'impression que rien ne se passe.
 */
@Composable
private fun TranscriptBody(card: TranscriptCard, stage: ChatTranscriptBubble.Stage, isExpanded: Boolean, onToggleExpansion: () -> Unit) {
    when (stage) {
        ChatTranscriptBubble.Stage.Listening -> Row(
            Modifier.clearAndSetSemantics {},
            horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            ActivitySpinner(MemoBookColor.action, size = 16.dp)
            BrandText(ChatCopy.transcriptPending, MemoBookFont.bubble, color = MemoBookColor.inkMuted)
        }

        // Le brut est là, en gris : le voyageur voit tout de suite qu'il a été
        // entendu, et le texte rédigé viendra le remplacer.
        ChatTranscriptBubble.Stage.Writing -> Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            Row(
                Modifier.clearAndSetSemantics {},
                horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                ActivitySpinner(MemoBookColor.action, size = 16.dp)
                BrandText(ChatCopy.transcriptWriting, MemoBookFont.caption, color = MemoBookColor.inkMuted)
            }
            Narrative(card.text.orEmpty(), MemoBookColor.inkMuted, isExpanded, onToggleExpansion)
        }

        ChatTranscriptBubble.Stage.Failed -> Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            BrandText(ChatCopy.transcriptFailed, MemoBookFont.caption, Modifier.clearAndSetSemantics {}, color = MemoBookColor.error)
            val text = card.text
            if (!text.isNullOrEmpty()) Narrative(text, MemoBookColor.inkMuted, isExpanded, onToggleExpansion)
        }

        ChatTranscriptBubble.Stage.Ready -> Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            val title = card.heading
            if (!title.isNullOrEmpty()) {
                BrandText(title, MemoBookFont.sectionTitle, Modifier.clearAndSetSemantics { heading() })
            }
            Narrative(card.text.orEmpty(), MemoBookColor.ink, isExpanded, onToggleExpansion)
        }
    }
}

/** Le récit, replié à sept lignes tant qu'on ne demande pas la suite. */
@Composable
private fun Narrative(text: String, tint: Color, isExpanded: Boolean, onToggleExpansion: () -> Unit) {
    val isExpandable = text.length > ChatTranscriptBubble.expandableLength
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
        BrandText(
            text,
            MemoBookFont.bubble,
            Modifier.clearAndSetSemantics {},
            color = tint,
            maxLines = if (isExpanded || !isExpandable) Int.MAX_VALUE else ChatTranscriptBubble.collapsedLineLimit,
        )
        if (isExpandable) {
            BrandText(
                if (isExpanded) ChatCopy.seeLess else ChatCopy.seeMore,
                MemoBookFont.bubbleAction,
                Modifier
                    .heightIn(min = MemoBookSpacing.minimumTapTarget)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = PlainButtonIndication,
                        role = Role.Button,
                        onClick = onToggleExpansion,
                    )
                    .padding(vertical = MemoBookSpacing.snug),
                color = MemoBookColor.action,
            )
        }
    }
}

// MARK: - MEMO réfléchit

/**
 * Trois points qui respirent, à la place de la bulle qui vient. Jumeau de
 * `ChatThinkingBubble`.
 *
 * Une bulle et non une roue centrée : l'attente doit se produire **là où la
 * réponse va apparaître**, sinon le fil saute quand elle arrive. Sans animation
 * quand « Supprimer les animations » est activé — trois points fixes disent la
 * même chose.
 */
@Composable
fun ChatThinkingBubble(modifier: Modifier = Modifier) {
    val reduceMotion = isReduceMotionEnabled()
    var phase by remember { mutableIntStateOf(0) }

    // Une boucle plutôt qu'une animation infinie : elle s'arrête d'elle-même
    // quand la bulle disparaît, sans qu'on ait à l'annuler.
    LaunchedEffect(reduceMotion) {
        if (reduceMotion) return@LaunchedEffect
        while (true) {
            delay(320)
            phase = (phase + 1) % THINKING_DOT_COUNT
        }
    }

    Row(
        modifier
            .fillMaxWidth()
            .clearAndSetSemantics { contentDescription = ChatCopy.Voice.thinking },
    ) {
        BrandChatBubble(ChatAuthor.Memo) {
            Row(
                Modifier.height(MemoBookSpacing.s),
                horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                repeat(THINKING_DOT_COUNT) { index ->
                    val opacity by animateFloatAsState(
                        if (reduceMotion || phase == index) 1f else 0.35f,
                        tween(250, easing = SwiftMotion.easeInOut),
                        label = "dot",
                    )
                    Box(
                        Modifier
                            .size(7.dp)
                            .alpha(opacity)
                            .background(MemoBookColor.inkMuted, CircleShape),
                    )
                }
            }
        }
        Spacer(Modifier.weight(1f))
    }
}

private const val THINKING_DOT_COUNT = 3
