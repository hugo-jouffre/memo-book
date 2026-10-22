package com.memobook.feature.home

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import coil3.compose.AsyncImage
import com.memobook.core.HomeFeed
import com.memobook.core.Subscription
import com.memobook.core.Trip
import com.memobook.design.BrandAlert
import com.memobook.design.BrandButton
import com.memobook.design.BrandMarkBackdrop
import com.memobook.design.BrandNotice
import com.memobook.design.BrandRefreshFlash
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandSwipeAction
import com.memobook.design.BrandSwipeDrawer
import com.memobook.design.BrandText
import com.memobook.design.DeviceScreen
import com.memobook.design.ErrorBanner
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.Refreshable
import com.memobook.design.SwiftMotion
import com.memobook.design.brandFooterScrim
import com.memobook.design.isAccessibilityTextSize
import com.memobook.design.isReduceMotionEnabled
import com.memobook.feature.HomeIntent
import com.memobook.feature.LocalAppSettings
import com.memobook.feature.LocalHomeReloadRequest
import com.memobook.feature.LocalLaunchOverlayIsVisible
import com.memobook.feature.LocalSubscriptionSession
import com.memobook.feature.LocalTripsAwaitingServer
import com.memobook.feature.PaywallVariant
import com.memobook.feature.paywall.PaywallView
import com.memobook.feature.recording.RecordingHandoff
import com.memobook.feature.recording.RecordingSheet
import com.memobook.feature.recording.rememberRecordingPermissionRequest
import com.memobook.feature.trip.AwaitingServerNotice
import com.memobook.feature.trip.TripAwaitingServer
import com.memobook.payments.PlayCatalog
import com.memobook.recording.RecordingPermission
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.math.max
import kotlin.math.min

/**
 * L'accueil : où on en est de ses voyages, et le micro toujours à portée de
 * pouce. Jumeau de `Home/HomeView.swift`.
 *
 * **L'écran ne contient aucun contenu.** Titres, pays, dates, compteurs,
 * co-voyageurs, carte de découverte : tout vient du `HomeFeed` que porte
 * [HomeModel]. Ce qui est écrit ici, ce sont les seuls libellés qui
 * appartiennent à l'interface — les titres de section et l'appel à l'action.
 *
 * **Le CTA ne défile pas.** Il est posé par-dessus le défilement : il reste
 * sous le pouce quelle que soit la longueur de la liste, et le contenu se
 * réserve la place qu'il occupe.
 *
 * **L'écran ne navigue pas.** Il émet des [HomeIntent] ; c'est `RootView` qui
 * décide où elles mènent.
 *
 * **Ce qui doit survivre à l'écran part dans la portée du modèle** — le vocal
 * qui s'envoie, la suppression, la relecture d'après l'achat : l'accueil
 * quitte la composition dès qu'un écran est poussé par-dessus lui (la
 * conversation, juste après un vocal), et son modèle, lui, reste tant qu'il
 * est au fond de la pile. Les `Task {}` d'iOS ne meurent pas avec la vue ; une
 * portée d'écran, si.
 *
 * ⚠️ **Plus de glissé vers le profil** (Hugo, 19/09/2026). Il ouvrait le
 * profil d'un glissé vers la droite parti de n'importe où ; le geste est
 * retiré, et non inversé — vers la gauche, il entrerait en concurrence avec le
 * tiroir des cartes, qui va de ce côté-là. L'avatar en haut à droite reste le
 * chemin, et il est le seul.
 *
 * @param showsSandbox pose le panneau d'essai en bas de l'écran — le `#if DEBUG`
 *   d'iOS, que la porte lit à l'exécution.
 */
