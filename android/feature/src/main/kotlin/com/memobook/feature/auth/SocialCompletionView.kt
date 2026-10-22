package com.memobook.feature.auth

import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.sp
import com.memobook.core.Account
import com.memobook.design.BrandButton
import com.memobook.design.BrandText
import com.memobook.design.BrandTextField
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import kotlinx.coroutines.launch

/**
 * La page qui suit une entrée par Apple ou Google : **vérifier ce que le
 * fournisseur a donné** — prénom, nom, adresse — avant d'entrer dans l'app.
 * Jumeau de `SocialCompletionView.swift`.
 *
 * Maquette `Social login - compléments` (`2707:9456`) : le titre, une ligne qui
 * dit d'où viennent les valeurs, le prénom et le nom côte à côte, l'adresse,
 * et « Continuer ». Elle manquait, et un compte ouvert par Google entrait sans
 * qu'on ait pu corriger un prénom en minuscules ou un nom de famille tronqué —
 * Hugo, 14/09/2026.
 *
 * **L'adresse se lit, elle ne se corrige pas**, pour la même raison que sur le
 * profil : c'est l'identifiant du compte, et la changer est un écran à part.
 * Quand le fournisseur ne l'a pas donnée — une adresse Apple masquée et
 * refusée —, la ligne n'apparaît pas : un champ vide et verrouillé ne dirait
 * rien.
 */
@Composable
internal fun SocialCompletionView(
    state: AuthModel.State,
    model: AuthModel,
    focus: AuthField?,
    onFocusChange: (AuthField?) -> Unit,
    onAuthenticated: (Account) -> Unit,
) {
    val scope = rememberCoroutineScope()

    fun submit() {
        val current = model.state.value
        if (!current.canCompleteProfile || current.isWorking) return
        onFocusChange(null)
        scope.launch { model.completeProfile()?.let(onAuthenticated) }
    }

    // Le clavier s'ouvre sur ce qu'il y a le plus souvent à corriger.
    LaunchedEffect(Unit) { if (model.firstName.isEmpty()) onFocusChange(AuthField.FirstName) }

    AuthScrollPage {
        Column(
            Modifier
                .fillMaxWidth()
                .semantics(mergeDescendants = true) { heading() },
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        ) {
            BrandText("Complète tes informations", MemoBookFont.h1.copy(letterSpacing = (-0.41).sp))
            // La minuscule initiale est celle de la maquette, comme le
            // sous-titre de l'écran d'entrée : la phrase continue le titre.
            BrandText(
                "nous avons récupéré les informations suivantes, vérifie leur validité",
                MemoBookFont.body.copy(letterSpacing = MemoBookFont.tracking),
                color = MemoBookColor.inkMuted,
            )
        }

        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
            NameFields(
                firstName = state.firstName,
                onFirstNameChange = { model.firstName = it },
                lastName = state.lastName,
                onLastNameChange = { model.lastName = it },
                focus = focus,
                onFocusChange = onFocusChange,
                keyboardActions = KeyboardActions(onDone = { submit() }),
                imeAction = ImeAction.Done,
            )

            if (state.completing?.email != null) ReadOnlyEmail(state.email)
        }

        BrandButton(
            "Continuer",
            modifier = Modifier.padding(top = MemoBookSpacing.xs),
            isLoading = state.isWorking,
            fillsWidth = true,
            enabled = state.canCompleteProfile,
            action = ::submit,
        )

        ErrorText(state.errorMessage)
    }
}

/**
 * L'adresse du compte, qu'on lit sans pouvoir la toucher — le `.disabled(true)`
 * d'iOS : `BrandTextField` n'a pas d'état désactivé, un voile prend donc le
 * doigt avant le champ, et le champ pâlit.
 */
@Composable
private fun ReadOnlyEmail(email: String) {
    Box {
        BrandTextField(
            "E-mail",
            email,
            {},
            field = AuthField.Email,
            focus = null,
            onFocusChange = {},
            modifier = Modifier
                .alpha(0.5f)
                .semantics { disabled() },
            contentType = ContentType.EmailAddress,
        )
        Box(
            Modifier
                .matchParentSize()
                .pointerInput(Unit) {
                    awaitEachGesture {
                        awaitFirstDown(pass = PointerEventPass.Initial).consume()
                    }
                },
        )
    }
}
