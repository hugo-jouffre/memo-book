package com.memobook.feature.chat

import androidx.annotation.DrawableRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.memobook.core.ChatBookPreview
import com.memobook.core.ChatCopy
import com.memobook.core.ChatGreeting
import com.memobook.core.ChatThread
import com.memobook.design.BrandMark
import com.memobook.design.BrandMarkDrawing
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookShadow
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.brandShadow
import com.memobook.design.scaled
import com.memobook.feature.trip.dimmedWhileAwaitingServer
import com.memobook.feature.home.CardPressStyle

/**
 * Les mesures que le chat partage entre son écran, son squelette et sa barre
 * d'envoi. Jumeau de `ChatMetrics` (`ChatHeader.swift`).
 *
 * Au même endroit et pour la même raison que `HomeMetrics` : c'est parce que
 * le squelette et l'écran réel tombent aux mêmes places que le passage de l'un
 * à l'autre ne saute pas.
 */
object ChatMetrics {
    /** La hauteur d'une commande ronde de l'en-tête, et sa cible tactile. */
    val control: Dp = MemoBookSpacing.minimumTapTarget

    /** L'icône posée dans cette commande — voir [MemoBookSpacing.contentIcon]. */
    val controlIcon: Dp = MemoBookSpacing.contentIcon

    /**
     * Le fond des barres qui flottent au-dessus du fil — en-tête, rail de
     * suggestions, barre d'envoi.
     *
     * La maquette demande du blanc à 50 % **et** un flou de 50 : c'est un
     * matériau, que le système d'iOS donne (`Material.ultraThin`). Compose
     * Foundation ne floute pas ce qui passe **dessous** — `Modifier.blur` floute
     * le contenu lui-même : le crème de la marque, presque opaque, laisse
     * seulement deviner le fil qui passe derrière, sans que ses mots se
     * mélangent à ceux de la barre.
     */
    val barMaterial: Color = MemoBookColor.background.copy(alpha = 0.95f)

    /** Le pas entre deux messages du fil. */
    val messageSpacing: Dp = MemoBookSpacing.snug

    /**
     * L'air laissé entre deux messages **du même auteur**. Plus serré : deux
     * bulles de MEMO d'affilée sont une même prise de parole, pas deux.
     */
    val sameAuthorSpacing: Dp = MemoBookSpacing.xs / 2

    // ⚠️ `recordingBarCount` a disparu (Hugo, 19/09/2026). La frise ne compte
    // plus ses barres : elle en dessine autant que la place reçue peut en
    // tenir, et c'est ce qui l'empêche à la fois de s'arrêter avant le bord et
    // de faire grandir la barre qui la porte — voir `BrandWaveform`.

    /**
     * Combien de photos un envoi porte, et combien de vignettes sa bulle
     * montre : six, le plus que MEMO demande pour une étape sur deux pages
     * (`backend/src/services/photoBudget.ts`, Hugo, 01/10/2026). Le serveur
     * applique la même borne (`MAX_PHOTOS`, `routes/chat.ts`).
     */
    const val visiblePhotoCount = 6
}

/**
 * L'en-tête du chat : d'où l'on vient, de quoi on parle, et les deux réglages
 * du voyage. Jumeau de `ChatHeader` (`ChatHeader.swift`).
 *
 * Il flotte au-dessus du fil plutôt que de le pousser : le contenu passe
 * dessous et se laisse deviner, ce qui dit que la conversation continue
 * au-delà du bord haut. Il descend sous la barre d'état, et ses commandes
 * commencent sous elle.
 *
 * @param isAwaitingServer le serveur n'a pas encore reçu ce voyage : la roue
 *   et l'imprimante pâlissent — voir `TripAwaitingServer`.
 */
@Composable
fun ChatHeader(
    thread: ChatThread,
    onBack: () -> Unit,
    onSettings: () -> Unit,
    onBook: () -> Unit,
    modifier: Modifier = Modifier,
    isAwaitingServer: Boolean = false,
) {
    Row(
        modifier
            .fillMaxWidth()
            .background(ChatMetrics.barMaterial)
            .statusBarsPadding()
            .padding(horizontal = MemoBookSpacing.xs)
            .padding(bottom = MemoBookSpacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ChatHeaderButton(R.drawable.icon_arrow, ChatCopy.Voice.back, onBack)

        // Le titre se centre entre le retour et la roue — les deux `Spacer`
        // d'iOS — et, long, se coupe d'une ellipse : les deux commandes de
        // droite gardent toujours leur place.
        Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
            ChatHeaderIdentity(thread)
        }

        ChatHeaderButton(
            R.drawable.icon_settings,
            ChatCopy.Voice.settings,
            onSettings,
            Modifier.dimmedWhileAwaitingServer(isAwaitingServer),
        )
        // L'imprimante, **la même que sur l'accueil du voyage** (Hugo,
        // 17/09/2026) : les deux ouvrent l'aperçu du carnet, et deux dessins
        // pour une même porte se lisaient comme deux portes. C'est le même
        // écran que la bannière bleue du fil ouvre.
        ChatHeaderButton(
            R.drawable.icon_printer,
            ChatCopy.Voice.openPreview,
            onBook,
            Modifier.dimmedWhileAwaitingServer(isAwaitingServer),
        )
    }
}

