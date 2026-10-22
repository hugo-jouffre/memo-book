package com.memobook.feature.auth

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.memobook.core.PasswordRule
import com.memobook.design.BrandText
import com.memobook.design.BrandTextField
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.SwiftMotion
import com.memobook.design.isAccessibilityTextSize

/** Les champs de l'inscription. Jumeau de `SignUpFields.swift`. */
@Composable
internal fun SignUpFields(
    state: AuthModel.State,
    model: AuthModel,
    focus: AuthField?,
    onFocusChange: (AuthField?) -> Unit,
    onSubmit: () -> Unit,
) {
    val next = KeyboardActions(onNext = { onSubmit() })
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NameFields(
            firstName = state.firstName,
            onFirstNameChange = { model.firstName = it },
            lastName = state.lastName,
            onLastNameChange = { model.lastName = it },
            focus = focus,
            onFocusChange = onFocusChange,
            keyboardActions = next,
        )

        BrandTextField(
            "E-mail",
            state.email,
            { model.email = it },
            field = AuthField.Email,
            focus = focus,
            onFocusChange = onFocusChange,
            keyboardOptions = emailKeyboard,
            keyboardActions = next,
            contentType = ContentType.EmailAddress,
        )

        // Ce que le serveur reproche à l'adresse, **sous son champ** : c'est
        // là que la maquette le pose (`3394:10929`), et c'est la ligne à
        // changer. Le reste des échecs reste sous le bouton.
        FieldError(state.emailError)

        BrandTextField(
            "Mot de passe",
            state.password,
            { model.password = it },
            field = AuthField.Password,
            focus = focus,
            onFocusChange = onFocusChange,
            isSecure = true,
            hint = PasswordRule.hint,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            keyboardActions = next,
            // `NewPassword` déclenche la proposition de mot de passe fort du
            // gestionnaire de mots de passe ; sans les règles, il en propose un
            // que notre validation refuserait.
            contentType = ContentType.NewPassword,
        )

        BrandTextField(
            "Confirme ton mot de passe",
            state.passwordConfirmation,
            { model.passwordConfirmation = it },
            field = AuthField.PasswordConfirmation,
            focus = focus,
            onFocusChange = onFocusChange,
            isSecure = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            keyboardActions = next,
            contentType = ContentType.NewPassword,
        )

        FieldError(state.passwordConfirmationError)
    }
}

/**
 * Prénom et nom côte à côte — et l'un sous l'autre aux tailles de texte
 * accessibles : deux champs côte à côte ne laissent plus la place à leur propre
 * intitulé. La page de compléments après Apple ou Google les reprend.
 */
@Composable
internal fun NameFields(
    firstName: String,
    onFirstNameChange: (String) -> Unit,
    lastName: String,
    onLastNameChange: (String) -> Unit,
    focus: AuthField?,
    onFocusChange: (AuthField?) -> Unit,
    keyboardActions: KeyboardActions,
    imeAction: ImeAction = ImeAction.Next,
) {
    val words = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = imeAction)
    val first: @Composable (Modifier) -> Unit = { modifier ->
        BrandTextField(
            "Prénom",
            firstName,
            onFirstNameChange,
            field = AuthField.FirstName,
            focus = focus,
            onFocusChange = onFocusChange,
            modifier = modifier,
            keyboardOptions = words,
            keyboardActions = keyboardActions,
            contentType = ContentType.PersonFirstName,
        )
    }
    val last: @Composable (Modifier) -> Unit = { modifier ->
        BrandTextField(
            "Nom",
            lastName,
            onLastNameChange,
            field = AuthField.LastName,
            focus = focus,
            onFocusChange = onFocusChange,
            modifier = modifier,
            keyboardOptions = words,
            keyboardActions = keyboardActions,
            contentType = ContentType.PersonLastName,
        )
    }

    if (isAccessibilityTextSize()) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            first(Modifier.fillMaxWidth())
            last(Modifier.fillMaxWidth())
        }
    } else {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            first(Modifier.weight(1f))
            last(Modifier.weight(1f))
        }
    }
}

/**
 * Une erreur posée sous son champ, alignée sur le texte du champ (20 de
 * marge), qui arrive et s'en va en fondu. Elle garde sa phrase le temps de
 * s'effacer.
 */
@Composable
internal fun FieldError(message: String?, modifier: Modifier = Modifier) {
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
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp),
            color = MemoBookColor.error,
        )
    }
}

/** La dernière valeur non nulle : ce qu'un message qui s'efface doit encore montrer. */
@Composable
internal fun <T : Any> rememberLast(value: T?): T? {
    val last = remember { LastValue<T>() }
    if (value != null) last.value = value
    return last.value
}

private class LastValue<T : Any> {
    var value: T? = null
}
