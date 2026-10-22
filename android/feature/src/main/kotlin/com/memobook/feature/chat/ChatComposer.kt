package com.memobook.feature.chat

import androidx.annotation.DrawableRes
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsBottomHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.core.ChatCopy
import com.memobook.core.ChatSuggestion
import com.memobook.core.DailyCreditCopy
import com.memobook.design.BrandButton
import com.memobook.design.BrandNotice
import com.memobook.design.BrandSkeleton
import com.memobook.design.BrandText
import com.memobook.design.BrandWaveform
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookShadow
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.brandShadow
import com.memobook.design.isAccessibilityTextSize
import com.memobook.design.isReduceMotionEnabled
import com.memobook.design.scaled
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import com.memobook.feature.home.CardPressStyle

/**
 * Ce qui est posé en bas de l'écran : les réponses que MEMO propose, et de quoi
 * répondre autrement. Jumeau de `ChatComposer` (`ChatComposer.swift`).
 *
 * Les deux bandes flottent au-dessus du fil sur le même fond que l'en-tête : la
 * conversation passe dessous et se laisse deviner, ce qui dit qu'elle continue
 * au-delà du bord.
 *
 * **Le crédit du jour** (Hugo, 03/10/2026) : pendant qu'on parle, le bandeau
 * rouge doux paraît à trente secondes de la limite **à la place des puces** —
 * qui n'ont rien à faire sous un micro ouvert. Au repos, « Crédit du jour
 * épuisé » se pose **au-dessus** d'elles quand on touche le micro ou le clavier
 * pâlis, et s'en va de lui-même : les puces sont gratuites, et c'est avec elles
 * qu'on valide une fiche (recette du 03/10/2026). **Dans la pile, jamais en
 * calque** : sinon il ne se toucherait pas. Quand on écrit, la boîte « trop
 * long » prend la place des puces ; le rappel discret des caractères qui
 * restent se glisse, lui, juste au-dessus du champ.
 *
 * @param keyboard le champ de saisie et celui qui garde le clavier pendant un
 *   vocal — l'`@FocusState` que l'écran tient sur iOS. Voir [ChatKeyboard].
 * @param onSubscribe ce que fait le bandeau « Crédit du jour épuisé » : ouvrir l'offre.
 * @param flyingSuggestionId la puce en vol vers le fil, s'il y en a une : la
 *   bande la cache, c'est sa copie en vol qu'on regarde.
 * @param extendsUnderSystemBars la barre est au pied de l'écran : son fond
 *   descend sous la barre de navigation, et le clavier la pousse.
 * @param onLaunch ce qu'une puce fait quand on la touche, avec son cadre à
 *   l'écran. `null` envoie tout de suite, sans vol.
 */
@Composable
fun ChatComposer(
    model: ChatModel,
    keyboard: ChatKeyboard,
    onAddPhotos: () -> Unit,
    modifier: Modifier = Modifier,
    onSubscribe: () -> Unit = {},
    flyingSuggestionId: String? = null,
    extendsUnderSystemBars: Boolean = false,
    onLaunch: ((ChatSuggestion, Rect) -> Unit)? = null,
) {
    // L'état, collecté pour que le pied se redessine avec lui : le modèle le
    // relit dans ses propriétés calculées.
    model.observe()
    val isRecording = model.recorder.state.collectAsStateWithLifecycle().value.isRecording
    val reduceMotion = isReduceMotionEnabled()
    val banner = model.creditBanner
    val notice = model.creditTextNotice

    Column(
        modifier
            .fillMaxWidth()
            .background(ChatMetrics.barMaterial)
            // La place gardée de la bande se rend en douceur quand MEMO a
            // répondu sans nouvelles puces ; le bandeau arrive et s'en va en
            // douceur — sur son **état**, pas sur son compte à rebours.
            .animateContentSize(if (reduceMotion) snap() else SwiftMotion.smooth(0.3f)),
    ) {
        // Un message vient de partir dans la file faute de réseau : la barre le
        // dit, et dit qu'on peut continuer (Hugo, 12/10/2026). **Dans la pile**,
        // comme le bandeau du crédit.
        AnimatedVisibility(
            visible = model.showsQueuedNotice && !isRecording,
            enter = if (reduceMotion) fadeIn(snap()) else fadeIn() + slideInVertically { it / 2 },
            exit = if (reduceMotion) fadeOut(snap()) else fadeOut() + slideOutVertically { it / 2 },
        ) {
            BrandNotice(
                ChatCopy.queuedOffline,
                Modifier
                    .padding(horizontal = MemoBookSpacing.snug)
                    .padding(top = MemoBookSpacing.xs),
            )
        }

        // Ce qui se pose au-dessus de la barre. Pendant qu'on parle, le bandeau
        // du compte à rebours **à la place** des puces, muettes de toute façon.
        // Sinon, le bandeau « épuisé » quand il est demandé, **au-dessus** de la
        // boîte « trop long » ou des puces — jamais à leur place : « Ça me
        // convient » doit rester à portée de doigt, crédit ou pas.
        if (isRecording && banner != null) {
            CreditBanner(banner, onSubscribe)
        } else {
            banner?.let { CreditBanner(it, onSubscribe) }
            if (notice is ChatCreditTextNotice.TooLong) {
                BrandNotice(
                    notice.message,
                    Modifier
                        .padding(horizontal = MemoBookSpacing.snug)
                        .padding(top = MemoBookSpacing.xs),
                    tone = BrandNotice.Tone.Information,
                )
            } else {
                ChatSuggestionRail(
                    model = model,
                    onAddPhotos = onAddPhotos,
                    flyingSuggestionId = flyingSuggestionId,
                    onLaunch = onLaunch,
                    isMuted = isRecording,
                )
            }
        }

        if (notice is ChatCreditTextNotice.Reminder) {
            BrandText(
                notice.message,
                MemoBookFont.caption,
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = MemoBookSpacing.screenMargin)
                    .padding(top = MemoBookSpacing.xs / 2)
                    .wrapContentWidth(Alignment.End),
                color = MemoBookColor.inkMuted,
            )
        }

        ChatSendingBar(model = model, keyboard = keyboard, onAddPhotos = onAddPhotos)

        // Au pied de l'écran, la barre descend sous la barre de navigation, et
        // le clavier la pousse : le fond la suit jusqu'au bord.
        if (extendsUnderSystemBars) {
            Spacer(Modifier.windowInsetsBottomHeight(WindowInsets.ime.union(WindowInsets.navigationBars)))
        }
    }
}

