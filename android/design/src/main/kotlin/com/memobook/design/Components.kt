package com.memobook.design

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

// Le jumeau de `Components.swift`, moins `StatusBadge` et `EmptyStateView` :
// sur iOS, seuls `MemoList/` et `MemoDetail/` s'en servent, et ces écrans ne se
// portent pas (docs/android.md, « Ce qui ne se porte pas »).

/**
 * Message d'erreur avec possibilité de réessayer, plutôt qu'une alerte
 * modale : l'utilisateur garde le contexte de l'écran.
 *
 * @param message ce qui s'est passé, en une phrase.
 * @param advice ce qu'on peut **faire** — la phrase qui suit le constat
 *   (`APIError.recoveryAdvice`). « Erreur interne du serveur » laissait le
 *   voyageur chercher ce qu'il avait mal fait (Hugo, 15/09/2026).
 * @param retry relance ce qui a échoué.
 * @param help ouvre le support — la porte de sortie quand réessayer ne suffit pas.
 */
@Composable
fun ErrorBanner(
    message: String,
    modifier: Modifier = Modifier,
    advice: String? = null,
    retry: (() -> Unit)? = null,
    help: (() -> Unit)? = null,
) {
    val container = modifier
        .fillMaxWidth()
        .background(MemoBookColor.error.copy(alpha = 0.1f), RoundedCornerShape(MemoBookSpacing.cornerRadius))
        .padding(MemoBookSpacing.s)

    if (advice == null && help == null) {
        // Une ligne : le constat, et « Réessayer » au bout.
        Row(container, horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
            ErrorMark()
            BrandText(message, MemoBookFont.notification, Modifier.weight(1f))
            retry?.let { ErrorLink("Réessayer", it) }
        }
    } else {
        // Le constat, le conseil dessous, et les gestes sur leur propre ligne :
        // une phrase de conseil ne tient pas au bout d'une ligne.
        Column(container, verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs), verticalAlignment = Alignment.Top) {
                ErrorMark()
                BrandText(message, MemoBookFont.notification, Modifier.weight(1f))
            }
            advice?.let { BrandText(it, MemoBookFont.caption, color = MemoBookColor.inkMuted) }
            if (retry != null || help != null) {
                Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
                    retry?.let { ErrorLink("Réessayer", it) }
                    help?.let { ErrorLink("Besoin d’aide ?", it) }
                }
            }
        }
    }
}

@Composable
private fun ErrorMark() {
    Image(
        painter = painterResource(R.drawable.system_exclamation_triangle),
        contentDescription = null,
        colorFilter = ColorFilter.tint(MemoBookColor.error),
        modifier = Modifier.size(20.dp),
    )
}

/** Un lien du bandeau : le corps du message, au vert d'action — le `Button` nu de SwiftUI, teinté. */
@Composable
private fun ErrorLink(title: String, action: () -> Unit) {
    BrandText(
        text = title,
        style = MemoBookFont.notification,
        color = MemoBookColor.action,
        modifier = Modifier
            .sizeIn(minHeight = MemoBookSpacing.minimumTapTarget)
            .clickable(role = Role.Button, onClick = action)
            .wrapContentHeight(),
    )
}

/**
 * Fait **fondre** une bande qui défile sur ses deux bords, au lieu de la
 * trancher net : une pastille pleine coupée à la verticale se lit comme un
 * défaut de rendu, une pastille qui s'efface en sortant comme un débordement.
 *
 * @param width la largeur du fondu, de chaque côté.
 */
fun Modifier.brandHorizontalFade(width: Dp = MemoBookSpacing.s): Modifier = this
    .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)
    .drawWithContent {
        drawContent()
        val edge = (width.toPx() / size.width).coerceIn(0f, 0.5f)
        drawRect(
            brush = Brush.horizontalGradient(
                0f to Color.Transparent,
                edge to Color.Black,
                1f - edge to Color.Black,
                1f to Color.Transparent,
            ),
            blendMode = BlendMode.DstIn,
        )
    }

@Preview(name = "Bandeaux d'erreur", widthDp = 390)
@Composable
private fun ErrorBannerPreview() {
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        ErrorBanner("Connexion impossible.", retry = {})
        ErrorBanner(
            "Le serveur ne répond pas.",
            advice = "La panne est chez nous : réessaie dans quelques minutes.",
            retry = {},
            help = {},
        )
    }
}
