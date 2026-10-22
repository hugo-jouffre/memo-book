package com.memobook.feature

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.Modifier
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.viewmodel.navigation3.rememberViewModelStoreNavEntryDecorator
import androidx.navigation3.runtime.NavEntry
import androidx.navigation3.runtime.rememberSaveableStateHolderNavEntryDecorator
import androidx.navigation3.ui.NavDisplay
import com.memobook.core.Account
import com.memobook.core.BookCopy
import com.memobook.core.TermsOfUse
import com.memobook.design.BrandAlert
import com.memobook.design.BrandBackdrop
import com.memobook.design.BrandSheetPresentation
import com.memobook.design.BrandSheetPresenter
import com.memobook.design.BrandStatusBarScrim
import com.memobook.design.LocalBrandSheetPresentation
import com.memobook.design.MemoBookColor
import com.memobook.feature.auth.AuthEntry
import com.memobook.feature.bookpreview.BookPreviewEntry
import com.memobook.feature.chat.ChatEntry
import com.memobook.feature.covers.CoverPhotoEntry
import com.memobook.feature.covers.CoverStyleEntry
import com.memobook.feature.covers.CoverTextsEntry
import com.memobook.feature.covers.CoversEntry
import com.memobook.feature.debug.DesignCatalogueView
import com.memobook.feature.gallery.GalleryEntry
import com.memobook.feature.home.HomeEntry
import com.memobook.feature.legal.LegalDocumentEntry
import com.memobook.feature.onboarding.LastQuestionsEntry
import com.memobook.feature.onboarding.LastQuestionsModel
import com.memobook.feature.onboarding.LaunchView
import com.memobook.feature.order.OrderEntry
import com.memobook.feature.paywall.PaywallEntry
import com.memobook.feature.profile.PasswordResetSheetEntry
import com.memobook.feature.profile.ProfileEntry
import com.memobook.feature.recording.RecordingHandoff
import com.memobook.feature.support.SupportEntry
import com.memobook.feature.trip.TripHomeEntry
import com.memobook.feature.tripcreation.TripCreationEntry
import com.memobook.feature.tripsettings.BookCustomisationEntry
import com.memobook.feature.tripsettings.TripSettingsEntry
import com.memobook.feature.welcome.WelcomeEntry
import com.memobook.networking.ApiError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.UUID

/**
 * Point d'entrée de l'interface, et le seul endroit qui décide de l'étape où
 * se trouve l'utilisateur : le tracé du M au lancement, l'écran d'entrée, les
 * « Dernières questions », puis l'app. Jumeau de `RootView.swift`.
 *
 * Rien n'est mis derrière un écran d'attente réseau : les erreurs appartiennent
 * à l'écran qui fait l'appel. La seule exception est la **restauration de
 * session** — voir [SessionRestore].
 *
 * **Les écrans annoncent une intention, et c'est ici qu'elle devient une
 * destination** (`Navigation.kt`). Les deux piles — l'entrée, et l'app une fois
 * entré — sont des [NavDisplay] : la pile de `NavigationStack(path:)`, le geste
 * de retour d'Android à la place du glissé depuis le bord, et un magasin de
 * modèles par destination, vidé quand elle quitte la pile.
 *
 * @param showsDeveloperDetails vrai dans un build Debug seulement : l'écran de
 *   lancement dit alors à quelle adresse l'app parle.
 * @param incomingLinks les liens `memobook://` et `https://…/j/…` reçus par
 *   l'activité — à froid comme app ouverte. `RootView` les consomme un à un
 *   ([IncomingLinks]).
 */
