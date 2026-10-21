package com.memobook.design

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Le bouton de l'app, repris du composant versionné du design system Figma
 * (frame « Button », node `1296:10750`). Le jumeau de `BrandButton.swift`, au
 * dessin près : ce fichier en reprend chaque mesure et chaque couleur.
 *
 * Les quatre axes du composant Figma : [style], [size], [alternate] (posé sur
 * un fond sombre), et [icon] + [iconPlacement] — ou [title] `null`.
 *
 * ```kotlin
 * BrandButton("Découvre MemoBook", icon = painterResource(R.drawable.icon_arrow_right), fillsWidth = true) { … }
 * ```
 *
 * @param title `null` donne la variante « Icon only » du design system ; poser
 *   alors [contentDescription].
 * @param icon teintée par la couleur du bouton, quelles que soient les couleurs
 *   du fichier source.
 * @param isRound la variante ronde, pour un bouton sans libellé.
 * @param alternate à activer quand le bouton est posé sur un fond sombre.
 * @param isSubdued pour un lien qui n'appelle à rien — « Besoin d'aide ? » :
 *   la taille et le gris du texte secondaire. N'a de sens qu'avec [Style.Link].
 * @param fillsWidth pour les appels à l'action pleine largeur en bas d'écran.
 * @param enabled le `.disabled` de SwiftUI : le bouton garde sa place et sa
 *   forme, mais passe au gris — « Continuer » tant que le formulaire est
 *   incomplet.
 */