@Composable
fun HomeView(
    model: HomeModel,
    onIntent: (HomeIntent) -> Unit,
    modifier: Modifier = Modifier,
    showsSandbox: Boolean = false,
) {
    val state by model.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val density = LocalDensity.current
    val settings = LocalAppSettings.current
    val subscriptionSession = LocalSubscriptionSession.current
    val reloadRequest = LocalHomeReloadRequest.current
    val isCoveredByLaunch = LocalLaunchOverlayIsVisible.current
    val tripsAwaitingServer = LocalTripsAwaitingServer.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val requestMicrophone = rememberRecordingPermissionRequest()
    val scope = rememberCoroutineScope()
    val work = model.viewModelScope

    // Chaque bloc monte de quelques points en apparaissant, l'un après l'autre.
    // C'est ce décalage qui prolonge le tracé du M au lieu de faire tomber
    // l'écran d'un bloc. Gardé quand un écran est poussé par-dessus : au
    // retour, l'accueil se relit sans rejouer sa cascade.
    var hasAppeared by rememberSaveable { mutableStateOf(false) }

    // Le M du lancement ne s'en va pas : il descend de 50 % à 20 % et reste
    // derrière le contenu. Il part de l'opacité du tracé pour que le passage
    // depuis l'écran de lancement ne saute pas.
    val markOpacity = remember {
        Animatable(if (hasAppeared) BrandMarkBackdrop.restingOpacity else BrandMarkBackdrop.drawingOpacity)
    }

    // Le contenu est arrivé. Ce n'est pas encore le signal de la cascade : il
    // faut aussi que le tracé du M se soit effacé.
    //
    // **Arrivé, pas rechargé.** Il se lève dès que l'écran a quelque chose à
    // montrer — ce que le cache avait, en quelques millisecondes — et non au
    // retour du serveur : attendre l'aller-retour faisait durer le lancement
    // exactement du temps que le cache était censé faire gagner (Hugo,
    // 18/09/2026). Le serveur, lui, arrive quand il arrive, et le flash de
    // rafraîchissement dit si quelque chose a changé.
    var isLoaded by rememberSaveable { mutableStateOf(false) }

    // La feuille d'enregistrement est ouverte. Même raison que celle du
    // carnet : une feuille propose, elle ne navigue pas.
    var isRecording by remember { mutableStateOf(false) }

    // Le paywall est ouvert — par « Me réabonner », dans l'alerte de fin
    // d'abonnement. Plein écran, comme depuis le profil. Le CTA, lui, ne mène
    // plus jamais au paywall : tout le monde raconte (Hugo, 03/10/2026).
    var showsPaywall by remember { mutableStateOf(false) }

    // L'alerte « Ton abonnement MemoBook s'est arrêté », ouverte quand le mois
    // payé s'est achevé depuis la dernière ouverture.
    //
    // **Une alerte et non une feuille de la marque** : elle n'arrive au bout
    // d'aucun geste — on ouvre l'app, et on l'apprend. Une feuille qui monterait
    // toute seule se lirait comme un écran de plus dans un parcours ; une alerte
    // se lit comme une nouvelle, et c'est aussi la forme qu'iOS emploie
    // lui-même pour annoncer la fin d'un abonnement.
    var showsSubscriptionEnded by remember { mutableStateOf(false) }

    // **Le rappel de fin de voyage** (01/10/2026) — ce qui reste de « l'arrêt
    // automatique » de l'offre. Le store ne laisse pas l'app résilier à la
    // place de la personne : quand l'abonnement va se renouveler sans voyage en
    // cours (`Traveller.subscriptionOutlivesTrip`), l'accueil le lui propose.
    // Sur iOS, « Résilier » ouvre la feuille de gestion des abonnements d'Apple ;
    // ici, la page des abonnements de Google Play — et seulement pour un
    // abonnement que Google Play tient (`HomeModel.tripEndReminderCanOpenHere`).
    var showsTripEndReminder by remember { mutableStateOf(false) }

    // La feuille « Nouveau carnet » est ouverte.
    //
    // Une feuille ne mène nulle part, elle propose, et ce n'est donc pas une
    // entorse à la règle qui veut que l'accueil ne navigue pas. Ce qu'on y
    // choisit, en revanche, redevient une [HomeIntent] que `RootView` route.
    var isCreatingNotebook by remember { mutableStateOf(false) }

    // Le voyage dont on confirme la suppression — depuis le tiroir de sa carte
    // (Hugo, 17/09/2026). La même feuille que celle des réglages du voyage :
    // le bouton plein garde, le rouge supprime.
    var tripToDelete by remember { mutableStateOf<Trip?>(null) }

    // Les voyages que le serveur n'a pas encore reçus : leur partage et leur
    // aperçu pâlissent dans le tiroir — voir `TripAwaitingServer` (T239).
    var showsAwaitingServer by remember { mutableStateOf(false) }

    // Le micro a été refusé dans Android : la feuille ne s'ouvrira pas, et
    // c'est cette boîte qui dit pourquoi, et où aller. `false` le reste du
    // temps.
    var showsMicrophoneDenied by remember { mutableStateOf(false) }

    // La hauteur du CTA, pour que le contenu se réserve sa place — le
    // `safeAreaInset(edge: .bottom) { recordCallToAction.hidden() }` d'iOS.
    var callToActionHeight by remember { mutableIntStateOf(0) }

    // Ce que `RootView` a déjà demandé de relire : un compteur, comme sur iOS.
    var seenReloadRequest by rememberSaveable { mutableIntStateOf(reloadRequest) }

    val ongoingTripId = state.ongoingTrips.firstOrNull()?.id
    val hasOngoingTrip = ongoingTripId != null

    // MARK: Chargement et relectures

    // Au premier passage, le chargement ; **au retour d'un écran poussé** — un
    // voyage, ses réglages, sa suppression —, l'accueil se relit, sans cascade
    // ni écran vide, pour que ce qui a changé là-bas se voie ici.
    LaunchedEffect(model) {
        seenReloadRequest = reloadRequest
        model.load()
        isLoaded = true
    }
    LaunchedEffect(state.feed != null || state.errorMessage != null) {
        if (state.feed != null || state.errorMessage != null) isLoaded = true
    }

    // `RootView` demande une relecture — une transaction remise hors du
    // paywall, la feuille du store refermée.
    LaunchedEffect(reloadRequest) {
        if (reloadRequest == seenReloadRequest) return@LaunchedEffect
        seenReloadRequest = reloadRequest
        model.load()
    }

    // **Au retour dans l'app**, l'accueil se relit (03/10/2026). Il ne le
    // faisait qu'en réapparaissant derrière un écran poussé : laissé en
    // arrière-plan le soir, il rouvrait le lendemain sur le crédit épuisé de la
    // veille. C'est aussi ce qui le relit au retour de la page d'abonnements de
    // Google Play : le serveur aura appris du store ce qui a été coupé, et le
    // rappel cesse. Au premier passage, c'est le chargement ci-dessus.
    DisposableEffect(lifecycleOwner) {
        var wentToBackground = false
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_STOP -> wentToBackground = true
                Lifecycle.Event.ON_START -> if (wentToBackground) {
                    wentToBackground = false
                    if (isLoaded) work.launch { model.load() }
                }
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    // Ce que le serveur dit de l'abonnement, la session le retient : c'est ce
    // qui permet à la conversation et aux réglages d'un voyage de savoir s'il
    // faut compter, et quelle version du paywall ouvrir.
    LaunchedEffect(state.feed) {
        val traveller = state.feed?.traveller ?: return@LaunchedEffect
        subscriptionSession?.learn(traveller)

        // **L'alerte de fin d'abonnement, une seule fois par arrêt.** Le serveur
        // ne dit que « le mois payé s'est achevé ce jour-là », et il le dira à
        // chaque chargement de l'accueil pendant quinze jours : c'est à l'app de
        // se souvenir qu'elle l'a annoncé. Une date et non un booléen : le
        // prochain abonnement qui s'arrêtera portera une autre date, et l'alerte
        // reviendra. Sur l'appareil et non sur le serveur : c'est de l'état
        // d'**affichage**, et deux téléphones du même compte doivent chacun
        // l'apprendre.
        traveller.subscriptionEndedOn?.let { endedOn ->
            val stamp = endedOn.epochSecond + endedOn.nano / 1e9
            val announced = settings.getString(HomeStorage.announcedEnd)?.toDoubleOrNull() ?: 0.0
            if (stamp > announced) {
                settings.putString(HomeStorage.announcedEnd, stamp.toString())
                showsSubscriptionEnded = true
            }
        }

        // Propose de résilier **une fois par jour au plus**, tant que
        // l'abonnement survit à tous les voyages : un rappel à chaque ouverture
        // deviendrait une alerte qu'on ferme sans la lire ; une fois par jour, il
        // reste un rappel. Le jour n'est retenu que si le rappel s'ouvre : quand
        // on ne sait pas encore qui tient l'abonnement, la lecture suivante
        // reposera la question.
        if (traveller.subscriptionOutlivesTrip) {
            val today = TripEndReminder.today()
            if (settings.getString(TripEndReminder.storageKey) != today && model.tripEndReminderCanOpenHere()) {
                settings.putString(TripEndReminder.storageKey, today)
                showsTripEndReminder = true
            }
        }
    }

    // MARK: La cascade

    // Deux conditions, dans n'importe quel ordre : le contenu est là, et le
    // tracé du M ne couvre plus l'écran. C'est la seconde qui manquait —
    // l'accueil étant désormais monté **sous** le voile, sa cascade se jouait
    // en entier avant qu'on puisse la voir.
    val isReadyToRise = isLoaded && !isCoveredByLaunch
    LaunchedEffect(isReadyToRise) {
        if (!isReadyToRise || hasAppeared) return@LaunchedEffect
        // Une image avant de lever le drapeau, sinon rien ne bouge : le
        // contenu posé en même temps que le drapeau naîtrait déjà en place.
        delay(16)
        hasAppeared = true
        markOpacity.animateTo(BrandMarkBackdrop.restingOpacity, SwiftMotion.smooth(0.8f))
    }

    // MARK: Gestes

    /**
     * Le partage et l'aperçu sont des écrans du serveur : pour un voyage qu'il
     * n'a pas encore reçu, l'appui dit pourquoi (T239).
     */
    fun openFromServer(intent: HomeIntent, trip: Trip) {
        if (trip.id in tripsAwaitingServer) showsAwaitingServer = true else onIntent(intent)
    }

    /**
     * **La permission d'abord, la feuille ensuite** (Hugo, 17/09/2026).
     *
     * « Commencer à enregistrer » faisait disparaître l'app sur son iPhone : la
     * feuille s'ouvrait et le micro démarrait pendant que la demande d'accès du
     * système montait par-dessus. Le premier appui ne fait donc que poser la
     * question — l'app ne touche pas au micro avant la réponse — et c'est le
     * second qui ouvre la feuille ; avec l'accès déjà accordé, le premier appui
     * l'ouvre directement. La reconnaissance vocale n'est plus demandée : la
     * feuille ne l'emploie plus (T176, 29/09/2026).
     *
     * Refusé pour de bon, Android ne repose plus la question : la boîte le dit
     * et mène aux Paramètres, comme le micro barré de la conversation.
     */
    fun startRecording() {
        when (RecordingPermission.current(context)) {
            RecordingPermission.State.Granted -> {
                showsMicrophoneDenied = false
                isRecording = true
            }
            RecordingPermission.State.Undetermined -> scope.launch {
                if (!requestMicrophone()) showsMicrophoneDenied = true
            }
            RecordingPermission.State.Denied -> showsMicrophoneDenied = true
        }
    }

    // MARK: L'écran

    CompositionLocalProvider(LocalHomeContentHasAppeared provides hasAppeared) {
        Box(
            modifier
                .fillMaxSize()
                .background(MemoBookColor.background),
        ) {
            BrandMarkBackdrop(progress = 1f, opacity = markOpacity.value, modifier = Modifier.fillMaxSize())

            AwaitingServerNotice(
                isPresented = showsAwaitingServer,
                onIsPresentedChange = { showsAwaitingServer = it },
                below = DeviceScreen.topSafeInset(),
                modifier = Modifier.fillMaxSize(),
            ) {
                // **L'accueil s'ouvre sur ce qu'on avait, et le dit quand ça
                // change.** C'est l'écran qui gagne le plus au cache — c'est le
                // premier — et celui qui risque le plus de changer sous les
                // yeux : une étape de plus, un vocal transcrit, une photo
                // arrivée d'un co-voyageur.
                BrandRefreshFlash(isUpdated = state.freshness.isUpdated, modifier = Modifier.fillMaxSize()) {
                    // Deux couches : le contenu qui défile, et le bouton qui
                    // reste — avec, en fond, le voile de la marque qui dissout
                    // ce qui passe dessous (`BrandFooterScrim`). Il descend
                    // jusqu'au bord de la dalle, sous la barre de navigation.
                    Box(Modifier.fillMaxSize()) {
                        Refreshable(
                            onRefresh = { model.load() },
                            modifier = Modifier.fillMaxSize(),
                            indicatorTop = DeviceScreen.topSafeInset(),
                        ) {
                            Column(
                                Modifier
                                    .fillMaxSize()
                                    .verticalScroll(rememberScrollState())
                                    .padding(horizontal = MemoBookSpacing.screenMargin)
                                    .padding(top = DeviceScreen.topSafeInset() + MemoBookSpacing.xs)
                                    // Le bouton est dessiné par la pile, pas ici :
                                    // cette marge ne sert qu'à lui **réserver sa
                                    // place**, pour que le dernier carnet de la
                                    // liste puisse défiler jusqu'au-dessus de lui.
                                    .padding(bottom = with(density) { callToActionHeight.toDp() } + MemoBookSpacing.m),
                                verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.l),
                            ) {
                                // Rien tant qu'il n'y a rien à montrer. Sans ce
                                // garde-fou, le premier rendu affichait
                                // « Bienvenue 👋 » sans prénom, puis le
                                // remplaçait — et la cascade rendait le fondu
                                // croisé des deux textes bien visible. L'écran de
                                // lancement couvre cette attente.
                                if (state.feed != null || state.errorMessage != null) {
                                    HomeLoadedContent(
                                        state = state,
                                        model = model,
                                        showsMicrophoneDenied = showsMicrophoneDenied,
                                        showsSandbox = showsSandbox,
                                        tripsAwaitingServer = tripsAwaitingServer,
                                        onIntent = onIntent,
                                        onOpenFromServer = ::openFromServer,
                                        onCreateNotebook = { isCreatingNotebook = true },
                                        onDelete = { tripToDelete = it },
                                        onRetry = { work.launch { model.retry() } },
                                        onOpenSettings = { openAppSettings(context) },
                                    )
                                }
                            }
                        }

                        RecordCallToAction(
                            hasOngoingTrip = hasOngoingTrip,
                            modifier = Modifier
                                .align(Alignment.BottomCenter)
                                .onSizeChanged { callToActionHeight = it.height },
                        ) {
                            // Un voyage ouvert : on raconte. Aucun : il faut
                            // d'abord un carnet, et c'est la feuille qui demande
                            // lequel.
                            if (hasOngoingTrip) startRecording() else isCreatingNotebook = true
                        }
                    }
                }
            }

            // **Le paywall, par « Me réabonner ».** Le même écran que celui du
            // profil, dans la version que la session a apprise de l'accueil : un
            // ancien abonné y revoit les deux écrans du retour, pas la
            // découverte.
            HomeFullScreenCover(isPresented = showsPaywall) {
                PaywallView(
                    subscription = Subscription.offer,
                    onSubscribe = {
                        subscriptionSession?.record(isSubscribed = true)
                        showsPaywall = false
                        // L'accueil relu, le serveur confirme l'achat — et la
                        // session lui rend la main (03/10/2026).
                        work.launch { model.load() }
                    },
                    onDismiss = { showsPaywall = false },
                    variant = subscriptionSession?.paywallVariant ?: PaywallVariant.FirstTime,
                    previewMemoId = ongoingTripId,
                )
            }
        }
    }

    // MARK: Feuilles et alertes

    BrandSheetHost(isPresented = isCreatingNotebook, onDismissRequest = { isCreatingNotebook = false }) {
        NewNotebookSheet(
            resumableTrip = state.resumableTrip,
            join = { code -> model.join(code) },
            onIntent = onIntent,
        )
    }

    BrandSheetHost(
        item = tripToDelete,
        onDismissRequest = { tripToDelete = null },
        dismissDisabled = state.deletingTripId != null,
    ) { trip ->
        DisposableEffect(trip.id) { onDispose { model.dismissDeletionError() } }
        DeleteTripSheet(
            tripName = trip.title,
            isDeleting = state.deletingTripId == trip.id,
            errorMessage = state.deletionError,
            onKeep = { tripToDelete = null },
            onDelete = {
                work.launch {
                    if (model.deleteTrip(trip.id)) tripToDelete = null
                }
            },
        )
    }

    BrandSheetHost(isPresented = isRecording, onDismissRequest = { isRecording = false }) {
        // Deux choses, et les deux : l'envoi est l'affaire du modèle de
        // l'écran, comme son chargement — la file décide d'envoyer ou de
        // garder. Et **on arrive dans la conversation, le vocal déjà posé**
        // (Hugo, 14/09/2026) : c'est ça qui se route.
        //
        // Le crédit du jour est celui du voyage en cours, relu avec le dernier
        // geste d'abonnement de la session ; « Crédit du jour épuisé » ouvre
        // l'offre une fois la feuille refermée (03/10/2026). **Un seul point
        // d'accès**, `HomeModel.ongoingTripCredit` : il recharge le crédit d'hier
        // passé minuit, cache compris.
        val credit = model.ongoingTripCredit
        RecordingSheet(
            credit = subscriptionSession?.applied(credit) ?: credit,
            onSubscribe = { showsPaywall = true },
        ) { audio, levels, stoppedAtLimit ->
            // Un seul identifiant pour les deux : la bulle le porte, et la file
            // s'en sert pour dire où en est **cet** envoi-là. Sans lui, la
            // conversation devrait deviner — et elle devinerait « envoyé » dès
            // que MEMO répond, même sur un vocal qui attend encore le réseau.
            val handoff = RecordingHandoff(audio = audio, levels = levels, stoppedAtLimit = stoppedAtLimit)
            work.launch { model.upload(audio, levels = levels, handoffId = handoff.id) }
            model.ongoingTrips.firstOrNull()?.id?.let { tripId ->
                onIntent(HomeIntent.OpenConversation(tripId, handoff))
            }
        }
    }

    BrandAlert(
        isPresented = showsTripEndReminder,
        title = SubscriptionCopy.tripEndTitle,
        message = SubscriptionCopy.tripEndMessage,
        actions = listOf(
            BrandAlert.Action(SubscriptionCopy.tripEndCancel) {
                showsTripEndReminder = false
                TripEndReminder.openPlaySubscriptions(context)
            },
            BrandAlert.Action(SubscriptionCopy.tripEndKeep, BrandAlert.Role.Cancel) { showsTripEndReminder = false },
        ),
        onDismissRequest = { showsTripEndReminder = false },
    )

    // **L'alerte de fin d'abonnement.** Elle ne propose que deux gestes : en
    // prendre acte, ou se réabonner — et le second ouvre le paywall, où l'offre
    // est déjà écrite. Une alerte qui ne mènerait qu'à « D'accord »
    // annoncerait une porte fermée sans dire où est la poignée.
    BrandAlert(
        isPresented = showsSubscriptionEnded,
        title = SubscriptionCopy.endedTitle,
        message = SubscriptionCopy.endedMessage(tripTitle = state.ongoingTrips.firstOrNull()?.title),
        actions = listOf(
            BrandAlert.Action(SubscriptionCopy.endedResubscribe) {
                showsSubscriptionEnded = false
                showsPaywall = true
            },
            BrandAlert.Action(SubscriptionCopy.endedDismiss, BrandAlert.Role.Cancel) { showsSubscriptionEnded = false },
        ),
        onDismissRequest = { showsSubscriptionEnded = false },
    )
}

