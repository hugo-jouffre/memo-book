package com.memobook.feature.auth

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.memobook.design.BrandText
import com.memobook.design.BrandTextField
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication

/** Les champs de la connexion. Jumeau de `SignInFields.swift`. */
@Composable
internal fun SignInFields(
    state: AuthModel.State,
    model: AuthModel,
    focus: AuthField?,
    onFocusChange: (AuthField?) -> Unit,
    onSubmit: () -> Unit,
    onForgottenPassword: () -> Unit,
) {
    val next = KeyboardActions(onNext = { onSubmit() })
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
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

        BrandTextField(
            "Mot de passe",
            state.password,
            { model.password = it },
            field = AuthField.Password,
            focus = focus,
            onFocusChange = onFocusChange,
            isSecure = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            keyboardActions = next,
            contentType = ContentType.Password,
        )

        // Lien souligné vert : le style `Link` du design system est un
        // texte noir sans soulignement, il ne couvre pas ce cas. À
        // remonter au design plutôt qu'à décliner `BrandButton` ici.
        Box(
            Modifier
                .heightIn(min = MemoBookSpacing.minimumTapTarget)
                .clickable(interactionSource = null, indication = PlainButtonIndication, role = Role.Button, onClick = onForgottenPassword),
            contentAlignment = Alignment.CenterStart,
        ) {
            BrandText(
                "Mot de passe oublié ?",
                MemoBookFont.bodySemibold.copy(textDecoration = TextDecoration.Underline),
                color = MemoBookColor.action,
            )
        }
    }
}

/** Le clavier d'une adresse : ni majuscule, ni correction — ce qu'on lit est ce qui part. */
internal val emailKeyboard = KeyboardOptions(
    keyboardType = KeyboardType.Email,
    capitalization = KeyboardCapitalization.None,
    autoCorrectEnabled = false,
    imeAction = ImeAction.Next,
)
