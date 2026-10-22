package com.memobook.feature.covers

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.memobook.core.BookCopy
import com.memobook.core.BookCovers
import com.memobook.core.CoverStat
import com.memobook.design.BrandButton
import com.memobook.design.BrandSheet
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.SwiftMotion
import com.memobook.design.isAccessibilityTextSize
import com.memobook.design.scaled
import kotlinx.coroutines.runBlocking

/**
 * Le choix des chiffres qui s'impriment au dos du carnet. Jumeau de
 * `Covers/CoverStatsSheet.swift`.
 *
 * Ouverte par le crayon posé sur le bandeau « Mon voyage en quelques chiffres »
 * de la quatrième de couverture — c'est le seul endroit de l'app qui y mène, et
 * c'est le bon : on règle un bloc en le regardant.
 *
 * **C'est la version 2 de la maquette** : le chiffre en gros au-dessus de son
 * libellé, six cartes en grille. Elle reprend exactement la composition du
 * bandeau imprimé, là où la version 1 alignait des lignes de réglage — et
 * choisir ce qui va sur un plat en lisant une liste, c'est choisir à l'aveugle.
 *
 * La sélection est bornée à trois ou quatre — voir `BookCovers.statRange`. La
 * contrainte vient du gabarit : sous trois, le bandeau a des colonnes vides ;
 * au-delà de quatre, les chiffres ne sont plus lisibles à la taille imprimée.
 *
 * @param onDismiss la feuille se referme, après « Valider » — le `dismiss()` d'iOS.
 */
@Composable
internal fun CoverStatsSheet(model: CoversModel, onDismiss: () -> Unit) {
    // Le brouillon. La feuille ne pose rien tant qu'on n'a pas validé : on doit
    // pouvoir en décocher un pour en essayer un autre sans que le plat change
    // trois fois derrière.
    var selection by remember { mutableStateOf(model.covers?.back?.statIds ?: emptyList()) }
    val stats = model.covers?.stats ?: emptyList()

    // Deux colonnes, comme la maquette — une seule en taille accessible, où
    // « personnes rencontrées » sur une demi-largeur tiendrait en quatre lignes
    // de deux syllabes.
    val columns = if (isAccessibilityTextSize()) 1 else 2

    /**
     * Coche ou décoche, en gardant **l'ordre de sélection**.
     *
     * C'est cet ordre-là qui s'imprime, de gauche à droite : quelqu'un qui
     * choisit d'abord les kilomètres veut les voir en premier sur le plat.
     */
    fun toggle(stat: CoverStat) {
        selection = when {
            stat.id in selection -> selection - stat.id
            selection.size < BookCovers.statRange.last -> selection + stat.id
            else -> selection
        }
    }

    BrandSheet(BookCopy.Covers.Stats.title, subtitle = BookCopy.Covers.Stats.message) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
            Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
                stats.chunked(columns).forEach { row ->
                    Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
                        row.forEach { stat ->
                            val isSelected = stat.id in selection
                            CoverStatCard(
                                stat,
                                isSelected = isSelected,
                                isSelectable = isSelected || selection.size < BookCovers.statRange.last,
                                modifier = Modifier.weight(1f).fillMaxHeight(),
                            ) {
                                toggle(stat)
                            }
                        }
                        // La dernière ligne garde sa grille : une carte seule ne
                        // s'étire pas sur toute la largeur.
                        repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }

            // En dessous de trois, le bandeau imprimé aurait des colonnes vides :
            // le bouton attend plutôt que d'accepter et de rogner.
            BrandButton(BookCopy.Covers.validate, fillsWidth = true, enabled = selection.size in BookCovers.statRange) {
                model.setStats(selection)
                onDismiss()
            }
        }
    }
}

/**
 * Une carte de chiffre : la valeur, son libellé, et le rond qui dit si elle part
 * à l'impression.
 *
 * @param isSelectable `false` quand quatre chiffres sont déjà retenus et que
 *   celui-ci n'en fait pas partie. La carte reste **lisible** et cesse d'être
 *   touchable : la masquer ferait disparaître la moitié de la grille à la
 *   quatrième coche.
 */
@Composable
private fun CoverStatCard(stat: CoverStat, isSelected: Boolean, isSelectable: Boolean, modifier: Modifier = Modifier, action: () -> Unit) {
    val shape = RoundedCornerShape(MemoBookSpacing.snug)
    val fill by animateColorAsState(
        if (isSelected) MemoBookColor.listeningBackground.copy(alpha = 0.5f) else MemoBookColor.surface,
        SwiftMotion.snappy(0.2f),
        label = "carte",
    )

    Row(
        modifier
            .heightIn(min = MemoBookSpacing.xl * 2)
            .toggleable(
                value = isSelected,
                enabled = isSelectable,
                role = Role.Checkbox,
                interactionSource = null,
                indication = PlainButtonIndication,
                onValueChange = { action() },
            )
            // Le chiffre et son libellé d'une traite ; coché, non coché et
            // indisponible viennent de `toggleable`.
            .clearAndSetSemantics { contentDescription = "${stat.value} ${stat.label.replace("\n", " ")}" }
            // Une carte qu'on ne peut plus cocher reste lisible, mais se voit :
            // sans ce gris, on tape dessus sans comprendre pourquoi rien ne se
            // passe.
            .alpha(if (isSelectable) 1f else 0.45f)
            .background(fill, shape)
            .border(1.dp, if (isSelected) MemoBookColor.outline else MemoBookColor.hairline, shape)
            .padding(MemoBookSpacing.snug),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        verticalAlignment = Alignment.Top,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            // Un chiffre tient sur une ligne — « 2,3k » ne se coupe pas (Clara,
            // 17/09/2026).
            BrandText(stat.value, MemoBookFont.figure, maxLines = 1, minimumScaleFactor = 0.7f)
            BrandText(stat.label, MemoBookFont.taglineRegular)
        }

        RadioMark(isOn = isSelected)
    }
}

/**
 * Le rond de sélection de la maquette.
 *
 * Ce n'est pas un interrupteur : ces cartes forment un choix **multiple borné**,
 * et un interrupteur dirait « active ceci » là où il faut lire « celui-ci part à
 * l'impression, et il y en a quatre au plus ».
 */
@Composable
private fun RadioMark(isOn: Boolean) {
    val side = scaled(20.dp)
    Box(
        Modifier
            .size(side)
            .border(if (isOn) 1.5.dp else 1.dp, if (isOn) MemoBookColor.blueText else MemoBookColor.disabledOutline, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        if (isOn) Box(Modifier.size(side / 2).background(MemoBookColor.blueText, CircleShape))
    }
}

@Preview(locale = "fr-rFR", name = "Choix des statistiques", widthDp = 390)
@Composable
private fun CoverStatsSheetPreview() {
    // Le modèle est chargé avant d'ouvrir la feuille : celle-ci lit les chiffres
    // à l'apparition, et la grille serait vide sans ça.
    val model = remember { CoversModel(tripId = "trip-rome").also { runBlocking { it.load() } } }
    CoverStatsSheet(model, onDismiss = {})
}