/** Ce que l'accueil montre une fois qu'il a quelque chose à montrer. */
@Composable
private fun ColumnScope.HomeLoadedContent(
    state: HomeModel.State,
    model: HomeModel,
    showsMicrophoneDenied: Boolean,
    showsSandbox: Boolean,
    tripsAwaitingServer: Set<String>,
    onIntent: (HomeIntent) -> Unit,
    onOpenFromServer: (HomeIntent, Trip) -> Unit,
    onCreateNotebook: () -> Unit,
    onDelete: (Trip) -> Unit,
    onRetry: () -> Unit,
    onOpenSettings: () -> Unit,
) {
    val ongoing = state.ongoingTrips
    val upcoming = state.upcomingTrips
    val past = state.pastTrips

    // MARK: Rangs d'apparition
    //
    // Chaque élément monte à son tour. Les rangs se calculent à partir du
    // contenu plutôt que d'être écrits en dur : ajouter un voyage décale
    // automatiquement tout ce qui le suit.
    //
    // La section « à venir » n'apparaît pas toujours : elle sert soit à
    // montrer un voyage déjà prévu, soit à inviter à en préparer un — et cette
    // invitation n'a de sens que si rien n'est en cours.
    val showsUpcomingSection = upcoming.isNotEmpty() || ongoing.isEmpty()
    val ongoingHeadingOrder = 1
    val upcomingHeadingOrder = ongoingHeadingOrder + if (ongoing.isEmpty()) 0 else 1 + ongoing.size
    val pastHeadingOrder = upcomingHeadingOrder + if (showsUpcomingSection) 1 + max(upcoming.size, 1) else 0
    val showcaseOrder = pastHeadingOrder + 1 + max(past.size, 1)

    /**
     * Le tiroir d'une carte de voyage : **supprimer, partager, prévisualiser**
     * — la croix, la flèche de partage, l'imprimante (Hugo, 17/09/2026). Le
     * même `BrandSwipeDrawer` que la liste des co-voyageurs, au rayon des
     * cartes de l'accueil. Le geste qui défait est le premier sous le doigt, et
     * il demande confirmation ; les deux autres ouvrent l'aperçu du carnet.
     *
     * Un voyage créé hors ligne que le serveur n'a pas encore reçu garde sa
     * croix — il s'oublie sur le téléphone —, mais son partage et son aperçu
     * pâlissent et disent pourquoi (T239).
     *
     * **La croix n'est qu'au propriétaire** (T233, Hugo, 06/10/2026) : un
     * co-voyageur ne la voit pas, ni dans le tiroir, ni dans le menu de l'appui
     * long, ni dans les actions de TalkBack — les trois lisent la même liste.
     */
    @Composable
    fun TripDrawer(trip: Trip, card: @Composable (Modifier) -> Unit) {
        val serverTint = if (trip.id in tripsAwaitingServer) {
            MemoBookColor.action.copy(alpha = TripAwaitingServer.dimmedOpacity)
        } else {
            MemoBookColor.action
        }
        val actions = buildList {
            if (trip.isDeletable) {
                add(BrandSwipeAction(R.drawable.icon_cross, MemoBookColor.error, "Supprimer « ${trip.title} »") { onDelete(trip) })
            }
            add(
                BrandSwipeAction(R.drawable.icon_share_system, serverTint, "Partager « ${trip.title} »") {
                    onOpenFromServer(HomeIntent.ShareTrip(trip.id), trip)
                },
            )
            add(
                BrandSwipeAction(
                    R.drawable.icon_printer,
                    serverTint,
                    "Prévisualiser « ${trip.title} »",
                    // Le tracé de l'imprimante est plus petit dans sa boîte que
                    // les deux autres — voir `BrandSwipeAction.iconScale`.
                    iconScale = 1.15f,
                ) { onOpenFromServer(HomeIntent.OrderPrint(trip.id), trip) },
            )
        }
        BrandSwipeDrawer(actions) { accessibility -> card(accessibility) }
    }

    Rising(0) { HomeGreeting(state.feed?.traveller?.firstName, state.feed?.traveller?.avatarUrl?.toString()) { onIntent(HomeIntent.OpenProfile) } }

    // La boîte d'information : hors ligne, vocaux en attente, envoi en cours,
    // vocaux arrivés.
    //
    // Elle est **sous la salutation et au-dessus des voyages**, et elle y
    // reste : une bande d'état qui change de place selon le message se cherche
    // à chaque fois. Le contenu, lui, vient de [HomeNotice] — la vue n'écrit pas
    // un mot de ces phrases, comme elle n'écrit pas les titres de voyages.
    //
    // Elle apparaît et disparaît **pendant** qu'on regarde l'écran — une
    // coupure de réseau ne prévient pas. Elle se pose donc au lieu de surgir.
    // Et le réseau qui tombe ou qui revient ne se voit pas quand on ne regarde
    // pas l'écran : TalkBack l'annonce, une fois, à chaque changement — c'est
    // exactement ce que la boîte fait pour quelqu'un qui voit.
    val notice = state.notice
    val shownNotice = remember { NoticeMemory() }
    if (notice != null) shownNotice.last = notice
    AnimatedVisibility(
        visible = notice != null,
        enter = fadeIn(SwiftMotion.smooth(0.35f)) +
            scaleIn(SwiftMotion.smooth(0.35f), initialScale = 0.97f, transformOrigin = TransformOrigin(0.5f, 0f)) +
            expandVertically(SwiftMotion.smooth(0.35f), expandFrom = Alignment.Top),
        exit = fadeOut(SwiftMotion.smooth(0.35f)) +
            scaleOut(SwiftMotion.smooth(0.35f), targetScale = 0.97f, transformOrigin = TransformOrigin(0.5f, 0f)) +
            shrinkVertically(SwiftMotion.smooth(0.35f), shrinkTowards = Alignment.Top),
    ) {
        Rising(1) {
            BrandNotice(
                (notice ?: shownNotice.last)?.message.orEmpty(),
                modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
            )
        }
    }

    state.errorMessage?.let { message ->
        Rising(1) { ErrorBanner(message, retry = onRetry) }
    }

    if (showsMicrophoneDenied) {
        Rising(1) { MicrophoneDeniedNotice(onOpenSettings) }
    }

    // MARK: Les voyages en cours

    if (ongoing.isNotEmpty()) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
            // Le titre suit le nombre : un seul voyage, « Ton voyage » ;
            // plusieurs, « Tes voyages ». Le singulier figé sonnait faux dès le
            // deuxième carnet ouvert.
            Rising(ongoingHeadingOrder) {
                HomeSectionHeading(if (ongoing.size > 1) "Tes voyages" else "Ton voyage", showsLiveDot = true, onAdd = onCreateNotebook)
            }

            // Le voyage le plus récent porte sa couverture ; les autres tiennent
            // sur une ligne. Une seule photo par écran, celle qui compte.
            val featured = ongoing.first()
            Rising(ongoingHeadingOrder + 1) {
                TripDrawer(featured) { accessibility ->
                    FeaturedTripCard(featured, accessibility) { onIntent(HomeIntent.OpenTrip(featured.id)) }
                }
            }

            ongoing.drop(1).forEachIndexed { index, trip ->
                Rising(ongoingHeadingOrder + 2 + index) {
                    TripDrawer(trip) { accessibility ->
                        CompactTripCard(trip, accessibility) { onIntent(HomeIntent.OpenTrip(trip.id)) }
                    }
                }
            }
        }
    }

    // MARK: Les voyages à venir

    if (showsUpcomingSection) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
            // Le « + » ne se pose ici que si aucun voyage n'est en cours : sinon
            // il est déjà sur « Ton voyage », et deux ronds pour la même porte se
            // lisent comme deux portes.
            Rising(upcomingHeadingOrder) {
                HomeSectionHeading("Voyage à venir", onAdd = if (ongoing.isEmpty()) onCreateNotebook else null)
            }

            if (upcoming.isEmpty()) {
                Rising(upcomingHeadingOrder + 1) { UpcomingTripInvite(onOpen = onCreateNotebook) }
            } else {
                // La carte de la maquette `3125:33113` (Clara, 26/09/2026) :
                // photo d'attente floutée, compte à rebours, scotch.
                upcoming.forEachIndexed { index, trip ->
                    Rising(upcomingHeadingOrder + 1 + index) {
                        TripDrawer(trip) { accessibility ->
                            UpcomingTripCard(trip, accessibility) { onIntent(HomeIntent.OpenTrip(trip.id)) }
                        }
                    }
                }
            }
        }
    }

    // MARK: Les voyages précédents
    //
    // Toujours là, même vide : c'est une promesse — les carnets terminés
    // viendront se ranger ici.

    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
        Rising(pastHeadingOrder) { HomeSectionHeading("Voyages précédents", count = past.size) }

        if (past.isEmpty()) {
            Rising(pastHeadingOrder + 1) { PastTripsPlaceholder() }
        } else {
            past.forEachIndexed { index, trip ->
                Rising(pastHeadingOrder + 1 + index) {
                    TripDrawer(trip) { accessibility ->
                        PastTripCard(
                            trip,
                            accessibility,
                            onOpen = { onIntent(HomeIntent.OpenTrip(trip.id)) },
                            onOrderPrint = { onOpenFromServer(HomeIntent.OrderPrint(trip.id), trip) },
                        )
                    }
                }
            }
        }
    }

    state.feed?.showcase?.let { showcase ->
        Rising(showcaseOrder) { ShowcaseCard(showcase) { onIntent(HomeIntent.OpenGallery) } }
    }

    Rising(showcaseOrder + 1) {
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            BrandButton("Besoin d’aide ?", style = BrandButton.Style.Link, isSubdued = true) { onIntent(HomeIntent.OpenHelp) }
        }
    }

    if (showsSandbox) {
        Rising(showcaseOrder + 2) { HomeDebugPanel(model) }
    }
}

