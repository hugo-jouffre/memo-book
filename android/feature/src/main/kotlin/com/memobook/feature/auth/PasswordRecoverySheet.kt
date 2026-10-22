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
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.design.BrandButton
import com.memobook.design.BrandKeyboardDismissBar
import com.memobook.design.BrandSheet
import com.memobook.design.BrandText
import com.memobook.design.BrandTextField
import com.memobook.design.LocalBrandSheetDismiss
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.isAccessibilityTextSize
import com.memobook.design.isReduceMotionEnabled
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/**
 * « Mot de passe oublié » — la feuille qui monte sur le formulaire de
 * connexion. Jumeau de `PasswordRecoverySheet.swift`.
 *
 * Un parcours en plusieurs temps dans **une seule** feuille dont le contenu
 * change, jamais une pile de feuilles (voir `BrandSheet`). Le premier temps
 * confirme l'adresse et envoie l'e-mail ; il s'ouvre sur ce que la connexion
 * contenait déjà, et le crayon dit que ça se corrige.
 *
 * L'écran qui la présente retient le glissé le temps de l'appel
 * (`BrandSheetHost(dismissDisabled = …)`) : une demande partie à moitié n'a pas
 * de sens.
 *
 * @param onClose appelé quand la feuille est descendue, avec l'adresse telle
 *   qu'elle a été laissée : le formulaire de connexion la reprend, pour ne pas
 *   la faire retaper à la reconnexion.
 * @param onSignUp « Tu peux en créer un en cliquant ici » : la feuille se
 *   referme et l'écran d'entrée bascule sur l'inscription, adresse déjà posée.
 */
@Composable
internal fun PasswordRecoverySheet(
    model: PasswordRecoveryModel,
    onClose: (String) -> Unit,
    onSignUp: (String) -> Unit,
) {
    val state by model.state.collectAsStateWithLifecycle(context = Dispatchers.Main.immediate)
    val dismiss = LocalBrandSheetDismiss.current
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    val reduceMotion = isReduceMotionEnabled()
    var focus by remember { mutableStateOf<PasswordRecoveryField?>(null) }

    // Le `onDisappear` d'iOS : la feuille a fini de descendre.
    DisposableEffect(model) { onDispose { onClose(model.email) } }

    // Le refus vibre comme une erreur, l'envoi comme une réussite.
    LaunchedEffect(model) {
        model.state.map { it.isUnknownAccount }.distinctUntilChanged().drop(1).collect { unknown ->
            if (unknown) haptics.performHapticFeedback(HapticFeedbackType.Reject)
        }
    }
    LaunchedEffect(model) {
        model.state.map { it.step }.distinctUntilChanged().drop(1).collect { step ->
            if (step == PasswordRecoveryModel.Step.Sent) haptics.performHapticFeedback(HapticFeedbackType.Confirm)
        }
    }

    fun submit() {
        if (!model.state.value.canSubmit) return
        focus = null
        scope.launch { model.submit() }
    }

    BrandKeyboardDismissBar {
        BrandSheet(
            PasswordRecoveryCopy.title,
            icon = R.drawable.icon_locker,
            subtitle = if (state.step == PasswordRecoveryModel.Step.Request) PasswordRecoveryCopy.requestSubtitle else null,
            titleAlignment = BrandSheet.TitleAlignment.Centered,
        ) {
            AnimatedContent(
                targetState = state.step,
                contentKey = { it::class },
                transitionSpec = { stepTransition(reduceMotion) },
                label = "étape",
            ) { step ->
                when (step) {
                    PasswordRecoveryModel.Step.Request -> RequestStep(
                        state = state,
                        model = model,
                        focus = focus,
                        onFocusChange = { focus = it },
                        reduceMotion = reduceMotion,
                        onSubmit = ::submit,
                        onBackHome = dismiss,
                        onSignUp = { onSignUp(model.email) },
                    )
                    PasswordRecoveryModel.Step.Sent -> SentStep(email = state.email, onBackHome = dismiss)
                    // Jamais dans la feuille : arrivé par le lien de l'e-mail, il
                    // n'y a pas d'écran dessous — c'est une page, `PasswordResetView`.
                    is PasswordRecoveryModel.Step.Reset -> Box(Modifier)
                }
            }
        }
    }
}

// MARK: - Étape 1 : l'adresse