@Composable
private fun CreditBanner(banner: DailyCreditBanner, onSubscribe: () -> Unit) {
    DailyCreditBannerView(
        banner,
        onSubscribe,
        Modifier
            .padding(horizontal = MemoBookSpacing.snug)
            .padding(top = MemoBookSpacing.xs),
    )
}

/**
 * Le champ de saisie de la barre, et celui qui garde le clavier pendant un
 * vocal — les deux `@FocusState` que `ChatView` tient sur iOS. C'est l'écran
 * qui les crée ([rememberChatKeyboard]) : il replie le clavier quand la barre
 * quitte le champ, ou que le paywall s'ouvre.
 */
class ChatKeyboard internal constructor() {
    /** Le champ de saisie. */
    val field = FocusRequester()

    /**
     * **Le clavier levé pendant un vocal** (Hugo, 12/10/2026). Le clavier
     * appartient à un champ : quand le micro remplace le champ, il se baissait
     * au milieu de l'enregistrement. Un champ invisible le prend des mains du
     * vrai juste avant — Android passe le clavier d'un champ à l'autre sans le
     * baisser —, et le rend au champ quand la barre y revient.
     */
    val holder = FocusRequester()

    /** Le champ tient le clavier en ce moment. */
    internal var isWriting = false
}

@Composable
fun rememberChatKeyboard(): ChatKeyboard = remember { ChatKeyboard() }

/**
 * Les réponses toutes prêtes que MEMO propose. Jumeau de `ChatSuggestionRail`.
 *
 * **Une bande qui défile, comme celle des filtres d'un voyage.** Les puces
 * portent des phrases entières — « J'aimerais faire des modifications à la
 * main » —, aucune largeur de téléphone n'en tient trois, et les serrer les
 * rendrait illisibles.
 *
 * **Elle reste horizontale à toutes les tailles de texte**, contrairement à la
 * règle des composants en colonnes — et **chaque puce tient sur une ligne**,
 * aussi longue soit-elle. Les empiler en taille accessible mangeait la moitié
 * de l'écran au-dessus de la barre d'envoi ; les laisser se replier faisait
 * déborder leur seconde ligne de leur fond. Une bande qui défile a déjà sa
 * réponse au débordement, et c'est le défilement : la dernière puce sort par le
 * bord droit, comme la maquette le montre.
 *
 * @param isMuted un micro est ouvert : les puces s'effacent mais **gardent leur
 *   place**. Une puce touchée pendant qu'on parle partirait par-dessus le vocal,
 *   et la bande qui disparaîtrait ferait sauter le fil au premier mot ; c'est
 *   aussi là que le bandeau du crédit viendra se poser.
 */
@Composable
fun ChatSuggestionRail(
    model: ChatModel,
    onAddPhotos: () -> Unit,
    flyingSuggestionId: String? = null,
    onLaunch: ((ChatSuggestion, Rect) -> Unit)? = null,
    isMuted: Boolean = false,
) {
    // La hauteur d'une puce : **plus basse qu'une bulle du fil** (Hugo,
    // 29/09/2026) — 2 rem, en corps d'accroche — pour qu'on lise une
    // proposition et non un message déjà dit. Elle suit le corps du texte.
    val chipHeight = scaled(MemoBookSpacing.l)
    // La hauteur de la bande : la puce et ses marges, jamais moins qu'une
    // cible tactile — la puce est plus basse que 3 rem, la bande non.
    val railHeight = maxOf(MemoBookSpacing.minimumTapTarget, chipHeight + MemoBookSpacing.xs)
    val suggestions = model.visibleSuggestions
    // Les cadres des puces à l'écran : le point de départ du vol. Une boîte
    // **non observée** : ils changent à chaque image d'un défilement de la
    // bande, et seul le toucher les lit.
    val frames = remember { mutableMapOf<String, Rect>() }

    when {
        isMuted -> if (suggestions.isNotEmpty() || model.reservesSuggestionRail) {
            Spacer(
                Modifier
                    .padding(vertical = MemoBookSpacing.xs / 2)
                    .height(railHeight)
                    .clearAndSetSemantics {},
            )
        }
        suggestions.isNotEmpty() -> Row(
            Modifier
                .fillMaxWidth()
                .padding(vertical = MemoBookSpacing.xs / 2)
                // ⚠️ **La bande impose sa hauteur.** Sur iOS, une `ScrollView`
                // posée dans la barre se faisait attribuer une hauteur plus
                // courte que ses puces, qui restaient dessinées hors de sa zone
                // tactile. Ici aussi, la hauteur est celle de la cible.
                .height(railHeight)
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = MemoBookSpacing.snug),
            horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            suggestions.forEach { suggestion ->
                SuggestionChip(
                    suggestion = suggestion,
                    chipHeight = chipHeight,
                    railHeight = railHeight,
                    isFlying = flyingSuggestionId == suggestion.id,
                    onPositioned = { frames[suggestion.id] = it },
                ) {
                    val frame = frames[suggestion.id]
                    if (onLaunch != null && frame != null) {
                        onLaunch(suggestion, frame)
                    } else {
                        model.choose(suggestion, addPhotos = onAddPhotos)
                    }
                }
            }
        }
        // La place de la bande le temps que MEMO réponde — voir
        // `ChatModel.reservesSuggestionRail`. **Des puces grises qui
        // chargent**, et non une ligne vide (Hugo, 08/10/2026) : la bande dit
        // qu'elle attend les prochaines propositions.
        model.reservesSuggestionRail -> PendingChips(chipHeight, railHeight)
    }
}

