package com.memobook.design

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.snap
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.boundsInParent
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onPlaced
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt

/**
 * Sélecteur à segments aux couleurs de la marque. **Le** sélecteur à segments
 * de l'app (jumeau de `BrandSegmentedPicker.swift`).
 *
 * La pastille verte ne se redessine pas d'un segment à l'autre : c'est la
 * **même** pastille qui se déplace, d'un ressort, vers le segment choisi — le
 * glissé continu d'un segment natif plutôt qu'un fondu entre deux états. iOS
 * passe par `matchedGeometryEffect` ; ici, chaque segment dit où il est posé et
 * la pastille y va.
 *
 * Sur iOS 26, le rail regular prend un fond Liquid Glass. Android n'a pas de
 * verre : il garde l'aplat crème cerclé de la maquette, celui d'avant iOS 26.
 *
 * @param isAvailable ce segment mène-t-il quelque part. Un segment indisponible
 *   reste **lisible et tapable** : il pâlit, il n'est pas retiré, et son appui
 *   appelle [onUnavailable] au lieu de changer la sélection. C'est la seule
 *   façon d'expliquer *pourquoi* on ne peut pas y aller — un `disabled` avale
 *   le geste et ne dit rien (Hugo, 16/09/2026).
 * @param onUnavailable ce qu'on fait de cet appui. Poser un message, toujours :
 *   un segment qui ne répond pas se lit comme une panne.
 */