@Composable
fun RootView(dependencies: AppDependencies, showsDeveloperDetails: Boolean, incomingLinks: IncomingLinks = remember { IncomingLinks() }) {
    if (dependencies.switches.designCatalogue) {
        DesignCatalogueView()
        return
    }
    val state = remember(dependencies) { RootState(dependencies) }
    val scope = rememberCoroutineScope()
    val sheets = remember { BrandSheetPresentation() }

    LaunchedEffect(state) { state.restore() }

    // Un lien reçu : réinitialisation, invitation, notification.
    val link = incomingLinks.pending
    LaunchedEffect(link, state.stage) {
        if (link != null && state.receive(link)) incomingLinks.consume(link)
    }

    // « Ce qui n'a pas eu le temps de partir repart au retour dans l'app », et
    // une session refusée pendant qu'on était dedans ramène à l'entrée.
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        scope.launch { state.onReturnToForeground() }
    }

    CompositionLocalProvider(
        LocalBrandSheetPresentation provides sheets,
        LocalSubscriptionSession provides state.subscription,
        LocalAppSettings provides dependencies.settings,
        LocalLaunchOverlayIsVisible provides state.isLaunching,
        LocalHomeReloadRequest provides state.homeReloadRequest,
    ) {
        // L'app entière recule pendant qu'une feuille est ouverte : c'est ici,
        // au seul niveau qui occupe vraiment tout l'écran.
        BrandSheetPresenter(isPresented = sheets.isPresenting, modifier = Modifier.fillMaxSize()) {
            // **Le voile de la barre d'état, une fois pour toute l'app** (T210),
            // sauf sur l'accueil d'un voyage, dont la photo monte sous l'heure.
            BrandStatusBarScrim(Modifier.fillMaxSize(), isVisible = !state.showsFullBleedPhoto) {
                Box(Modifier.fillMaxSize()) {
                    AnimatedContent(
                        targetState = state.stage,
                        contentKey = { it::class },
                        transitionSpec = { stageTransition() },
                        label = "étape",
                    ) { stage ->
                        when (stage) {
                            RootState.Stage.Restoring -> Box(Modifier.fillMaxSize().background(MemoBookColor.background)) {
                                BrandBackdrop(Modifier.fillMaxSize())
                            }
                            RootState.Stage.SignedOut -> SignedOutStack(state)
                            is RootState.Stage.LastQuestions -> LastQuestionsEntry(
                                dependencies = dependencies,
                                account = stage.account,
                                onFinished = { state.finishLastQuestions(it) },
                            )
                            is RootState.Stage.SignedIn -> SignedInStack(state, stage.account)
                        }
                    }

                    AnimatedVisibility(
                        visible = state.isLaunching,
                        enter = fadeIn(tween(0)),
                        // Le signe grandit d'un cheveu en s'effaçant : il s'éloigne au
                        // lieu de s'éteindre.
                        exit = fadeOut(tween(450)) + scaleOut(tween(450), targetScale = 1.06f),
                    ) {
                        LaunchView(
                            developerDetails = if (showsDeveloperDetails) dependencies.apiConfiguration?.let { LaunchCopy.apiAddress(it) } else null,
                            onDrawingFinished = { state.drawingDidFinish() },
                        )
                    }
                }
            }
        }

        PasswordResetSheetEntry(
            dependencies = dependencies,
            token = state.signedInResetToken,
            onDismiss = { state.signedInResetToken = null },
        )

        BrandAlert(
            isPresented = state.routingProblem != null,
            title = "Impossible d’ouvrir ce voyage",
            message = state.routingProblem,
            actions = listOf(BrandAlert.Action("D’accord", BrandAlert.Role.Cancel) { state.routingProblem = null }),
            onDismissRequest = { state.routingProblem = null },
        )
    }
}

private fun stageTransition(): ContentTransform =
    (fadeIn(tween(250)) + slideInHorizontally(tween(300)) { it / 6 }) togetherWith fadeOut(tween(200))

/** La pile de l'écran d'entrée : l'écran d'accueil, et le formulaire par e-mail qu'il pousse. */
@Composable
private fun SignedOutStack(state: RootState) {
    val dependencies = state.dependencies
    val backStack: List<Any> = listOf(SignedOutRoot) + state.signedOutPath
    NavDisplay(
        backStack = backStack,
        onBack = { state.signedOutPath.removeLastOrNull() },
        entryDecorators = listOf(rememberSaveableStateHolderNavEntryDecorator(), rememberViewModelStoreNavEntryDecorator()),
        transitionSpec = { pushTransition() },
        popTransitionSpec = { popTransition() },
        predictivePopTransitionSpec = { popTransition() },
        entryProvider = { key ->
            NavEntry(key, contentKey = key.toString()) {
                when (key) {
                    SignedOutRoot -> WelcomeEntry(
                        dependencies = dependencies,
                        onAuthenticated = { state.enterApp(it) },
                        onEmail = { state.signedOutPath.add(SignedOutRoute.Email) },
                        onTermsOfUse = { state.signedOutPath.add(SignedOutRoute.TermsOfUse) },
                    )
                    SignedOutRoute.Email -> AuthEntry(
                        dependencies = dependencies,
                        resetToken = state.pendingResetToken,
                        onResetTokenConsumed = { state.pendingResetToken = null },
                        onAuthenticated = { state.enterApp(it) },
                        onBack = { state.signedOutPath.removeLastOrNull() },
                    )
                    // Sans « Besoin d'aide ? » : le support demande un compte (T151).
                    SignedOutRoute.TermsOfUse -> LegalDocumentEntry(
                        document = TermsOfUse.document,
                        showsHelp = false,
                        onIntent = {},
                        onBack = { state.signedOutPath.removeLastOrNull() },
                    )
                }
            }
        },
    )
}

