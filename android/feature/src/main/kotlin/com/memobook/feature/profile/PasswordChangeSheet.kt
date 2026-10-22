package com.memobook.feature.profile

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.core.PasswordRule
import com.memobook.design.BrandButton
import com.memobook.design.BrandKeyboardDismissBar
import com.memobook.design.BrandSheet
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandText
import com.memobook.design.BrandTextField
import com.memobook.design.LocalBrandSheetDismiss
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.isReduceMotionEnabled
import com.memobook.feature.auth.AuthModel
import com.memobook.feature.auth.PasswordRecoveryCopy
import com.memobook.networking.ApiError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * « Modifier mon mot de passe » — la feuille sous la ligne « Mot de passe »
 * du profil (Hugo, 29/09/2026), et la même feuille pour le nouveau mot de
 * passe d'un lien reçu par e-mail quand on est déjà entré. Jumeau de
 * `Profile/PasswordChangeSheet.swift`.
 *
 * Trois champs, un bouton, et le bouton reste gris tant que les trois ne
 * disent pas la même chose : le mot de passe actuel n'est pas vide, le nouveau
 * respecte les trois critères — cochés **pendant qu'on tape** —, et la
 * confirmation le répète. Le serveur revérifie tout, mais la feuille ne lui
 * envoie rien qu'il refuserait à coup sûr.
 *
 * Quatre issues, et une phrase pour chacune :
 *
 * - **mot de passe actuel faux** : sous son champ, avec « Mot de passe
 *   oublié ? », qui sort du parcours et envoie l'e-mail de réinitialisation ;
 * - **réussite** : « Mot de passe modifié ✓ », et « Retour à mon compte » ;
 * - **session expirée** : on demande de se reconnecter ;
 * - **panne** : « Impossible de modifier ton mot de passe pour le moment. »
 *
 * Un envoi parti à moitié n'a pas de sens : le temps de l'appel, la feuille ne
 * se referme ni au glissé ni au toucher hors d'elle — c'est l'écran qui la
 * présente qui le dit à son `BrandSheetHost` (`dismissDisabled =
 * state.isWorking`).
 */
@Composable
internal fun PasswordChangeSheet(model: PasswordChangeModel) {
    val state by model.state.collectAsStateWithLifecycle(context = Dispatchers.Main.immediate)
    val dismiss = LocalBrandSheetDismiss.current
    val reduceMotion = isReduceMotionEnabled()
    val haptics = LocalHapticFeedback.current
    // Les appels partent de la feuille, comme les `Task` d'iOS : elle ne se
    // referme pas tant qu'ils courent.
    val scope = rememberCoroutineScope()
    var focus by remember { mutableStateOf<PasswordChangeField?>(null) }

    fun submit() {
        if (!model.state.value.canSubmit) return
        focus = null
        scope.launch { model.submit() }
    }

    // Une vibration d'échec, une de réussite — le `sensoryFeedback` d'iOS.
    LaunchedEffect(model) {
        model.state.map { it.failure }.distinctUntilChanged().drop(1).collect { failure ->
            if (failure != null) haptics.performHapticFeedback(HapticFeedbackType.Reject)
        }
    }
    LaunchedEffect(model) {
        model.state.map { it.step }.distinctUntilChanged().drop(1).collect { step ->
            if (step == PasswordChangeModel.Step.Done) haptics.performHapticFeedback(HapticFeedbackType.Confirm)
        }
    }

    BrandKeyboardDismissBar {
        BrandSheet(
            PasswordChangeCopy.title,
            icon = R.drawable.icon_locker,
            subtitle = if (state.step == PasswordChangeModel.Step.Form) model.mode.subtitle else null,
            titleAlignment = BrandSheet.TitleAlignment.Centered,
        ) {
            AnimatedContent(
                targetState = state.step,
                transitionSpec = {
                    if (reduceMotion) {
                        fadeIn(tween(200)) togetherWith fadeOut(tween(200))
                    } else {
                        (slideInHorizontally(SwiftMotion.snappy(0.35f, extraBounce = 0.05f)) { it } + fadeIn()) togetherWith
                            (slideOutHorizontally(SwiftMotion.snappy(0.35f, extraBounce = 0.05f)) { -it } + fadeOut())
                    } using SizeTransform(clip = false)
                },
                label = "étape",
            ) { step ->
                when (step) {
                    PasswordChangeModel.Step.Form -> PasswordForm(
                        model = model,
                        state = state,
                        focus = focus,
                        onFocusChange = { focus = it },
                        onSubmit = ::submit,
                        onForgotten = { scope.launch { model.requestReset() } },
                    )
                    PasswordChangeModel.Step.Done -> PasswordOutcome(
                        lines = listOf(
                            PasswordChangeCopy.doneTitle to MemoBookFont.h2,
                            PasswordChangeCopy.doneBody to MemoBookFont.body,
                        ),
                        onBack = dismiss,
                    )
                    PasswordChangeModel.Step.ResetSent -> PasswordOutcome(
                        lines = listOf(
                            PasswordRecoveryCopy.sentBody(model.email) to MemoBookFont.body,
                            PasswordRecoveryCopy.sentHint to MemoBookFont.caption,
                        ),
                        onBack = dismiss,
                    )
                }
            }
        }
    }
}

