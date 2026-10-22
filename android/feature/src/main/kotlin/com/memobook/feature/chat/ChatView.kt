package com.memobook.feature.chat

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.snap
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableStateSetOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.core.ChatAuthor
import com.memobook.core.ChatCallToAction
import com.memobook.core.ChatCopy
import com.memobook.core.ChatMessage
import com.memobook.core.ChatMessageBody
import com.memobook.core.ChatSuggestion
import com.memobook.core.ChatThread
import com.memobook.core.Subscription
import com.memobook.design.BrandBackdrop
import com.memobook.design.BrandChatBubble
import com.memobook.design.BrandNotice
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandText
import com.memobook.design.ErrorBanner
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.SwiftMotion
import com.memobook.design.isReduceMotionEnabled
import com.memobook.feature.ChatIntent
import com.memobook.feature.LocalAppSettings
import com.memobook.feature.LocalSubscriptionSession
import com.memobook.feature.LocalTripsAwaitingServer
import com.memobook.feature.PaywallVariant
import com.memobook.feature.PhotoFlowHost
import com.memobook.feature.notifications.NotificationAuthorization
import com.memobook.feature.paywall.PaywallView
import com.memobook.feature.rememberPhotoFlow
import com.memobook.feature.trip.AwaitingServerNotice
import com.memobook.recording.RecordingError
import com.memobook.recording.RecordingPermission
import com.memobook.feature.recording.rememberRecordingPermissionRequest
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * La conversation avec MEMO : on raconte, il écoute, et le carnet se remplit
 * pendant ce temps-là. Jumeau de `ChatView.swift`.
 *
 * **L'écran ne contient aucun contenu.** Titre, bulles, fiches, suggestions,
 * compteurs : tout vient du [ChatThread] que porte [ChatModel]. Ce qui est écrit
 * ici, ce sont les seuls libellés qui appartiennent à l'interface — et ils
 * vivent eux-mêmes dans [ChatCopy].
 *
 * **Aucune bulle blanche ne s'écrit à la main.** Chacune est produite par MEMO
 * à partir du message bleu qui la précède : c'est lui qui lit ce qu'on vient de
 * dire, choisit quoi répondre, et décide du temps qu'il prend pour le faire.
 *
 * **Trois couches, une seule qui défile.** Le fil occupe tout l'écran ;
 * l'en-tête et la barre d'envoi flottent au-dessus de lui. La conversation
 * passe donc dessous et se laisse deviner — c'est ce qui dit qu'elle continue
 * au-delà des deux bords. Le fil se pose **à l'envers** (`reverseLayout`) : il
 * s'ouvre sur sa fin, une conversation courte tombe au pied de l'écran, et le
 * clavier ou le bandeau du crédit qui font grandir le pied le poussent avec
 * lui — le `defaultScrollAnchor(.bottom)` d'iOS.
 *
 * @param tripId le voyage dont on parle. Gardé pour les deux commandes de
 *   l'en-tête, qui mènent aux réglages du voyage et à l'aperçu de son carnet.
 * @param stepId l'étape sur laquelle se poser en arrivant, consommée **une
 *   fois** : se replacer à chaque nouveau message empêcherait de lire la suite.
 * @param arrivesWithRecording on arrive avec un vocal enregistré depuis
 *   l'accueil. Le fil a déjà beaucoup à faire — poser la bulle, suivre la
 *   transcription, défiler — et la bannière d'aperçu n'y ajoute que du
 *   mouvement : elle ne descend pas à l'ouverture dans ce cas (Hugo,
 *   18/09/2026).
 */
