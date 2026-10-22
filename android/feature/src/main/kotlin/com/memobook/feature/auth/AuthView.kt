package com.memobook.feature.auth

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedContentTransitionScope
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.core.Account
import com.memobook.design.BrandBackdrop
import com.memobook.design.BrandButton
import com.memobook.design.BrandKeyboardDismissBar
import com.memobook.design.BrandSegmentedPicker
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.isReduceMotionEnabled
import com.memobook.feature.InMemoryAppSettings
import com.memobook.feature.PreviewSupport
import com.memobook.feature.welcome.WelcomeCopy
import com.memobook.networking.MemoBookApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.hypot
import java.lang.reflect.Proxy

/**
 * L'entrée **par e-mail** : inscription et connexion sous un même sélecteur.
 * Jumeau de `AuthView.swift`.
 *
 * **Ce n'est plus la porte de l'app.** Apple et Google vivent désormais sur
 * l'écran d'accueil (`WelcomeView`), qui pousse celui-ci quand on choisit
 * « S'inscrire avec un e-mail ». D'où la flèche de retour en tête : c'est un
 * écran poussé comme un autre, et on doit pouvoir revenir aux deux entrées
 * rapides sans quitter l'app.
 *
 * Le passage d'un mode à l'autre est une seule animation : la pastille du
 * sélecteur glisse, et le formulaire se décale dans le même sens — depuis la
 * droite quand on va vers « Connexion », depuis la gauche au retour. C'est le
 * geste d'un `UIPageViewController`, sans la navigation.
 *
 * @param resetToken le secret d'un lien « Réinitialiser mon mot de passe »
 *   ouvert pendant qu'on est dehors. Posé par `RootView`, qui reçoit les liens ;
 *   consommé ici, où la page peut s'ouvrir ([onResetTokenConsumed]). Le lien
 *   peut arriver avant que cet écran existe (lancement à froid) comme pendant
 *   qu'il est là, et il ne doit servir qu'une fois.
 * @param api pour les modèles de « Mot de passe oublié », un neuf à chaque ouverture.
 */
