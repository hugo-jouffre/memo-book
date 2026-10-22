package com.memobook.feature.bookpreview

import android.content.ActivityNotFoundException
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.memobook.core.BookCopy
import com.memobook.core.SupportMessage
import com.memobook.design.BrandButton
import com.memobook.design.BrandHeaderAction
import com.memobook.design.BrandNotice
import com.memobook.design.BrandRefreshFlash
import com.memobook.design.BrandScreenHeader
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandText
import com.memobook.design.ErrorBanner
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.feature.BookPreviewIntent
import com.memobook.feature.LocalAppSettings
import com.memobook.feature.OnboardingStorage
import com.memobook.feature.support.SupportModel
import com.memobook.feature.support.SupportSheet
import com.memobook.feature.support.SupportSheetRoute
import com.memobook.feature.trip.AwaitingServerNotice
import com.memobook.feature.trip.dimmedWhileAwaitingServer
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.time.Duration.Companion.seconds

/**
 * Le parcours de l'aperçu du carnet : la page qui se monte, puis le carnet
 * qu'on feuillette. Jumeau de `BookPreview/BookPreviewFlowView.swift`.
 *
 * **Un seul écran pour les deux temps**, parce que c'en est un seul : la
 * composition finit et l'aperçu apparaît, sans que personne appuie sur quoi que
 * ce soit. Deux destinations de navigation auraient laissé la composition dans
 * la pile, et la flèche de retour de l'aperçu y serait revenue.
 *
 * On y arrive de trois endroits, et c'est voulu — c'est le même carnet : la
 * bannière bleue de la conversation, l'icône de carnet de son en-tête, et la
 * ligne « Prévisualisation PDF » des paramètres du voyage.
 *
 * @param opensShare ouvre la feuille de partage dès l'arrivée — depuis le
 *   tiroir d'une carte de l'accueil, où « partager » mène ici. **Une fois** : la
 *   valeur est gardée avec la destination, et revenir d'une commande ne rouvre
 *   pas la feuille.
 * @param support le support de la session, celui de « Nous contacter » — voir
 *   « Partager mes retours ». `null` dans un aperçu, qui en fabrique un sur
 *   place, comme le paywall.
 * @param isAwaitingServer le voyage a été créé hors ligne et le serveur ne l'a
 *   pas encore reçu (T239) : rien ne se compose, l'aperçu pâlit, et chaque
 *   porte dit « Disponible dès ta reconnexion ». La composition part toute
 *   seule quand le voyage arrive.
 */
