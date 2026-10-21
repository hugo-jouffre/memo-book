package com.memobook.design

import androidx.compose.animation.Crossfade
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import com.memobook.core.ShippingCountry

/**
 * Le champ « Pays » : un choix dans la liste que **le serveur** sert, jamais un
 * texte libre. Jumeau de `BrandCountryField.swift`.
 *
 * La liste suit l'imprimeur, pas nos livraisons ([ShippingCountry]). Un champ
 * libre laisserait écrire « Monaco » dans une adresse où le carnet ne partira
 * jamais — et « FRANCE », « France », « Fr » pour le même pays. Le tunnel de
 * commande et la feuille « Adresse postale » du profil le partagent.
 *
 * Il a le dessin d'un [BrandTextField] à intitulé au-dessus — même intitulé,
 * même cadre, même hauteur —, pour se poser dans la colonne sans qu'on voie
 * qu'il n'est pas un champ de saisie. Le double chevron dit « ça se choisit »
 * là où le curseur dirait « ça se tape ».
 *
 * Un code qui n'est pas dans la liste — l'adresse d'un profil enregistré avant
 * elle — s'affiche tel quel, en gris : c'est ce que la personne avait écrit, et
 * le menu l'invite à choisir un pays livrable. Une valeur vide montre « Choisir
 * un pays », en texte indicatif.
 *
 * Le menu du système d'iOS devient ici un menu de marque posé sous le champ :
 * Compose Foundation n'en a pas.
 *
 * @param countries la liste servie par le serveur, dans son ordre.
 * @param code le code ISO 3166-1 alpha-2 choisi.
 * @param label l'intitulé au-dessus du cadre. « Pays » partout pour l'instant,
 *   mais c'est l'écran qui le dit, comme pour tout champ.
 */
@Composable
fun BrandCountryField(
    countries: List<ShippingCountry>,
    code: String,
    onCodeChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    label: String = "Pays",
) {
    val height = scaled(MemoBookSpacing.fieldHeight)
    val chevronSide = scaled(20.dp)
    val shape = RoundedCornerShape(MemoBookSpacing.controlCornerRadius)
    val display = countryDisplay(countries, code)
    // Sans liste, il n'y a rien à choisir : le serveur ne l'a pas envoyée, et un
    // menu vide s'ouvrirait sur rien.
    val isAvailable = countries.isNotEmpty()
    var isOpen by remember { mutableStateOf(false) }
    var fieldWidth by remember { mutableIntStateOf(0) }

    Column(modifier, verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
        // Le menu porte déjà ce mot pour TalkBack.
        BrandText(label, MemoBookFont.bodySemibold, Modifier.clearAndSetSemantics {})

        Box {
            Row(
                Modifier
                    .fillMaxWidth()
                    .height(height)
                    .onSizeChanged { fieldWidth = it.width }
                    .alpha(if (isAvailable) 1f else 0.45f)
                    .border(1.dp, MemoBookColor.separator, shape)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        enabled = isAvailable,
                        role = Role.DropdownList,
                    ) { isOpen = true }
                    .semantics {
                        contentDescription = label
                        stateDescription = if (display.isPlaceholder) "Aucun" else display.text
                    }
                    .padding(horizontal = 20.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Le nom change en fondu quand on choisit, comme une valeur qui
                // s'écrit — pas d'un coup sec.
                Crossfade(display, Modifier.weight(1f), animationSpec = SwiftUISpring.snappy(200), label = "pays") { shown ->
                    BrandText(
                        shown.text,
                        // Le texte indicatif prend le dessin de celui d'un
                        // `BrandTextField` ; une valeur, celui d'une valeur.
                        if (shown.isPlaceholder) MemoBookFont.bodySemibold else MemoBookFont.body,
                        Modifier.clearAndSetSemantics {},
                        color = if (shown.isPlaceholder || !shown.isKnown) MemoBookColor.inkMuted else MemoBookColor.ink,
                        maxLines = 1,
                    )
                }
                Spacer(Modifier.width(MemoBookSpacing.xs))
                // `chevron.up.chevron.down` d'iOS, redessiné.
                Image(
                    painter = painterResource(R.drawable.system_chevron_up_chevron_down),
                    contentDescription = null,
                    colorFilter = ColorFilter.tint(MemoBookColor.inkMuted),
                    modifier = Modifier.size(chevronSide),
                )
            }

            if (isOpen) {
                CountryMenu(
                    label = label,
                    countries = countries,
                    code = code,
                    width = with(LocalDensity.current) { fieldWidth.toDp() },
                    onPick = { picked ->
                        onCodeChange(picked)
                        isOpen = false
                    },
                    onDismiss = { isOpen = false },
                )
            }
        }
    }
}

