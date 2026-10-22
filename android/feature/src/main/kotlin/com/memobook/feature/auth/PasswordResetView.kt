package com.memobook.feature.auth

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
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
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.core.Account
import com.memobook.core.PasswordRule
import com.memobook.design.BrandButton
import com.memobook.design.BrandIconBadge
import com.memobook.design.BrandText
import com.memobook.design.BrandTextField
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/**
 * La page qui suit le lien de l'e-mail « Mot de passe oublié » : **le nouveau
 * mot de passe, deux fois**, puis l'app. Jumeau de `PasswordResetView.swift`.
 *
 * Maquette « Mdp oublié – config » (Hugo, 15/09/2026) : le cadenas, le titre,
 * les deux champs, « Continuer ». Une **page** et non une feuille : on arrive
 * par un lien, il n'y a pas d'écran dessous qu'une feuille prolongerait — même
 * dessin que [SocialCompletionView], l'autre page qui s'interpose avant
 * l'entrée.
 *
 * Les deux champs sont ceux de l'inscription — même règle ([PasswordRule]),
 * même phrase de désaccord, même proposition de mot de passe fort du
 * gestionnaire de mots de passe. La réussite ouvre une session : on entre sans
 * retaper ce qu'on vient d'écrire.
 *
 * @param onRequestAgain « Ce lien n'est plus valable » → en redemander un. La
 *   page se referme et la feuille de l'adresse s'ouvre à sa place.
 * @param onCancel sortir sans rien changer — un lien ouvert par erreur, ou trop tard.
 */
@Composable
internal fun PasswordResetView(
    model: PasswordRecoveryModel,
    onAuthenticated: (Account) -> Unit,
    onRequestAgain: () -> Unit,
    onCancel: () -> Unit,
) {
    val state by model.state.collectAsStateWithLifecycle(context = Dispatchers.Main.immediate)
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    var focus by remember { mutableStateOf<PasswordRecoveryField?>(null) }

    fun save() {
        if (!model.state.value.canSave) return
        focus = null
        scope.launch { model.resetPassword()?.let(onAuthenticated) }
    }

    // Le clavier s'ouvre tout de suite : il n'y a rien d'autre à faire sur
    // cette page que d'écrire.
    LaunchedEffect(model) { if (model.password.isEmpty()) focus = PasswordRecoveryField.Password }

    LaunchedEffect(model) {
        model.state.map { it.errorMessage }.distinctUntilChanged().drop(1).collect { message ->
            if (message != null) haptics.performHapticFeedback(HapticFeedbackType.Reject)
        }
    }

    AuthScrollPage {
        BrandIconBadge(R.drawable.icon_locker, Modifier.align(Alignment.CenterHorizontally))

        BrandText(
            PasswordRecoveryCopy.resetTitle,
            MemoBookFont.h1.copy(letterSpacing = (-0.41).sp),
            Modifier
                .fillMaxWidth()
                .semantics { heading() },
        )

        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
            BrandTextField(
                PasswordRecoveryCopy.passwordLabel,
                state.password,
                { model.password = it },
                field = PasswordRecoveryField.Password,
                focus = focus,
                onFocusChange = { focus = it },
                isSecure = true,
                hint = PasswordRule.hint,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                keyboardActions = KeyboardActions(onNext = { focus = PasswordRecoveryField.PasswordConfirmation }),
                contentType = ContentType.NewPassword,
            )

            BrandTextField(
                PasswordRecoveryCopy.confirmationLabel,
                state.passwordConfirmation,
                { model.passwordConfirmation = it },
                field = PasswordRecoveryField.PasswordConfirmation,
                focus = focus,
                onFocusChange = { focus = it },
                isSecure = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { save() }),
                contentType = ContentType.NewPassword,
            )

            FieldError(state.passwordConfirmationError)
        }

        Column(
            Modifier.padding(top = MemoBookSpacing.xs),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        ) {
            BrandButton(
                PasswordRecoveryCopy.save,
                isLoading = state.isWorking,
                fillsWidth = true,
                enabled = state.canSave,
                action = ::save,
            )

            ErrorText(state.errorMessage)

            // Le lien ne vaut plus rien : la seule issue est d'en redemander un.
            AnimatedVisibility(
                visible = state.errorMessage != null,
                modifier = Modifier.fillMaxWidth(),
                enter = fadeIn(SwiftMotion.snappy(0.2f)),
                exit = fadeOut(SwiftMotion.snappy(0.2f)),
            ) {
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    BrandButton(PasswordRecoveryCopy.requestAgain, style = BrandButton.Style.Link, action = onRequestAgain)
                }
            }
        }

        // La porte de sortie. La maquette n'en dessine pas ; sans elle, un lien
        // ouvert par erreur laisse quelqu'un devant deux champs qu'il ne veut
        // pas remplir, avec pour seule issue de tuer l'app. Effacée, comme
        // « Besoin d'aide ? » du profil.
        Box(
            Modifier
                .padding(top = MemoBookSpacing.s)
                .fillMaxWidth()
                .heightIn(min = MemoBookSpacing.minimumTapTarget),
            contentAlignment = Alignment.Center,
        ) {
            BrandButton(PasswordRecoveryCopy.backHome, style = BrandButton.Style.Link, isSubdued = true, action = onCancel)
        }
    }
}

@Preview(locale = "fr-rFR", name = "Nouveau mot de passe", widthDp = 390, heightDp = 844)
@Composable
private fun PasswordResetViewPreview() {
    val model = remember { PasswordRecoveryModel.forReset(previewApi(), resetToken = "aperçu") }
    PasswordResetView(model, onAuthenticated = {}, onRequestAgain = {}, onCancel = {})
}