@Composable
fun ChatView(
    model: ChatModel,
    tripId: String,
    onIntent: (ChatIntent) -> Unit,
    onBack: () -> Unit,
    stepId: String? = null,
    arrivesWithRecording: Boolean = false,
) {
    val state by model.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val settings = LocalAppSettings.current
    val subscriptionSession = LocalSubscriptionSession.current
    val reduceMotion = isReduceMotionEnabled()
    val scope = rememberCoroutineScope()
    val focusManager = LocalFocusManager.current
    val keyboardController = LocalSoftwareKeyboardController.current
    val keyboard = rememberChatKeyboard()

    // Le parcours d'ajout de photos : feuille de choix, sélecteur ou appareil
    // photo. Voir `PhotoFlow`.
    val photos = rememberPhotoFlow()

    // Le paywall, ouvert par le bouton « Raconter sans limite » d'une bulle de
    // MEMO, ou par le bandeau « Crédit du jour épuisé » au-dessus de la barre
    // (Hugo, 03/10/2026). Plus jamais par le micro lui-même : tout le monde
    // raconte, cinq minutes par jour et par voyage.
    var showsPaywall by remember { mutableStateOf(false) }

    // Le fil est posé : ce qui arrive **ensuite** est un envoi ou une réponse,
    // et se dessine comme tel. À l'ouverture, les messages déjà là ne rejouent
    // pas leur arrivée.
    var isSettled by remember { mutableStateOf(false) }

    // La fiche du contexte du voyage, ouverte depuis sa pastille.
    var showsTripContext by remember { mutableStateOf(false) }

    // Les voyages que le serveur n'a pas encore reçus : la roue et
    // l'imprimante de l'en-tête pâlissent pour celui-ci (T239).
    val isAwaitingServer = tripId in LocalTripsAwaitingServer.current
    var showsAwaitingServer by remember { mutableStateOf(false) }

    // Le bas de l'en-tête, en coordonnées de la fenêtre : la boîte « Disponible
    // dès ta reconnexion » se pose juste dessous.
    var headerBottom by remember { mutableStateOf(0.dp) }

    // Ce qu'Android a répondu pour les notifications, relu à l'ouverture et à
    // chaque retour au premier plan — au retour des Paramètres, surtout. `null`
    // tant qu'on ne l'a pas lu. Voir `ChatNotificationsNudge` (T246).
    var notificationAuthorization by remember { mutableStateOf<NotificationAuthorization?>(null) }
    val refreshNotificationAuthorization: suspend () -> Unit = {
        notificationAuthorization = NotificationsNudge.systemAuthorization(context, settings)
    }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        scope.launch { refreshNotificationAuthorization() }
    }

    // La page de MemoBook dans les Paramètres du téléphone : le seul recours
    // après un micro refusé pour de bon — et le chemin de l'accès aux photos,
    // le bouton « Modifier l’autorisation » d'une bulle de MEMO.
    val openSettings: () -> Unit = {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(intent) }
    }

    ChatDeviceBridge(model, openSettings)

    // `.task` d'iOS : à **chaque** apparition, donc aussi au retour des
    // réglages, posés par-dessus dans la pile : « Supprimer la conversation » a
    // pu vider le fil, et c'est lui qu'on retrouve. Le fil n'est jamais mis en
    // cache pour s'ouvrir — « un fil périmé se lit comme un message perdu ».
    LaunchedEffect(model) {
        model.load()
        // Les bulles qu'on vient de lire sont posées ; celles qui suivent
        // arrivent.
        isSettled = true
    }
    // Un écran de chat laissé derrière soi ne doit ni parler ni enregistrer.
    DisposableEffect(model) { onDispose { model.teardown() } }
    // La session d'abonnement, prêtée au modèle : un achat fait passer le crédit
    // du jour en illimité tout de suite — plus de bandeau, plus de micro pâli —,
    // sans attendre que le serveur le redise.
    SideEffect { model.subscription = subscriptionSession }

    // **La barre quitte le champ, le clavier part avec elle — dans le même
    // temps** (Hugo, 12/10/2026). Une puce, des photos, un vocal parti : le
    // champ sortait en transition et gardait le clavier jusqu'au bout. Sauf
    // pour un vocal commencé clavier levé, qui le garde.
    LaunchedEffect(state.composer, state.returnsToWritingAfterRecording) {
        if (state.composer == ChatComposerMode.Writing || state.returnsToWritingAfterRecording) return@LaunchedEffect
        focusManager.clearFocus()
        keyboardController?.hide()
    }

    val openFromServer: (ChatIntent) -> Unit = { intent ->
        // Les réglages et l'aperçu sont des écrans du serveur : pour un voyage
        // qu'il n'a pas encore reçu, l'appui dit pourquoi au lieu d'ouvrir un
        // écran d'erreur (T239).
        if (isAwaitingServer) showsAwaitingServer = true else onIntent(intent)
    }
    // Le paywall en plein écran. Le clavier se replie d'abord : il resterait
    // sinon ouvert derrière l'offre, et au retour.
    val openPaywall: () -> Unit = {
        focusManager.clearFocus()
        keyboardController?.hide()
        showsPaywall = true
    }
    // Ce que le bouton d'une bulle de MEMO ouvre — `ChatCallToAction.Kind`.
    // Rien ne part dans le fil : un bouton ouvre un écran, il ne dit rien à
    // MEMO. Chaque destination passe par le chemin qui l'ouvre déjà d'ici —
    // l'en-tête pour les réglages et l'aperçu, la puce pour les photos.
    val perform: (ChatCallToAction) -> Unit = { callToAction ->
        when (callToAction.kind) {
            ChatCallToAction.Kind.Subscribe -> openPaywall()
            ChatCallToAction.Kind.OpenTripSettings -> openFromServer(ChatIntent.OpenSettings(tripId))
            ChatCallToAction.Kind.OpenPreview -> openFromServer(ChatIntent.OpenBookPreview(tripId))
            ChatCallToAction.Kind.ImportPhotos -> photos.begin()
            ChatCallToAction.Kind.OpenPhotoSettings -> openSettings()
            // Posé par l'app seule (`ChatNotificationsNudge`), qui le traite
            // elle-même ; venu du serveur, la page de MemoBook dans les
            // Paramètres, où se trouvent les notifications.
            ChatCallToAction.Kind.EnableNotifications -> openSettings()
            // Jamais affiché (`ChatModel.showsCallToAction`) : un bouton inconnu
            // ne mènerait nulle part.
            is ChatCallToAction.Kind.Unknown -> Unit
        }
    }

    Box(Modifier.fillMaxSize()) {
        BrandBackdrop(Modifier.fillMaxSize())

        AwaitingServerNotice(
            isPresented = showsAwaitingServer,
            onIsPresentedChange = { showsAwaitingServer = it },
            below = headerBottom,
            modifier = Modifier.fillMaxSize(),
        ) {
            val thread = state.thread
            when {
                thread != null -> ChatConversation(
                    thread = thread,
                    model = model,
                    keyboard = keyboard,
                    tripId = tripId,
                    stepId = stepId,
                    arrivesWithRecording = arrivesWithRecording,
                    isSettled = isSettled,
                    isAwaitingServer = isAwaitingServer,
                    notificationAuthorization = notificationAuthorization,
                    photosDeniedMessage = photos.deniedMessage,
                    onRefreshNotifications = refreshNotificationAuthorization,
                    onHeaderBottom = { headerBottom = it },
                    onBack = onBack,
                    onOpenFromServer = openFromServer,
                    onAddPhotos = photos::begin,
                    onSubscribe = openPaywall,
                    onCallToAction = perform,
                    onOpenTripContext = { showsTripContext = true },
                    onOpenSettings = openSettings,
                )
                state.thread == null && state.errorMessage == null -> ChatSkeleton()
                // La conversation n'a pas pu être chargée du tout : il n'y a pas
                // de fil à montrer, donc pas de bandeau en ligne où poser
                // l'erreur.
                else -> Box(
                    Modifier
                        .fillMaxSize()
                        .padding(horizontal = MemoBookSpacing.screenMargin),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorBanner(state.errorMessage.orEmpty(), retry = { scope.launch { model.load() } })
                }
            }
        }

        PhotoFlowHost(photos) { model.sendPhotos(it) }

        BrandSheetHost(isPresented = showsTripContext, onDismissRequest = { showsTripContext = false }) {
            state.thread?.tripContext?.let { ChatTripContextSheet(it) }
        }

        // La photo en plein écran, par-dessus tout — le `fullScreenCover` d'iOS.
        AnimatedVisibility(
            visible = state.viewedPhotos != null,
            enter = fadeIn(if (reduceMotion) snap() else SwiftMotion.smooth(0.25f)),
            exit = fadeOut(if (reduceMotion) snap() else SwiftMotion.smooth(0.25f)),
        ) {
            val viewing = remember { mutableStateOf<ChatPhotoViewing?>(null) }
            state.viewedPhotos?.let { viewing.value = it }
            viewing.value?.let { ChatPhotoViewer(it, model) { model.viewedPhotos = null } }
        }

        // Le paywall, plein écran, monté du bas.
        AnimatedVisibility(
            visible = showsPaywall,
            enter = if (reduceMotion) fadeIn(snap()) else slideInVertically(SwiftMotion.smooth(0.35f)) { it },
            exit = if (reduceMotion) fadeOut(snap()) else slideOutVertically(SwiftMotion.smooth(0.3f)) { it },
        ) {
            PaywallView(
                subscription = Subscription.offer,
                onSubscribe = {
                    subscriptionSession?.record(isSubscribed = true)
                    showsPaywall = false
                    model.refreshAfterSubscribing()
                },
                onDismiss = { showsPaywall = false },
                // La version « retour » pour qui a déjà été abonné — la session
                // l'a appris de l'accueil ou du profil.
                variant = subscriptionSession?.paywallVariant ?: PaywallVariant.FirstTime,
                previewMemoId = tripId,
            )
        }
    }
}