/** La dernière boîte montrée, le temps qu'elle s'efface. */
private class NoticeMemory {
    var last: HomeNotice? = null
}

// MARK: - En-tête

/**
 * La salutation et l'avatar.
 *
 * Le prénom vient du serveur : sans lui, on salue quand même plutôt que
 * d'afficher un trou ou un « Bienvenue  » à deux espaces.
 *
 * L'espace avant la main est insécable : sur un petit écran la salutation se
 * coupe, et sans ça l'emoji se retrouvait seul sur sa ligne. On coupe entre
 * « Bienvenue » et le prénom, jamais avant la main.
 */
@Composable
private fun HomeGreeting(firstName: String?, avatarUrl: String?, onOpenProfile: () -> Unit) {
    val title = firstName?.let { "Bienvenue $it 👋" } ?: "Bienvenue 👋"

    if (isAccessibilityTextSize()) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            // L'avatar reste **à droite**, comme hors des grandes tailles :
            // c'est là que le pouce le cherche.
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) { AvatarButton(avatarUrl, onOpenProfile) }
            BrandText(title, MemoBookFont.greeting, color = MemoBookColor.ink)
        }
    } else {
        Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s), verticalAlignment = Alignment.CenterVertically) {
            BrandText(title, MemoBookFont.greeting, color = MemoBookColor.ink, modifier = Modifier.weight(1f))
            AvatarButton(avatarUrl, onOpenProfile)
        }
    }
}