@Composable
private fun RequestStep(
    state: PasswordRecoveryModel.State,
    model: PasswordRecoveryModel,
    focus: PasswordRecoveryField?,
    onFocusChange: (PasswordRecoveryField?) -> Unit,
    reduceMotion: Boolean,
    onSubmit: () -> Unit,
    onBackHome: () -> Unit,
    onSignUp: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
        BrandTextField(
            "E-mail",
            state.email,
            { model.email = it },
            field = PasswordRecoveryField.Email,
            focus = focus,
            onFocusChange = onFocusChange,
            labelPlacement = BrandTextField.LabelPlacement.Hidden,
            placeholder = PasswordRecoveryCopy.emailPlaceholder,
            trailingIcon = R.drawable.icon_pen,
            keyboardOptions = emailKeyboard.copy(imeAction = ImeAction.Send),
            keyboardActions = KeyboardActions(onSend = { onSubmit() }),
            contentType = ContentType.EmailAddress,
        )

        val unknownEmail = rememberLast(state.unknownEmail)
        val rise = with(LocalDensity.current) { 6.dp.roundToPx() }
        AnimatedVisibility(
            visible = state.isUnknownAccount,
            enter = if (reduceMotion) {
                EnterTransition.None
            } else {
                fadeIn(SwiftMotion.snappy(0.28f)) + slideInVertically(SwiftMotion.snappy<IntOffset>(0.28f)) { -rise }
            },
            exit = if (reduceMotion) {
                ExitTransition.None
            } else {
                fadeOut(SwiftMotion.snappy(0.28f)) + slideOutVertically(SwiftMotion.snappy<IntOffset>(0.28f)) { -rise }
            },
        ) {
            UnknownAccount(unknownEmail.orEmpty(), onSignUp)
        }

        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            // Le même bouton change de mot et de geste : « Continuer » envoie,
            // « Revenir à l'accueil » referme. Une seule place, pour que le
            // pouce le trouve au même endroit dans les deux cas.
            BrandButton(
                if (state.isUnknownAccount) PasswordRecoveryCopy.backHome else PasswordRecoveryCopy.send,
                isLoading = state.isWorking,
                fillsWidth = true,
                enabled = state.canSubmit || state.isUnknownAccount,
                action = if (state.isUnknownAccount) onBackHome else onSubmit,
            )

            ErrorText(state.errorMessage, centered = true)
        }
    }
}

/**
 * Le refus du serveur, et la porte de sortie : la phrase rouge reprend
 * l'adresse telle qu'elle est écrite, et le lien mène à l'inscription.
 */
@Composable
private fun UnknownAccount(email: String, onSignUp: () -> Unit) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
        BrandText(PasswordRecoveryCopy.unknownAccount(email), MemoBookFont.notification, color = MemoBookColor.error)

        // Deux textes côte à côte et non un seul : la seconde moitié est un
        // bouton, avec sa cible de 48, pas un mot souligné dans une phrase
        // qu'on ne saurait pas toucher à TalkBack. Aux tailles accessibles, la
        // phrase ne tient plus sur une ligne : le lien passe dessous.
        if (isAccessibilityTextSize()) {
            Column {
                SignUpLead()
                SignUpLink(onSignUp)
            }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                SignUpLead(Modifier.alignByBaseline())
                SignUpLink(onSignUp, Modifier.alignByBaseline())
            }
        }
    }
}

@Composable
private fun SignUpLead(modifier: Modifier = Modifier) {
    BrandText(PasswordRecoveryCopy.signUpLead, MemoBookFont.body, modifier)
}

@Composable
private fun SignUpLink(onSignUp: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier
            .heightIn(min = MemoBookSpacing.minimumTapTarget)
            .clickable(interactionSource = null, indication = PlainButtonIndication, role = Role.Button, onClick = onSignUp)
            // TalkBack entend ce que le lien fait, pas « en cliquant ici ».
            .clearAndSetSemantics { contentDescription = PasswordRecoveryCopy.signUpAccessibility },
        contentAlignment = Alignment.CenterStart,
    ) {
        BrandText(
            PasswordRecoveryCopy.signUpLink,
            MemoBookFont.bodySemibold.copy(textDecoration = TextDecoration.Underline),
            color = MemoBookColor.action,
        )
    }
}

// MARK: - Étape 2 : l'e-mail est parti