/** Ce que le cadre écrit : le nom du pays choisi, le code inconnu tel quel, ou l'invitation à choisir. */
private data class CountryDisplay(val text: String, val isPlaceholder: Boolean, val isKnown: Boolean)

private fun countryDisplay(countries: List<ShippingCountry>, code: String): CountryDisplay {
    countries.firstOrNull { it.code == code }?.let { return CountryDisplay(it.name, isPlaceholder = false, isKnown = true) }
    val raw = code.trim()
    return if (raw.isEmpty()) {
        CountryDisplay("Choisir un pays", isPlaceholder = true, isKnown = false)
    } else {
        CountryDisplay(raw, isPlaceholder = false, isKnown = false)
    }
}

/** La liste, sous le champ et à sa largeur ; la coche au vert d'action, le `.tint` du menu d'iOS. */
@Composable
private fun CountryMenu(
    label: String,
    countries: List<ShippingCountry>,
    code: String,
    width: Dp,
    onPick: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val density = LocalDensity.current
    val margin = MemoBookSpacing.snug
    val position = remember(density) {
        with(density) { BelowTheField(margin = margin.roundToPx(), gap = MemoBookSpacing.xs.roundToPx()) }
    }
    val shape = RoundedCornerShape(MemoBookSpacing.cornerRadius)
    val checkSide = scaled(20.dp)
    Popup(popupPositionProvider = position, onDismissRequest = onDismiss, properties = PopupProperties(focusable = true)) {
        Column(
            Modifier
                // De quoi laisser l'ombre se poser dans la fenêtre du menu.
                .padding(margin)
                .width(width)
                .heightIn(max = DeviceScreen.height() / 2)
                .brandShadow(MemoBookShadow.Raised, shape)
                .clip(shape)
                .background(MemoBookColor.surface)
                .semantics { paneTitle = label }
                .verticalScroll(rememberScrollState()),
        ) {
            countries.forEach { country ->
                val isSelected = country.code == code
                Row(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = MemoBookSpacing.minimumTapTarget)
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            role = Role.Button,
                        ) { onPick(country.code) }
                        .semantics(mergeDescendants = true) { selected = isSelected }
                        .padding(horizontal = MemoBookSpacing.s),
                    horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.size(checkSide), contentAlignment = Alignment.Center) {
                        if (isSelected) {
                            Image(
                                painter = painterResource(R.drawable.icon_lucide_check),
                                contentDescription = null,
                                colorFilter = ColorFilter.tint(MemoBookColor.action),
                                modifier = Modifier.size(checkSide),
                            )
                        }
                    }
                    BrandText(country.name, MemoBookFont.body)
                }
            }
        }
    }
}

/** Le menu sous le champ, ou au-dessus s'il n'y tient pas ; la marge est celle de l'ombre. */
private class BelowTheField(private val margin: Int, private val gap: Int) : PopupPositionProvider {
    override fun calculatePosition(
        anchorBounds: IntRect,
        windowSize: IntSize,
        layoutDirection: LayoutDirection,
        popupContentSize: IntSize,
    ): IntOffset {
        val below = anchorBounds.bottom + gap - margin
        val above = anchorBounds.top - gap - popupContentSize.height + margin
        val y = if (below + popupContentSize.height <= windowSize.height || above < 0) below else above
        return IntOffset(anchorBounds.left - margin, y)
    }
}

@Preview(name = "Pays", widthDp = 390, heightDp = 360)
@Composable
private fun BrandCountryFieldPreview() {
    val countries = listOf(
        ShippingCountry(code = "FR", name = "France"),
        ShippingCountry(code = "BE", name = "Belgique"),
        ShippingCountry(code = "CH", name = "Suisse"),
    )
    var code by remember { mutableStateOf("FR") }
    var legacy by remember { mutableStateOf("Monaco") }
    var empty by remember { mutableStateOf("") }
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        BrandCountryField(countries, code, { code = it })
        BrandCountryField(countries, legacy, { legacy = it })
        BrandCountryField(countries, empty, { empty = it })
    }
}