/**
 * La vignette du voyage et son nom. Un seul élément pour TalkBack : la photo
 * ne dit rien que le titre ne dise déjà.
 */
@Composable
private fun ChatHeaderIdentity(thread: ChatThread, modifier: Modifier = Modifier) {
    Row(
        modifier.semantics(mergeDescendants = true) {
            contentDescription = thread.title
            heading()
        },
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ChatHeaderAvatar(thread)
        BrandText(thread.title, MemoBookFont.heading, Modifier.weight(1f, fill = false).clearAndSetSemantics {}, maxLines = 1)
    }
}

/**
 * La photo du voyage. Taille **fixe**, hors taille de police : une photo n'est
 * pas du texte, et un avatar qui grandit avec le corps pousserait le titre
 * hors de sa ligne au lieu de l'accompagner.
 */
@Composable
private fun ChatHeaderAvatar(thread: ChatThread) {
    Box(
        Modifier
            .size(MemoBookSpacing.avatarSide)
            .clip(CircleShape)
            .background(MemoBookColor.outline, CircleShape)
            .clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        // La montagne d'abord, la photo par-dessus : elle tient la place tant
        // que la photo charge, et la remplace si elle ne vient pas — les deux
        // phases de l'`AsyncImage` d'iOS.
        Image(
            painter = painterResource(R.drawable.icon_mountain),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.ink),
            modifier = Modifier.size(MemoBookSpacing.m),
        )
        thread.avatarUrl?.let { url ->
            AsyncImage(
                model = url.toString(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.matchParentSize(),
            )
        }
    }
}

/**
 * Une commande ronde de l'en-tête : une icône de 2 rem au centre d'une cible
 * de 3 rem.
 *
 * Sans fond, contrairement à celles de l'accueil d'un voyage : là-bas elles
 * sont posées sur une photo qu'on ne choisit pas et il leur faut un disque
 * pour rester lisibles. Ici le fond est le crème de la marque, et un disque de
 * plus ne ferait qu'alourdir la ligne.
 */
@Composable
private fun ChatHeaderButton(@DrawableRes icon: Int, label: String, action: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(ChatMetrics.control)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = PlainButtonIndication,
                role = Role.Button,
                onClick = action,
            )
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Image(
            painter = painterResource(icon),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.ink),
            modifier = Modifier.size(ChatMetrics.controlIcon),
        )
    }
}

/**
 * « Ton carnet prend forme » — la capsule posée sous l'en-tête, qui mène à
 * l'aperçu du carnet. Jumeau de `ChatPreviewBanner` (`ChatHeader.swift`).
 *
 * **Une capsule, pas une carte** (Hugo, 18/09/2026). La version d'avant tenait
 * trois lignes et toute la largeur du fil : elle se lisait comme un message de
 * plus, et un message qui revient toutes les dix secondes agace. Celle-ci
 * tient sur une ligne : elle se pose sur le fil sans le couvrir. Le compte de
 * souvenirs et de pages n'est plus écrit — il est dit à TalkBack, et l'aperçu
 * le montre.
 *
 * **Elle se détache par l'ombre, pas par la couleur** (Hugo, 15/10/2026). Elle
 * était en verre teinté du bleu du voyageur — c'est-à-dire de la couleur des
 * bulles qui défilent dessous : un calque ne porte pas la teinte de ce qu'il
 * survole, sinon il s'y fond. Crème, filet bleu et [MemoBookShadow.Raised]
 * désormais, l'ombre que la marque réserve à ce qui flotte au-dessus du fil.
 * Le filet et l'ombre sont aussi ce qui la distingue d'une bulle de MEMO, en
 * `surface` elle aussi, mais posée à plat sur la page.
 *
 * **Et à droite, sous l'imprimante de l'en-tête** plutôt qu'au milieu (même
 * jour) : les deux ouvrent le même aperçu, et deux portes alignées se lisent
 * comme une seule.
 *
 * **Toujours tapable** (Hugo, 30/09/2026). Elle se désactivait tant que le
 * serveur n'avait pas de PDF prêt (`isOpenable`) — donc presque toujours, sans
 * rien dire, alors que l'icône de carnet de l'en-tête ouvre le même aperçu sans
 * condition. C'est l'aperçu qui dit où en est le carnet, pas la capsule.
 */