@Composable
fun BookPreviewFlowView(
    model: BookPreviewModel,
    onIntent: (BookPreviewIntent) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    opensShare: Boolean = false,
    support: SupportModel? = null,
    isAwaitingServer: Boolean = false,
) {
    val state by model.state.collectAsStateWithLifecycle()
    val settings = LocalAppSettings.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var showsFoundersNote by remember { mutableStateOf(false) }
    var showsShareChoice by rememberSaveable { mutableStateOf(opensShare) }
    // Le formulaire de retours est ouvert — voir « Partager mes retours » du
    // mot des fondateurs.
    var showsFeedback by remember { mutableStateOf(false) }
    var showsAwaitingServer by remember { mutableStateOf(false) }
    var headerBottom by remember { mutableStateOf(0.dp) }

    // Ce qui part dans la feuille de partage du système. `null` quand rien
    // n'est en partage — c'est ce qui la présente.
    var systemShare by remember { mutableStateOf<BookSharePayload?>(null) }
    // Les gestes du dernier partage, gardés au-delà de la feuille : voir
    // `BookShareSheet.ActionsReceiver`.
    var shareActions by remember { mutableStateOf(emptyList<ShareAction>()) }

    // Hors session — un aperçu —, on fabrique le modèle sur place plutôt que de
    // laisser la feuille vide.
    val feedbackSupport = support ?: viewModel(key = "bookPreview.support") { SupportModel() }

    val awaitingServer: () -> Unit = { showsAwaitingServer = true }
    val openShare: () -> Unit = {
        if (isAwaitingServer) {
            awaitingServer()
        } else {
            showsShareChoice = true
        }
    }
    val handle: (BookPreviewIntent) -> Unit = { intent ->
        if (isAwaitingServer && intent != BookPreviewIntent.ShareFeedback) awaitingServer() else onIntent(intent)
    }

    /**
     * Le partage, habillé comme la maquette `3551:26331` : la photo et le titre
     * du voyage en tête, « Commander » et « Partager sur Whatsapp » sous les
     * apps.
     */
    fun payload(title: String, pages: Int, file: java.io.File?, link: String?): BookSharePayload {
        val draft = BookSharePayload(title = title, pages = pages, file = file, link = link, coverPhotoUrl = state.preview?.coverPhotoUrl)
        val actions = buildList {
            add(
                ShareAction(BookCopy.Share.orderAction, R.drawable.icon_cart, perform = {
                    systemShare = null
                    onIntent(BookPreviewIntent.Order)
                }),
            )
            draft.message?.let { message -> ShareAction.whatsApp(context, message)?.let(::add) }
        }
        shareActions = actions
        return draft.copy(actions = actions)
    }

    /**
     * Ouvre la feuille de partage du système avec ce qu'il faut dedans.
     *
     * La feuille de choix se referme **d'abord** : sans ça, on retrouverait
     * « Partager ton MemoBook » sous la feuille du système en sortant, et il
     * faudrait la fermer deux fois.
     */
    fun share(kind: BookShareKind) {
        scope.launch {
            val current = model.state.value
            val title = current.preview?.title ?: ""
            // Les pages que l'en-tête annonce — celles du PDF quand il est là.
            val pages = current.sheetCount

            when (kind) {
                BookShareKind.Pdf -> {
                    val file = model.exportPdf() ?: return@launch
                    // Le lien accompagne **aussi** le PDF : c'est le message qui
                    // dit où suivre le carnet, pas la pièce jointe.
                    val link = model.prepareShareLink()
                    showsShareChoice = false
                    systemShare = payload(title, pages, file, link)
                }
                BookShareKind.Link -> {
                    val link = model.prepareShareLink() ?: return@launch
                    showsShareChoice = false
                    systemShare = payload(title, pages, null, link)
                }
            }
        }
    }

    val mode = when {
        state.stage == BookPreviewModel.Stage.Composing -> FlowMode.Composing
        state.isFullScreen -> FlowMode.FullScreen
        else -> FlowMode.Reader
    }

    AwaitingServerNotice(
        isPresented = showsAwaitingServer,
        onIsPresentedChange = { showsAwaitingServer = it },
        below = headerBottom,
        modifier = modifier
            .fillMaxSize()
            .background(MemoBookColor.background),
    ) {
        AnimatedContent(
            targetState = mode,
            transitionSpec = {
                val motion = SwiftMotion.smooth<Float>(0.35f)
                if (initialState == FlowMode.Composing) {
                    // La composition s'efface **en montant** d'un cheveu, et
                    // l'aperçu arrive de la même façon : la page qui vient de se
                    // monter et celle qu'on va feuilleter sont la même, elle ne
                    // doit pas glisser sur le côté.
                    (fadeIn(motion) + scaleIn(motion, initialScale = 0.98f)) togetherWith
                        (fadeOut(motion) + scaleOut(motion, targetScale = 1.03f))
                } else {
                    fadeIn(motion) togetherWith fadeOut(motion)
                }
            },
            label = "aperçu",
        ) { shown ->
            when (shown) {
                FlowMode.Composing -> BookCompositionView(
                    model = model,
                    state = state,
                    onIntent = handle,
                    onBack = onBack,
                    isAwaitingServer = isAwaitingServer,
                    onHeaderPlaced = { headerBottom = it },
                )
                FlowMode.Reader -> BookReaderView(model = model, state = state, onIntent = handle, onShare = openShare, onBack = onBack)
                FlowMode.FullScreen -> BookFullScreenView(model = model, onShare = openShare, onBack = onBack)
            }
        }
    }

    BrandSheetHost(isPresented = showsFoundersNote, onDismissRequest = { showsFoundersNote = false }) {
        FoundersNoteSheet(
            onFeedback = {
                showsFoundersNote = false
                showsFeedback = true
                onIntent(BookPreviewIntent.ShareFeedback)
            },
            onContinue = { showsFoundersNote = false },
        )
    }

    // **Le formulaire du support**, celui de « Nous contacter » : c'est là
    // qu'on écrit à l'équipe, et « Partager mes retours » n'a pas de raison
    // d'ouvrir autre chose.
    BrandSheetHost(isPresented = showsFeedback, onDismissRequest = { showsFeedback = false }) {
        // « Partager mes retours » part comme tel (T226).
        SupportSheet(
            model = feedbackSupport,
            route = SupportSheetRoute.Contact(about = null),
            source = SupportMessage.Source.FoundersNote,
            tripId = state.preview?.memoId,
        )
    }

    BrandSheetHost(isPresented = showsShareChoice, onDismissRequest = { showsShareChoice = false }) {
        ShareBookSheet(
            preview = state.preview,
            isPreparingLink = state.isPreparingLink,
            onSharePdf = { share(BookShareKind.Pdf) },
            onShareLink = { share(BookShareKind.Link) },
        )
    }

    // La feuille de partage du système, et non une feuille de la marque : c'est
    // **elle** qui connaît les apps installées, le partage à proximité et les
    // contacts récents. En redessiner une ne donnerait qu'une liste plus courte.
    systemShare?.let { shared ->
        SystemShareLauncher(shared, onFinished = { if (systemShare?.id == shared.id) systemShare = null })
    }
    BookShareSheet.ActionsReceiver { shareActions }

    // Le parcours entier — et, pour un voyage pas encore reçu, rien tant qu'il
    // n'est pas arrivé : le serveur ne connaît pas encore ce carnet.
    LaunchedEffect(model, isAwaitingServer) {
        if (isAwaitingServer) {
            showsAwaitingServer = true
        } else {
            model.run()
        }
    }

    // Capte une étape validée pendant que l'aperçu était en arrière-plan — voir
    // `BookPreviewModel.refreshIfNeeded()`. Le `.task(id: scenePhase)` d'iOS.
    LifecycleResumeEffect(model) {
        val refresh = scope.launch { model.refreshIfNeeded() }
        onPauseOrDispose { refresh.cancel() }
    }

    /**
     * Invite le mot des fondateurs, une fois l'aperçu ouvert et si on ne l'a
     * jamais lu.
     *
     * L'effet est attaché à l'étape : il démarre quand l'aperçu apparaît et
     * s'annule si l'écran se referme avant. Quitter l'écran au bout de trois
     * secondes ne doit pas faire surgir une feuille sur l'écran suivant.
     */
    LaunchedEffect(state.stage) {
        if (state.stage != BookPreviewModel.Stage.Preview) return@LaunchedEffect
        if (settings.getBoolean(OnboardingStorage.HAS_SEEN_FOUNDERS_NOTE)) return@LaunchedEffect

        delay(FOUNDERS_DELAY)

        // Ni par-dessus la feuille de partage, ni par-dessus le plein écran :
        // le mot des fondateurs s'invite, il n'interrompt pas.
        if (showsShareChoice || systemShare != null || model.state.value.isFullScreen) return@LaunchedEffect

        settings.putBoolean(OnboardingStorage.HAS_SEEN_FOUNDERS_NOTE, true)
        showsFoundersNote = true
    }
}