// MARK: - Le formulaire

@Composable
private fun PasswordForm(
    model: PasswordChangeModel,
    state: PasswordChangeModel.State,
    focus: PasswordChangeField?,
    onFocusChange: (PasswordChangeField?) -> Unit,
    onSubmit: () -> Unit,
    onForgotten: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
            if (model.mode.asksCurrentPassword) {
                BrandTextField(
                    PasswordChangeCopy.current,
                    state.currentPassword,
                    { model.currentPassword = it },
                    field = PasswordChangeField.Current,
                    focus = focus,
                    onFocusChange = onFocusChange,
                    isSecure = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                    keyboardActions = KeyboardActions(onNext = { onFocusChange(PasswordChangeField.New) }),
                    contentType = ContentType.Password,
                )

                AnimatedVisibility(
                    visible = state.failure == PasswordChangeModel.Failure.WrongPassword,
                    enter = fadeIn(SwiftMotion.snappy(0.2f)),
                    exit = fadeOut(SwiftMotion.snappy(0.2f)),
                ) {
                    WrongPassword(isWorking = state.isWorking, onForgotten = onForgotten)
                }
            }

            // `NewPassword` fait proposer un mot de passe fort au gestionnaire
            // de mots de passe, comme à l'inscription.
            BrandTextField(
                PasswordChangeCopy.new,
                state.newPassword,
                { model.newPassword = it },
                field = PasswordChangeField.New,
                focus = focus,
                onFocusChange = onFocusChange,
                isSecure = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                keyboardActions = KeyboardActions(onNext = { onFocusChange(PasswordChangeField.Confirmation) }),
                contentType = ContentType.NewPassword,
            )

            PasswordCriteria(state.newPassword)

            BrandTextField(
                PasswordChangeCopy.confirmation,
                state.confirmation,
                { model.confirmation = it },
                field = PasswordChangeField.Confirmation,
                focus = focus,
                onFocusChange = onFocusChange,
                isSecure = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { onSubmit() }),
                contentType = ContentType.NewPassword,
            )

            state.confirmationError?.let { FieldError(it) }

            if (state.failure == PasswordChangeModel.Failure.SamePassword) FieldError(PasswordChangeCopy.samePassword)
        }

        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            BrandButton(
                model.mode.callToAction,
                isLoading = state.isWorking,
                fillsWidth = true,
                enabled = state.canSubmit,
                action = onSubmit,
            )

            AnimatedVisibility(visible = state.failure?.message != null, enter = fadeIn(), exit = fadeOut()) {
                // La dernière phrase reste le temps de disparaître.
                val message = remember { mutableStateOf("") }
                state.failure?.message?.let { message.value = it }
                BrandText(
                    message.value,
                    MemoBookFont.notification,
                    Modifier.fillMaxWidth(),
                    color = MemoBookColor.error,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

/**
 * Les trois critères, cochés à mesure : c'est ce que « en temps réel » veut
 * dire — on voit lequel manque avant d'appuyer.
 */
@Composable
private fun PasswordCriteria(password: String) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = MemoBookSpacing.xs),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2),
    ) {
        PasswordRule.Criterion.entries.forEach { criterion ->
            val isMet = criterion.isMet(password)
            val labelColor by animateColorAsState(
                if (isMet) MemoBookColor.ink else MemoBookColor.inkMuted,
                SwiftMotion.snappy(0.2f),
                label = "critère",
            )
            Row(
                Modifier.semantics(mergeDescendants = true) { stateDescription = if (isMet) "respecté" else "manquant" },
                horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Le rond plein et coché, ou le rond vide — les deux symboles
                // d'iOS, le second dessiné ici faute de son jumeau.
                if (isMet) {
                    Image(
                        painterResource(R.drawable.system_checkmark_circle_fill),
                        contentDescription = null,
                        colorFilter = ColorFilter.tint(MemoBookColor.valid),
                        modifier = Modifier.size(14.dp),
                    )
                } else {
                    Box(
                        Modifier
                            .size(14.dp)
                            .border(1.5.dp, MemoBookColor.inkFaint, CircleShape),
                    )
                }
                BrandText(criterion.label, MemoBookFont.caption, color = labelColor)
            }
        }
    }
}