@Composable
fun AuthView(
    model: AuthModel,
    api: MemoBookApi,
    resetToken: String?,
    onResetTokenConsumed: () -> Unit,
    onAuthenticated: (Account) -> Unit,
    onBack: () -> Unit,
) {
    val state by model.state.collectAsStateWithLifecycle(context = Dispatchers.Main.immediate)
    val scope = rememberCoroutineScope()
    val reduceMotion = isReduceMotionEnabled()
    val haptics = LocalHapticFeedback.current

    var focus by remember { mutableStateOf<AuthField?>(null) }

    /** La feuille « Mot de passe oublié », quand elle est ouverte. Un modèle neuf à chaque ouverture : c'est lui qui la présente. */
    var recovery by remember { mutableStateOf<PasswordRecoveryModel?>(null) }

    /**
     * La page du nouveau mot de passe, ouverte par le lien de l'e-mail. Elle
     * **remplace** l'écran d'entrée le temps de choisir, comme la page de
     * compléments après Apple ou Google — voir [PasswordResetView].
     */
    var reset by remember { mutableStateOf<PasswordRecoveryModel?>(null) }

    // Un lien de l'e-mail est arrivé : la page du nouveau mot de passe prend
    // la place de l'écran, et le secret est consommé pour qu'un second rendu
    // ne la rouvre pas. Une feuille encore ouverte se referme d'abord.
    LaunchedEffect(resetToken) {
        val token = resetToken ?: return@LaunchedEffect
        onResetTokenConsumed()
        focus = null
        recovery = null
        reset = PasswordRecoveryModel.forReset(api, token)
    }

    // Changer de mode rend le clavier, et donne le petit « clic » d'un
    // sélecteur, que le geste vienne du balayage ou du sélecteur lui-même.
    LaunchedEffect(model) {
        model.state.map { it.mode }.distinctUntilChanged().drop(1).collect {
            focus = null
            haptics.performHapticFeedback(HapticFeedbackType.SegmentTick)
        }
    }

    fun submit() {
        focus = null
        scope.launch {
            // `null` : l'appel a échoué, et le message est déjà à l'écran.
            model.submit()?.let(onAuthenticated)
        }
    }

    fun advanceFocus() {
        val next = focus?.let(model::fieldAfter)
        if (next == null) {
            focus = null
            if (model.state.value.canSubmit) submit()
        } else {
            focus = next
        }
    }

    // Ouvre « Mot de passe oublié » sur l'adresse déjà tapée, s'il y en a une.
    fun recoverPassword() {
        focus = null
        recovery = PasswordRecoveryModel(api, email = model.email)
    }

    val page: AuthPage = when {
        // Entré par Apple ou Google, on vérifie d'abord ce que le fournisseur
        // a donné — voir `SocialCompletionView`.
        state.completing != null -> AuthPage.Completion
        reset != null -> AuthPage.Reset(reset!!)
        else -> AuthPage.Form
    }

    AnimatedContent(
        targetState = page,
        contentKey = { it::class },
        transitionSpec = { pageTransition(reduceMotion) },
        label = "page",
    ) { shown ->
        when (shown) {
            AuthPage.Completion -> SocialCompletionView(
                state = state,
                model = model,
                focus = focus,
                onFocusChange = { focus = it },
                onAuthenticated = onAuthenticated,
            )
            is AuthPage.Reset -> PasswordResetView(
                model = shown.model,
                onAuthenticated = { account ->
                    reset = null
                    onAuthenticated(account)
                },
                onRequestAgain = {
                    // La page se retire et la feuille de l'adresse monte à sa
                    // place, dans le même mouvement.
                    reset = null
                    recovery = PasswordRecoveryModel(api, email = model.email)
                },
                onCancel = { reset = null },
            )
            AuthPage.Form -> AuthForm(
                state = state,
                model = model,
                focus = focus,
                onFocusChange = { focus = it },
                reduceMotion = reduceMotion,
                onBack = onBack,
                onSubmit = ::submit,
                onAdvanceFocus = ::advanceFocus,
                onForgottenPassword = ::recoverPassword,
            )
        }
    }

    // Une demande partie à moitié n'a pas de sens : le temps de l'appel, la
    // feuille ne se referme ni au glissé ni au toucher hors d'elle.
    val recoveryIsWorking = recovery?.let { it.state.collectAsStateWithLifecycle().value.isWorking } ?: false
    BrandSheetHost(item = recovery, onDismissRequest = { recovery = null }, dismissDisabled = recoveryIsWorking) { shown ->
        PasswordRecoverySheet(
            model = shown,
            onClose = { email ->
                // L'adresse corrigée dans la feuille revient dans le
                // formulaire : c'est celle avec laquelle on va se reconnecter.
                if (email.isNotEmpty()) model.email = email
            },
            onSignUp = { email ->
                // La feuille descend et le sélecteur glisse vers
                // « Inscription » dans le même mouvement, l'adresse déjà en
                // place : il ne reste que le prénom et le mot de passe.
                recovery = null
                model.email = email
                model.mode = AuthMode.SignUp
            },
        )
    }
}

/** Ce que l'écran montre : le formulaire, ou l'une des deux pages qui s'interposent avant l'entrée. */
private sealed interface AuthPage {
    data object Form : AuthPage
    data object Completion : AuthPage
    data class Reset(val model: PasswordRecoveryModel) : AuthPage
}

/** Une page qui s'interpose arrive de la droite et y repart ; le formulaire, lui, se fond. */
private fun AnimatedContentTransitionScope<AuthPage>.pageTransition(reduceMotion: Boolean): ContentTransform {
    if (reduceMotion) return EnterTransition.None togetherWith ExitTransition.None
    val motion = SwiftMotion.snappy<IntOffset>(0.35f)
    val fade = SwiftMotion.snappy<Float>(0.35f)
    return if (targetState != AuthPage.Form) {
        (slideInHorizontally(motion) { it } + fadeIn(fade)) togetherWith fadeOut(fade)
    } else {
        fadeIn(fade) togetherWith (slideOutHorizontally(motion) { it } + fadeOut(fade))
    }
}