/**
 * Trois puces de la forme et de la hauteur des vraies, en [BrandSkeleton] : le
 * reflet qui les traverse dit que ça charge, et la place qu'elles tiennent est
 * celle que les propositions prendront.
 *
 * Trois longueurs différentes, comme les vraies — trois barres égales se
 * liraient comme un motif, pas comme des phrases qui arrivent. ⚠️ **Bornée en
 * largeur** (Hugo, 12/10/2026 : « les skeleton loader élargissent la page du
 * chat ») : les trois puces font plus que l'écran, et c'est la dernière qui
 * sort par le bord, rognée — la bande ne défile pas.
 */
@Composable
private fun PendingChips(chipHeight: androidx.compose.ui.unit.Dp, railHeight: androidx.compose.ui.unit.Dp) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = MemoBookSpacing.xs / 2)
            .height(railHeight)
            .clipToBounds()
            .padding(horizontal = MemoBookSpacing.snug)
            .clearAndSetSemantics {},
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        PENDING_CHIP_WIDTHS.forEach { width ->
            BrandSkeleton(Modifier.wrapContentWidth(unbounded = true), width = width.dp, height = chipHeight)
        }
    }
}

private val PENDING_CHIP_WIDTHS = listOf(132, 176, 112)

@Composable
private fun SuggestionChip(
    suggestion: ChatSuggestion,
    chipHeight: androidx.compose.ui.unit.Dp,
    railHeight: androidx.compose.ui.unit.Dp,
    isFlying: Boolean,
    onPositioned: (Rect) -> Unit,
    onTap: () -> Unit,
) {
    val shape = RoundedCornerShape(percent = 50)
    // La cible reste à 3 rem, la puce dessinée plus basse.
    Box(
        Modifier
            .height(railHeight)
            // Pendant son vol, la puce laisse sa place vide : c'est sa copie
            // en vol qu'on regarde, et elle part d'ici.
            .alpha(if (isFlying) 0f else 1f)
            .onGloballyPositioned { onPositioned(it.boundsInWindow()) }
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = CardPressStyle,
                role = Role.Button,
                onClick = onTap,
            )
            .clearAndSetSemantics {
                contentDescription = suggestion.label
                onClick { onTap(); true }
            },
        contentAlignment = Alignment.Center,
    ) {
        // **Une capsule**, blanche, l'émoji devant : c'est la bulle des
        // propositions de la maquette de Hugo (`3520:35958`, 17/09/2026), et non
        // le rectangle arrondi des bulles du fil.
        Row(
            Modifier
                .height(chipHeight)
                .background(MemoBookColor.surface, shape)
                .border(1.dp, MemoBookColor.hairline, shape)
                .padding(horizontal = MemoBookSpacing.snug),
            horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // L'emoji est porté à part du libellé : il ne part pas dans le
            // message envoyé, et TalkBack ne le lit pas.
            suggestion.symbol?.let { BrandText(it, MemoBookFont.taglineRegular) }
            // Le corps d'accroche (14) et non celui des bulles (17) : une
            // proposition se lit plus petit que ce qu'on a dit. Une ligne,
            // jamais tronquée : la puce s'allonge autant qu'il faut, et c'est la
            // bande qui défile.
            BrandText(suggestion.label, MemoBookFont.taglineRegular, maxLines = 1)
        }
    }
}

// MARK: - La barre d'envoi

/** La disposition de la barre — trois modes du modèle, et l'enregistrement qui se lit sur le micro. */
private enum class BarLayout { Tools, Writing, Speaking, Recording }

/**
 * La barre d'envoi, dans ses quatre dispositions. Jumeau de `ChatSendingBar`.
 *
 * | Disposition | Ce qu'on voit | Nœud Figma |
 * |---|---|---|
 * | [ChatComposerMode.Tools] | photo · clavier · micro, à égalité de largeur | `start` |
 * | [ChatComposerMode.Speaking] | croix · photo · clavier serrés, « Record » qui s'étire | `Default` |
 * | [ChatComposerMode.Writing] | croix · le champ · le micro | `Start Typing` / `Finish Typing` |
 * | *en cours d'enregistrement* | croix · pause ou corbeille · la frise · le chrono · envoyer | `Start Recording` / `Finish Recording` |
 *
 * Le dernier n'est pas un mode : il se lit sur [com.memobook.recording.AudioRecorder.isRecording].
 * Deux sources pour le même fait finissent toujours par se contredire.
 *
 * **Chaque disposition a sa variante « sans micro »** — l'accès peut être
 * refusé pour de bon. Le bouton garde alors sa place, perd son cerne vert et
 * porte un micro **barré** : il a quelque chose à dire (où aller le
 * réautoriser), ce qu'un bouton absent ne dirait pas.
 *
 * **Tout bouge au ressort.** Les dispositions ne se remplacent pas, elles
 * s'échangent : ce qui part rétrécit, ce qui arrive dépasse d'un cheveu puis
 * revient. C'est ce léger dépassement qui fait que la barre a l'air vivante
 * plutôt que redessinée — et il s'annule sous « Supprimer les animations ».
 *
 * ⚠️ La maquette ne dessine **pas** la croix : ses états de saisie n'ont aucune
 * commande à gauche. Elle est ajoutée sur demande de Hugo — pouvoir revenir à
 * l'état d'origine à tout moment — et prend la place du burger, qui n'a de sens
 * qu'au repos.
 */