/**
 * Combien de temps l'aperçu tourne avant que le mot des fondateurs s'invite.
 *
 * Douze secondes : la maquette dit « 10 à 15 », et il faut laisser le temps de
 * tourner deux ou trois pages avant d'interrompre. Plus tôt, la feuille
 * couvrirait un carnet qu'on n'a pas encore vu ; plus tard, elle arriverait
 * après qu'on a rangé le téléphone.
 */
private val FOUNDERS_DELAY = 12.seconds

private enum class BookShareKind { Pdf, Link }

/** Ce que l'écran montre : la composition, l'aperçu, ou son plein écran. */
private enum class FlowMode { Composing, Reader, FullScreen }

/**
 * Lance la feuille du système, et dit quand elle s'est refermée — par un geste,
 * par une app choisie, ou par le retour.
 */
@Composable
private fun SystemShareLauncher(payload: BookSharePayload, onFinished: () -> Unit) {
    val context = LocalContext.current
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { onFinished() }
    LaunchedEffect(payload.id) {
        try {
            launcher.launch(BookShareSheet.chooser(context, payload))
        } catch (_: ActivityNotFoundException) {
            onFinished()
        }
    }
}

// MARK: - On compose ton Carnet

/**
 * L'attente : une page de carnet qui se monte sous les yeux.
 *
 * Elle occupe exactement la place de l'aperçu qui va suivre — même en-tête,
 * mêmes boutons —, et c'est ce qui fait que le passage de l'un à l'autre ne
 * saute pas. Seule la page change, et c'est bien la seule chose qui ait changé.
 */