/** La pile de l'app, une fois entré : l'accueil, et tout ce qu'il pousse. */
@Composable
private fun SignedInStack(state: RootState, account: Account) {
    val dependencies = state.dependencies
    // Les modèles **de la session** — le support, les couvertures : un magasin
    // vidé quand le compte change.
    val sessionModels = remember(account.id) {
        object : ViewModelStoreOwner {
            override val viewModelStore = ViewModelStore()
        }
    }
    DisposableEffect(sessionModels) { onDispose { sessionModels.viewModelStore.clear() } }

    // Le vocal en route vers la conversation ne vit que le temps de celle-ci.
    LaunchedEffect(state.path.toList()) {
        if (state.path.none { it is HomeRoute.Chat }) state.recordingHandoff = null
    }

    CompositionLocalProvider(
        LocalSessionViewModelStoreOwner provides sessionModels,
        LocalTravellerFirstName provides account.firstName,
    ) {
        val back: () -> Unit = { state.path.removeLastOrNull() }
        NavDisplay(
            backStack = listOf<Any>(HomeRoot) + state.path,
            onBack = back,
            entryDecorators = listOf(rememberSaveableStateHolderNavEntryDecorator(), rememberViewModelStoreNavEntryDecorator()),
            transitionSpec = { pushTransition() },
            popTransitionSpec = { popTransition() },
            predictivePopTransitionSpec = { popTransition() },
            entryProvider = { key ->
                NavEntry(key, contentKey = key.toString()) {
                    when (key) {
                        HomeRoot -> HomeEntry(dependencies, onIntent = state::handle)
                        is HomeRoute -> Destination(state, key, account, back)
                    }
                }
            },
        )

        if (state.showsNotificationPaywall) {
            PaywallEntry(
                dependencies = dependencies,
                onSubscribe = {
                    state.subscription.record(isSubscribed = true)
                    state.showsNotificationPaywall = false
                    state.homeReloadRequest += 1
                },
                onDismiss = { state.showsNotificationPaywall = false },
            )
        }
    }
}

@Composable
private fun Destination(state: RootState, route: HomeRoute, account: Account, back: () -> Unit) {
    val dependencies = state.dependencies
    when (route) {
        HomeRoute.Profile, HomeRoute.ManageSubscription -> ProfileEntry(
            dependencies = dependencies,
            opensSubscription = route == HomeRoute.ManageSubscription,
            onSignOut = { state.signOut() },
            onIntent = state::handle,
            onBack = back,
        )
        is HomeRoute.Trip -> TripHomeEntry(dependencies, route.id, onIntent = state::handle, onBack = back)
        // La file passe par ici parce que c'est par ici qu'on arrive après un
        // enregistrement rapide : le vocal est déjà parti, et la bulle suit son sort.
        is HomeRoute.Chat -> ChatEntry(dependencies, route.tripId, route.stepId, state.recordingHandoff, onIntent = state::handle, onBack = back)
        // La galerie et la création **réémettent** des intentions de l'accueil.
        HomeRoute.Gallery -> GalleryEntry(dependencies, onIntent = state::handle, onBack = back)
        HomeRoute.TripCreation -> TripCreationEntry(dependencies, onIntent = state::handle, onBack = back)
        is HomeRoute.TripSettings -> TripSettingsEntry(dependencies, route.id, route.opening, onIntent = state::handle, onBack = back)
        is HomeRoute.BookPreview -> BookPreviewEntry(dependencies, route.memoId, route.sharing, onIntent = state::handle, onBack = back)
        is HomeRoute.Order -> OrderEntry(dependencies, route.memoId, account.email, onIntent = state::handle, onBack = back)
        is HomeRoute.BookCustomisation -> BookCustomisationEntry(dependencies, route.tripId, onIntent = state::handle, onBack = back)
        is HomeRoute.Covers -> CoversEntry(dependencies, route.tripId, onIntent = state::handle, onBack = back)
        is HomeRoute.CoverStyle -> CoverStyleEntry(dependencies, route.tripId, onBack = back)
        is HomeRoute.CoverPhoto -> CoverPhotoEntry(dependencies, route.tripId, onBack = back)
        is HomeRoute.CoverTexts -> CoverTextsEntry(dependencies, route.tripId, onBack = back)
        // Le voyage d'où l'on vient part avec le message (T226).
        HomeRoute.Support -> SupportEntry(dependencies, tripId = state.supportTripId, onBack = back)
        is HomeRoute.Legal -> LegalDocumentEntry(route.document.content, showsHelp = true, onIntent = state::handle, onBack = back)
    }
}