@Composable
fun ChatSendingBar(model: ChatModel, keyboard: ChatKeyboard, onAddPhotos: () -> Unit, modifier: Modifier = Modifier) {
    val state by model.state.collectAsStateWithLifecycle()
    val recording by model.recorder.state.collectAsStateWithLifecycle()
    val reduceMotion = isReduceMotionEnabled()
    val isAtRest = state.composer == ChatComposerMode.Tools && !recording.isRecording
    val layout = when {
        recording.isRecording -> BarLayout.Recording
        state.composer == ChatComposerMode.Tools -> BarLayout.Tools
        state.composer == ChatComposerMode.Writing -> BarLayout.Writing
        else -> BarLayout.Speaking
    }
    // Le ressort de la barre. Sous-amorti **exprès** : la barre dépasse d'un
    // cheveu puis revient, ce qui donne le rebond.
    val bounce = SwiftMotion.spring<Float>(response = 0.34f, dampingFraction = 0.62f)

    Box(
        modifier
            .fillMaxWidth()
            .padding(horizontal = MemoBookSpacing.snug, vertical = MemoBookSpacing.xs),
    ) {
        // Le champ qui garde le clavier pendant un vocal commencé au clavier —
        // voir [ChatKeyboard.holder]. Invisible, sans geste ni voix, et hors de
        // la rangée — le `.background` d'iOS : il ne fait que garder le
        // clavier, et ce qu'on y taperait ne va nulle part.
        if (state.composer == ChatComposerMode.Writing || state.returnsToWritingAfterRecording) {
            KeyboardHolder(keyboard)
        }

        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            // La croix, dès qu'un outil est ouvert — et rien au repos. C'est
            // **la** sortie de secours : quel que soit l'outil ouvert — clavier,
            // micro armé, enregistrement en cours —, une tape ramène la barre à
            // ses trois boutons. Le burger de la maquette, qui tenait cette
            // place au repos, est parti : rien n'était dessiné derrière (Hugo,
            // 16/09/2026). Son écart vit avec elle : au repos, les trois pavés
            // prennent toute la largeur.
            AnimatedVisibility(
                visible = !isAtRest,
                enter = if (reduceMotion) fadeIn(snap()) else scaleIn(bounce, initialScale = 0.6f) + fadeIn(),
                exit = if (reduceMotion) fadeOut(snap()) else scaleOut(targetScale = 0.6f) + fadeOut(),
            ) {
                Box(Modifier.padding(end = MemoBookSpacing.snug)) {
                    BarGlyph(R.drawable.icon_lucide_close, ChatCopy.Voice.collapse, MemoBookColor.ink) {
                        keyboard.isWriting = false
                        model.collapseComposer()
                    }
                }
            }

            AnimatedContent(
                targetState = layout,
                modifier = Modifier.weight(1f),
                transitionSpec = {
                    if (reduceMotion) {
                        fadeIn(snap()) togetherWith fadeOut(snap())
                    } else {
                        val scale = if (targetState == BarLayout.Tools) 0.9f else 0.94f
                        (scaleIn(bounce, initialScale = scale) + fadeIn()) togetherWith (scaleOut(targetScale = scale) + fadeOut())
                    }
                },
                label = "bar",
            ) { target ->
                when (target) {
                    BarLayout.Tools -> ToolControls(model, keyboard, onAddPhotos)
                    BarLayout.Writing -> WritingControls(model, keyboard)
                    BarLayout.Speaking -> SpeakingControls(model, keyboard, onAddPhotos)
                    BarLayout.Recording -> RecordingControls(model)
                }
            }
        }
    }
}

/** **Pâli, pas désactivé** (règle du design system) : le micro et le clavier d'un crédit épuisé gardent leur place et répondent au doigt. */
private fun Modifier.creditDimmed(model: ChatModel): Modifier {
    if (!model.isCreditExhausted) return this
    // Ce que TalkBack dit d'un micro, d'un clavier ou d'un champ pâlis : la
    // pâleur ne s'entend pas (03/10/2026).
    return alpha(0.45f).semantics { stateDescription = "${DailyCreditCopy.exhaustedTitle}. ${DailyCreditCopy.exhaustedDetail}" }
}

// MARK: Au repos — nœud `start`

/** Les trois commandes se partagent la largeur. C'est ce partage égal qui dit qu'aucune n'est la bonne : on raconte comme on veut. */
@Composable
private fun ToolControls(model: ChatModel, keyboard: ChatKeyboard, onAddPhotos: () -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug), verticalAlignment = Alignment.CenterVertically) {
        CameraButton(onAddPhotos, Modifier.weight(1f), fills = true)
        KeyboardButton(model, keyboard, Modifier.weight(1f), fills = true)
        MicButton(model, keyboard, Modifier.weight(1f), fills = true)
    }
}

// MARK: Le micro armé — nœud `Default`