@Composable
private fun BookCompositionView(
    model: BookPreviewModel,
    state: BookPreviewModel.State,
    onIntent: (BookPreviewIntent) -> Unit,
    onBack: () -> Unit,
    isAwaitingServer: Boolean,
    onHeaderPlaced: (Dp) -> Unit,
) {
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(horizontal = MemoBookSpacing.screenMargin)
            .padding(top = MemoBookSpacing.xs, bottom = MemoBookSpacing.l),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
    ) {
        BrandScreenHeader(
            BookCopy.Composition.title,
            onBack = onBack,
            modifier = Modifier.onGloballyPositioned { header ->
                onHeaderPlaced(with(density) { (header.positionInWindow().y + header.size.height).toDp() })
            },
            subtitle = BookCopy.Composition.message,
            // Le partage n'a rien à partager tant que le carnet n'est pas
            // composé. Le bouton reste à sa place — il déciderait sinon de la
            // hauteur de l'en-tête en apparaissant.
            //
            // ⚠️ **Désactivé ici, et pas sur l'en-tête** (Hugo, 19/09/2026) :
            // posé sur l'en-tête entier, le `disabled` emportait la flèche de
            // retour avec lui, et on restait bloqué sur l'écran de composition
            // jusqu'à la fin du chargement.
            trailing = { DisabledHeaderAction() },
        )

        // **La page se monte, puis la suivante** (Hugo, 08/10/2026), et ce qui
        // se passe s'écrit **par-dessus**, en corps de texte, avec un sablier :
        // en légende grise sous la page, la phrase ne se lisait pas, et une page
        // montée puis immobile pendant des minutes semblait cassée. Un échec
        // retire la carte : c'est le bandeau qui parle.
        Box(
            Modifier
                .fillMaxWidth()
                // TalkBack n'a pas besoin de la cascade : une phrase suffit à
                // dire ce qui se passe.
                .semantics { contentDescription = BookCopy.Composition.voiceOverStatus },
        ) {
            BookPageStage(Modifier.dimmedWhileAwaitingServer(isAwaitingServer)) {
                BookCompositionLoop(firstPass = if (isAwaitingServer) 0.0 else state.compositionProgress, modifier = Modifier.fillMaxSize())
            }
            CompositionStatusOverlay(
                visible = state.errorMessage == null && !isAwaitingServer,
                state = state,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .offset(y = MemoBookSpacing.m),
            )
        }

        // La place de l'indicateur de pages qui viendra avec l'aperçu — et
        // celle de la carte d'état, qui déborde du bas de la page : les boutons
        // du dessous ne sautent pas quand l'aperçu arrive.
        Spacer(
            Modifier
                .fillMaxWidth()
                .heightIn(min = MemoBookSpacing.minimumTapTarget),
        )

        BookActionsBlock(
            // La composition est en cours : il n'y a rien à commander encore,
            // mais on peut déjà aller régler son style.
            isComposed = false,
            onCustomise = { onIntent(BookPreviewIntent.Customise) },
            onOrder = { onIntent(BookPreviewIntent.Order) },
            isAwaitingServer = isAwaitingServer,
        )

        state.errorMessage?.let { message ->
            ErrorBanner(message, retry = { scope.launch { model.retry() } })
        }
    }
}

/** La carte d'état posée sur la page, qui s'efface quand le bandeau d'erreur parle. */
@Composable
private fun CompositionStatusOverlay(visible: Boolean, state: BookPreviewModel.State, modifier: Modifier = Modifier) {
    AnimatedVisibility(
        visible = visible,
        modifier = modifier,
        enter = fadeIn(tween(250, easing = SwiftMotion.easeInOut)),
        exit = fadeOut(tween(250, easing = SwiftMotion.easeInOut)),
    ) {
        BookCompositionStatus(
            phase = state.compositionPhase,
            pendingMemories = state.pendingMemoryCount,
            modifier = Modifier.padding(horizontal = MemoBookSpacing.xs),
        )
    }
}

/**
 * Le partage de l'en-tête, fermé : à sa place, pâli, sans geste. Le
 * `.disabled(true)` d'iOS, que `BrandHeaderAction` n'a pas.
 */