/**
 * L'avatar, qui mène au profil.
 *
 * **Plus de pastille sur l'avatar** (Hugo, 03/10/2026) : elle décomptait
 * l'essai gratuit d'avant, qui n'existe plus. Le crédit du jour se lit là où
 * l'on raconte — la barre d'enregistrement —, et dans les réglages du voyage.
 */
@Composable
private fun AvatarButton(avatarUrl: String?, onOpenProfile: () -> Unit) {
    Box(
        Modifier
            .size(MemoBookSpacing.minimumTapTarget)
            .clip(CircleShape)
            .clickable(interactionSource = null, indication = PlainButtonIndication, role = Role.Button, onClick = onOpenProfile)
            .semantics { contentDescription = "Ton profil" },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(HomeMetrics.avatarSide)
                .clip(CircleShape)
                .background(MemoBookColor.outline, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            // L'icône d'abord, la photo par-dessus : elle tient la place tant
            // que la photo charge, et la remplace si elle ne vient pas — le
            // `AsyncImage` d'iOS et ses deux phases.
            Image(
                painterResource(R.drawable.icon_user),
                contentDescription = null,
                colorFilter = ColorFilter.tint(MemoBookColor.ink),
                modifier = Modifier.size(MemoBookSpacing.contentIcon),
            )
            if (avatarUrl != null) {
                AsyncImage(
                    model = avatarUrl,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.matchParentSize(),
                )
            }
        }
    }
}