/**
 * Photo et clavier se serrent pour laisser « Record » s'étirer : la barre dit
 * alors d'elle-même ce qu'on attend de nous.
 *
 * Sans micro, « Record » n'a rien à proposer : la barre bascule sur le champ de
 * saisie, exactement comme le nœud `Default snas micro`.
 */
@Composable
private fun SpeakingControls(model: ChatModel, keyboard: ChatKeyboard, onAddPhotos: () -> Unit) {
    if (model.microphoneIsDenied) {
        WritingControls(model, keyboard)
        return
    }
    Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug), verticalAlignment = Alignment.CenterVertically) {
        CameraButton(onAddPhotos, fills = false)
        KeyboardButton(model, keyboard, fills = false)

        // « Record » dans la maquette ; « Enregistrer » dans l'app (T51). Aux
        // tailles accessibles, le micro seul : à côté de deux boutons ronds, le
        // libellé se coupait lettre par lettre sur cinq lignes (recette du
        // 30/09/2026). TalkBack dit toujours ce qu'il fait.
        val accessible = isAccessibilityTextSize()
        BrandButton(
            title = if (accessible) null else ChatCopy.record,
            modifier = Modifier
                .weight(1f)
                .brandShadow(MemoBookShadow.Raised, RoundedCornerShape(percent = 50))
                .creditDimmed(model),
            icon = painterResource(R.drawable.icon_mic),
            iconPlacement = BrandButton.IconPlacement.Trailing,
            style = BrandButton.Style.Secondary,
            isRound = true,
            fillsWidth = true,
            contentDescription = ChatCopy.Voice.microphone,
            action = model::startRecording,
        )
    }
}

// MARK: Au clavier — nœuds `Start Typing` / `Finish Typing`

/**
 * Le micro **s'efface** quand on corrige une retranscription : on a choisi « à
 * la main », et à ce corps-là, un bouton de 48 à côté du champ coupait chaque
 * ligne à quatorze caractères — on ne relit pas cinquante mots dans une
 * colonne. Le champ prend toute la barre ; le micro revient avec le prochain
 * message.
 */
@Composable
private fun WritingControls(model: ChatModel, keyboard: ChatKeyboard) {
    Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs), verticalAlignment = Alignment.Bottom) {
        ComposerField(model, keyboard, Modifier.weight(1f))
        if (!model.isEditingTranscript) MicButton(model, keyboard, fills = false)
    }
}

/**
 * Le champ grandit avec ce qu'on écrit.
 *
 * `BrandTextField` ne convient pas ici : c'est un champ de formulaire à
 * étiquette flottante, d'une seule ligne et de 3.5 rem de haut. Un composeur de
 * conversation est un autre objet — il n'a pas d'étiquette, il s'agrandit, et
 * il vit dans une barre. Le contrat de focus, lui, reste celui de l'app : c'est
 * l'écran qui le tient ([ChatKeyboard]), pas le champ.
 *
 * C'est aussi ce champ qui porte l'état `Modifying transcription` de la
 * maquette : corriger une retranscription, c'est écrire un long texte, et le
 * champ s'y étire tout seul — voir la hauteur ci-dessous.
 *
 * **Trois lignes, et une seule au départ** (Hugo, 19/09/2026) : trois suffisent
 * à relire ce qu'on vient d'écrire ; au-delà, c'est le champ qui défile. **Dix
 * quand on corrige une retranscription** (Hugo, 17/09/2026) : là, c'est le
 * texte qu'on regarde, et il faut le lire en entier pour trouver les trois mots
 * à changer. En taille accessible, cinq : au-delà, le champ dépasserait l'écran
 * avec le clavier.
 */