/** La transition d'un écran poussé : il arrive de la droite, celui du dessous recule d'un tiers, comme sur iOS. */
private fun pushTransition(): ContentTransform =
    slideInHorizontally(tween(350)) { it } togetherWith slideOutHorizontally(tween(350)) { -it / 3 }

private fun popTransition(): ContentTransform =
    slideInHorizontally(tween(350)) { -it / 3 } togetherWith slideOutHorizontally(tween(350)) { it }

/** La racine de la pile de l'entrée — l'écran d'accueil — sous ce qu'elle pousse. */
private data object SignedOutRoot

/** La racine de la pile de l'app — l'accueil — sous ce qu'elle pousse. */
private data object HomeRoot

/**
 * Les liens reçus par l'activité, en attente que `RootView` les consomme : un
 * lien ouvert à froid arrive avant que la racine existe, et se perdrait s'il
 * l'attendait. Le `onOpenURL` d'iOS.
 */
class IncomingLinks {
    var pending: String? by mutableStateOf(null)
        private set

    fun receive(url: String) {
        pending = url
    }

    internal fun consume(url: String) {
        if (pending == url) pending = null
    }
}

/**
 * L'état de [RootView] — ses `@State` sur iOS, réunis dans un objet qui vit
 * autant que la racine.
 */
internal class RootState(val dependencies: AppDependencies) {
    sealed interface Stage {
        /** On regarde si la session gardée vaut encore quelque chose. */
        data object Restoring : Stage
        data object SignedOut : Stage

        /** Le compte vient d'être ouvert : les « Dernières questions » avant l'accueil. */
        data class LastQuestions(val account: Account) : Stage
        data class SignedIn(val account: Account) : Stage
    }

    var stage: Stage by mutableStateOf(Stage.Restoring)
        private set

    /**
     * Le M est en train de s'écrire par-dessus tout le reste. **Faux au
     * démarrage** : le tracé n'est pas une marque d'ouverture, c'est l'attente
     * de l'accueil. Il s'écrit dès qu'un jeton est gardé, et la vérification se
     * joue dessous (Hugo, 18/09/2026).
     */
    var isLaunching by mutableStateOf(false)
        private set

    /** Le M a fini de s'écrire, mais l'accueil n'est pas encore là pour le recevoir. */
    private var drawingFinished = false

    val signedOutPath: SnapshotStateList<SignedOutRoute> = mutableStateListOf()
    val path: SnapshotStateList<HomeRoute> = mutableStateListOf()

    val subscription = SubscriptionSession()
    var homeReloadRequest by mutableIntStateOf(0)

    /** Le vocal enregistré depuis l'accueil, le temps d'ouvrir la conversation qui va le montrer. */
    var recordingHandoff: RecordingHandoff? by mutableStateOf(null)

    /** Ce qui empêche d'aller là où on vient de demander à aller — une alerte **sur l'accueil**. */
    var routingProblem: String? by mutableStateOf(null)

    /** Le code d'un lien d'invitation, en attendant une session. */
    private var pendingInviteCode: String? = null

    /** Le secret d'un lien de réinitialisation, en attendant que l'écran d'entrée le consomme. */
    var pendingResetToken: String? by mutableStateOf(null)

    /** Un lien de réinitialisation ouvert **depuis l'app entrée** : la feuille du nouveau mot de passe. */
    var signedInResetToken: String? by mutableStateOf(null)

    /** L'offre, ouverte par un lien `memobook://paywall`. */
    var showsNotificationPaywall by mutableStateOf(false)

