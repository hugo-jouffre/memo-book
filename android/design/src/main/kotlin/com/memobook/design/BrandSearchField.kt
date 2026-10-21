package com.memobook.design

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.LocalTextSelectionColors
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp

/**
 * **Le** champ de recherche de MemoBook : une loupe, ce qu'on tape, et la
 * croix qui efface. Jumeau de `BrandSearchField.swift`.
 *
 * À ne pas confondre avec [BrandTextField], le champ des **formulaires**.
 * Celui-ci ne saisit rien : il **filtre ce qui est en dessous**, à chaque
 * caractère, et son contenu ne part nulle part. D'où un dessin à lui —
 * capsule, loupe en tête, pas de libellé — et un clavier qui s'arrête à lui.
 *
 * **La croix n'apparaît qu'une fois qu'il y a quelque chose à effacer**, et
 * elle efface sans rendre le clavier : on efface pour retaper, pas pour partir.
 * C'est le comportement du champ de recherche d'iOS, et le seul endroit où on
 * le recopie plutôt que de le redessiner (R6).
 *
 * @param placeholder ce que le champ propose quand il est vide. Il dit **où**
 *   l'on cherche : « Rechercher une question » se lit, « Rechercher » se devine.
 * @param onClear ce que fait la croix en plus de vider le texte.
 */
@Composable
fun BrandSearchField(
    placeholder: String,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    onClear: (() -> Unit)? = null,
) {
    var isFocused by remember { mutableStateOf(false) }
    val glyphSide = scaled(18.dp)
    val focusManager = LocalFocusManager.current
    val shape = RoundedCornerShape(percent = 50)
    val borderColor by animateColorAsState(
        if (isFocused) MemoBookColor.action else MemoBookColor.hairline,
        SwiftMotion.smooth(0.2f),
        label = "contour",
    )
    val borderWidth by animateDpAsState(if (isFocused) 1.5.dp else 1.dp, SwiftMotion.smooth(0.2f), label = "trait")

    CompositionLocalProvider(LocalTextSelectionColors provides BrandTextSelectionColors) {
        Row(
            modifier
                .heightIn(min = MemoBookSpacing.minimumTapTarget)
                .background(MemoBookColor.surface, shape)
                .border(borderWidth, borderColor, shape)
                .padding(horizontal = MemoBookSpacing.s),
            horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // La loupe du jeu de marque, là où iOS pose le symbole `magnifyingglass`.
            Image(
                painter = painterResource(R.drawable.icon_magnifier),
                contentDescription = null,
                colorFilter = ColorFilter.tint(MemoBookColor.inkMuted),
                modifier = Modifier
                    .size(glyphSide)
                    .clearAndSetSemantics {},
            )

            Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                if (value.isEmpty()) {
                    BrandText(placeholder, MemoBookFont.body, Modifier.clearAndSetSemantics {}, color = MemoBookColor.inkMuted, maxLines = 1)
                }
                BasicTextField(
                    value = value,
                    onValueChange = onValueChange,
                    modifier = Modifier
                        .fillMaxWidth()
                        .onFocusChanged { isFocused = it.isFocused }
                        .semantics { contentDescription = placeholder },
                    textStyle = MemoBookFont.body.copy(color = MemoBookColor.ink),
                    // Un champ de recherche ne valide rien : le clavier propose de
                    // chercher et de se refermer, pas d'aller au champ suivant.
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.None,
                        autoCorrectEnabled = false,
                        imeAction = ImeAction.Search,
                    ),
                    keyboardActions = KeyboardActions(onSearch = { focusManager.clearFocus() }),
                    singleLine = true,
                    cursorBrush = SolidColor(MemoBookColor.action),
                )
            }

            AnimatedVisibility(
                visible = value.isNotEmpty(),
                enter = fadeIn(SwiftMotion.smooth(0.2f)),
                exit = fadeOut(SwiftMotion.smooth(0.2f)),
            ) {
                // La croix ne pousse pas le champ en apparaissant : elle est ramenée
                // à la hauteur du glyphe, sa cible de 48 déborde la capsule.
                Box(Modifier.size(width = MemoBookSpacing.minimumTapTarget, height = glyphSide), contentAlignment = Alignment.Center) {
                    Box(
                        Modifier
                            .requiredSize(MemoBookSpacing.minimumTapTarget)
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                                role = Role.Button,
                            ) {
                                onValueChange("")
                                onClear?.invoke()
                            }
                            .semantics { contentDescription = "Effacer la recherche" },
                        contentAlignment = Alignment.Center,
                    ) {
                        // `xmark.circle.fill` d'iOS, redessiné.
                        Image(
                            painter = painterResource(R.drawable.system_xmark_circle_fill),
                            contentDescription = null,
                            colorFilter = ColorFilter.tint(MemoBookColor.inkMuted),
                            modifier = Modifier.size(glyphSide),
                        )
                    }
                }
            }
        }
    }
}

@Preview(locale = "fr-rFR", name = "Champ de recherche", widthDp = 390, heightDp = 200)
@Composable
private fun BrandSearchFieldPreview() {
    var empty by remember { mutableStateOf("") }
    var filled by remember { mutableStateOf("remboursement") }
    Column(
        Modifier
            .fillMaxSize()
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        BrandSearchField("Rechercher une question", empty, { empty = it }, Modifier.fillMaxWidth())
        BrandSearchField("Rechercher une question", filled, { filled = it }, Modifier.fillMaxWidth())
    }
}