// MARK: - Le micro

@Composable
private fun MicrophoneDeniedNotice(onOpenSettings: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
        BrandNotice(
            "**Le micro est refusé** dans les Paramètres du téléphone : MemoBook ne peut pas t’écouter tant qu’il l’est.",
            tone = BrandNotice.Tone.Information,
        )
        BrandButton("Ouvrir les Paramètres", style = BrandButton.Style.Link, action = onOpenSettings)
    }
}

/** Les Paramètres de l'app — l'`openSettingsURLString` d'iOS. */
private fun openAppSettings(context: Context) {
    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    try {
        context.startActivity(intent)
    } catch (_: ActivityNotFoundException) {
        // Un téléphone sans écran de détails d'app : il n'y a rien à ouvrir.
    }
}

// MARK: - Action

/**
 * Le CTA : un voyage ouvert, on raconte ; aucun, on en crée un.
 *
 * **Toujours vert, toujours le micro** (Hugo, 03/10/2026). Il passait au lime
 * avec un cadenas et ouvrait le paywall une fois l'essai gratuit épuisé ; avec
 * le crédit du jour, personne n'est jamais bloqué d'avance — la feuille
 * d'enregistrement prévient à 4:30 et coupe à 5:00, et le serveur tranche
 * (`daily_credit_exhausted`).
 *
 * Le libellé suit la taille de police, mais s'arrête à la première taille
 * accessible (×1,5, le `...accessibility1` d'iOS). Au-delà, une barre ancrée en
 * bas prend la moitié de l'écran et cache ce qu'elle sert à enrichir — c'est la
 * limite habituelle des barres persistantes. TalkBack, lui, lit le libellé
 * entier quelle que soit la taille.
 */