/**
 * Ce que le modèle demande au téléphone — vibrer, parler à TalkBack, copier,
 * ouvrir les Paramètres, poser la question du micro —, prêté par l'écran le
 * temps qu'il est à l'écran, et repris en partant : un `ViewModel` survit à
 * son activité.
 */
@Composable
private fun ChatDeviceBridge(model: ChatModel, openSettings: () -> Unit) {
    val haptics = LocalHapticFeedback.current
    val view = LocalView.current
    val context = LocalContext.current
    val requestMicrophone = rememberRecordingPermissionRequest()

    DisposableEffect(model, haptics, view, context, requestMicrophone) {
        model.onFeedback = { feedback ->
            haptics.performHapticFeedback(
                when (feedback) {
                    ChatModel.Feedback.Warning -> HapticFeedbackType.Reject
                    ChatModel.Feedback.Light -> HapticFeedbackType.SegmentTick
                    ChatModel.Feedback.Medium -> HapticFeedbackType.ContextClick
                    ChatModel.Feedback.Success -> HapticFeedbackType.Confirm
                },
            )
        }
        model.onAnnouncement = { message ->
            @Suppress("DEPRECATION")
            view.announceForAccessibility(message)
        }
        model.onCopy = { text ->
            context.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(ClipData.newPlainText(text, text))
        }
        model.onOpenSettings = openSettings
        model.isScreenReaderOn = {
            context.getSystemService(AccessibilityManager::class.java)?.isTouchExplorationEnabled == true
        }
        model.audio.requestPermission = requestMicrophone
        model.audio.permissionState = { RecordingPermission.current(context) }
        onDispose {
            model.onFeedback = null
            model.onAnnouncement = null
            model.onCopy = null
            model.onOpenSettings = null
            model.isScreenReaderOn = { false }
            model.audio.requestPermission = null
            model.audio.permissionState = null
        }
    }
}

/** Une puce de suggestion en vol vers le fil — voir [ChatConversation]. */
private class SuggestionFlight(
    val suggestion: ChatSuggestion,
    /** Le cadre de la puce au départ, en coordonnées de la fenêtre. */
    val from: Rect,
) {
    /** La taille de la bulle en vol, mesurée une fois posée. */
    var size by mutableStateOf(IntSize.Zero)

    /** De 0 (sur la puce) à 1 (posée au bas du fil). */
    val progress = Animatable(0f)

    /** De combien le fil se lève pour laisser la place à la bulle. */
    val lift = Animatable(0f)

    /** Le vrai message a pris sa place : la puce s'efface. */
    var hasLanded by mutableStateOf(false)
}

/**
 * Les compteurs du défilement de la conversation : de combien on a remonté ou
 * redescendu sans changer de sens. Jumeau de `ChatScrollTracker`. Une classe
 * **sans observation** : les écrire ne redessine rien — seule la bannière
 * qu'ils décident de montrer est un état de l'écran.
 */
private class ChatScrollTracker {
    var scrolledUp = 0f
    var scrolledDown = 0f
}