@Composable
private fun ComposerField(model: ChatModel, keyboard: ChatKeyboard, modifier: Modifier = Modifier) {
    val state by model.state.collectAsStateWithLifecycle()
    val isPreview = LocalInspectionMode.current
    // La hauteur du champ à une ligne : **celle du texte**, et la cible de
    // l'avion au plus bas (Hugo, 19/10/2026).
    val fieldHeight = scaled(MemoBookSpacing.minimumTapTarget)
    // Ce qui sépare la cible de l'avion du bord droit du champ, pour que son
    // rond soit **aussi loin du bord que du haut et du bas**.
    val sendInset = maxOf(0.dp, (fieldHeight - MemoBookSpacing.contentIcon) / 2 - (MemoBookSpacing.minimumTapTarget - MemoBookSpacing.contentIcon) / 2)
    val maxLines = when {
        !state.isEditingTranscript -> 3
        isAccessibilityTextSize() -> 5
        else -> 10
    }
    // Une capsule tant que le champ tient sur une ligne, un rectangle arrondi
    // dès qu'il grandit : un rayon égal à la moitié de la ligne se comporte
    // comme une capsule à la hauteur d'origine, et cesse de gonfler ensuite.
    val shape = RoundedCornerShape(MemoBookSpacing.minimumTapTarget / 2)

    // Le champ qui apparaît prend le clavier. C'est ce qui manquait aux puces
    // « à la main » : elles ouvraient le champ, et il fallait encore le toucher
    // pour écrire dedans. **Une image après** qu'il est posé (Hugo,
    // 12/10/2026) : demandé dans la même passe que son apparition, le focus ne
    // prenait qu'une fois sur deux.
    LaunchedEffect(Unit) {
        if (isPreview) return@LaunchedEffect
        delay(20)
        runCatching { keyboard.field.requestFocus() }
    }

    Row(
        modifier
            .heightIn(min = fieldHeight)
            // Pâli, comme le micro, quand le crédit est épuisé : on peut encore
            // y toucher, le bandeau au-dessus dit pourquoi rien ne partira. Sauf
            // pour corriger une fiche : les 200 caractères offerts passent
            // encore (QA D8, 19/10/2026).
            .then(if (model.isWritingCorrection) Modifier else Modifier.creditDimmed(model))
            .brandShadow(MemoBookShadow.Raised, shape)
            .background(MemoBookColor.surface, shape)
            .border(1.dp, MemoBookColor.hairline, shape)
            .padding(start = MemoBookSpacing.s, end = sendInset),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        verticalAlignment = Alignment.Bottom,
    ) {
        Box(
            Modifier
                .weight(1f)
                .heightIn(min = fieldHeight),
            contentAlignment = Alignment.CenterStart,
        ) {
            if (state.draft.isEmpty()) {
                BrandText(ChatCopy.composerPlaceholder, MemoBookFont.composer, Modifier.clearAndSetSemantics {}, color = MemoBookColor.inkFaint, maxLines = 1)
            }
            BasicTextField(
                value = state.draft,
                onValueChange = { model.draft = it },
                modifier = Modifier
                    .fillMaxWidth()
                    // La marge du texte, et **elle seule** : c'est elle qui fait
                    // grandir le champ ligne après ligne. Quatre points : le
                    // champ épouse la ligne écrite, il ne l'encadre pas.
                    .padding(vertical = MemoBookSpacing.xs / 2)
                    .focusRequester(keyboard.field)
                    .onFocusChanged { keyboard.isWriting = it.isFocused }
                    .semantics { contentDescription = ChatCopy.composerPlaceholder },
                textStyle = MemoBookFont.composer.copy(color = MemoBookColor.ink),
                cursorBrush = SolidColor(MemoBookColor.send),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                minLines = 1,
                maxLines = maxLines,
            )
        }
        // L'avion garde sa cible de 3 rem en largeur, et prend la hauteur d'une
        // ligne du champ : son rond se centre sur la première ligne, puis reste
        // en bas quand le texte grandit.
        SendGlyph(isActive = model.canSendDraft, Modifier.height(fieldHeight), action = model::sendDraft)
    }
}

// MARK: Pendant qu'on parle — nœuds `Start Recording` / `Finish Recording`

/**
 * La frise, le chrono, et de quoi suspendre, jeter ou envoyer.
 *
 * Deux temps, comme la maquette : **en cours**, on peut suspendre, et la frise
 * qui bouge dit que ça enregistre ; **suspendu**, la pause devient une
 * corbeille — c'est là qu'on renonce — et la frise s'éteint sans s'effacer.
 * L'envoi est possible dans les deux.
 */
@Composable
private fun RecordingControls(model: ChatModel) {
    val recording by model.recorder.state.collectAsStateWithLifecycle()
    val levels by model.capturedLevels.collectAsStateWithLifecycle()
    val shape = RoundedCornerShape(percent = 50)

    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = MemoBookSpacing.minimumTapTarget)
            .brandShadow(MemoBookShadow.Raised, shape)
            .background(MemoBookColor.surface, shape)
            .padding(horizontal = MemoBookSpacing.snug),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (recording.isPaused) {
            BarGlyph(R.drawable.icon_trash, ChatCopy.Voice.discardRecording, MemoBookColor.error, action = model::cancelRecording)
        } else {
            BarGlyph(R.drawable.icon_lucide_pause_circle, ChatCopy.Voice.pauseRecording, MemoBookColor.error, action = model::pauseRecording)
        }

        BrandWaveform(live = levels, modifier = Modifier.weight(1f), size = BrandWaveform.Size.Bar, isDimmed = recording.isPaused)

        BrandText(recording.elapsed.chatDurationLabel, MemoBookFont.label.copy(fontFeatureSettings = "tnum"), maxLines = 1)

        // ⚠️ Il y avait ici un petit micro vert, entre le chrono et l'envoi.
        // Retiré (Hugo, 19/09/2026) : la frise qui bouge et le chrono qui court
        // disent déjà qu'on enregistre, et il ne se touchait pas. Sa place
        // revient à la frise.
        SendGlyph(isActive = true, action = model::finishRecording)
    }
}

// MARK: Les trois pavés ronds

@Composable
private fun CameraButton(onAddPhotos: () -> Unit, modifier: Modifier = Modifier, fills: Boolean) {
    RoundButton(R.drawable.icon_lucide_camera, ChatCopy.Voice.camera, BrandButton.Style.Secondary, fills, modifier, action = onAddPhotos)
}

@Composable
private fun KeyboardButton(model: ChatModel, keyboard: ChatKeyboard, modifier: Modifier = Modifier, fills: Boolean) {
    RoundButton(
        R.drawable.icon_lucide_keyboard,
        ChatCopy.Voice.keyboard,
        BrandButton.Style.Raised,
        fills,
        modifier.creditDimmed(model),
    ) {
        // Le champ qui apparaît prend le clavier de lui-même.
        model.tapKeyboard()
    }
}

/**
 * Le micro, dans ses deux états.
 *
 * Refusé pour de bon, il **garde sa place** : perdre son cerne vert et porter
 * un micro barré dit où on en est, alors qu'un bouton qui disparaît laisse
 * croire à un bug. Une tape ouvre alors les Paramètres, seul recours.
 *
 * Touché clavier levé : le clavier **reste** levé pendant qu'on parle. Le champ
 * invisible le prend d'abord, puis le micro s'arme — une image plus tard, pour
 * que le clavier ait changé de mains avant que le champ visible parte.
 */