    private val isPreview get() = dependencies.isPreviewingSignedIn

    // MARK: - Lancement

    /**
     * Décide de l'écran d'ouverture. Une session périmée renvoie 401, que le
     * client traduit en oubli du jeton ; **une panne n'y mène plus** : on entre
     * avec le compte gardé (`SessionRestore`, 29/09/2026).
     */
    suspend fun restore() {
        if (stage != Stage.Restoring) return

        // Le raccourci de vérification en émulateur — sans effet en Release.
        if (isPreview) {
            enterApp(Account(id = "preview", firstName = "Camille", createdAt = Instant.now()))
            return
        }

        // Pas de jeton : la décision est immédiate, l'écran d'entrée. **Pas de
        // tracé du M** — une animation devant un formulaire retarde la saisie.
        if (!dependencies.api.hasStoredSession()) {
            stage = Stage.SignedOut
            return
        }

        isLaunching = true
        when (val restore = dependencies.restoreSession()) {
            is SessionRestore.Verified -> enterApp(restore.account)
            is SessionRestore.Remembered -> enterApp(restore.account)
            SessionRestore.Closed, SessionRestore.Unreachable -> {
                stage = Stage.SignedOut
                endLaunch()
            }
        }
    }

    /**
     * Entrer dans l'app, d'où qu'on vienne. C'est **le seul chemin** vers
     * l'accueil, et c'est pour ça que le tracé du M est ici.
     */
    fun enterApp(account: Account) {
        remember(account)
        // Un compte qui vient d'être ouvert passe d'abord par les « Dernières
        // questions » (Clara, 26/09/2026) — une seule fois, jamais dans le bac à sable.
        val asksLastQuestions = dependencies.switches.lastQuestions ||
            (!isPreview && LastQuestionsModel.shouldAsk(account, dependencies.settings))
        if (asksLastQuestions && stage != Stage.LastQuestions(account)) {
            signedOutPath.clear()
            stage = Stage.LastQuestions(account)
            endLaunch()
            return
        }
        openApp(account)
    }

    fun finishLastQuestions(account: Account) {
        LastQuestionsModel.markAnswered(account, dependencies.settings)
        remember(account)
        openApp(account)
    }

    /** Garde le compte pour le prochain lancement. Jamais celui du bac à sable. */
    private fun remember(account: Account) {
        if (isPreview) return
        dependencies.scope.launch { dependencies.rememberAccount(account) }
    }

    private fun openApp(account: Account) {
        stage = Stage.SignedIn(account)
        signedOutPath.clear()
        // Les raccourcis du bac à sable — sans effet en Release.
        if (dependencies.switches.openOrder) path.apply { clear(); add(HomeRoute.Order(PREVIEW_ORDER_MEMO_ID)) }
        if (dependencies.switches.composeBook) {
            path.apply { clear(); add(HomeRoute.Trip(PREVIEW_ROME_TRIP_ID)); add(HomeRoute.BookPreview(PREVIEW_ROME_TRIP_ID)) }
        }
        isLaunching = true
        if (drawingFinished) endLaunch()
        openPendingInvite()
    }

    fun drawingDidFinish() {
        drawingFinished = true
        if (stage == Stage.Restoring) return
        endLaunch()
    }

    private fun endLaunch() {
        drawingFinished = false
        isLaunching = false
    }

    // MARK: - Sortie

    /**
     * Ferme la session. L'ordre compte : la pile d'abord, puis l'oubli. La
     * déconnexion ne peut pas échouer — elle oublie le jeton local même si le
     * serveur est injoignable.
     */
    fun signOut() {
        dependencies.scope.launch {
            runCatching { dependencies.api.signOut() }
            dependencies.forgetAccountContent()
            subscription.reset()
            path.clear()
            stage = Stage.SignedOut
        }
    }

    /** Un appel a reçu un 401 pendant qu'on était dans l'app : on retourne à l'entrée. */
    suspend fun onReturnToForeground() {
        if (stage !is Stage.SignedIn || isPreview) return
        subscription.expireIfDue()
        if (dependencies.api.hasStoredSession()) return
        dependencies.forgetAccountContent()
        subscription.reset()
        path.clear()
        stage = Stage.SignedOut
    }

    // MARK: - Liens