@Composable
private fun AuthForm(
    state: AuthModel.State,
    model: AuthModel,
    focus: AuthField?,
    onFocusChange: (AuthField?) -> Unit,
    reduceMotion: Boolean,
    onBack: () -> Unit,
    onSubmit: () -> Unit,
    onAdvanceFocus: () -> Unit,
    onForgottenPassword: () -> Unit,
) {
    // Balayage latéral pour passer d'un mode à l'autre, comme entre deux
    // pages. On exige un geste franchement horizontal : sans ça, un
    // défilement un peu de travers ferait basculer le formulaire au milieu de
    // la saisie.
    val swipe by rememberUpdatedState { dx: Float, dy: Float ->
        if (abs(dx) > 60 && abs(dx) > abs(dy) * 1.5f) {
            model.mode = if (dx < 0) AuthMode.SignIn else AuthMode.SignUp
        }
    }

    AuthScrollPage(scrollModifier = Modifier.onHorizontalSwipe(minimumDistance = 20.dp) { dx, dy -> swipe(dx, dy) }) {
        AuthBackButton(onBack)

        BrandSegmentedPicker(AuthMode.entries, selection = state.mode, onSelectionChange = { model.mode = it }) { it.segmentTitle }

        // Le titre change de texte, pas de rôle : il glisse avec le formulaire.
        AnimatedContent(
            targetState = state.mode,
            transitionSpec = { modeTransition(reduceMotion) },
            label = "titre",
        ) { mode ->
            Column(
                Modifier
                    .fillMaxWidth()
                    .semantics(mergeDescendants = true) { heading() },
                verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
            ) {
                BrandText(mode.title, MemoBookFont.h1.copy(letterSpacing = (-0.41).sp))
                BrandText(mode.subtitle, MemoBookFont.body.copy(letterSpacing = MemoBookFont.tracking), color = MemoBookColor.inkMuted)
            }
        }

        AnimatedContent(
            targetState = state.mode,
            transitionSpec = { modeTransition(reduceMotion) },
            label = "champs",
        ) { mode ->
            when (mode) {
                AuthMode.SignUp -> SignUpFields(state, model, focus, onFocusChange, onSubmit = onAdvanceFocus)
                AuthMode.SignIn -> SignInFields(state, model, focus, onFocusChange, onSubmit = onAdvanceFocus, onForgottenPassword = onForgottenPassword)
            }
        }

        BrandButton(
            "Continuer",
            modifier = Modifier.padding(top = MemoBookSpacing.xs),
            isLoading = state.isWorking,
            fillsWidth = true,
            enabled = state.canSubmit,
            action = onSubmit,
        )

        ErrorText(state.errorMessage)
    }
}

/**
 * Glissé dans le sens du sélecteur. Sous « Supprimer les animations », un
 * simple fondu : c'est exactement le genre de déplacement que le réglage vise.
 */
private fun AnimatedContentTransitionScope<AuthMode>.modeTransition(reduceMotion: Boolean): ContentTransform {
    val fade = SwiftMotion.snappy<Float>(0.35f, extraBounce = 0.1f)
    if (reduceMotion) return fadeIn(fade) togetherWith fadeOut(fade)
    val forward = targetState == AuthMode.SignIn
    val motion = SwiftMotion.snappy<IntOffset>(0.35f, extraBounce = 0.1f)
    return (slideInHorizontally(motion) { if (forward) it else -it } + fadeIn(fade)) togetherWith
        (slideOutHorizontally(motion) { if (forward) -it else it } + fadeOut(fade)) using
        SizeTransform(clip = false)
}

/**
 * La sortie : on revient à l'accueil, et à ses deux entrées rapides.
 *
 * Elle porte son mot, contrairement aux autres écrans poussés de l'app : ici
 * on quitte un formulaire à moitié rempli, et une flèche seule ne dit pas assez
 * clairement qu'on ne perd que ça.
 */
@Composable
private fun AuthBackButton(onBack: () -> Unit) {
    Row(
        Modifier
            .heightIn(min = MemoBookSpacing.minimumTapTarget)
            // Le libellé est le mot écrit : « Retour », que le bouton annonce.
            .clickable(interactionSource = null, indication = PlainButtonIndication, role = Role.Button, onClick = onBack),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(
            painter = painterResource(R.drawable.icon_arrow_duo),
            contentDescription = null,
            modifier = Modifier.size(MemoBookSpacing.navigationIcon),
        )
        BrandText(WelcomeCopy.back, MemoBookFont.tagline)
    }
}

// MARK: - Ce que les pages de l'entrée partagent