@Composable
private fun MicButton(model: ChatModel, keyboard: ChatKeyboard, modifier: Modifier = Modifier, fills: Boolean) {
    val scope = rememberCoroutineScope()
    if (model.microphoneIsDenied) {
        RoundButton(
            R.drawable.icon_lucide_mic_off,
            ChatCopy.Voice.microphoneDenied,
            BrandButton.Style.Raised,
            fills,
            modifier,
            isMuted = true,
            action = model::openMicrophoneSettings,
        )
    } else {
        RoundButton(R.drawable.icon_mic, ChatCopy.Voice.microphone, BrandButton.Style.Secondary, fills, modifier.creditDimmed(model)) {
            if (!keyboard.isWriting || model.composer != ChatComposerMode.Writing || model.isCreditExhausted) {
                model.tapMicrophone()
            } else {
                runCatching { keyboard.holder.requestFocus() }
                scope.launch {
                    delay(20)
                    model.tapMicrophone(keepingKeyboard = true)
                }
            }
        }
    }
}

@Composable
private fun RoundButton(
    @DrawableRes icon: Int,
    label: String,
    style: BrandButton.Style,
    fills: Boolean,
    modifier: Modifier = Modifier,
    isMuted: Boolean = false,
    action: () -> Unit,
) {
    val shape = RoundedCornerShape(percent = 50)
    BrandButton(
        modifier = modifier
            .brandShadow(MemoBookShadow.Raised, shape)
            // `BrandButton.Style.Raised` n'a pas de contour ; le micro refusé,
            // lui, en veut un — gris. C'est le seul cerne de la barre qui ne
            // soit pas vert, et il n'existe que pour cet état-là.
            .then(if (isMuted) Modifier.border(1.dp, MemoBookColor.disabledOutline, shape) else Modifier),
        icon = painterResource(icon),
        style = style,
        isRound = true,
        fillsWidth = fills,
        contentDescription = label,
        action = action,
    )
}

/**
 * Le bouton d'envoi : **un rond plein du bleu qui s'écrit, l'avion en blanc
 * dedans** (Hugo, 17/09/2026, T59). Gris tant qu'il n'y a rien à envoyer, bleu
 * dès qu'il y a un mot : c'est le seul endroit de la barre où la couleur
 * annonce que l'action vient de devenir possible — avec un petit sursaut, parce
 * que c'est le moment où le message devient envoyable.
 */
@Composable
private fun SendGlyph(isActive: Boolean, modifier: Modifier = Modifier, action: () -> Unit) {
    val glyph = scaled(MemoBookSpacing.sectionGap)
    val reduceMotion = isReduceMotionEnabled()
    val scale by animateFloatAsState(
        if (isActive) 1f else 0.86f,
        if (reduceMotion) snap() else SwiftMotion.spring(response = 0.34f, dampingFraction = 0.62f),
        label = "send",
    )
    Box(
        modifier
            .sizeIn(minWidth = MemoBookSpacing.minimumTapTarget, minHeight = MemoBookSpacing.minimumTapTarget)
            .clickable(
                enabled = isActive,
                interactionSource = remember { MutableInteractionSource() },
                indication = PlainButtonIndication,
                role = Role.Button,
                onClick = action,
            )
            .semantics { contentDescription = ChatCopy.Voice.send },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .scale(scale)
                .size(MemoBookSpacing.contentIcon)
                .background(if (isActive) MemoBookColor.send else MemoBookColor.disabledOutline, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            // **Un point à gauche, un point en bas** (Hugo, 19/09/2026).
            // L'avion pointe vers le coin haut droit : sa masse est en bas à
            // gauche, et centré au pixel il se lisait poussé vers le haut à
            // droite de son rond. C'est un recentrage optique.
            Image(
                painter = painterResource(R.drawable.icon_lucide_send),
                contentDescription = null,
                colorFilter = ColorFilter.tint(MemoBookColor.surface),
                modifier = Modifier
                    .offset(x = (-1).dp, y = 1.dp)
                    .size(glyph * 0.8f),
            )
        }
    }
}

/** Une icône nue posée dans la barre, dans une cible de 3 rem. */
@Composable
private fun BarGlyph(@DrawableRes icon: Int, label: String, tint: Color, action: () -> Unit) {
    val glyph = scaled(MemoBookSpacing.sectionGap)
    Box(
        Modifier
            .sizeIn(minWidth = MemoBookSpacing.minimumTapTarget, minHeight = MemoBookSpacing.minimumTapTarget)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = PlainButtonIndication,
                role = Role.Button,
                onClick = action,
            )
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Image(painterResource(icon), contentDescription = null, colorFilter = ColorFilter.tint(tint), modifier = Modifier.size(glyph))
    }
}

/**
 * Lit l'état du modèle pour que l'appelant se redessine avec lui — les
 * propriétés calculées du modèle (`creditBanner`, `canSendDraft`…) le relisent.
 */
@Composable
internal fun ChatModel.observe(): ChatModel.State = state.collectAsStateWithLifecycle().value

/** Le champ invisible qui garde le clavier — voir [ChatKeyboard.holder]. */
@Composable
private fun KeyboardHolder(keyboard: ChatKeyboard) {
    BasicTextField(
        value = TextFieldValue(""),
        onValueChange = {},
        modifier = Modifier
            .size(1.dp)
            .alpha(0f)
            .focusRequester(keyboard.holder)
            .clearAndSetSemantics {},
    )
}

/**
 * La pastille « Retourner en bas », qui n'apparaît que si on est remonté.
 * Jumeau de `ChatBackToBottomPill`.
 *
 * Elle flotte au-dessus de la barre d'envoi plutôt que d'y prendre place :
 * c'est un raccourci de lecture, pas une commande de la conversation, et il
 * disparaît dès qu'il a servi.
 */