@Composable
private fun ChatConversation(
    thread: ChatThread,
    model: ChatModel,
    keyboard: ChatKeyboard,
    tripId: String,
    stepId: String?,
    arrivesWithRecording: Boolean,
    isSettled: Boolean,
    isAwaitingServer: Boolean,
    notificationAuthorization: NotificationAuthorization?,
    photosDeniedMessage: String?,
    onRefreshNotifications: suspend () -> Unit,
    onHeaderBottom: (Dp) -> Unit,
    onBack: () -> Unit,
    onOpenFromServer: (ChatIntent) -> Unit,
    onAddPhotos: () -> Unit,
    onSubscribe: () -> Unit,
    onCallToAction: (ChatCallToAction) -> Unit,
    onOpenTripContext: () -> Unit,
    onOpenSettings: () -> Unit,
) {
    val state by model.state.collectAsStateWithLifecycle()
    val readingId by model.reader.readingId.collectAsStateWithLifecycle()
    val settings = LocalAppSettings.current
    val density = LocalDensity.current
    val reduceMotion = isReduceMotionEnabled()
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    val messages = thread.messages

    // Les fiches de retranscription dépliées. Un état de **lecture**, pas de
    // donnée : il n'a rien à faire dans le modèle, et il se perd volontiers
    // quand on quitte l'écran.
    val expanded = remember { mutableStateSetOf<String>() }

    // On est au bas du fil. C'est cette seule question qui décide si une
    // nouvelle bulle fait défiler l'écran, et si « Retourner en bas »
    // apparaît. **Seul le doigt la fait passer à faux** (Hugo, 12/10/2026 :
    // « si on scrolle pas beaucoup vers le haut, il y a un sursaut qui nous
    // ramène en bas ») : elle se lit pendant le geste, sur ce qui reste à
    // défiler sous l'écran (`BOTTOM_TOLERANCE`), et repasse à vrai quand on
    // redescend, ou qu'on est ramené en bas. Un pied qui grandit, une bulle qui
    // arrive ne la changent pas : on n'a pas bougé.
    var isAtBottom by remember { mutableStateOf(true) }

    // L'étape sur laquelle il reste à se poser en arrivant.
    var pendingFocus by remember { mutableStateOf(stepId) }

    // Les hauteurs de l'en-tête et du pied, que le fil laisse en marge.
    var headerHeight by remember { mutableIntStateOf(0) }
    var footerHeight by remember { mutableIntStateOf(0) }
    var footerTop by remember { mutableFloatStateOf(0f) }

    // La puce de suggestion en vol : elle quitte la barre, devient bleue et
    // monte se poser en bulle du voyageur (Hugo, 29/09/2026). `null` le reste
    // du temps.
    var flight by remember { mutableStateOf<SuggestionFlight?>(null) }

    // La bannière d'aperçu en direct est **posée sur le fil**, pas dedans
    // (Hugo, 17/09/2026). **Une règle, et deux sens** (Hugo, 19/09/2026) : on
    // remonte vers les anciens messages, elle vient ; on redescend vers les
    // récents, elle s'en va. **Le temps ne la reprend qu'à l'arrivée** : elle se
    // montre quatre secondes en ouvrant le fil, puis se retire. Rappelée par un
    // geste, elle **reste** : c'est une descente qui la renvoie, et rien
    // d'autre.
    var showsPreviewBanner by remember { mutableStateOf(!arrivesWithRecording) }
    var bannerLingerTask by remember { mutableStateOf<Job?>(null) }
    val tracker = remember { ChatScrollTracker() }
    val revealDistance = with(density) { BANNER_REVEAL_DISTANCE.toPx() }
    val dismissDistance = with(density) { BANNER_DISMISS_DISTANCE.toPx() }
    val bottomTolerance = with(density) { BOTTOM_TOLERANCE.toPx() }

    // ⚠️ **N'écrit que ce qui change.** Appelée à chaque image d'une remontée.
    fun revealBanner(withdrawing: Boolean = false) {
        if (!showsPreviewBanner) showsPreviewBanner = true
        bannerLingerTask?.cancel()
        bannerLingerTask = null
        if (!withdrawing) return
        bannerLingerTask = scope.launch {
            delay(BANNER_LINGER_MS)
            showsPreviewBanner = false
        }
    }

    fun hideBanner() {
        bannerLingerTask?.cancel()
        bannerLingerTask = null
        if (showsPreviewBanner) showsPreviewBanner = false
    }

    fun scrollToBottom() {
        if (!isAtBottom) isAtBottom = true
        // Quand une puce vient d'atterrir, le fil est **déjà** à sa place :
        // animer ce défilement-là le faisait plonger de la hauteur de la bulle,
        // puis remonter (vu en vidéo, 30/09/2026).
        val landing = flight?.hasLanded == true
        scope.launch { if (reduceMotion || landing) listState.scrollToItem(0) else listState.animateScrollToItem(0) }
    }

    // Ce que le doigt fait au fil : les écarts du défilement, rien que ceux du
    // geste — un `scrollToItem` ne passe pas par ici. Le fil est à l'envers :
    // un écart positif remonte vers les anciens messages.
    val nestedScroll = remember {
        object : NestedScrollConnection {
            override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
                val delta = consumed.y
                if (delta > 0f) {
                    tracker.scrolledDown = 0f
                    tracker.scrolledUp += delta
                    // On remonte : elle vient, et le délai repart de zéro tant
                    // que le geste dure.
                    if (tracker.scrolledUp >= revealDistance) revealBanner()
                } else if (delta < 0f) {
                    tracker.scrolledUp = 0f
                    tracker.scrolledDown -= delta
                    if (tracker.scrolledDown >= dismissDistance) hideBanner()
                }
                if (delta != 0f) {
                    val atBottom = listState.firstVisibleItemIndex == 0 && listState.firstVisibleItemScrollOffset <= bottomTolerance
                    if (atBottom != isAtBottom) isAtBottom = atBottom
                }
                return Offset.Zero
            }
        }
    }

    // Quatre secondes à l'arrivée, puis elle s'en va toute seule. Pas
    // d'arrivée du tout avec un vocal de l'accueil.
    LaunchedEffect(thread.preview != null) {
        if (thread.preview == null || arrivesWithRecording) return@LaunchedEffect
        revealBanner(withdrawing = true)
    }
    DisposableEffect(Unit) { onDispose { bannerLingerTask?.cancel() } }

    // Suit la conversation **sans voler le défilement** : on ne redescend que
    // si on était déjà en bas, ou si c'est nous qui venons de parler. Quelqu'un
    // qui remonte pour relire une fiche ne doit pas se faire ramener en bas
    // parce que MEMO a répondu. Tant qu'on n'a pas atterri sur l'étape
    // demandée, le fil ne suit rien.
    val follow = {
        if (pendingFocus == null) {
            val weJustSpoke = model.messages.lastOrNull()?.author?.isTraveller == true
            if (isAtBottom || weJustSpoke) scrollToBottom()
        }
    }
    LaunchedEffect(messages.size) { follow() }
    LaunchedEffect(state.turn == ChatTurnState.Thinking) { if (state.turn == ChatTurnState.Thinking) follow() }

    // Se pose sur **le récit** de l'étape qu'on est venu voir : la bulle qui
    // l'a racontée, et sa fiche juste dessous (Hugo, 12/10/2026). Sans étape à
    // viser — ou si elle n'a rien encore —, le fil s'ouvre sur sa fin. ⚠️ **Le
    // bas de la fiche, et non le haut du récit** : le bas est toujours
    // atteignable, et le récit se lit juste au-dessus. La liste paresseuse
    // d'Android sait viser une rangée qu'elle n'a pas encore composée : une
    // tentative suffit, là où iOS en demande trois.
    LaunchedEffect(Unit) {
        val target = pendingFocus?.let { ChatView.focusTarget(thread, it) }
        if (target == null) {
            pendingFocus = null
            return@LaunchedEffect
        }
        val index = ChatView.rows(thread, model, state, notificationAuthorization, settings).indexOfFirst { it.key == target.id }
        if (index >= 0) listState.scrollToItem(index)
        // Posé ailleurs qu'en bas : la pastille « Retourner en bas » le dit, et
        // une réponse de MEMO ne vient pas l'en arracher.
        if (target.id != model.messages.lastOrNull()?.id) isAtBottom = false
        pendingFocus = null
    }

    // Les rangées du fil, du bas vers le haut — posées une fois par fil reçu,
    // pas à chaque image : la vue ne trie pas.
    val rows = remember(thread, state.turn, state.callToActionStates, notificationAuthorization) {
        ChatView.rows(thread, model, state, notificationAuthorization, settings)
    }
    val isGatheringContext = thread.tripContext?.isGathering == true
    // Les bulles déjà là quand le fil s'est posé — une boîte **non observée** :
    // seule la rangée qui naît la lit, une fois. Avant que le fil soit posé,
    // tout ce qu'on montre était déjà là.
    val seen = remember { mutableSetOf<String>() }
    if (!isSettled) messages.forEach { seen += it.id }

    Box(Modifier.fillMaxSize()) {
        LazyColumn(
            state = listState,
            reverseLayout = true,
            modifier = Modifier
                .fillMaxSize()
                .nestedScroll(nestedScroll)
                // **Le fil se lève dès que la puce décolle** (Hugo,
                // 30/09/2026) : la bulle qui monte se pose dans le creux qu'il
                // laisse au lieu de passer sur le dernier message. Un décalage
                // **de dessin**, et non une rangée de plus.
                .graphicsLayer { translationY = -(flight?.lift?.value ?: 0f) },
            contentPadding = with(density) {
                PaddingValues(
                    start = MemoBookSpacing.snug,
                    end = MemoBookSpacing.snug,
                    top = headerHeight.toDp() + MemoBookSpacing.s,
                    bottom = footerHeight.toDp() + MemoBookSpacing.s,
                )
            },
            // Une conversation s'ouvre sur sa fin : c'est le dernier message
            // qu'on vient lire. Un fil **vide**, lui, n'a ni haut ni bas — il a
            // un centre, et c'est là que la maquette pose son accueil.
            verticalArrangement = Arrangement.spacedBy(
                ChatMetrics.messageSpacing,
                if (thread.isEmpty) Alignment.CenterVertically else Alignment.Bottom,
            ),
        ) {
            rows.forEach { row ->
                item(key = row.key, contentType = row.contentType) {
                    when (row) {
                        ChatView.Row.Thinking -> ChatThinkingBubble()
                        ChatView.Row.Nudge -> notificationAuthorization?.let { authorization ->
                            ChatNotificationsNudge(model, authorization, onAnswered = onRefreshNotifications)
                        }
                        is ChatView.Row.Message -> {
                            val message = row.message
                            ArrivingRow(message, isSettled, seen, reduceMotion, flight != null) {
                                ChatMessageRow(
                                    message = message,
                                    model = model,
                                    row = ChatView.rowState(message, model, state, readingId),
                                    isExpanded = message.id in expanded,
                                    onToggleExpansion = {
                                        if (message.id in expanded) expanded -= message.id else expanded += message.id
                                    },
                                    onCallToAction = onCallToAction,
                                )
                            }
                        }
                        ChatView.Row.Greeting -> thread.greeting?.let { ChatGreetingView(it) }
                        ChatView.Row.Privacy -> ChatPrivacyNote()
                        ChatView.Row.Notices -> ChatNotices(model, state, photosDeniedMessage, onOpenSettings)
                    }
                }
            }
        }

        // **La bannière, par-dessus le fil**, sous l'imprimante. Elle glisse vers
        // le haut avec un rebond quand elle s'en va, et revient de la même façon.
        // Pendant le contexte du voyage, sa pastille tient la place : deux
        // capsules l'une sur l'autre se liraient comme une pile.
        val preview = thread.preview
        AnimatedVisibility(
            visible = showsPreviewBanner && !isGatheringContext && preview != null,
            modifier = Modifier
                .align(Alignment.TopEnd)
                // À l'aplomb de l'imprimante de l'en-tête, qui ouvre le même
                // aperçu (Hugo, 15/10/2026) : la marge de l'app, celle de
                // l'encre des commandes de l'en-tête.
                .padding(top = with(density) { headerHeight.toDp() } + MemoBookSpacing.xs)
                .padding(horizontal = MemoBookSpacing.screenMargin),
            enter = if (reduceMotion) fadeIn() else slideInVertically(SwiftMotion.spring(0.55f, 0.65f)) { -it } + fadeIn(),
            exit = if (reduceMotion) fadeOut() else slideOutVertically(SwiftMotion.spring(0.55f, 0.65f)) { -it } + fadeOut(),
        ) {
            val shown = remember { mutableStateOf(preview) }
            if (preview != null) shown.value = preview
            shown.value?.let { ChatPreviewBanner(it, onOpen = { onOpenFromServer(ChatIntent.OpenBookPreview(tripId)) }) }
        }

        // L'en-tête, et sous lui la pastille du contexte — **dans** sa marge et
        // non en calque : le fil se décale d'autant, et la pastille ne recouvre
        // jamais la première bulle. Elle ne s'efface pas au défilement — elle dit
        // ce qui manque tant qu'il manque quelque chose.
        Column(
            Modifier
                .align(Alignment.TopCenter)
                .fillMaxWidth()
                .onSizeChanged { headerHeight = it.height }
                .onGloballyPositioned { onHeaderBottom(with(density) { (it.positionInWindow().y + it.size.height).toDp() }) },
        ) {
            ChatHeader(
                thread = thread,
                onBack = onBack,
                onSettings = { onOpenFromServer(ChatIntent.OpenSettings(tripId)) },
                onBook = { onOpenFromServer(ChatIntent.OpenBookPreview(tripId)) },
                isAwaitingServer = isAwaitingServer,
            )
            AnimatedVisibility(
                visible = isGatheringContext,
                enter = if (reduceMotion) fadeIn() else slideInVertically(SwiftMotion.spring(0.55f, 0.7f)) { -it } + fadeIn(),
                exit = if (reduceMotion) fadeOut() else slideOutVertically(SwiftMotion.spring(0.55f, 0.7f)) { -it } + fadeOut(),
            ) {
                val tripContext = thread.tripContext
                if (tripContext != null) {
                    ChatTripContextBanner(
                        tripContext,
                        onOpen = onOpenTripContext,
                        modifier = Modifier
                            .fillMaxWidth()
                            // Le fond de l'en-tête, prolongé : le fil passe
                            // **dessous**, jamais à côté de la capsule en
                            // restant lisible.
                            .background(ChatMetrics.barMaterial)
                            .padding(horizontal = MemoBookSpacing.screenMargin)
                            .padding(bottom = MemoBookSpacing.xs)
                            .wrapContentWidth(),
                    )
                }
            }
        }

        // La barre d'envoi, et la pastille « Retourner en bas » posée au-dessus
        // d'elle — ⚠️ **empilée, pas posée en calque** : un calque décalé hors
        // du cadre de la barre se dessine très bien et ne reçoit aucune touche.
        Column(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .onSizeChanged { footerHeight = it.height }
                .onGloballyPositioned { footerTop = it.positionInWindow().y },
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            AnimatedVisibility(
                visible = !isAtBottom && messages.isNotEmpty(),
                enter = if (reduceMotion) fadeIn(snap()) else fadeIn() + slideInVertically { it },
                exit = if (reduceMotion) fadeOut(snap()) else fadeOut() + slideOutVertically { it },
            ) {
                ChatBackToBottomPill(action = ::scrollToBottom, modifier = Modifier.padding(bottom = MemoBookSpacing.xs))
            }

            ChatComposer(
                model = model,
                keyboard = keyboard,
                onAddPhotos = onAddPhotos,
                onSubscribe = onSubscribe,
                flyingSuggestionId = flight?.suggestion?.id,
                extendsUnderSystemBars = true,
                onLaunch = launch@{ suggestion, frame ->
                    // « Voir ma page » ouvre l'aperçu : rien ne part dans le
                    // fil, rien ne vole.
                    if (suggestion.intent == ChatSuggestion.Intent.OpenPreview) {
                        onOpenFromServer(ChatIntent.OpenBookPreview(tripId))
                        return@launch
                    }
                    if (reduceMotion || flight != null) {
                        model.choose(suggestion, addPhotos = onAddPhotos)
                        return@launch
                    }
                    val launched = SuggestionFlight(suggestion, frame)
                    flight = launched
                    scope.launch {
                        fly(
                            launched,
                            // « Ajouter des photos » ne devient pas une bulle : rien à lever pour elle.
                            lifts = suggestion.intent != ChatSuggestion.Intent.ImportPhotos,
                            wasAtBottom = isAtBottom,
                            minimumRow = with(density) { MemoBookSpacing.minimumTapTarget.toPx() },
                            spacing = with(density) { ChatMetrics.messageSpacing.toPx() },
                            scrollDown = {
                                // **Remonté dans les anciens messages, le fil
                                // redescend d'abord** (Hugo, 12/10/2026).
                                isAtBottom = true
                                scope.launch { listState.animateScrollToItem(0) }
                            },
                            land = { model.choose(suggestion, addPhotos = onAddPhotos) },
                        )
                        flight = null
                    }
                },
            )
        }

        // La puce en vol, par-dessus le fil et la barre : elle part de la barre
        // et se pose au bas du fil, là où sa bulle va apparaître.
        flight?.let { FlyingSuggestion(it, footerTop) }
    }
}

