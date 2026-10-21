package com.memobook.design

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp

/**
 * Une carte à interrupteur : ce que l'option ajoute, et sa bascule. Jumeau de
 * `BrandToggleCard.swift`.
 *
 * À ne pas confondre avec la ligne à interrupteur de [BrandRowGroup] : celle-là
 * **nomme** un réglage sur une ligne, celle-ci l'**explique** sur deux ou trois.
 * C'est le dessin que la maquette donne aux extras du carnet, aux quatre
 * alertes d'un voyage, et aux deux feuilles « Fun Facts » et « Pointillés ».
 *
 * ```kotlin
 * BrandToggleCard(
 *     title = "Rappel d’écriture",
 *     detail = "Alerte selon le rythme du récit choisi",
 *     isOn = wantsWritingReminder,
 *     onIsOnChange = { wantsWritingReminder = it },
 * )
 * ```
 *
 * @param isAvailable l'option peut-elle basculer. Indisponible, la carte
 *   **pâlit et reste tapable** : l'appui appelle [onUnavailable] au lieu de
 *   basculer — même contrat que [BrandSegmentedPicker] : un `disabled` avale le
 *   geste et n'explique rien.
 * @param onUnavailable ce qu'on fait de cet appui. Poser un message, toujours.
 */
@Composable
fun BrandToggleCard(
    title: String,
    detail: String,
    isOn: Boolean,
    onIsOnChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    isAvailable: Boolean = true,
    onUnavailable: (() -> Unit)? = null,
) {
    val shape = RoundedCornerShape(MemoBookSpacing.snug)
    val unavailable = if (isAvailable) {
        Modifier
    } else {
        // Toute la carte répond, l'interrupteur compris : il ne prend plus le
        // doigt, c'est elle qui le reçoit. TalkBack y lit un seul bouton.
        Modifier
            .clickable(
                interactionSource = null,
                indication = PlainButtonIndication,
                role = Role.Button,
            ) { onUnavailable?.invoke() }
            .semantics(mergeDescendants = true) {
                stateDescription = if (isOn) "Activé, non disponible" else "Désactivé, non disponible"
            }
    }
    Box(
        modifier
            .then(unavailable)
            .fillMaxWidth()
            .background(MemoBookColor.surface, shape)
            // Figma dessine #E6DAD0, un beige ; `hairline` est l'encre à 10 %,
            // qui tombe à #E6DFD8 sur le crème. Trois points d'écart sur un
            // canal : on garde le token plutôt qu'une sixième valeur de filet.
            .border(1.dp, MemoBookColor.hairline, shape)
            .padding(MemoBookSpacing.s),
    ) {
        // Le contenu pâlit, pas la carte : son aplat et son filet restent ceux
        // des autres, elle est toujours là.
        val content = Modifier.alpha(if (isAvailable) 1f else 0.45f)
        val switch: @Composable () -> Unit = {
            BrandSwitch(
                isOn = isOn,
                // Indisponible, il ne bascule pas sous le doigt : un
                // interrupteur qui glisse puis revient se lirait comme un
                // réglage qui n'a pas pris.
                onIsOnChange = if (isAvailable) onIsOnChange else null,
                contentDescription = title,
            )
        }
        // En taille accessible, l'interrupteur passe **sous** le texte : à côté
        // d'un paragraphe de trois lignes, il ne laisse plus que deux mots par
        // ligne.
        if (isAccessibilityTextSize()) {
            Column(content, verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
                ToggleCardText(title, detail, Modifier.fillMaxWidth())
                switch()
            }
        } else {
            Row(
                content,
                horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                ToggleCardText(title, detail, Modifier.weight(1f))
                switch()
            }
        }
    }
}

@Composable
private fun ToggleCardText(title: String, detail: String, modifier: Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        BrandText(title, MemoBookFont.bodySemibold)
        // 14 et non 12 : ce détail porte une **phrase entière** — ce que l'extra
        // ajoute au carnet —, et la légende de 12 est réservée à ce qui se lit
        // d'un coup d'œil (Hugo, 16/09/2026).
        BrandText(detail, MemoBookFont.taglineRegular, color = MemoBookColor.inkMuted)
    }
}

