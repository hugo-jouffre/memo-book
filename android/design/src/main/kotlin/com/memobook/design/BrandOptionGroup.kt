package com.memobook.design

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds

/**
 * Un choix unique parmi plusieurs, présenté en lignes encadrées : le motif des
 * feuilles de sélection — un moyen de paiement aujourd'hui, un style de carnet
 * ou une typographie demain. Jumeau de `BrandOptionGroup.swift`.
 *
 * À ne pas confondre avec [BrandRowGroup] : celui-ci **range** des actions et
 * les sépare d'un filet, celui-là **fait choisir** et encadre chaque option.
 * Deux motifs, deux dessins, deux composants.
 *
 * ```kotlin
 * BrandOptionGroup {
 *     cards.forEach { card ->
 *         BrandOptionRow(card.label, isSelected = card.id == selection, subtitle = card.maskedNumber) {
 *             selection = card.id
 *         }
 *     }
 * }
 * ```
 */
@Composable
fun BrandOptionGroup(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)
    Column(
        modifier
            .border(1.dp, MemoBookColor.hairline, shape)
            .padding(MemoBookSpacing.xs)
            // TalkBack lit un groupe d'options : « 2 sur 3 ».
            .selectableGroup(),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        content = content,
    )
}

/**
 * Une option d'un [BrandOptionGroup].
 *
 * @param value ce que l'option coûte, ou son état — « Inclus », « 9,90 € »,
 *   « disponible ». Posé **avant** la pastille de sélection : on lit ce qu'on
 *   choisit, puis ce que ça change, puis ce qui est coché.
 */
@Composable
fun BrandOptionRow(
    title: String,
    isSelected: Boolean,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    value: String? = null,
    action: () -> Unit,
) {
    val shape = RoundedCornerShape(MemoBookSpacing.controlCornerRadius)
    Row(
        modifier
            .selectable(
                selected = isSelected,
                interactionSource = null,
                indication = PlainButtonIndication,
                role = Role.RadioButton,
                onClick = action,
            )
            .fillMaxWidth()
            .heightIn(min = MemoBookSpacing.minimumTapTarget)
            .background(if (isSelected) MemoBookColor.outline.copy(alpha = 0.35f) else Color.Transparent, shape)
            .border(1.dp, if (isSelected) MemoBookColor.outline else MemoBookColor.hairline, shape)
            .padding(horizontal = MemoBookSpacing.s, vertical = MemoBookSpacing.s - 2.dp),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            BrandText(title, MemoBookFont.bodySemibold)
            if (subtitle != null) {
                // 0.75 rem, pas 1 : la précision se lit **sous** le titre, elle
                // ne le double pas. Les deux au même corps faisaient lire deux
                // titres par option (`option-card` des feuilles du carnet,
                // `3443:9853`, le même composant que le moyen de paiement).
                BrandText(subtitle, MemoBookFont.caption, color = MemoBookColor.inkMuted)
            }
        }
        if (value != null) {
            // Le prix ne s'enroule pas et ne se rogne pas : il cède la largeur
            // au libellé, qui sait s'enrouler. Mesuré avant lui, il prend la
            // sienne d'abord.
            BrandText(
                value,
                MemoBookFont.label.copy(fontFeatureSettings = "tnum"),
                color = MemoBookColor.inkMuted,
                maxLines = 1,
            )
        }
        SelectionMark(isSelected)
    }
}

object BrandOptionRow {
    /**
     * Le temps de voir la coche posée avant qu'une feuille de choix se referme
     * d'elle-même. Une feuille qui part à l'instant du toucher ne dit pas ce
     * qu'elle a retenu ; un tiers de seconde le dit (Hugo, 18/09/2026 — la
     * feuille « Genre », puis « Rythme du récit »).
     */
    val lingerBeforeDismiss: Duration = 350.milliseconds
}

/**
 * Le rond de sélection. Le bleu de la marque et non le vert d'action : c'est
 * le dessin de la maquette — voir « À trancher » de la fiche écran,
 * `Tokens.swift` réservant plutôt le vert à la sélection.
 */
@Composable
private fun SelectionMark(isSelected: Boolean) {
    Box(
        Modifier
            .size(scaled(22.dp))
            .border(1.5.dp, if (isSelected) MemoBookColor.blueText else MemoBookColor.separator, CircleShape)
            .clearAndSetSemantics {},
    ) {
        if (isSelected) {
            Box(
                Modifier
                    .fillMaxSize()
                    .padding(5.dp)
                    .background(MemoBookColor.blueText, CircleShape),
            )
        }
    }
}

@Preview(name = "Options", widthDp = 390)
@Composable
private fun BrandOptionGroupPreview() {
    Column(
        Modifier
            .background(MemoBookColor.surface)
            .padding(MemoBookSpacing.screenMargin),
    ) {
        BrandOptionGroup {
            BrandOptionRow("Carte business", isSelected = false, subtitle = "XXXX XXXX XXXX 3246") {}
            BrandOptionRow("Carte perso", isSelected = true, subtitle = "XXXX XXXX XXXX 1820") {}
        }
    }
}
