package com.memobook.design

import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties

/**
 * L'alerte de l'app : le `.alert(_:isPresented:actions:message:)` de SwiftUI.
 *
 * iOS dessine l'alerte du système ; l'`AlertDialog` d'Android est un composant
 * Material, que l'app ne prend pas (`android/CLAUDE.md`). C'est donc une
 * fenêtre `Dialog` aux couleurs du papier : le titre en Sora, le message en
 * General Sans, les boutons en texte d'action — le rouge pour ce qui détruit,
 * le gras pour l'annulation, comme le rôle `.cancel` d'iOS.
 *
 * **Deux boutons se posent côte à côte, trois et plus s'empilent**, comme sur
 * iOS — l'annulation à gauche, ou en bas de la pile. En taille de texte accessible, ils s'empilent toujours.
 *
 * ```kotlin
 * BrandAlert(
 *     isPresented = problem != null,
 *     title = "Impossible d’ouvrir ce voyage",
 *     message = problem,
 *     actions = listOf(BrandAlert.Action("D’accord", BrandAlert.Role.Cancel) { problem = null }),
 *     onDismissRequest = { problem = null },
 * )
 * ```
 *
 * @param onDismissRequest le retour du système, ou un toucher hors de
 *   l'alerte. Une alerte à une seule issue la passe comme son bouton.
 */
@Composable
fun BrandAlert(
    isPresented: Boolean,
    title: String,
    actions: List<BrandAlert.Action>,
    onDismissRequest: () -> Unit,
    message: String? = null,
) {
    if (!isPresented) return
    Dialog(onDismissRequest = onDismissRequest, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        BrandAlertCard(title, message, actions)
    }
}

/** Les axes de l'alerte, sous le nom du composant (`BrandAlert.Action`). */
object BrandAlert {
    /** Le rôle d'un bouton — le `ButtonRole` de SwiftUI. */
    enum class Role {
        /** Un bouton ordinaire. */
        Default,

        /** Renoncer : en gras, à gauche de deux boutons, en bas d'une pile. */
        Cancel,

        /** Ce qui ne se défait pas : en rouge. */
        Destructive,
    }

    /** Un bouton de l'alerte. L'alerte se referme d'elle-même : [action] n'a pas à le faire. */
    data class Action(val title: String, val role: Role = Role.Default, val action: () -> Unit = {})
}

@Composable
private fun BrandAlertCard(title: String, message: String?, actions: List<BrandAlert.Action>) {
    // Comme sur iOS : côte à côte, l'annulation à gauche ; empilés, en dernier.
    val stacks = actions.size > 2 || isAccessibilityTextSize()
    val cancel = actions.filter { it.role == BrandAlert.Role.Cancel }
    val others = actions.filter { it.role != BrandAlert.Role.Cancel }
    val ordered = if (stacks) others + cancel else cancel + others
    Box(Modifier.fillMaxSize().padding(MemoBookSpacing.l), contentAlignment = Alignment.Center) {
        Column(
            Modifier
                .widthIn(max = 320.dp)
                .fillMaxWidth()
                .clip(RoundedCornerShape(MemoBookSpacing.largeCornerRadius))
                .background(MemoBookColor.surface)
                .semantics { paneTitle = title },
        ) {
            Column(
                Modifier.fillMaxWidth().padding(horizontal = MemoBookSpacing.m, vertical = MemoBookSpacing.m),
                verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                BrandText(
                    title,
                    MemoBookFont.cardTitle,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.semantics { heading() },
                )
                message?.let {
                    BrandText(it, MemoBookFont.taglineRegular, color = MemoBookColor.inkMuted, textAlign = TextAlign.Center)
                }
            }
            Box(Modifier.fillMaxWidth().heightIn(min = 1.dp).background(MemoBookColor.hairline))
            if (stacks) {
                ordered.forEachIndexed { index, action ->
                    if (index > 0) Box(Modifier.fillMaxWidth().heightIn(min = 1.dp).background(MemoBookColor.hairline))
                    BrandAlertButton(action, Modifier.fillMaxWidth())
                }
            } else {
                Row(Modifier.fillMaxWidth()) {
                    ordered.forEachIndexed { index, action ->
                        if (index > 0) Box(Modifier.widthIn(min = 1.dp).heightIn(min = MemoBookSpacing.minimumTapTarget).background(MemoBookColor.hairline))
                        BrandAlertButton(action, Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

@Composable
private fun BrandAlertButton(action: BrandAlert.Action, modifier: Modifier) {
    val color: Color = when (action.role) {
        BrandAlert.Role.Destructive -> MemoBookColor.error
        else -> MemoBookColor.action
    }
    val style = if (action.role == BrandAlert.Role.Cancel) MemoBookFont.bodySemibold else MemoBookFont.body
    Box(
        modifier
            .heightIn(min = MemoBookSpacing.minimumTapTarget)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = PlainButtonIndication,
                role = Role.Button,
                onClick = action.action,
            )
            .padding(horizontal = MemoBookSpacing.s, vertical = MemoBookSpacing.snug),
        contentAlignment = Alignment.Center,
    ) {
        BrandText(
            action.title,
            if (action.role == BrandAlert.Role.Cancel) style else style.copy(fontWeight = FontWeight.Medium),
            color = color,
            textAlign = TextAlign.Center,
        )
    }
}

@Preview(locale = "fr-rFR", name = "Alerte, deux boutons", widthDp = 390, heightDp = 300)
@Composable
private fun BrandAlertPreview() {
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.4f))) {
        BrandAlertCard(
            "Supprimer ce voyage ?",
            "Ses récits et son carnet disparaîtront pour tous les co-voyageurs.",
            listOf(
                BrandAlert.Action("Annuler", BrandAlert.Role.Cancel),
                BrandAlert.Action("Supprimer", BrandAlert.Role.Destructive),
            ),
        )
    }
}

@Preview(locale = "fr-rFR", name = "Alerte, une issue", widthDp = 390, heightDp = 260)
@Composable
private fun BrandAlertSinglePreview() {
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.4f))) {
        BrandAlertCard(
            "Impossible d’ouvrir ce voyage",
            "Ce voyage n’existe pas encore sur ton compte : il n’y a rien à ouvrir.",
            listOf(BrandAlert.Action("D’accord", BrandAlert.Role.Cancel)),
        )
    }
}