@Composable
private fun RecordCallToAction(hasOngoingTrip: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val density = LocalDensity.current
    val capped = Density(density.density, fontScale = min(density.fontScale, HomeMetrics.callToActionFontScaleCap))
    CompositionLocalProvider(LocalDensity provides capped) {
        Box(
            modifier
                .fillMaxWidth()
                .brandFooterScrim()
                .navigationBarsPadding()
                .padding(horizontal = MemoBookSpacing.screenMargin)
                .padding(top = MemoBookSpacing.s, bottom = MemoBookSpacing.xs),
        ) {
            BrandButton(
                if (hasOngoingTrip) "Commencer à enregistrer" else "Créer un nouveau voyage",
                // Le micro du jeu d'icônes de la marque, pas l'illustration du
                // Welcome : `BrandButton` teinte l'icône, il lui faut un tracé
                // plein d'une seule couleur.
                icon = if (hasOngoingTrip) painterResource(R.drawable.icon_mic) else null,
                fillsWidth = true,
                action = onClick,
            )
        }
    }
}

/**
 * Un écran posé **par-dessus** l'accueil, qui monte du bas — le
 * `fullScreenCover` d'iOS. Le paywall porte son propre retour.
 */
@Composable
private fun HomeFullScreenCover(isPresented: Boolean, content: @Composable () -> Unit) {
    val reduceMotion = isReduceMotionEnabled()
    AnimatedVisibility(
        visible = isPresented,
        enter = if (reduceMotion) fadeIn() else slideInVertically(SwiftMotion.smooth(0.35f)) { it },
        exit = if (reduceMotion) fadeOut() else slideOutVertically(SwiftMotion.smooth(0.3f)) { it },
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .background(MemoBookColor.background),
        ) { content() }
    }
}

// MARK: - Le rappel de fin de voyage

/**
 * Le rappel « Ton voyage est terminé » : une fois par jour au plus, retenu sur
 * l'appareil. Deux écrans l'écrivent — l'accueil quand il l'ouvre, `RootView`
 * quand la notification de rappel arrive — et doivent lire la même clé et le
 * même jour.
 *
 * **Et la porte de résiliation, sur Android.** iOS ouvre la feuille de gestion
 * des abonnements d'Apple ; ici, la page des abonnements de Google Play, sur ce
 * produit. Elle n'existe que pour un abonnement que Google Play tient — voir
 * `HomeModel.tripEndReminderCanOpenHere`.
 */
object TripEndReminder {
    const val storageKey = "subscription.tripEndReminded"