/** « Mot de passe incorrect », et la sortie de secours. */
@Composable
private fun WrongPassword(isWorking: Boolean, onForgotten: () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = MemoBookSpacing.xs),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2),
    ) {
        BrandText(PasswordChangeCopy.wrongPassword, MemoBookFont.notification, color = MemoBookColor.error)

        Box(
            Modifier
                .heightIn(min = MemoBookSpacing.minimumTapTarget)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = PlainButtonIndication,
                    enabled = !isWorking,
                    role = Role.Button,
                    onClickLabel = PasswordChangeCopy.forgottenHint,
                    onClick = onForgotten,
                ),
            contentAlignment = Alignment.CenterStart,
        ) {
            BrandText(
                PasswordChangeCopy.forgotten,
                MemoBookFont.tagline.copy(textDecoration = TextDecoration.Underline),
                color = MemoBookColor.action,
            )
        }
    }
}

@Composable
private fun FieldError(text: String) {
    BrandText(
        text,
        MemoBookFont.notification,
        Modifier
            .fillMaxWidth()
            .padding(horizontal = MemoBookSpacing.xs),
        color = MemoBookColor.error,
    )
}

// MARK: - Réussite, et l'e-mail parti

/** Deux lignes centrées — un titre et sa phrase —, puis « Retour à mon compte ». */
@Composable
private fun PasswordOutcome(lines: List<Pair<String, TextStyle>>, onBack: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            lines.forEachIndexed { index, (text, style) ->
                BrandText(
                    text,
                    style,
                    Modifier.fillMaxWidth(),
                    // La première ligne à l'encre, la seconde effacée.
                    color = if (index == 0) MemoBookColor.ink else MemoBookColor.inkMuted,
                    textAlign = TextAlign.Center,
                )
            }
        }

        BrandButton(PasswordChangeCopy.backToAccount, fillsWidth = true, action = onBack)
    }
}

internal enum class PasswordChangeField {
    Current,
    New,
    Confirmation,
}

// MARK: - Le modèle

/**
 * Ce que la feuille sait faire : vérifier les trois champs, envoyer, et dire
 * ce qui s'est passé.
 *
 * Il reçoit des fonctions et non l'API, comme [ProfileModel] : l'app leur
 * branche `POST /v1/profile/password` et « mot de passe oublié » ; un aperçu
 * n'en fournit aucune et la feuille joue alors la réussite.
 *
 * **Un objet par ouverture**, comme `PasswordRecoveryModel` — pas un
 * `ViewModel` : il ne vit que le temps de la feuille, et ses appels partent
 * d'elle, comme les `Task` d'iOS. Son [id] présente la feuille
 * (`BrandSheetHost(item:)`) : une seconde ouverture repart d'un modèle neuf.
 */