@Composable
fun ChatPreviewBanner(preview: ChatBookPreview, onOpen: () -> Unit, modifier: Modifier = Modifier) {
    val iconSide = scaled(18.dp)
    val shape = RoundedCornerShape(percent = 50)
    val description = "${ChatCopy.previewTitle}. ${ChatCopy.previewSubtitle(memories = preview.memoryCount, pages = preview.pageCount)}"

    Row(
        modifier
            .brandShadow(MemoBookShadow.Raised, shape)
            .background(MemoBookColor.surface.copy(alpha = 0.95f), shape)
            .border(1.dp, MemoBookColor.outline, shape)
            .clip(shape)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = CardPressStyle,
                role = Role.Button,
                onClick = onOpen,
            )
            .clearAndSetSemantics {
                contentDescription = description
                onClick(label = ChatCopy.Voice.openPreview) { onOpen(); true }
            }
            .padding(horizontal = MemoBookSpacing.s, vertical = MemoBookSpacing.xs + 2.dp),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(
            painter = painterResource(R.drawable.icon_pdf),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.ink),
            modifier = Modifier.size(iconSide),
        )
        BrandText(ChatCopy.previewTitle, MemoBookFont.label, Modifier.weight(1f, fill = false), maxLines = 1)
        Image(
            painter = painterResource(R.drawable.icon_arrow_right),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.ink),
            modifier = Modifier.size(iconSide),
        )
    }
}

/**
 * L'accueil d'une conversation qui n'a rien dedans : le signe de la marque, le
 * voyage qu'on ouvre, et ce que MEMO propose d'en faire. Jumeau de
 * `ChatGreetingView`.
 *
 * Il occupe la place du fil au lieu de se poser au-dessus : une conversation
 * vide n'a pas de haut ni de bas, elle a un centre.
 */
@Composable
fun ChatGreetingView(greeting: ChatGreeting, modifier: Modifier = Modifier) {
    val markWidth = scaled(64.dp)
    Column(
        modifier
            .fillMaxWidth()
            .padding(horizontal = MemoBookSpacing.screenMargin, vertical = MemoBookSpacing.xl),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        BrandMarkDrawing(
            progress = 1f,
            color = MemoBookColor.action,
            modifier = Modifier
                .width(markWidth)
                .height(BrandMark.height(forWidth = markWidth))
                .clearAndSetSemantics {},
        )
        BrandText(
            greeting.title,
            MemoBookFont.bodySemibold,
            Modifier.semantics { heading() },
            textAlign = TextAlign.Center,
        )
        BrandText(greeting.message, MemoBookFont.bubble, color = MemoBookColor.inkMuted, textAlign = TextAlign.Center)
    }
}

/**
 * « Ta conversation est privée… » — la mention posée **en tête du fil**, avant
 * le premier message. Jumeau de `ChatPrivacyNote`.
 *
 * **Dans le fil, pas par-dessus** : elle défile avec la conversation, comme le
 * début d'une page, au lieu de flotter sous l'en-tête et de cacher une bulle.
 * En gris, en petit : elle rassure sans prendre la parole.
 */
@Composable
fun ChatPrivacyNote(modifier: Modifier = Modifier) {
    BrandText(
        ChatCopy.privacyNote,
        MemoBookFont.caption,
        modifier
            .fillMaxWidth()
            .padding(horizontal = MemoBookSpacing.screenMargin, vertical = MemoBookSpacing.xs),
        color = MemoBookColor.inkMuted,
        textAlign = TextAlign.Center,
    )
}

// MARK: - Aperçus

@Preview(locale = "fr-rFR", name = "En-tête, capsule de l’aperçu, accueil", widthDp = 390, heightDp = 520)
@Composable
private fun ChatHeaderPreview() {
    val thread = ChatThread.fixture(tripId = "trip-rome")
    Column(Modifier.background(MemoBookColor.background), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
        ChatHeader(thread, onBack = {}, onSettings = {}, onBook = {})
        ChatHeader(thread, onBack = {}, onSettings = {}, onBook = {}, isAwaitingServer = true)
        ChatPreviewBanner(ChatBookPreview(memoryCount = 4, pageCount = 12), onOpen = {}, Modifier.padding(horizontal = MemoBookSpacing.screenMargin))
        ChatPrivacyNote()
        thread.greeting?.let { ChatGreetingView(it) }
    }
}