/**
 * La colonne des pages de l'entrée — le formulaire, la page de compléments, le
 * nouveau mot de passe : le motif de la marque derrière, la colonne de la
 * maquette (390, centrée au-delà), et la barre qui range le clavier.
 *
 * Le contenu défile sous la barre d'état, que le voile de `RootView` couvre ; le
 * clavier réduit la zone qui défile, et le champ qui a le focus remonte dedans.
 * iOS referme aussi le clavier en tirant la liste (`scrollDismissesKeyboard`) :
 * Android n'a pas ce geste, la barre du clavier en tient lieu.
 */
@Composable
internal fun AuthScrollPage(
    modifier: Modifier = Modifier,
    scrollModifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    BrandKeyboardDismissBar(modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize()) {
            BrandBackdrop(Modifier.fillMaxSize())
            Column(
                Modifier
                    .fillMaxSize()
                    .imePadding()
                    .then(scrollModifier)
                    .verticalScroll(rememberScrollState())
                    .windowInsetsPadding(WindowInsets.safeDrawing),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Column(
                    Modifier
                        .widthIn(max = AUTH_CONTENT_WIDTH)
                        .fillMaxWidth()
                        .padding(horizontal = MemoBookSpacing.screenMargin, vertical = MemoBookSpacing.m),
                    verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
                    content = content,
                )
            }
        }
    }
}

/**
 * Largeur du cadre de la maquette : au-delà, la colonne se centre au lieu de
 * s'étirer. Même règle que l'écran d'accueil.
 */
internal val AUTH_CONTENT_WIDTH: Dp = 390.dp

/** Le message d'échec sous un bouton, qui arrive et s'en va en fondu. */
@Composable
internal fun ErrorText(message: String?, modifier: Modifier = Modifier, centered: Boolean = false) {
    val shown = rememberLast(message)
    AnimatedVisibility(
        visible = message != null,
        modifier = modifier,
        enter = fadeIn(SwiftMotion.snappy(0.2f)),
        exit = fadeOut(SwiftMotion.snappy(0.2f)),
    ) {
        BrandText(
            shown.orEmpty(),
            MemoBookFont.notification,
            Modifier.fillMaxWidth(),
            color = MemoBookColor.error,
            textAlign = if (centered) TextAlign.Center else null,
        )
    }
}

/**
 * Un glissé guetté **à côté** du défilement, sans le lui prendre — le
 * `simultaneousGesture(DragGesture(minimumDistance:))` d'iOS. Le geste n'est
 * jamais consommé : la liste continue de défiler, les champs de recevoir le
 * doigt, et [onEnded] reçoit au relâché le déplacement total, en dp.
 */
internal fun Modifier.onHorizontalSwipe(minimumDistance: Dp, onEnded: (dx: Float, dy: Float) -> Unit): Modifier =
    pointerInput(Unit) {
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
            var end = down.position
            while (true) {
                val change = awaitPointerEvent(PointerEventPass.Initial).changes.firstOrNull { it.id == down.id } ?: break
                end = change.position
                if (!change.pressed) break
            }
            val dx = (end.x - down.position.x).toDp().value
            val dy = (end.y - down.position.y).toDp().value
            if (hypot(dx, dy) >= minimumDistance.value) onEnded(dx, dy)
        }
    }

@Preview(locale = "fr-rFR", name = "Entrée par e-mail", widthDp = 390, heightDp = 844)
@Composable
private fun AuthViewPreview() {
    val api = previewApi()
    val model = remember { AuthModel(api, InMemoryAppSettings()) }
    AuthView(model, api, resetToken = null, onResetTokenConsumed = {}, onAuthenticated = {}, onBack = {})
}

/**
 * Le double d'API des aperçus de l'entrée : celui du bac à sable quand il est
 * là (`PreviewSupport.api()`, phase A3b), sinon un double inerte — aucun aperçu
 * de ces écrans n'appelle le serveur, ils dessinent un état.
 */
internal fun previewApi(): MemoBookApi = runCatching { PreviewSupport.api() }.getOrElse {
    Proxy.newProxyInstance(MemoBookApi::class.java.classLoader, arrayOf(MemoBookApi::class.java)) { proxy, method, arguments ->
        when (method.name) {
            "equals" -> proxy === arguments?.firstOrNull()
            "hashCode" -> System.identityHashCode(proxy)
            "toString" -> "MemoBookApi (aperçu)"
            else -> throw UnsupportedOperationException("Aperçu : ${method.name} n’appelle pas le serveur.")
        }
    } as MemoBookApi
}