    /**
     * Reçoit un lien. Rend `true` quand il est consommé, `false` quand il doit
     * attendre (une invitation hors session attend l'entrée).
     */
    fun receive(url: String): Boolean {
        val uri = runCatching { java.net.URI(url.trim()) }.getOrNull() ?: return true
        val notification = com.memobook.core.NotificationLink.from(uri)
        if (notification != null) {
            if (notification is com.memobook.core.NotificationLink.Join) {
                pendingInviteCode = notification.code
                openPendingInvite()
                return true
            }
            if (stage !is Stage.SignedIn) return false
            open(notification)
            return true
        }
        val token = com.memobook.core.PasswordResetLink.token(uri) ?: return true
        // Déjà entré : la feuille du nouveau mot de passe, par-dessus l'écran où l'on est.
        if (stage is Stage.SignedIn) {
            signedInResetToken = token
            return true
        }
        pendingResetToken = token
        if (signedOutPath.isEmpty()) signedOutPath.add(SignedOutRoute.Email)
        return true
    }

    /**
     * Ouvre l'écran d'une notification touchée — ou d'un lien `memobook://`.
     * **Une pile neuve**, posée sur le voyage : la flèche de retour ramène au
     * voyage, puis à l'accueil.
     */
    private fun open(link: com.memobook.core.NotificationLink) {
        when (link) {
            com.memobook.core.NotificationLink.Paywall -> showsNotificationPaywall = true
            com.memobook.core.NotificationLink.Subscription -> path.apply { clear(); add(HomeRoute.ManageSubscription) }
            com.memobook.core.NotificationLink.NewTrip -> path.apply { clear(); add(HomeRoute.TripCreation) }
            is com.memobook.core.NotificationLink.Join -> {
                pendingInviteCode = link.code
                openPendingInvite()
            }
            is com.memobook.core.NotificationLink.Chat -> if (isResourceId(link.tripId)) {
                path.apply { clear(); add(HomeRoute.Trip(link.tripId)); add(HomeRoute.Chat(link.tripId)) }
            }
            is com.memobook.core.NotificationLink.BookPreview -> if (isResourceId(link.tripId)) {
                path.apply { clear(); add(HomeRoute.Trip(link.tripId)); add(HomeRoute.BookPreview(link.tripId)) }
            }
        }
    }

    /**
     * **Rejoint le voyage d'un lien d'invitation, puis ouvre son écran** (Hugo,
     * 18/10/2026). Déjà membre, le serveur rend le même voyage. Hors session,
     * le code attend l'entrée.
     */
    private fun openPendingInvite() {
        if (stage !is Stage.SignedIn) return
        val code = pendingInviteCode ?: return
        pendingInviteCode = null
        dependencies.scope.launch {
            try {
                val joined = dependencies.api.joinTrip(code)
                homeReloadRequest += 1
                path.apply { clear(); add(HomeRoute.Trip(joined.trip.id)) }
            } catch (error: CancellationException) {
                throw error
            } catch (error: ApiError) {
                routingProblem = if (error is ApiError.Server && (error.statusCode == 404 || error.code == "trip_not_found")) {
                    BookCopy.Invite.linkNotFound
                } else {
                    error.message
                }
            } catch (error: Exception) {
                routingProblem = error.message
            }
        }
    }

    // MARK: - Les intentions

    /** Où mène chaque intention de l'accueil. */
    fun handle(intent: HomeIntent) {
        when (intent) {
            HomeIntent.OpenProfile -> path.add(HomeRoute.Profile)
            is HomeIntent.OpenTrip -> {
                // **On n'ouvre pas un voyage dont l'identifiant n'est pas celui
                // d'une ressource** : le serveur répondrait « Requête invalide. ».
                if (!isResourceId(intent.id)) {
                    routingProblem = "Ce voyage n’existe pas encore sur ton compte : il n’y a rien à ouvrir."
                    return
                }
                // Sortir de la création **remplace** l'étape au lieu de s'empiler.
                if (path.lastOrNull() == HomeRoute.TripCreation) path.removeAt(path.lastIndex)
                path.add(HomeRoute.Trip(intent.id))
            }
            HomeIntent.OpenGallery -> path.add(HomeRoute.Gallery)
            HomeIntent.CreateTrip -> path.add(HomeRoute.TripCreation)
            // **L'imprimante ouvre l'aperçu** : on ne commande pas un carnet qu'on n'a pas vu.
            is HomeIntent.OrderPrint -> {
                if (!isResourceId(intent.tripId)) {
                    routingProblem = "Ce voyage n’existe pas encore sur ton compte : il n’y a rien à prévisualiser."
                    return
                }
                path.add(HomeRoute.BookPreview(intent.tripId))
            }
            is HomeIntent.ShareTrip -> {
                if (!isResourceId(intent.id)) {
                    routingProblem = "Ce voyage n’existe pas encore sur ton compte : il n’y a rien à partager."
                    return
                }
                path.add(HomeRoute.BookPreview(intent.id, sharing = true))
            }
            HomeIntent.OpenHelp -> path.add(HomeRoute.Support)
            is HomeIntent.OpenConversation -> {
                // Le paquet est posé **avant** la destination : c'est en se
                // construisant que la conversation le lit.
                recordingHandoff = intent.handoff
                path.add(HomeRoute.Chat(intent.tripId))
            }
            HomeIntent.ImportFromPolarsteps -> Unit
        }
    }

