package com.memobook.design

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Le champ de saisie **de plusieurs lignes** de MemoBook. Jumeau de
 * `BrandTextBox.swift`.
 *
 * Le pendant de [BrandTextField], et la frontière est nette : un
 * `BrandTextField` reçoit une **valeur** — un e-mail, un code —, un
 * `BrandTextBox` reçoit un **texte**. Le premier est haut de 3,5 rem et ne
 * s'enroule pas ; le second part d'une hauteur de départ et grandit avec ce
 * qu'on y écrit. Deux écrans l'emploient : le message au support, et le texte
 * de quatrième de couverture — la règle est de factoriser à la **deuxième**
 * occurrence.
 *
 * Il porte la barre du clavier ([BrandKeyboardDismissBar]) : un texte de
 * plusieurs lignes garde la touche Entrée pour ses retours à la ligne.
 *
 * @param placeholder l'exemple affiché tant que le champ est vide.
 * @param isFocused le focus, que l'écran tient — le `FocusState<Bool>` d'iOS.
 * @param minimumHeight la hauteur de départ du cadre. Il grandit ensuite avec le texte.
 * @param lineSpan entre combien de lignes le cadre respire. La borne haute
 *   compte : au-delà, c'est la feuille qui défilerait, et le bouton de
 *   validation partirait hors de vue.
 * @param accessibilityLabel ce que TalkBack annonce. Par défaut le texte
 *   d'invite, qui suffit quand il nomme ce qu'on attend.
 */
@Composable
fun BrandTextBox(
    placeholder: String,
    value: String,
    onValueChange: (String) -> Unit,
    isFocused: Boolean,
    onFocusChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    minimumHeight: Dp = 133.dp,
    lineSpan: IntRange = 4..10,
    accessibilityLabel: String? = null,
) {
    // La hauteur de départ suit le corps de texte, comme un `@ScaledMetric`
    // relatif à `.body` : le facteur des 16 du corps, appliqué aux 133.
    val bodyScale = scaled(16.dp) / 16.dp
    val span = resolvedSpan(lineSpan, isAccessibilityTextSize())
    val binding = rememberFocusBinding(
        wanted = isFocused,
        released = !isFocused,
        onFocusGained = { onFocusChange(true) },
        onFocusLost = { onFocusChange(false) },
    )
    val shape = RoundedCornerShape(MemoBookSpacing.cornerRadius)

    BrandKeyboardDismissBar(modifier) {
        CompositionLocalProvider(LocalTextSelectionColors provides BrandTextSelectionColors) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = minimumHeight * bodyScale)
                    .background(MemoBookColor.surface, shape)
                    // Figma dessine #E6DAD0 ; `hairline` est l'encre à 10 %, qui tombe
                    // à #E6DFD8 sur le crème — un sixième filet de moins à tenir.
                    .border(1.dp, MemoBookColor.hairline, shape)
                    .pointerInput(Unit) { detectTapGestures { binding.requester.requestFocus() } }
                    .padding(MemoBookSpacing.snug),
                contentAlignment = Alignment.TopStart,
            ) {
                if (value.isEmpty()) {
                    BrandText(placeholder, MemoBookFont.body, Modifier.clearAndSetSemantics {}, color = MemoBookColor.inkMuted)
                }
                BasicTextField(
                    value = value,
                    onValueChange = onValueChange,
                    modifier = Modifier
                        .fillMaxWidth()
                        .then(binding.modifier)
                        .semantics { contentDescription = accessibilityLabel ?: placeholder },
                    textStyle = MemoBookFont.body.copy(color = MemoBookColor.ink),
                    // La majuscule de début de phrase, celle du clavier d'iOS.
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                    minLines = span.first,
                    maxLines = span.last,
                    cursorBrush = SolidColor(MemoBookColor.action),
                )
            }
        }
    }
}

/**
 * En taille accessible, le cadre montre moins de lignes : chacune est plus
 * haute, et dix d'entre elles dépasseraient l'écran.
 */
private fun resolvedSpan(lineSpan: IntRange, isAccessibilitySize: Boolean): IntRange {
    if (!isAccessibilitySize) return lineSpan
    return maxOf(2, lineSpan.first - 1)..maxOf(3, lineSpan.last - 4)
}

@Preview(locale = "fr-rFR", name = "Texte long", widthDp = 390)
@Composable
private fun BrandTextBoxPreview() {
    var empty by remember { mutableStateOf("") }
    var filled by remember { mutableStateOf("Bonjour,\nje n’arrive pas à commander mon carnet.") }
    var focused by remember { mutableStateOf(false) }
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        BrandTextBox("Ton message…", empty, { empty = it }, isFocused = false, onFocusChange = {})
        BrandTextBox("Ton message…", filled, { filled = it }, isFocused = focused, onFocusChange = { focused = it })
    }
}