// Le libellé vient avant le `modifier`, contre la règle de Compose : c'est
// l'ordre d'iOS (`BrandButton("Continuer") { … }`), et le libellé est optionnel
// parce qu'un bouton peut n'être qu'une icône.
@Suppress("ModifierParameter")
@Composable
fun BrandButton(
    title: String? = null,
    modifier: Modifier = Modifier,
    icon: Painter? = null,
    iconPlacement: BrandButton.IconPlacement = BrandButton.IconPlacement.Leading,
    style: BrandButton.Style = BrandButton.Style.Primary,
    size: BrandButton.Size = BrandButton.Size.Regular,
    isRound: Boolean = false,
    alternate: Boolean = false,
    isLoading: Boolean = false,
    isSubdued: Boolean = false,
    fillsWidth: Boolean = false,
    enabled: Boolean = true,
    contentDescription: String? = null,
    action: () -> Unit,
) {
    val metrics = BrandButton.Metrics(style, size, isRound, isIconOnly = title == null, fillsWidth)
    val colors = BrandButton.Colors(style, alternate, enabled, isSubdued)

    // Hauteur de la ligne de texte : 1,5 × 16 dans le design system. Elle suit
    // la taille de police pour que le libellé ne soit jamais rogné.
    val lineBox = scaled(24.dp)
    // La boîte de l'icône dans la mise en page, et ce qu'elle dessine : plus
    // grand, et qui en déborde. Les glyphes du jeu de marque n'occupent qu'une
    // part de leur carré de 24 ; on agrandit le dessin, la boîte reste.
    val iconSide = scaled(24.dp)
    val iconGlyphSide = scaled(28.dp)
    val minimumHeight: Dp? = when {
        style == BrandButton.Style.Link || size == BrandButton.Size.Small -> null
        size == BrandButton.Size.Medium -> scaled(MemoBookSpacing.mediumControlHeight)
        else -> scaled(MemoBookSpacing.controlHeight)
    }

    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    // Retour tactile discret : le bouton s'éteint légèrement sous le doigt.
    val pressAlpha by animateFloatAsState(if (pressed) 0.7f else 1f, tween(120), label = "press")

    val shape = RoundedCornerShape(metrics.cornerRadius)

    // Un bouton « small » ou « link » descend sous la cible tactile minimale :
    // on agrandit la zone de toucher sans toucher au dessin.
    Box(
        modifier = modifier
            .sizeIn(minWidth = MemoBookSpacing.minimumTapTarget, minHeight = MemoBookSpacing.minimumTapTarget)
            .then(if (fillsWidth) Modifier.fillMaxWidth() else Modifier)
            .clickable(
                interactionSource = interaction,
                indication = null,
                enabled = enabled && !isLoading,
                role = Role.Button,
                onClick = action,
            )
            .semantics { (title ?: contentDescription)?.let { this.contentDescription = it } },
        contentAlignment = Alignment.Center,
    ) {
        Row(
            modifier = Modifier
                .alpha(pressAlpha)
                .then(if (fillsWidth) Modifier.fillMaxWidth() else Modifier)
                .then(minimumHeight?.let { Modifier.heightIn(min = it) } ?: Modifier)
                .background(colors.background, shape)
                .then(colors.border?.let { Modifier.border(1.dp, it, shape) } ?: Modifier)
                .padding(horizontal = metrics.horizontalPadding, vertical = metrics.verticalPadding)
                .heightIn(min = lineBox),
            horizontalArrangement = Arrangement.spacedBy(metrics.gap, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val accessory: @Composable () -> Unit = {
                when {
                    isLoading -> ActivitySpinner(colors.foreground, Modifier.size(iconSide))
                    icon != null -> Box(Modifier.size(iconSide), contentAlignment = Alignment.Center) {
                        Image(
                            painter = icon,
                            contentDescription = null,
                            // Les icônes du design system sont dessinées dans une
                            // couleur figée ; c'est le bouton qui décide de leur teinte.
                            colorFilter = ColorFilter.tint(colors.foreground),
                            modifier = Modifier.requiredSize(iconGlyphSide),
                        )
                    }
                }
            }
            if (iconPlacement == BrandButton.IconPlacement.Leading) accessory()
            if (title != null) {
                BrandText(
                    text = title,
                    style = when {
                        isSubdued -> MemoBookFont.label
                        size == BrandButton.Size.Regular -> MemoBookFont.button
                        else -> MemoBookFont.buttonSmall
                    },
                    color = colors.foreground,
                    // Un appel à l'action pleine largeur a le droit de passer à
                    // la ligne ; un bouton d'appoint tient sur une ligne, quitte
                    // à rétrécir d'un cheveu, mais ne se coupe pas au milieu d'un mot.
                    maxLines = if (fillsWidth && size == BrandButton.Size.Regular) Int.MAX_VALUE else 1,
                    minimumScaleFactor = if (size == BrandButton.Size.Regular) 1f else 0.85f,
                    // Un libellé qui passe à la ligne se centre, comme le bouton entier.
                    textAlign = TextAlign.Center,
                    modifier = if (fillsWidth) Modifier.weight(1f, fill = false) else Modifier,
                )
            }
            if (iconPlacement == BrandButton.IconPlacement.Trailing) accessory()
        }
    }
}

/** Les axes du bouton, sous le nom du composant comme sur iOS (`BrandButton.Style`). */
object BrandButton {
    /** Les styles du design system, du plus au moins appuyé. */
    enum class Style {
        /** Aplat vert. Une seule action primaire par écran. */
        Primary,

        /** Contour vert sur fond blanc. */
        Secondary,

        /** Ni fond ni contour, mais garde les marges d'un bouton. */
        Tertiary,

        /** Aplat crème sans contour : les actions posées **dans** une carte blanche. */
        Soft,

        /** Pavé blanc sans contour, qui tient par son ombre — « passer au clavier » du chat. */
        Raised,

        /** Aplat lime cerclé de vert : **le bouton de l'abonnement**, un seul par écran. */
        Accent,

        /** Aplat bleu, libellé à l'encre : l'action qui fait simplement avancer. */
        Blue,

        /** Texte rouge, sans fond ni contour, aux marges d'un bouton : l'action qui défait. */
        Destructive,

        /** Texte seul, sans marges : à poser dans une phrase ou une barre. */
        Link,
    }

    enum class Size {
        Regular,

        /** Le libellé de 16 et **48 de haut** : les boutons d'appoint qui comptent. */
        Medium,
        Small,
    }

    enum class IconPlacement { Leading, Trailing }

    internal class Metrics(
        private val style: Style,
        private val size: Size,
        private val isRound: Boolean,
        private val isIconOnly: Boolean,
        private val fillsWidth: Boolean,
    ) {
        /** Un grand nombre plutôt qu'un demi-cercle calculé : la forme ramène le rayon à la moitié du côté. */
        val cornerRadius: Dp
            get() = when {
                isRound -> 9999.dp
                style == Style.Link -> 0.dp
                else -> MemoBookSpacing.controlCornerRadius
            }

        val gap: Dp get() = if (style == Style.Link) 8.dp else 12.dp

        val verticalPadding: Dp
            get() = when {
                style == Style.Link -> 0.dp
                size == Size.Regular -> 12.dp
                else -> 8.dp
            }

        val horizontalPadding: Dp
            get() = when {
                // Un bouton rond n'a qu'une marge, la même partout : c'est elle
                // qui fait le cercle plutôt qu'un ovale.
                isRound -> verticalPadding
                // Un bouton d'appoint qui remplit sa colonne n'a pas besoin de
                // la marge qui le fait respirer : la colonne s'en charge.
                fillsWidth && size != Size.Regular -> MemoBookSpacing.snug
                style == Style.Link -> 0.dp
                size == Size.Regular -> if (isIconOnly) 12.dp else 24.dp
                else -> if (isIconOnly) 8.dp else 20.dp
            }
    }

    // Le design system nomme un blanc pur pour le texte des boutons pleins ; on
    // lui préfère le blanc de la marque (`#FFFCF8`), comme sur iOS.
    internal class Colors(
        private val style: Style,
        private val alternate: Boolean,
        private val enabled: Boolean,
        private val isSubdued: Boolean,
    ) {
        /** Les styles qui posent un aplat plein : désactivés, ils gardent leur pavé et passent au gris. */
        private val isFilled get() = style == Style.Primary || style == Style.Accent

        val foreground: Color
            get() {
                if (isSubdued && enabled) return MemoBookColor.inkMuted
                if (!enabled) return if (isFilled) MemoBookColor.surface else MemoBookColor.disabled
                return when (style) {
                    Style.Primary -> if (alternate) MemoBookColor.ink else MemoBookColor.onAction
                    Style.Secondary -> if (alternate) MemoBookColor.onAction else MemoBookColor.action
                    Style.Tertiary, Style.Link, Style.Soft, Style.Raised ->
                        if (alternate) MemoBookColor.onAction else MemoBookColor.ink
                    // Le lime est clair : c'est le vert du contour qui s'y pose.
                    Style.Accent -> MemoBookColor.action
                    Style.Blue -> MemoBookColor.ink
                    // Le rouge ne s'inverse pas sur fond sombre : c'est un signal.
                    Style.Destructive -> MemoBookColor.error
                }
            }

        val background: Color
            get() {
                if (!enabled) return if (isFilled) MemoBookColor.disabled else Color.Transparent
                return when (style) {
                    Style.Primary -> if (alternate) MemoBookColor.onAction else MemoBookColor.action
                    // Le contour secondaire est posé sur un aplat blanc sur fond
                    // clair, et reste transparent en `alternate`.
                    Style.Secondary -> if (alternate) Color.Transparent else MemoBookColor.surface
                    Style.Soft -> if (alternate) MemoBookColor.onAction.copy(alpha = 0.15f) else MemoBookColor.background
                    Style.Raised -> if (alternate) MemoBookColor.onAction.copy(alpha = 0.15f) else MemoBookColor.surface
                    Style.Accent -> MemoBookColor.accent
                    Style.Blue -> MemoBookColor.outline
                    Style.Tertiary, Style.Link, Style.Destructive -> Color.Transparent
                }
            }

        val border: Color?
            get() {
                if (!enabled) return null
                return when (style) {
                    Style.Primary, Style.Secondary -> if (alternate) MemoBookColor.onAction else MemoBookColor.action
                    Style.Accent -> MemoBookColor.action
                    else -> null
                }
            }
    }
}

@Preview(name = "Boutons", widthDp = 390, heightDp = 760)
@Composable
private fun BrandButtonPreview() {
    val arrow = painterResource(R.drawable.icon_arrow_right)
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        BrandButton("Découvre MemoBook", icon = arrow, fillsWidth = true) {}
        Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            BrandButton("Primary", icon = arrow) {}
            BrandButton("Secondary", style = BrandButton.Style.Secondary) {}
        }
        Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            BrandButton("Tertiary", style = BrandButton.Style.Tertiary) {}
            BrandButton(
                "Link",
                icon = arrow,
                iconPlacement = BrandButton.IconPlacement.Trailing,
                style = BrandButton.Style.Link,
            ) {}
        }
        Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            BrandButton("Small", size = BrandButton.Size.Small) {}
            BrandButton(icon = arrow, size = BrandButton.Size.Small, contentDescription = "Suivant") {}
            BrandButton(icon = arrow, contentDescription = "Suivant") {}
            BrandButton("Chargement", isLoading = true) {}
        }
        BrandButton(
            "Découvrir l’abonnement",
            icon = arrow,
            iconPlacement = BrandButton.IconPlacement.Trailing,
            style = BrandButton.Style.Accent,
            fillsWidth = true,
        ) {}
        BrandButton("Continuer", style = BrandButton.Style.Blue, fillsWidth = true) {}
        BrandButton("Résilier mon abonnement", style = BrandButton.Style.Destructive, fillsWidth = true) {}
        BrandButton("Continuer", fillsWidth = true, enabled = false) {}
        Row(
            Modifier
                .background(MemoBookColor.surface, RoundedCornerShape(MemoBookSpacing.largeCornerRadius))
                .padding(MemoBookSpacing.s),
            horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        ) {
            BrandButton("Soft", style = BrandButton.Style.Soft) {}
            BrandButton(icon = arrow, style = BrandButton.Style.Soft, isRound = true, contentDescription = "Suivant") {}
            BrandButton(icon = arrow, style = BrandButton.Style.Secondary, isRound = true, contentDescription = "Suivant") {}
        }
    }
}