@Composable
private fun DisabledHeaderAction() {
    Box(
        Modifier
            .alpha(0.4f)
            .clearAndSetSemantics {
                contentDescription = BookCopy.Preview.Voice.share
                role = Role.Button
                disabled()
            },
    ) {
        BrandHeaderAction(R.drawable.icon_share_system, BookCopy.Preview.Voice.share, action = {})
        // Le toucher s'arrête ici : il ne doit pas même faire pâlir la commande.
        Box(
            Modifier
                .matchParentSize()
                .pointerInput(Unit) { detectTapGestures { } },
        )
    }
}

// MARK: - Aperçu PDF

/**
 * Le carnet qu'on feuillette : une page à la fois, et ce qu'on peut en faire.
 *
 * `BookReaderView` et non `BookPreviewView` : ce dernier nom est pris sur iOS
 * par l'aperçu non brandé de `MemoDetail/`, qui ne se porte pas — le nom reste
 * celui du jumeau.
 */
@Composable
private fun BookReaderView(
    model: BookPreviewModel,
    state: BookPreviewModel.State,
    onIntent: (BookPreviewIntent) -> Unit,
    onShare: () -> Unit,
    onBack: () -> Unit,
) {
    val scope = rememberCoroutineScope()

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(horizontal = MemoBookSpacing.screenMargin)
            .padding(top = MemoBookSpacing.xs, bottom = MemoBookSpacing.l),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
    ) {
        BrandScreenHeader(
            BookCopy.Preview.title,
            onBack = onBack,
            subtitle = BookCopy.Preview.subtitle(title = state.preview?.title ?: "", pages = state.sheetCount),
            isSubtitleLoading = state.preview == null,
            trailing = { BrandHeaderAction(R.drawable.icon_share_system, BookCopy.Preview.Voice.share, action = onShare) },
        )

        // Une régénération en fond (étape validée) ne doit jamais reprendre
        // l'écran plein de composition : les pages déjà là restent
        // feuilletables, ce bandeau discret suffit à le dire.
        AnimatedVisibility(
            visible = state.isRecomposing,
            enter = fadeIn(SwiftMotion.snappy(0.25f)) + expandVertically(SwiftMotion.snappy(0.25f), expandFrom = Alignment.Top),
            exit = fadeOut(SwiftMotion.snappy(0.25f)) + shrinkVertically(SwiftMotion.snappy(0.25f), shrinkTowards = Alignment.Top),
        ) {
            BrandNotice(BookCopy.Preview.recomposing)
        }

        // Le crochet réservé pour « l'aperçu PDF qui se recompose » — voir
        // `BrandRefreshFlash`. Ne se joue jamais à la première arrivée ni sur un
        // sondage sans changement.
        BrandRefreshFlash(state.freshness.isUpdated, Modifier.fillMaxWidth(), showsBadge = true) {
            // **On tourne la page au doigt** (Hugo, 19/09/2026), comme en plein
            // écran : vers la gauche pour avancer, vers la droite pour revenir.
            // Le geste vit ici et non dans `BookSheetView`, qui sert aussi la
            // feuille du paywall — celle-là n'a pas de pages à tourner.
            BookPageStage(Modifier.pageTurnGesture(model)) {
                BookSheetView(
                    model,
                    onExpand = { model.setFullScreen(true) },
                    onConfigureCovers = { onIntent(BookPreviewIntent.ConfigureCovers) },
                )
            }
        }

        BookPageStepper(model)

        BookActionsBlock(
            // Ce que **le serveur** dit du carnet, et non ce que l'app a réussi à
            // dessiner : un PDF qui ne se charge pas est un problème
            // d'affichage, pas une raison de refuser une commande que
            // l'imprimeur, lui, peut honorer.
            isComposed = state.isComposed,
            onCustomise = { onIntent(BookPreviewIntent.Customise) },
            onOrder = { onIntent(BookPreviewIntent.Order) },
        )

        // « Fais-toi offrir ce carnet », la carte qui menait à la cagnotte, est
        // partie avec elle (Hugo, 06/10/2026, T230).

        val message = state.errorMessage
        if (state.document.didFail) {
            ErrorBanner(BookCopy.Preview.loadFailed, retry = { scope.launch { model.reloadDocument() } })
        } else if (message != null) {
            ErrorBanner(message, retry = { scope.launch { model.retry() } })
        }
    }
}