/**
 * Ce qu'il reste à faire est **dans la boîte mail**, pas dans l'app : la
 * feuille le dit, nomme le bouton de l'e-mail pour qu'on le reconnaisse, et
 * rend la main. Pas de « renvoyer » : rouvrir « Mot de passe oublié » fait
 * exactement ça, et une seconde porte au même endroit inviterait à taper deux
 * fois avant d'avoir regardé.
 */
@Composable
private fun SentStep(email: String, onBackHome: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
        Column(
            Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        ) {
            BrandText(PasswordRecoveryCopy.sentBody(email), MemoBookFont.body, textAlign = TextAlign.Center)
            BrandText(PasswordRecoveryCopy.sentHint, MemoBookFont.caption, color = MemoBookColor.inkMuted, textAlign = TextAlign.Center)
        }

        BrandButton(PasswordRecoveryCopy.backHome, fillsWidth = true, action = onBackHome)
    }
}

// MARK: - Mouvement

/**
 * Une étape pousse la précédente vers la gauche, comme une page qu'on tourne.
 * Sous « Supprimer les animations », un fondu.
 */
private fun AnimatedContentTransitionScope<PasswordRecoveryModel.Step>.stepTransition(reduceMotion: Boolean): ContentTransform {
    val fade = SwiftMotion.snappy<Float>(0.35f, extraBounce = 0.05f)
    if (reduceMotion) return fadeIn(fade) togetherWith fadeOut(fade)
    val motion = SwiftMotion.snappy<IntOffset>(0.35f, extraBounce = 0.05f)
    return (slideInHorizontally(motion) { it } + fadeIn(fade)) togetherWith
        (slideOutHorizontally(motion) { -it } + fadeOut(fade)) using
        SizeTransform(clip = false)
}

/**
 * Les champs du parcours, dans l'ordre où le clavier les enchaîne — l'adresse
 * sur la feuille, les deux mots de passe sur la page. Le focus appartient à
 * l'écran, comme partout.
 */
enum class PasswordRecoveryField {
    Email,
    Password,
    PasswordConfirmation,
}

/** Les mots de la feuille, tels que la maquette les écrit. */
object PasswordRecoveryCopy {
    const val title = "Mot de passe oublié"

    const val requestSubtitle =
        "Un email pour reconfigurer ton mot de passe va t’être envoyé à l’adresse suivante :"

    const val emailPlaceholder = "prenom@exemple.com"

    const val send = "Continuer"

    const val backHome = "Revenir à l’accueil"

    fun unknownAccount(email: String): String = "Il n’existe aucun compte associé à l’adresse $email"

    const val signUpLead = "Tu peux en créer un"
    const val signUpLink = "en cliquant ici"
    const val signUpAccessibility = "Créer un compte avec cette adresse"

    /**
     * L'e-mail est parti. On nomme le bouton de l'e-mail avec ses mots à lui
     * (« Réinitialiser mon mot de passe »), pour qu'on le reconnaisse.
     */
    fun sentBody(email: String): String =
        "C’est envoyé ! Ouvre l’e-mail reçu sur $email et appuie sur « Réinitialiser mon mot de passe »."

    const val sentHint = "Rien reçu d’ici quelques minutes ? Regarde dans tes courriers indésirables."

    // La page du nouveau mot de passe — maquette « Mdp oublié – config ».
    const val resetTitle = "Configure ton nouveau mot de passe"
    const val passwordLabel = "Mot de passe"
    const val confirmationLabel = "Confirme ton nouveau mot de passe"
    const val save = "Continuer"
    const val requestAgain = "Redemander un e-mail"
}

@Preview(locale = "fr-rFR", name = "Mot de passe oublié", widthDp = 390, heightDp = 640)
@Composable
private fun PasswordRecoverySheetPreview() {
    val model = remember { PasswordRecoveryModel(previewApi(), email = "ola.thioll@gmail.com") }
    Box(Modifier.fillMaxSize().background(MemoBookColor.background), contentAlignment = Alignment.BottomCenter) {
        PasswordRecoverySheet(model, onClose = {}, onSignUp = {})
    }
}

@Preview(locale = "fr-rFR", name = "Mot de passe oublié — vide", widthDp = 390, heightDp = 640)
@Composable
private fun PasswordRecoverySheetEmptyPreview() {
    val model = remember { PasswordRecoveryModel(previewApi(), email = "") }
    Box(Modifier.fillMaxSize().background(MemoBookColor.background), contentAlignment = Alignment.BottomCenter) {
        PasswordRecoverySheet(model, onClose = {}, onSignUp = {})
    }
}