@Composable
fun <T> BrandSegmentedPicker(
    values: List<T>,
    selection: T,
    onSelectionChange: (T) -> Unit,
    modifier: Modifier = Modifier,
    size: BrandSegmentedPicker.Size = BrandSegmentedPicker.Size.Regular,
    isAvailable: (T) -> Boolean = { true },
    onUnavailable: ((T) -> Unit)? = null,
    title: (T) -> String,
) {
    val segmentHeight = scaled(if (size == BrandSegmentedPicker.Size.Regular) 50.dp else 34.dp)
    val railShape = RoundedCornerShape(if (size == BrandSegmentedPicker.Size.Regular) 25.dp else 21.dp)
    // Rayon fixe plutôt qu'une capsule : sur un seul segment de 50 les deux se
    // confondent, mais dès que le libellé passe à deux lignes la capsule
    // devient une ellipse.
    val pillShape = RoundedCornerShape(if (size == BrandSegmentedPicker.Size.Regular) 21.dp else 17.dp)
    val reduceMotion = isReduceMotionEnabled()
    // Aux tailles de texte accessibles, deux libellés côte à côte ne tiennent
    // plus : les segments s'empilent, et la pastille glisse verticalement.
    val isStacked = isAccessibilityTextSize()

    // Où chaque segment est posé, et la pastille qui va de l'un à l'autre.
    val bounds = remember { mutableStateMapOf<Int, Rect>() }
    val pill = remember { Animatable(Rect.Zero, Rect.VectorConverter) }
    var pillIndex by remember { mutableIntStateOf(-1) }
    val selectedIndex = values.indexOf(selection)
    val target = bounds[selectedIndex]
    LaunchedEffect(target, selectedIndex, reduceMotion) {
        if (target == null) return@LaunchedEffect
        // Elle glisse quand la sélection change, et seulement alors : un rail
        // qui change de largeur la déplace d'un coup, comme dans SwiftUI.
        if (pillIndex < 0 || pillIndex == selectedIndex || reduceMotion) {
            pill.snapTo(target)
        } else {
            pill.animateTo(target, SwiftMotion.snappy(0.35f, extraBounce = 0.1f))
        }
        pillIndex = selectedIndex
    }

    val segments: @Composable (Modifier) -> Unit = { share ->
        values.forEachIndexed { index, value ->
            val available = isAvailable(value)
            val selected = value == selection
            val foreground by animateColorAsState(
                if (selected) MemoBookColor.onAction else MemoBookColor.ink,
                if (reduceMotion) snap() else SwiftMotion.snappy(0.35f, extraBounce = 0.1f),
                label = "libellé",
            )
            Box(
                share
                    .onPlaced { bounds[index] = it.boundsInParent() }
                    .selectable(
                        selected = selected,
                        interactionSource = null,
                        indication = PlainButtonIndication,
                        role = Role.Tab,
                    ) {
                        // Un segment fermé **ne change pas la sélection** : il explique.
                        if (available) onSelectionChange(value) else onUnavailable?.invoke(value)
                    }
                    // TalkBack doit l'entendre avant de taper, pas après :
                    // « non disponible » suit le libellé.
                    .semantics { if (!available) stateDescription = "Non disponible" }
                    .heightIn(min = segmentHeight)
                    .padding(horizontal = MemoBookSpacing.xs),
                contentAlignment = Alignment.Center,
            ) {
                BrandText(
                    title(value),
                    if (size == BrandSegmentedPicker.Size.Regular) MemoBookFont.button else MemoBookFont.tagline,
                    // Pâli, pas effacé : il faut encore pouvoir le lire pour
                    // comprendre le message qu'il pose.
                    Modifier.alpha(if (available) 1f else 0.4f),
                    color = foreground,
                    // Un libellé trop long **passe à la ligne**, il ne se coupe
                    // pas : en taille accessible, « 1re de couvert… » deux fois
                    // ne se distinguaient plus l'une de l'autre.
                    textAlign = TextAlign.Center,
                )
            }
        }
    }

    Box(
        modifier
            .then(
                if (size == BrandSegmentedPicker.Size.Regular) {
                    Modifier
                        .background(MemoBookColor.background, railShape)
                        .border(1.dp, MemoBookColor.ink, railShape)
                } else {
                    // Le rail compact garde son aplat blanc et le filet discret :
                    // il range le contenu, il ne l'annonce pas — une bordure à
                    // l'encre y ferait un cadre.
                    Modifier
                        .background(MemoBookColor.surface, railShape)
                        .border(1.dp, MemoBookColor.hairline, railShape)
                },
            )
            .padding(4.dp)
            // TalkBack annonce un sélecteur, pas des boutons sans lien entre eux.
            .selectableGroup(),
    ) {
        if (pillIndex >= 0 && selectedIndex >= 0) {
            Box(
                Modifier
                    // La pastille ne pèse rien dans la mise en page : elle se
                    // pose où est le segment choisi, à sa taille.
                    .layout { measurable, _ ->
                        val frame = pill.value
                        val placeable = measurable.measure(
                            Constraints.fixed(frame.width.roundToInt().coerceAtLeast(0), frame.height.roundToInt().coerceAtLeast(0)),
                        )
                        layout(0, 0) { placeable.place(frame.left.roundToInt(), frame.top.roundToInt()) }
                    }
                    .background(MemoBookColor.action, pillShape),
            )
        }
        if (isStacked) {
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                segments(Modifier.fillMaxWidth())
            }
        } else {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                segments(Modifier.weight(1f))
            }
        }
    }
}

object BrandSegmentedPicker {
    /** Les deux tailles du rail. */
    enum class Size {
        /** Le rail pleine page : deux libellés en typographie de bouton, 50 de haut. Celui de l'écran d'entrée. */
        Regular,

        /**
         * Le rail posé **dans** un écran, au-dessus de ce qu'il commande : les
         * deux plats de couverture. Plus bas, plus léger, cerclé du filet
         * discret plutôt que de l'encre.
         */
        Compact,
    }
}

@Preview(locale = "fr-rFR", name = "Sélecteur à segments", widthDp = 390)
@Composable
private fun BrandSegmentedPickerPreview() {
    var selection by remember { mutableStateOf("Inscription") }
    var cover by remember { mutableStateOf("1re de couverture") }
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
    ) {
        BrandSegmentedPicker(listOf("Inscription", "Connexion"), selection, { selection = it }) { it }
        BrandSegmentedPicker(
            listOf("1re de couverture", "4e de couverture"),
            cover,
            { cover = it },
            size = BrandSegmentedPicker.Size.Compact,
            isAvailable = { it != "4e de couverture" },
            onUnavailable = {},
        ) { it }
    }
}