/**
 * Fait décoller une puce : le vol, puis l'envoi.
 *
 * L'envoi attend la fin du vol pour que la bulle n'apparaisse pas en bas
 * pendant que la puce est encore à mi-chemin. **Le fil se lève au décollage**
 * (Hugo, 30/09/2026) : il se lève de la hauteur d'une **ligne** du fil en un
 * quart de seconde, vif, pendant que la bulle part doucement et met une
 * demi-seconde : elle trouve toujours la place faite. À l'atterrissage, le
 * décalage et le vrai message s'échangent **sans animation propre** : l'un
 * part, l'autre arrive à la même place.
 */
private suspend fun fly(
    flight: SuggestionFlight,
    lifts: Boolean,
    wasAtBottom: Boolean,
    minimumRow: Float,
    spacing: Float,
    scrollDown: () -> Unit,
    land: () -> Unit,
) {
    if (lifts && !wasAtBottom) scrollDown()
    // Une image pour que la bulle en vol soit mesurée et posée sur la puce
    // avant de partir — pas plus : le creux doit s'ouvrir **dès** l'appui.
    delay(16)
    kotlinx.coroutines.coroutineScope {
        if (lifts) {
            val row = maxOf(flight.size.height.toFloat(), minimumRow)
            launch { flight.lift.animateTo(row + spacing, SwiftMotion.snappy(0.25f)) }
        }
        launch { flight.progress.animateTo(1f, SwiftMotion.smooth(0.5f)) }
        delay(480)
    }
    // L'échange, sans animation à lui : le fil retombe de ce qu'il s'était levé
    // au moment où le vrai message l'agrandit d'autant, et la puce s'efface.
    flight.lift.snapTo(0f)
    flight.hasLanded = true
    land()
    delay(220)
}