// MARK: - Les pièces partagées avec la feuille du paywall

/** Le rapport de la maquette : 252 × 357, soit l'A5 du carnet. */
private const val PAGE_RATIO = 252f / 357f

/**
 * La page ne prend pas toute la largeur de la colonne : la maquette la pose à
 * 252 dans une colonne de 358, ce qui lui laisse de l'air des deux côtés. Une
 * **fraction** et non 252 dp, pour que la page respire pareil sur un petit
 * téléphone et sur un grand (R5). Compose la prend de la colonne elle-même, là
 * où `containerRelativeFrame` la prend de l'écran entier.
 */
private const val PAGE_WIDTH_FRACTION = 252f / 358f

/**
 * La scène où la page se pose : elle garde le rapport du carnet et se centre.
 *
 * Partagée avec la feuille « Prévisualisation » du paywall : c'est la même
 * page, regardée depuis deux endroits, et elle doit y avoir exactement la même
 * boîte.
 *
 * Elle existe pour une raison unique et vaut d'être un composant : la page en
 * composition et la page du PDF doivent occuper **exactement** la même boîte,
 * sinon le passage de l'une à l'autre décale tout l'écran de quelques dp.
 */
@Composable
internal fun BookPageStage(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Box(
            Modifier
                .fillMaxWidth(PAGE_WIDTH_FRACTION)
                .aspectRatio(PAGE_RATIO),
        ) { content() }
    }
}

/**
 * La page regardée, avec ses deux commandes posées dessus.
 *
 * @param onExpand `null` retire la commande de plein écran. C'est le cas de la
 *   feuille du paywall : il faudrait en sortir pour entrer en plein écran, et on
 *   ne reviendrait pas à l'offre. Retirée, et non désactivée — un bouton qui ne
 *   fait rien est pire que pas de bouton.
 * @param onConfigureCovers `null` retire le chemin vers les couvertures, pour la
 *   même raison : la feuille du paywall n'a pas de pile où pousser leur écran.
 */
@Composable
internal fun BookSheetView(model: BookPreviewModel, onExpand: (() -> Unit)?, onConfigureCovers: (() -> Unit)?) {
    val state by model.state.collectAsStateWithLifecycle()
    var width by remember { mutableIntStateOf(0) }
    val shape = RoundedCornerShape(MemoBookSpacing.pageCornerRadius)

    Box(
        Modifier
            .fillMaxSize()
            .onSizeChanged { width = it.width },
    ) {
        // La page du PDF, ou le plat choisi sur la première et la dernière —
        // voir `BookSheetFace`. Elle se remplace en fondu quand on tourne : sans
        // ça, la nouvelle apparaît d'un coup et le geste ne se sent pas.
        Crossfade(
            targetState = state.sheetIndex,
            animationSpec = tween(180, easing = SwiftMotion.easeInOut),
            label = "feuille",
        ) { index ->
            BookSheetFace(
                model.renderer,
                state,
                index,
                Modifier
                    .fillMaxSize()
                    .clip(shape)
                    .border(1.dp, MemoBookColor.hairline, shape),
            )
        }

        // L'invitation à choisir ses couvertures couvre la première et la
        // dernière page tant qu'elles ne sont pas choisies ; les deux gardent
        // ensuite leur bouton « Configurer » — voir
        // `BookPreviewModel.State.coverCallToAction`.
        if (onConfigureCovers != null) {
            val fade = tween<Float>(200, easing = SwiftMotion.easeInOut)
            AnimatedVisibility(
                visible = state.coverCallToAction == CoverCallToAction.Invitation,
                modifier = Modifier.fillMaxSize(),
                enter = fadeIn(fade),
                exit = fadeOut(fade),
            ) {
                CoverInvitation(onConfigureCovers, Modifier.clip(shape))
            }
            AnimatedVisibility(
                visible = state.coverCallToAction == CoverCallToAction.Edit,
                modifier = Modifier.fillMaxSize(),
                enter = fadeIn(fade),
                exit = fadeOut(fade),
            ) {
                CoverEditButton(onConfigureCovers)
            }
        }

        if (onExpand != null) {
            BookScreenModeButton(
                R.drawable.icon_full_screen,
                BookCopy.Preview.Voice.enterFullScreen,
                action = onExpand,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(MemoBookSpacing.xs),
            )
        }
    }

    // La page voisine est rendue pendant qu'on lit celle-ci : tourner ne coûte
    // alors plus rien. Voir `BookPageRenderer.prepare`.
    LaunchedEffect(state.sheetIndex, width, state.document.generation) {
        model.renderer.prepare(around = state.sheetIndex, width = width)
    }
}