@Composable
fun ChatBackToBottomPill(action: () -> Unit, modifier: Modifier = Modifier) {
    val glyph = scaled(MemoBookSpacing.m)
    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)
    Row(
        modifier
            .heightIn(min = MemoBookSpacing.minimumTapTarget)
            .brandShadow(MemoBookShadow.Soft, shape)
            .background(MemoBookColor.surface, shape)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = CardPressStyle,
                role = Role.Button,
                onClick = action,
            )
            .clearAndSetSemantics {
                contentDescription = ChatCopy.backToBottom
                onClick { action(); true }
            }
            .padding(horizontal = MemoBookSpacing.s, vertical = MemoBookSpacing.xs),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BrandText(ChatCopy.backToBottom, MemoBookFont.bodySemibold)
        Image(
            painter = painterResource(R.drawable.icon_lucide_arrow_down),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.ink),
            modifier = Modifier.size(glyph),
        )
    }
}

// MARK: - Aperçus

/** Les dispositions de la barre, empilées comme le nœud Figma les aligne. */
@Preview(locale = "fr-rFR", name = "Barre d’envoi — ses dispositions", widthDp = 390, heightDp = 700)
@Composable
private fun ChatSendingBarPreview() {
    val audio = rememberPreviewChatAudio()
    val thread = com.memobook.core.ChatThread.fixture(tripId = "trip-rome")
    Column(
        Modifier
            .background(MemoBookColor.background)
            .verticalScroll(rememberScrollState())
            .padding(vertical = MemoBookSpacing.s),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        PreviewBar("Au repos", ChatModel.preview(thread, audio))
        PreviewBar("Micro refusé", ChatModel.preview(thread, audio, microphoneIsDenied = true))
        PreviewBar("Micro armé", ChatModel.preview(thread, audio, composer = ChatComposerMode.Speaking))
        PreviewBar("Au clavier, rien à envoyer", ChatModel.preview(thread, audio, composer = ChatComposerMode.Writing))
        PreviewBar(
            "Au clavier, prêt à envoyer",
            ChatModel.preview(thread, audio, composer = ChatComposerMode.Writing, draft = "On a marché jusqu’au marché"),
        )
    }
}

/**
 * Le crédit du jour dans le pied du chat : les deux phases du bandeau, le micro
 * pâli, la boîte « trop long » et le rappel des caractères. Le micro ne tourne
 * pas dans un aperçu : le bandeau d'enregistrement y est posé tel quel.
 */
@Preview(locale = "fr-rFR", name = "Barre d’envoi — le crédit du jour", widthDp = 390, heightDp = 1100)
@Composable
private fun ChatCreditPreview() {
    val audio = rememberPreviewChatAudio()
    val thread = com.memobook.core.ChatThread.fixture(tripId = "trip-rome")
    Column(
        Modifier
            .background(MemoBookColor.background)
            .verticalScroll(rememberScrollState())
            .padding(vertical = MemoBookSpacing.s),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        PreviewComposer(
            "Plus que 24 secondes",
            ChatModel.preview(thread, audio, dailyCredit = ChatCreditFixture.lastSeconds, creditBanner = DailyCreditBanner.Warning(24_000)),
        )
        PreviewComposer(
            "Les 5 dernières secondes, qui pulsent",
            ChatModel.preview(thread, audio, dailyCredit = ChatCreditFixture.lastSeconds, creditBanner = DailyCreditBanner.Urgent(3_000)),
        )
        PreviewComposer(
            "Épuisé : micro et clavier pâlis, bandeau touché",
            ChatModel.preview(thread, audio, dailyCredit = ChatCreditFixture.exhausted, showsExhaustedNotice = true),
        )
        PreviewComposer(
            "Au clavier, message trop long",
            ChatModel.preview(
                thread,
                audio,
                composer = ChatComposerMode.Writing,
                draft = "On a marché jusqu’au marché. ".repeat(30),
                dailyCredit = ChatCreditFixture.lastSeconds,
            ),
        )
        PreviewComposer(
            "Au clavier, moins d’une minute de crédit",
            ChatModel.preview(thread, audio, composer = ChatComposerMode.Writing, draft = "On a marché jusqu’au marché", dailyCredit = ChatCreditFixture.lastSeconds),
        )
        PreviewComposer("Abonné : rien de tout ça", ChatModel.preview(thread, audio, dailyCredit = ChatCreditFixture.unlimited))
    }
}

@Composable
private fun PreviewBar(title: String, model: ChatModel) {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2)) {
        BrandText(title, MemoBookFont.caption, Modifier.padding(horizontal = MemoBookSpacing.screenMargin), color = MemoBookColor.inkMuted)
        ChatSendingBar(model, rememberChatKeyboard(), onAddPhotos = {}, Modifier.background(ChatMetrics.barMaterial))
    }
}

@Composable
private fun PreviewComposer(title: String, model: ChatModel) {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2)) {
        BrandText(title, MemoBookFont.caption, Modifier.padding(horizontal = MemoBookSpacing.screenMargin), color = MemoBookColor.inkMuted)
        ChatComposer(model, rememberChatKeyboard(), onAddPhotos = {})
    }
}

/** Le micro, le lecteur et la voix d'un aperçu : rien n'y tourne, mais le modèle en demande. */
@Composable
internal fun rememberPreviewChatAudio(): ChatAudio {
    val context = LocalContext.current
    return remember(context) { ChatAudio(context.applicationContext ?: context, File(context.cacheDir, "chat-preview")) }
}