internal class PasswordChangeModel(
    val mode: Mode = Mode.Change,
    val email: String,
    private val change: (suspend (String, String) -> Unit)? = null,
    private val reset: (suspend (String, String) -> Unit)? = null,
    requestReset: (suspend (String) -> Unit)? = null,
) {
    /**
     * Pourquoi la feuille est ouverte : changer, ou poser un nouveau mot de
     * passe depuis un lien reçu par e-mail.
     */
    sealed interface Mode {
        data object Change : Mode
        data class Reset(val token: String) : Mode

        val asksCurrentPassword: Boolean get() = this == Change

        val subtitle: String
            get() = when (this) {
                Change -> PasswordChangeCopy.subtitle
                is Reset -> PasswordChangeCopy.resetSubtitle
            }

        val callToAction: String
            get() = when (this) {
                Change -> PasswordChangeCopy.submit
                is Reset -> PasswordChangeCopy.submitReset
            }
    }

    enum class Step {
        Form,
        Done,
        ResetSent,
    }

    /** Ce qui a échoué, et la phrase qui va avec. */
    enum class Failure {
        WrongPassword,
        SamePassword,
        SessionExpired,
        NoPassword,
        Unavailable,
        ;

        val message: String?
            get() = when (this) {
                WrongPassword, SamePassword -> null // sous leur champ
                SessionExpired -> PasswordChangeCopy.sessionExpired
                NoPassword -> PasswordChangeCopy.noPassword
                Unavailable -> PasswordChangeCopy.unavailable
            }
    }

    data class State(
        val asksCurrentPassword: Boolean,
        val currentPassword: String = "",
        val newPassword: String = "",
        val confirmation: String = "",
        val step: Step = Step.Form,
        val failure: Failure? = null,
        val isWorking: Boolean = false,
    ) {
        val isNewPasswordValid: Boolean get() = PasswordRule.isValid(newPassword)

        val passwordsMatch: Boolean get() = newPassword == confirmation

        /** Même phrase que l'inscription, une fois qu'il y a de quoi juger. */
        val confirmationError: String?
            get() = if (confirmation.isEmpty() || passwordsMatch) null else AuthModel.passwordMismatchMessage

        /**
         * Le bouton s'allume quand les champs sont **bien remplis**, pas avant :
         * un bouton qui échoue après coup apprend moins qu'un bouton gris.
         */
        val canSubmit: Boolean
            get() {
                if (isWorking || !isNewPasswordValid || !passwordsMatch) return false
                if (!asksCurrentPassword) return true
                return currentPassword.isNotEmpty() && currentPassword != newPassword
            }
    }

    private val requestResetMail = requestReset

    /** Une identité par ouverture de la feuille. */
    val id: UUID = UUID.randomUUID()

    private val _state = MutableStateFlow(State(asksCurrentPassword = mode.asksCurrentPassword))
    val state: StateFlow<State> = _state.asStateFlow()

    var currentPassword: String
        get() = _state.value.currentPassword
        set(value) = _state.update {
            it.copy(currentPassword = value, failure = if (it.failure == Failure.WrongPassword) null else it.failure)
        }

    var newPassword: String
        get() = _state.value.newPassword
        set(value) = _state.update {
            it.copy(newPassword = value, failure = if (it.failure == Failure.SamePassword) null else it.failure)
        }

    var confirmation: String
        get() = _state.value.confirmation
        set(value) = _state.update { it.copy(confirmation = value) }

    suspend fun submit() {
        val current = _state.value
        if (!current.canSubmit) return
        _state.update { it.copy(isWorking = true, failure = null) }

        try {
            when (val mode = mode) {
                // Sans serveur (aperçu), la feuille joue la réussite.
                Mode.Change -> change?.invoke(current.currentPassword, current.newPassword)
                is Mode.Reset -> reset?.invoke(mode.token, current.newPassword)
            }
            _state.update { it.copy(step = Step.Done) }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            _state.update { it.copy(failure = failure(error)) }
        } finally {
            _state.update { it.copy(isWorking = false) }
        }
    }

    /**
     * « Mot de passe oublié ? » : l'e-mail de réinitialisation part à l'adresse
     * du compte, et la feuille le dit. C'est la sortie du parcours classique.
     */
    suspend fun requestReset() {
        _state.update { it.copy(isWorking = true, failure = null) }
        try {
            requestResetMail?.invoke(email)
            _state.update { it.copy(step = Step.ResetSent) }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            _state.update { it.copy(failure = Failure.Unavailable) }
        } finally {
            _state.update { it.copy(isWorking = false) }
        }
    }

    private fun failure(error: Throwable): Failure {
        val apiError = error as? ApiError ?: return Failure.Unavailable
        return when {
            apiError is ApiError.Server && apiError.code == "wrong_password" -> Failure.WrongPassword
            apiError is ApiError.Server && apiError.code == "same_password" -> Failure.SamePassword
            apiError is ApiError.Server && apiError.code == "no_password" -> Failure.NoPassword
            apiError is ApiError.Server && apiError.statusCode == 401 -> Failure.SessionExpired
            apiError is ApiError.NotAuthenticated -> Failure.SessionExpired
            else -> Failure.Unavailable
        }
    }
}

internal object PasswordChangeCopy {
    const val title = "Modifier mon mot de passe"
    const val subtitle = "Choisis un nouveau mot de passe pour ton compte."
    const val resetSubtitle = "Configure ton nouveau mot de passe."

    const val current = "Mot de passe actuel"
    const val new = "Nouveau mot de passe"
    const val confirmation = "Confirmer le nouveau mot de passe"

    const val submit = "Modifier mon mot de passe"
    const val submitReset = "Enregistrer mon mot de passe"

    const val wrongPassword = "Mot de passe incorrect. Vérifie ton mot de passe et réessaie."
    const val forgotten = "Mot de passe oublié ?"
    const val forgottenHint = "Envoie un e-mail pour réinitialiser ton mot de passe"
    const val samePassword = "Ton nouveau mot de passe doit être différent de l’ancien."
    const val sessionExpired = "Ta session a expiré : reconnecte-toi pour modifier ton mot de passe."
    const val noPassword = "Ce compte s’ouvre avec Apple ou Google : il n’a pas de mot de passe à modifier."
    const val unavailable =
        "Impossible de modifier ton mot de passe pour le moment. Réessaie dans quelques instants."

    const val doneTitle = "Mot de passe modifié ✓"
    const val doneBody = "Ton mot de passe a bien été modifié."
    const val backToAccount = "Retour à mon compte"
}

@Preview(locale = "fr-rFR", name = "Modifier mon mot de passe", heightDp = 900)
@Composable
private fun PasswordChangeSheetPreview() {
    val model = remember { PasswordChangeModel(email = "margaux@exemple.com") }
    BrandSheetHost(isPresented = true, onDismissRequest = {}) { PasswordChangeSheet(model) }
}