/**
 * Le voile posé sur une couverture pas encore choisie, et son invitation.
 *
 * Le voile est celui de la maquette : un aplat noir à 40 %. C'est assez pour
 * qu'on voie qu'il y a une page dessous, et pas assez pour qu'on la prenne pour
 * la couverture définitive.
 *
 * **La phrase au centre de la page, le bouton dans son bas** — comme
 * `3545:21634`, où ils ne forment pas un bloc : le bouton tombe à la place
 * exacte qu'il garde une fois le voile parti ([CoverEditButton]).
 */
@Composable
private fun CoverInvitation(action: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.4f)),
        contentAlignment = Alignment.Center,
    ) {
        BrandText(
            BookCopy.Preview.configureCover,
            MemoBookFont.body,
            Modifier
                .padding(horizontal = MemoBookSpacing.s)
                .clearAndSetSemantics {},
            color = MemoBookColor.onAction,
            textAlign = TextAlign.Center,
        )

        CoverEditButton(action)
    }
}

/**
 * Le bouton « Configurer », posé **sur** la première et la dernière page : il
 * mène aux écrans des couvertures (Hugo, 30/09/2026). Seul quand les
 * couvertures sont choisies — pas de voile, la couverture se voit, et le chemin
 * reste ; sous l'invitation sinon, à la même place.
 */
@Composable
private fun CoverEditButton(action: () -> Unit) {
    Box(
        Modifier
            .fillMaxSize()
            // 40 dp du bas d'une page de 357 : le bas du bouton de la maquette.
            .padding(bottom = MemoBookSpacing.xl),
        contentAlignment = Alignment.BottomCenter,
    ) {
        BrandButton(
            BookCopy.Preview.configureCoverAction,
            modifier = Modifier.clearAndSetSemantics {
                contentDescription = BookCopy.Preview.configureCovers
                role = Role.Button
                onClick {
                    action()
                    true
                }
            },
            style = BrandButton.Style.Raised,
            size = BrandButton.Size.Small,
            action = action,
        )
    }
}

/** « ‹ Page 4 / 10 › » — de quoi tourner les pages. */
@Composable
internal fun BookPageStepper(model: BookPreviewModel) {
    val state by model.state.collectAsStateWithLifecycle()

    Row(
        Modifier
            .fillMaxWidth()
            .padding(vertical = MemoBookSpacing.xs),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.l, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BookPageArrow(
            BookPageArrowDirection.Backward,
            label = BookCopy.Preview.Voice.previousPage,
            isEnabled = state.canGoBack,
            action = model::goBack,
        )

        // La largeur ne bouge pas d'une page à l'autre : sans les chiffres à
        // chasse fixe, le passage de « Page 9 / 10 » à « Page 10 / 10 » décale
        // les deux flèches.
        BrandText(
            BookCopy.Preview.pageIndicator(state.sheetIndex + 1, of = maxOf(state.sheetCount, 1)),
            MemoBookFont.body.copy(fontFeatureSettings = "tnum"),
            color = MemoBookColor.ink,
        )

        BookPageArrow(
            BookPageArrowDirection.Forward,
            label = BookCopy.Preview.Voice.nextPage,
            isEnabled = state.canGoForward,
            action = model::goForward,
        )
    }
}

@Preview(locale = "fr-rFR", name = "Aperçu PDF — sans document", heightDp = 900)
@Composable
private fun BookPreviewFlowViewPreview() {
    BookPreviewFlowView(viewModel { BookPreviewModel(memoId = "preview") }, onIntent = {}, onBack = {})
}

@Preview(locale = "fr-rFR", name = "Aperçu PDF — AX3", heightDp = 900, fontScale = 2f)
@Composable
private fun BookPreviewFlowViewLargePreview() {
    BookPreviewFlowView(viewModel { BookPreviewModel(memoId = "preview") }, onIntent = {}, onBack = {})
}