    /** Le paquet sous lequel l'app est publiée : celui de la fiche Play. */
    private const val PLAY_PACKAGE = "com.memobook.app"

    /** La page des abonnements de Google Play, ouverte sur celui de MemoBook. */
    val playSubscriptionsUrl: String =
        "https://play.google.com/store/account/subscriptions?sku=${PlayCatalog.MONTHLY_SUBSCRIPTION}&package=$PLAY_PACKAGE"

    /**
     * Aujourd'hui, `AAAA-MM-JJ` — en temps universel, comme le
     * `.iso8601.year().month().day()` d'iOS, dont le fuseau par défaut est GMT.
     */
    fun today(now: Instant = Instant.now()): String = LocalDate.ofInstant(now, ZoneOffset.UTC).toString()

    /** Ouvre la page des abonnements de Google Play — l'app Play Store, ou le navigateur sans elle. */
    fun openPlaySubscriptions(context: Context) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(playSubscriptionsUrl)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            // Ni Play Store ni navigateur : il n'y a rien à ouvrir.
        }
    }
}

/** Ce que l'accueil retient sur l'appareil, hors du rappel de fin de voyage. */
private object HomeStorage {
    /**
     * Le dernier arrêt d'abonnement **déjà annoncé**, en secondes depuis 1970 —
     * la clé de l'`@AppStorage` d'iOS. Zéro tant que rien n'a été annoncé.
     */
    const val announcedEnd = "subscription.endAnnounced"
}

/** Les mesures de l'accueil. */
internal object HomeMetrics {
    /**
     * L'avatar est **le** diamètre du design system : le chat pose le même
     * devant son titre, et c'est à sa deuxième occurrence qu'il est monté dans
     * `MemoBookSpacing`.
     */
    val avatarSide = MemoBookSpacing.avatarSide

    /** Le CTA s'arrête à la première taille accessible — voir [RecordCallToAction]. */
    const val callToActionFontScaleCap = 1.5f
}

// MARK: - Apparition

/**
 * `true` une fois le contenu de l'accueil chargé et prêt à se poser.
 *
 * Il passe par la composition plutôt que d'être repassé à chaque appel : un
 * rang suffit alors sur le lieu d'appel (`Rising(3) { … }`), et aucun élément
 * ne peut se retrouver oublié hors de la cascade.
 */
private val LocalHomeContentHasAppeared = compositionLocalOf { false }

/**
 * Fait monter un élément depuis le bas, en fondu, avec un retard qui suit son
 * rang : le contenu se pose morceau par morceau au lieu de tomber d'un bloc, et
 * prolonge le tracé du M plutôt que de lui succéder.
 */
@Composable
private fun Rising(order: Int, content: @Composable () -> Unit) {
    val hasAppeared = LocalHomeContentHasAppeared.current
    val reduceMotion = isReduceMotionEnabled()
    val progress = remember { Animatable(if (hasAppeared || reduceMotion) 1f else 0f) }
    // Distance parcourue. Assez pour qu'on voie l'élément *arriver*, pas assez
    // pour qu'il traverse l'écran.
    val travel = with(LocalDensity.current) { HomeRise.travel.toPx() }

    LaunchedEffect(hasAppeared, reduceMotion) {
        when {
            reduceMotion -> progress.snapTo(1f)
            hasAppeared -> {
                delay(min(order, HomeRise.maximumRank) * HomeRise.staggerMs)
                // Un soupçon de rebond : c'est ce qui fait qu'un élément se
                // *pose* au lieu de s'arrêter net — le `.smooth(duration: 0.5,
                // extraBounce: 0.12)` d'iOS.
                progress.animateTo(1f, SwiftMotion.spring(response = 0.5f, dampingFraction = 0.88f))
            }
            else -> progress.snapTo(0f)
        }
    }

    Box(
        Modifier.graphicsLayer {
            alpha = progress.value.coerceIn(0f, 1f)
            translationY = (1f - progress.value) * travel
        },
    ) { content() }
}

/** Les mesures de la cascade. */
private object HomeRise {
    val travel = 40.dp

    /**
     * Écart entre deux éléments. Quelques dizaines de millisecondes : en
     * dessous la cascade ne se lit plus, au-dessus elle traîne.
     */
    const val staggerMs = 60L

    /**
     * Le retard est plafonné : au-delà d'une dizaine d'éléments, attendre une
     * seconde de plus n'ajoute rien et retarde ce qu'on voulait voir.
     */
    const val maximumRank = 10
}

// MARK: - Aperçus

@Preview(locale = "fr-rFR", name = "Accueil", widthDp = 390, heightDp = 844)
@Composable
private fun HomeViewPreview() {
    HomeView(remember { HomeModel() }, onIntent = {})
}

@Preview(locale = "fr-rFR", name = "Accueil — aucun voyage", widthDp = 390, heightDp = 844)
@Composable
private fun HomeViewEmptyPreview() {
    HomeView(remember { HomeModel(source = { HomeFeed.emptyFixture }) }, onIntent = {})
}

@Preview(locale = "fr-rFR", name = "Accueil — erreur", widthDp = 390, heightDp = 844)
@Composable
private fun HomeViewErrorPreview() {
    HomeView(remember { HomeModel(source = { throw java.io.IOException("La connexion Internet semble être désactivée.") }) }, onIntent = {})
}

@Preview(locale = "fr-rFR", name = "Accueil — AX3", widthDp = 390, heightDp = 844, fontScale = 2f)
@Composable
private fun HomeViewAccessibilityPreview() {
    HomeView(remember { HomeModel() }, onIntent = {})
}

@Preview(locale = "fr-rFR", name = "Accueil — petit téléphone", widthDp = 360, heightDp = 640)
@Composable
private fun HomeViewSmallPreview() {
    HomeView(remember { HomeModel() }, onIntent = {}, showsSandbox = true)
}
