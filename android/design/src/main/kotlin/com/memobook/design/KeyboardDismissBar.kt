package com.memobook.design

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties

/**
 * Pose **la** barre d'accessoires du clavier de MemoBook : un seul bouton, à
 * droite, qui referme le clavier. Jumeau de `brandKeyboardDismissBar()`, qui
 * était un modificateur et devient ici une enveloppe : tant qu'un champ de son
 * contenu a le focus et que le clavier est sorti, le bouton flotte juste
 * au-dessus des touches.
 *
 * Une icône plutôt qu'un mot. « OK » laisse croire qu'on valide quelque chose,
 * alors qu'on ne fait que ranger le clavier — et sur un écran où
 * l'enregistrement se fait tout seul à la sortie du champ, ce faux bouton de
 * validation est un contresens. `IconKeyboardDownDuo` dit ce qu'il fait : **la
 * bichrome** depuis le 29/09/2026 (Hugo), dont l'aplat bleu se voit là où le
 * trait seul se perdait.
 *
 * Android n'a pas de barre d'accessoires au-dessus du clavier : le bouton y est
 * une pastille de papier posée au bout de la ligne, là où iOS 26 dessine sa
 * bulle de verre. La cible de 48 suffit à l'atteindre sans le soulever.
 */
@Composable
fun BrandKeyboardDismissBar(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    var holdsFocus by remember { mutableStateOf(false) }
    val resign = KeyboardDismissal.rememberResignFirstResponder()
    Box(modifier.onFocusChanged { holdsFocus = it.hasFocus }, propagateMinConstraints = true) {
        content()
        if (holdsFocus) KeyboardDismissButton(resign)
    }
}

/** Le bouton, dans une fenêtre à lui calée sur le haut du clavier. Rien tant que le clavier est rangé. */
@Composable
private fun KeyboardDismissButton(resign: () -> Unit) {
    val keyboardHeight = WindowInsets.ime.getBottom(LocalDensity.current)
    if (keyboardHeight <= 0) return
    val windowHeight = LocalWindowInfo.current.containerSize.height
    val position = remember(windowHeight, keyboardHeight) { AboveTheKeyboard(windowHeight - keyboardHeight) }
    // Une fenêtre qui ne prend pas le focus : le champ le garde, et le clavier reste.
    Popup(popupPositionProvider = position, properties = PopupProperties(focusable = false)) {
        Box(
            Modifier
                // De quoi laisser l'ombre se poser, et le bouton loin du bord.
                .padding(start = MemoBookSpacing.xs, top = MemoBookSpacing.xs, end = MemoBookSpacing.screenMargin, bottom = MemoBookSpacing.xs)
                .size(MemoBookSpacing.minimumTapTarget)
                .brandShadow(MemoBookShadow.Raised, CircleShape)
                .background(MemoBookColor.surface, CircleShape)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    role = Role.Button,
                    onClick = resign,
                )
                .semantics { contentDescription = "Masquer le clavier" },
            contentAlignment = Alignment.Center,
        ) {
            // Sans teinte : la bichrome porte ses couleurs, la teinter l'aplatirait en silhouette.
            Image(
                painter = painterResource(R.drawable.icon_keyboard_down_duo),
                contentDescription = null,
                modifier = Modifier.size(MemoBookSpacing.m),
            )
        }
    }
}

/** Le bouton au bout de la ligne, son bas sur le haut du clavier. */
private class AboveTheKeyboard(private val keyboardTop: Int) : PopupPositionProvider {
    override fun calculatePosition(
        anchorBounds: IntRect,
        windowSize: IntSize,
        layoutDirection: LayoutDirection,
        popupContentSize: IntSize,
    ): IntOffset {
        val x = if (layoutDirection == LayoutDirection.Ltr) windowSize.width - popupContentSize.width else 0
        return IntOffset(x, keyboardTop - popupContentSize.height)
    }
}

/**
 * Referme le clavier sans savoir quel champ le tenait.
 *
 * Les écrans qui corrigent une valeur sur place gardent leur focus pour eux —
 * c'est la sortie du champ qui enregistre. On retire donc le focus, quel qu'il
 * soit, plutôt que de faire remonter tous les états de focus de l'écran
 * jusqu'à la barre — le `resignFirstResponder` d'iOS.
 */
object KeyboardDismissal {
    /** L'action qui range le clavier, pour l'écran où elle est appelée. */
    @Composable
    fun rememberResignFirstResponder(): () -> Unit {
        val focusManager = LocalFocusManager.current
        val keyboard = LocalSoftwareKeyboardController.current
        return remember(focusManager, keyboard) {
            {
                focusManager.clearFocus()
                keyboard?.hide()
            }
        }
    }
}