/**
 * La puce qu'on vient de toucher, en vol. Elle se dessine **comme la bulle
 * qu'elle va devenir** — bleue, en corps de bulle —, part du cadre de la puce
 * et monte jusqu'au coin bas droit du fil.
 */
@Composable
private fun FlyingSuggestion(flight: SuggestionFlight, footerTop: Float) {
    val density = LocalDensity.current
    var origin by remember { mutableStateOf(Offset.Zero) }
    var width by remember { mutableIntStateOf(0) }
    Box(
        Modifier
            .fillMaxSize()
            .onGloballyPositioned {
                origin = it.positionInWindow()
                width = it.size.width
            },
    ) {
        val margin = with(density) { MemoBookSpacing.snug.toPx() }
        val bottomPadding = with(density) { MemoBookSpacing.s.toPx() }
        val minimumRow = with(density) { MemoBookSpacing.minimumTapTarget.toPx() }
        val size = flight.size
        // La place du prochain message au bas du fil : sous elle, la marge du
        // fil. La bulle se centre sur sa **ligne**, qui ne descend pas sous la
        // hauteur de ses boutons d'action.
        val row = maxOf(size.height.toFloat(), minimumRow)
        val landing = Offset(width - margin - size.width / 2f, footerTop - origin.y - bottomPadding - row / 2f)
        val start = Offset(flight.from.center.x - origin.x, flight.from.center.y - origin.y)
        val progress = flight.progress.value
        val x = start.x + (landing.x - start.x) * progress
        val y = start.y + (landing.y - start.y) * progress

        BrandChatBubble(
            ChatAuthor.Traveller,
            Modifier
                .onSizeChanged { flight.size = it }
                .offset { IntOffset((x - size.width / 2f).toInt(), (y - size.height / 2f).toInt()) }
                .graphicsLayer {
                    val scale = 0.7f + 0.3f * progress
                    scaleX = scale
                    scaleY = scale
                    // Posée : le vrai message est dessous, elle s'efface d'un coup.
                    alpha = if (flight.hasLanded) 0f else 1f
                },
        ) {
            BrandText(flight.suggestion.label, MemoBookFont.bubble)
        }
    }
}