    /** Raconter la suite et ouvrir une étape mènent au **même** écran. */
    fun handle(intent: TripIntent) {
        when (intent) {
            is TripIntent.TellMore -> path.add(HomeRoute.Chat(intent.tripId))
            is TripIntent.OpenStep -> path.add(HomeRoute.Chat(intent.tripId, intent.stepId))
            is TripIntent.OpenSettings -> path.add(HomeRoute.TripSettings(intent.tripId))
            is TripIntent.InviteCompanions -> path.add(HomeRoute.TripSettings(intent.tripId, TripSettingsSheet.Companions))
            is TripIntent.OpenBookPreview -> path.add(HomeRoute.BookPreview(intent.tripId))
            TripIntent.OpenHelp -> path.add(HomeRoute.Support)
        }
    }

    fun handle(intent: ProfileIntent) {
        when (intent) {
            is ProfileIntent.OpenTrip -> {
                if (!isResourceId(intent.id)) {
                    routingProblem = "Ce voyage n’existe pas encore sur ton compte : il n’y a rien à ouvrir."
                    return
                }
                path.add(HomeRoute.Trip(intent.id))
            }
            ProfileIntent.OpenGallery -> path.add(HomeRoute.Gallery)
            ProfileIntent.OpenHelp -> path.add(HomeRoute.Support)
            ProfileIntent.OpenTermsOfUse -> path.add(HomeRoute.Legal(LegalRoute.TermsOfUse))
            ProfileIntent.OpenPrivacyPolicy -> path.add(HomeRoute.Legal(LegalRoute.PrivacyPolicy))
            is ProfileIntent.OrderBook -> {
                if (!isResourceId(intent.memoId)) {
                    routingProblem = "Ce voyage n’existe pas encore sur ton compte : il n’y a rien à commander."
                    return
                }
                path.add(HomeRoute.Order(intent.memoId))
            }
        }
    }

    fun handle(intent: LegalIntent) {
        when (intent) {
            LegalIntent.OpenHelp -> path.add(HomeRoute.Support)
        }
    }

    fun handle(intent: ChatIntent) {
        when (intent) {
            is ChatIntent.OpenSettings -> path.add(HomeRoute.TripSettings(intent.tripId))
            is ChatIntent.OpenBookPreview -> path.add(HomeRoute.BookPreview(intent.memoId))
        }
    }

    fun handle(intent: TripSettingsIntent) {
        val tripId = currentTripId
        when (intent) {
            TripSettingsIntent.OpenBookPreview -> tripId?.let { path.add(HomeRoute.BookPreview(it)) }
            TripSettingsIntent.OpenCustomisation -> tripId?.let { path.add(HomeRoute.BookCustomisation(it)) }
            TripSettingsIntent.OpenHelp -> path.add(HomeRoute.Support)
            // « Commander le carnet » ouvre le tunnel, comme le bouton de l'aperçu (Hugo, 15/09/2026).
            TripSettingsIntent.OrderBook -> tripId?.let { path.add(HomeRoute.Order(it)) }
            // Le voyage n'existe plus : reculer d'un cran rouvrirait un écran sur un 404.
            TripSettingsIntent.TripDeleted -> path.clear()
            TripSettingsIntent.ConnectTricount -> Unit
            TripSettingsIntent.ManageSubscription -> path.add(HomeRoute.ManageSubscription)
        }
    }