/**
 * L'interrupteur de l'app : le `UISwitch` d'iOS, redessiné, puisque Compose
 * Foundation n'en a pas et que celui de Material ne se pose pas ici. Ses
 * mesures sont celles du système — un rail de 51 × 31, une pastille blanche de
 * 27 à 2 du bord, le vert d'action allumé — et il ne suit pas la taille de
 * texte, comme sur iOS. Il bascule au toucher et au glissé, et TalkBack
 * l'annonce « activé » ou « désactivé ».
 *
 * Partagé par [BrandToggleCard] et la ligne à interrupteur de [BrandRowGroup].
 *
 * @param onIsOnChange `null` : il ne prend plus le doigt — une carte indisponible.
 * @param isTapTarget `false` quand c'est la ligne entière qui bascule le réglage
 *   et porte l'annonce : l'interrupteur ne répond plus qu'au glissé.
 * @param contentDescription ce que TalkBack nomme, quand il est sa propre cible.
 */
@Composable
internal fun BrandSwitch(
    isOn: Boolean,
    onIsOnChange: ((Boolean) -> Unit)?,
    modifier: Modifier = Modifier,
    isTapTarget: Boolean = true,
    contentDescription: String? = null,
) {
    val progress by animateFloatAsState(if (isOn) 1f else 0f, SwiftMotion.smooth(0.3f), label = "interrupteur")
    val currentIsOn by rememberUpdatedState(isOn)
    val currentOnChange by rememberUpdatedState(onIsOnChange)

    val input = when {
        onIsOnChange == null || !isTapTarget -> Modifier.clearAndSetSemantics {}
        else -> Modifier
            .toggleable(
                value = isOn,
                interactionSource = null,
                indication = null,
                role = Role.Switch,
                onValueChange = onIsOnChange,
            )
            .semantics { contentDescription?.let { this.contentDescription = it } }
    }
    // Le glissé de la pastille : il bascule dès que le doigt a parcouru la
    // moitié de la course, dans le sens qui change quelque chose.
    val drag = if (onIsOnChange == null) {
        Modifier
    } else {
        Modifier.pointerInput(Unit) {
            val half = (SwitchWidth - SwitchKnob - SwitchInset * 2).toPx() / 2
            var travelled = 0f
            detectHorizontalDragGestures(onDragStart = { travelled = 0f }) { change, amount ->
                change.consume()
                travelled += amount
                if (travelled > half && !currentIsOn) {
                    travelled = 0f
                    currentOnChange?.invoke(true)
                } else if (travelled < -half && currentIsOn) {
                    travelled = 0f
                    currentOnChange?.invoke(false)
                }
            }
        }
    }

    Box(
        modifier
            .then(input)
            .then(drag)
            .size(SwitchWidth, SwitchHeight)
            .background(lerp(SwitchOffTrack, MemoBookColor.action, progress), CircleShape),
    ) {
        Box(
            Modifier
                .offset {
                    val travel = (SwitchWidth - SwitchKnob - SwitchInset * 2).toPx()
                    IntOffset((SwitchInset.toPx() + travel * progress).toInt(), SwitchInset.roundToPx())
                }
                .size(SwitchKnob)
                // L'ombre du système sous la pastille, pas une ombre de la
                // marque : c'est le dessin du `UISwitch`, repris tel quel.
                .dropShadow(CircleShape, Shadow(radius = 8.dp, color = Color.Black.copy(alpha = 0.15f), offset = DpOffset(0.dp, 3.dp)))
                .dropShadow(CircleShape, Shadow(radius = 1.dp, color = Color.Black.copy(alpha = 0.06f), offset = DpOffset(0.dp, 3.dp)))
                .background(Color.White, CircleShape),
        )
    }
}

private val SwitchWidth = 51.dp
private val SwitchHeight = 31.dp
private val SwitchKnob = 27.dp
private val SwitchInset = 2.dp

/** Le rail éteint du `UISwitch` : le gris de remplissage du système (#787880 à 16 %), repris tel quel. */
private val SwitchOffTrack = Color(0x29787880)

@Preview(name = "Carte à interrupteur", widthDp = 390)
@Composable
private fun BrandToggleCardPreview() {
    var isOn by remember { mutableStateOf(true) }
    Column(
        Modifier
            .background(MemoBookColor.surface)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug),
    ) {
        BrandToggleCard(
            title = "Insérer des fun facts",
            detail = "Encarts de culture générale toutes les 3 pages pour agrémenter tes récits.",
            isOn = isOn,
            onIsOnChange = { isOn = it },
        )
        BrandToggleCard(
            title = "Rappel d’écriture",
            detail = "Alerte selon le rythme du récit choisi",
            isOn = isOn,
            onIsOnChange = { isOn = it },
        )
        BrandToggleCard(
            title = "Pointillés",
            detail = "Lignes en pointillé sous le texte dans ton carnet",
            isOn = false,
            onIsOnChange = {},
            isAvailable = false,
            onUnavailable = {},
        )
    }
}