/**
 * Comment une bulle entre dans le fil : **elle grandit depuis son coin bas** —
 * droit pour le voyageur, gauche pour MEMO —, comme si elle partait du point
 * d'où on l'envoie (Hugo, 29/09/2026). Rien pour les bulles déjà là à
 * l'ouverture, ni en « Supprimer les animations », ni pour la bulle qui prend la
 * place d'une puce en vol, déjà posée par l'animation.
 */
@Composable
private fun ArrivingRow(
    message: ChatMessage,
    isSettled: Boolean,
    seen: MutableSet<String>,
    reduceMotion: Boolean,
    isFlying: Boolean,
    content: @Composable () -> Unit,
) {
    val isTraveller = message.author.isTraveller
    val arrives = remember(message.id) { isSettled && message.id !in seen && !reduceMotion && !(isFlying && isTraveller) }
    val appear = remember(message.id) { Animatable(if (arrives) 0f else 1f) }
    LaunchedEffect(message.id) {
        seen += message.id
        if (arrives) appear.animateTo(1f, SwiftMotion.smooth(0.3f))
    }
    Box(
        Modifier.graphicsLayer {
            val value = appear.value
            val scale = 0.35f + 0.65f * value
            scaleX = scale
            scaleY = scale
            alpha = value
            transformOrigin = TransformOrigin(if (isTraveller) 1f else 0f, 1f)
        },
    ) { content() }
}

/**
 * Les bandeaux en ligne, jamais des alertes : l'utilisateur garde le contexte de
 * sa conversation.
 */
@Composable
private fun ChatNotices(model: ChatModel, state: ChatModel.State, photosDeniedMessage: String?, onOpenSettings: () -> Unit) {
    val scope = rememberCoroutineScope()
    Column(verticalArrangement = Arrangement.spacedBy(ChatMetrics.messageSpacing)) {
        // Un fil local, sans le serveur : on peut raconter quand même, et c'est
        // ce que la boîte dit d'abord.
        if (state.isOffline) BrandNotice(ChatCopy.offline)
        if (state.microphoneIsDenied) {
            ErrorBanner(RecordingError.PermissionDenied.message, retry = onOpenSettings)
        }
        photosDeniedMessage?.let { ErrorBanner(it, retry = onOpenSettings) }
        state.errorMessage?.let { ErrorBanner(it, retry = { scope.launch { model.load() } }) }
    }
}

object ChatView {
    /** Une rangée du fil, du bas vers le haut — le fil est à l'envers. */
    sealed interface Row {
        val key: String
        val contentType: String

        data object Thinking : Row {
            override val key = "chat-thinking"
            override val contentType = "thinking"
        }

        data object Nudge : Row {
            override val key = "chat-notifications-nudge"
            override val contentType = "nudge"
        }

        data class Message(val message: ChatMessage) : Row {
            override val key: String get() = message.id
            override val contentType: String
                get() = when (message.body) {
                    is ChatMessageBody.Text -> "text"
                    is ChatMessageBody.Voice -> "voice"
                    is ChatMessageBody.Transcript -> "transcript"
                    is ChatMessageBody.Photos -> "photos"
                }
        }

        data object Greeting : Row {
            override val key = "chat-greeting"
            override val contentType = "greeting"
        }

        data object Privacy : Row {
            override val key = "chat-privacy"
            override val contentType = "privacy"
        }

        data object Notices : Row {
            override val key = "chat-notices"
            override val contentType = "notices"
        }
    }