    fun handle(intent: BookCustomisationIntent) {
        val tripId = currentTripId ?: return
        when (intent) {
            BookCustomisationIntent.OpenCovers -> show(HomeRoute.Covers(tripId))
            BookCustomisationIntent.OpenBookPreview -> path.add(HomeRoute.BookPreview(tripId))
            BookCustomisationIntent.OpenHelp -> path.add(HomeRoute.Support)
        }
    }

    fun handle(intent: CoversIntent) {
        val tripId = currentTripId ?: return
        when (intent) {
            CoversIntent.OpenStyle -> path.add(HomeRoute.CoverStyle(tripId))
            CoversIntent.OpenPhoto -> path.add(HomeRoute.CoverPhoto(tripId))
            CoversIntent.OpenTexts -> path.add(HomeRoute.CoverTexts(tripId))
            CoversIntent.OpenCustomisation -> show(HomeRoute.BookCustomisation(tripId))
        }
    }

    fun handle(intent: BookPreviewIntent) {
        val tripId = currentTripId ?: return
        when (intent) {
            // « Personnaliser mon carnet » mène aux **personnalisations du carnet**.
            BookPreviewIntent.Customise -> path.add(HomeRoute.BookCustomisation(tripId))
            BookPreviewIntent.ConfigureCovers -> show(HomeRoute.Covers(tripId))
            BookPreviewIntent.Order -> path.add(HomeRoute.Order(tripId))
            BookPreviewIntent.ShareFeedback -> Unit
        }
    }

    fun handle(intent: OrderIntent) {
        when (intent) {
            OrderIntent.OpenHelp -> path.add(HomeRoute.Support)
            // « Retour à l'accueil » **vide la pile** : reculer ramènerait sur le
            // paiement d'une commande déjà passée.
            OrderIntent.Finish -> path.clear()
        }
    }

    /**
     * Pousse un écran, **ou revient dessus** s'il est déjà dans la pile : les
     * personnalisations et les couvertures mènent chacune à l'autre (19/10/2026).
     */
    private fun show(route: HomeRoute) {
        val index = path.lastIndexOf(route)
        if (index >= 0) {
            while (path.lastIndex > index) path.removeAt(path.lastIndex)
        } else {
            path.add(route)
        }
    }

    /** Le voyage ouvert, s'il y en a un dans la pile. */
    val currentTripId: String?
        get() = path.asReversed().firstNotNullOfOrNull { route ->
            when (route) {
                is HomeRoute.Trip -> route.id
                is HomeRoute.TripSettings -> route.id
                is HomeRoute.BookPreview -> route.memoId
                is HomeRoute.Order -> route.memoId
                is HomeRoute.BookCustomisation -> route.tripId
                is HomeRoute.Covers -> route.tripId
                is HomeRoute.CoverStyle -> route.tripId
                is HomeRoute.CoverPhoto -> route.tripId
                is HomeRoute.CoverTexts -> route.tripId
                is HomeRoute.Chat -> route.tripId
                else -> null
            }
        }

    /** Le voyage d'où l'on ouvre le support, qui part avec le message (T226). */
    val supportTripId: String?
        get() = path.asReversed().firstNotNullOfOrNull { route ->
            when (route) {
                is HomeRoute.Trip -> route.id
                is HomeRoute.Chat -> route.tripId
                is HomeRoute.TripSettings -> route.id
                is HomeRoute.BookPreview -> route.memoId
                is HomeRoute.Order -> route.memoId
                is HomeRoute.BookCustomisation -> route.tripId
                else -> null
            }
        }

    /** L'écran du dessus pose sa photo sous la barre d'état : l'accueil d'un voyage. */
    val showsFullBleedPhoto: Boolean
        get() = stage is Stage.SignedIn && path.lastOrNull() is HomeRoute.Trip

    companion object {
        /** Le carnet du jeu d'essai du tunnel — voir `OrderContext.fixture`. */
        const val PREVIEW_ORDER_MEMO_ID = "trip-rome"

        /** Le voyage de Rome du jeu d'essai (`FixtureTripId.rome`). */
        const val PREVIEW_ROME_TRIP_ID = "1CE0FEED-0000-4000-A000-000000000001"

        /** Un identifiant qui est celui d'une ressource du serveur — un UUID. */
        fun isResourceId(id: String): Boolean = runCatching { UUID.fromString(id) }.isSuccess && id.length == 36
    }
}