    /**
     * Les rangées du fil, de la plus récente à la plus ancienne : les bandeaux,
     * la mention privée et l'accueil en tête du fil, puis les messages, la
     * bulle des notifications — après le fil : c'est une suggestion pour la
     * suite, pas un message d'hier (T246) —, et les trois points de MEMO.
     */
    internal fun rows(
        thread: ChatThread,
        model: ChatModel,
        state: ChatModel.State,
        notificationAuthorization: NotificationAuthorization?,
        settings: com.memobook.feature.AppSettings,
    ): List<Row> = buildList {
        if (state.turn == ChatTurnState.Thinking) add(Row.Thinking)
        if (notificationAuthorization != null &&
            NotificationsNudge.isShown(
                hasPassedStep = NotificationsNudge.hasPassedStep(settings),
                authorization = notificationAuthorization,
                state = model.callToActionState(NotificationsNudge.bubbleId),
            )
        ) {
            add(Row.Nudge)
        }
        thread.messages.asReversed().forEach { add(Row.Message(it)) }
        if (thread.isEmpty && thread.greeting != null) add(Row.Greeting)
        add(Row.Privacy)
        add(Row.Notices)
    }

    /** Ce que la rangée d'un message lit du modèle — voir [ChatRowState]. */
    internal fun rowState(message: ChatMessage, model: ChatModel, state: ChatModel.State, readingId: String?): ChatRowState =
        ChatRowState(
            isReading = readingId == message.id,
            isCopied = state.copiedMessageId == message.id,
            callToActionState = model.callToActionState(message.id),
            showsCallToAction = !message.author.isTraveller && model.showsCallToAction(message.callToAction),
            portrait = portrait(message, state),
            levels = (message.body as? ChatMessageBody.Voice)?.note?.let(model::levels) ?: emptyList(),
        )

    /**
     * Le portrait de celui qui a parlé, pour la bulle d'un vocal (Clara,
     * 26/09/2026) : ce que le serveur a mis sur la bulle — la sienne comme
     * celle d'un co-voyageur —, sinon celui de qui lit, pour une bulle qui
     * n'est pas encore partie. `null` pour MEMO, qui signe de son M.
     */
    private fun portrait(message: ChatMessage, state: ChatModel.State): ChatPortrait? {
        if (!message.author.isTraveller) return null
        message.authorInitials?.let { return ChatPortrait(url = message.authorAvatarUrl, initials = it) }
        val context = state.thread?.context
        return ChatPortrait(url = context?.travellerAvatarUrl, initials = context?.travellerInitials.orEmpty())
    }

    /** La fiche qui suit le récit de l'étape — sinon le récit lui-même. `null` : l'étape n'a rien encore. */
    internal fun focusTarget(thread: ChatThread, stepId: String): ChatMessage? {
        val story = thread.storyMessage(about = stepId) ?: return null
        val after = thread.messages.dropWhile { it.id != story.id }.drop(1).take(3)
        return after.firstOrNull { it.body is ChatMessageBody.Transcript && it.stepId == stepId } ?: story
    }
}

/** Ce qui peut rester sous l'écran en étant encore « en bas » : le rebond d'un doigt qui s'arrête ne fait pas paraître la pastille. */
private val BOTTOM_TOLERANCE = 32.dp

/**
 * Les seuils de la bannière : remonter demande un geste franc (60 dp) ;
 * redescendre en demande un aussi (40 dp, et non 20 : à vingt points, le rebond
 * d'un doigt qui s'arrête suffisait à la faire partir).
 */
private val BANNER_REVEAL_DISTANCE = 60.dp
private val BANNER_DISMISS_DISTANCE = 40.dp
private const val BANNER_LINGER_MS = 4_000L

// MARK: - Aperçus

@Preview(locale = "fr-rFR", name = "Chat", widthDp = 390, heightDp = 844)
@Composable
private fun ChatViewPreview() {
    val audio = rememberPreviewChatAudio()
    ChatView(ChatModel.preview(ChatThread.conversationFixture(tripId = "trip-rome"), audio), tripId = "trip-rome", onIntent = {}, onBack = {})
}

@Preview(locale = "fr-rFR", name = "Chat — conversation neuve", widthDp = 390, heightDp = 844)
@Composable
private fun ChatViewEmptyPreview() {
    val audio = rememberPreviewChatAudio()
    ChatView(ChatModel.preview(ChatThread.fixture(tripId = "trip-new"), audio), tripId = "trip-new", onIntent = {}, onBack = {})
}

@Preview(locale = "fr-rFR", name = "Chat — MEMO réfléchit", widthDp = 390, heightDp = 844)
@Composable
private fun ChatViewThinkingPreview() {
    val audio = rememberPreviewChatAudio()
    ChatView(
        ChatModel.preview(ChatThread.conversationFixture(tripId = "trip-rome"), audio, turn = ChatTurnState.Thinking),
        tripId = "trip-rome",
        onIntent = {},
        onBack = {},
    )
}

@Preview(locale = "fr-rFR", name = "Chat — crédit du jour épuisé", widthDp = 390, heightDp = 844)
@Composable
private fun ChatViewExhaustedPreview() {
    val audio = rememberPreviewChatAudio()
    ChatView(ChatModel.preview(ChatThread.creditExhaustedFixture(tripId = "trip-rome"), audio), tripId = "trip-rome", onIntent = {}, onBack = {})
}

@Preview(locale = "fr-rFR", name = "Chat — trop long pour une journée", widthDp = 390, heightDp = 844)
@Composable
private fun ChatViewTooLongPreview() {
    val audio = rememberPreviewChatAudio()
    ChatView(ChatModel.preview(ChatThread.tooLongForADayFixture(tripId = "trip-rome"), audio), tripId = "trip-rome", onIntent = {}, onBack = {})
}

@Preview(locale = "fr-rFR", name = "Chat — police à 200 %", widthDp = 390, heightDp = 844, fontScale = 2f)
@Composable
private fun ChatViewLargeTextPreview() {
    val audio = rememberPreviewChatAudio()
    ChatView(ChatModel.preview(ChatThread.conversationFixture(tripId = "trip-rome"), audio), tripId = "trip-rome", onIntent = {}, onBack = {})
}
