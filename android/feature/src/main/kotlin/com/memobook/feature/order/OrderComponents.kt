package com.memobook.feature.order

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.memobook.core.OrderContext
import com.memobook.core.Trip
import com.memobook.design.BrandSkeleton
import com.memobook.design.BrandSwitch
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookShadow
import com.memobook.design.MemoBookSpacing
import com.memobook.design.SwiftMotion
import com.memobook.design.brandShadow
import com.memobook.design.isAccessibilityTextSize
import com.memobook.design.isReduceMotionEnabled
import com.memobook.feature.home.TripCover
import com.memobook.feature.home.dateRangeLabel
import com.memobook.feature.profile.euros
import java.math.BigDecimal

// Les pièces que plusieurs étapes du tunnel se partagent. Le jumeau de
// `Order/OrderComponents.swift`. Rien ici ne décide de quoi que ce soit : ce
// sont des dessins, pilotés par ce qu'on leur passe.

// MARK: - L'intitulé d'une section

/** Le titre d'une étape, et la phrase qui l'explique quand il y en a une. */
@Composable
internal fun OrderSectionHeader(title: String, modifier: Modifier = Modifier, subtitle: String? = null) {
    // Le titre s'enroule au lieu de se faire rogner : en taille accessible,
    // « Vérifications finales avant impression » tient sur trois lignes.
    Column(
        modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) { heading() },
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        BrandText(title, MemoBookFont.h2)
        if (subtitle != null) {
            BrandText(subtitle, MemoBookFont.h3, color = MemoBookColor.inkMuted)
        }
    }
}

// MARK: - Une ligne de prix

/**
 * Un libellé à gauche, un montant à droite. Le motif de tout le
 * récapitulatif, et de la ligne « Prix unitaire ».
 *
 * @param detail « x2 », posé entre le libellé et le montant.
 * @param amount `null` tant que le montant n'est pas arrivé : un squelette tient sa place.
 */
@Composable
internal fun OrderPriceRow(
    label: String,
    modifier: Modifier = Modifier,
    detail: String? = null,
    amount: BigDecimal? = null,
    isProminent: Boolean = false,
) {
    val merged = modifier
        .fillMaxWidth()
        .semantics(mergeDescendants = true) {}
    // Côte à côte ils n'auraient plus que deux mots de large chacun en taille
    // accessible : ils s'empilent.
    if (isAccessibilityTextSize()) {
        Column(merged, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            OrderPriceLabel(label, detail, isProminent)
            OrderPriceValue(amount, isProminent)
        }
    } else {
        Row(merged, horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            OrderPriceLabel(label, detail, isProminent, Modifier.weight(1f).alignByBaseline())
            OrderPriceValue(amount, isProminent, Modifier.alignByBaseline())
        }
    }
}

@Composable
private fun OrderPriceLabel(label: String, detail: String?, isProminent: Boolean, modifier: Modifier = Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
        BrandText(
            label,
            if (isProminent) MemoBookFont.bodySemibold else MemoBookFont.body,
            Modifier.weight(1f, fill = false).alignByBaseline(),
        )
        if (detail != null) {
            BrandText(detail, MemoBookFont.label, Modifier.alignByBaseline(), color = MemoBookColor.inkMuted)
        }
    }
}

@Composable
private fun OrderPriceValue(amount: BigDecimal?, isProminent: Boolean, modifier: Modifier = Modifier) {
    if (amount == null) {
        BrandSkeleton(modifier, width = 64.dp, height = if (isProminent) 20.dp else 14.dp)
        return
    }
    val style = (if (isProminent) MemoBookFont.figure else MemoBookFont.bodySemibold)
        // Les chiffres à chasse fixe : un total qui change ne fait pas danser
        // la ligne.
        .copy(fontFeatureSettings = "tnum")
    val reduceMotion = isReduceMotionEnabled()
    // Le montant change quand on ajoute un exemplaire : il roule. Le
    // `.numericText()` d'iOS anime chiffre par chiffre ; ici le montant entier
    // monte, ce qui dit la même chose.
    AnimatedContent(
        targetState = amount.euros,
        modifier = modifier,
        transitionSpec = {
            if (reduceMotion) {
                fadeIn(SwiftMotion.smooth(0.25f)) togetherWith fadeOut(SwiftMotion.smooth(0.25f))
            } else {
                (slideInVertically(SwiftMotion.snappy(0.3f)) { it / 2 } + fadeIn(SwiftMotion.smooth(0.3f))) togetherWith
                    (slideOutVertically(SwiftMotion.snappy(0.3f)) { -it / 2 } + fadeOut(SwiftMotion.smooth(0.3f)))
            }
        },
        label = "montant",
    ) { text ->
        BrandText(text, style, maxLines = 1, minimumScaleFactor = 0.7f)
    }
}

// MARK: - La carte du voyage

/**
 * Le voyage qu'on s'apprête à faire imprimer, monté comme une photo dans un
 * album : un bout de ruban en haut, quatre coins de maintien.
 *
 * Elle **ne s'ouvre pas** — on est déjà dans le tunnel de commande, la carte
 * est là pour dire *lequel* de ses voyages on commande, pas pour y aller.
 */
@Composable
internal fun OrderTripCard(trip: Trip?, isLoading: Boolean, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)
    Box(
        modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {},
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .brandShadow(MemoBookShadow.Soft, shape)
                .background(MemoBookColor.surface, shape)
                .border(1.dp, MemoBookColor.hairline, shape)
                .padding(MemoBookSpacing.s),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        ) {
            OrderTripPhoto(trip)
            OrderTripCaption(trip, isLoading)
        }
        OrderTripTape(Modifier.align(Alignment.TopCenter))
    }
}

/**
 * Le ruban adhésif du haut. Décoratif, et volontairement discret : il dit
 * « photo collée dans un carnet », il ne se regarde pas.
 */
@Composable
private fun OrderTripTape(modifier: Modifier) {
    Box(
        modifier
            .offset(y = (-8).dp)
            .rotate(-1.5f)
            .size(width = 64.dp, height = 17.dp)
            .background(MemoBookColor.beige.copy(alpha = 0.9f), RoundedCornerShape(2.dp))
            .clearAndSetSemantics {},
    )
}

@Composable
private fun OrderTripPhoto(trip: Trip?) {
    if (trip == null) {
        BrandSkeleton(height = 190.dp, cornerRadius = MemoBookSpacing.cornerRadius)
        return
    }
    Box {
        TripCover(trip, aspectRatio = 8f / 5f, showsCompanions = false)
        CornerMounts(Modifier.matchParentSize())
    }
}

@Composable
private fun OrderTripCaption(trip: Trip?, isLoading: Boolean) {
    if (isLoading || trip == null) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            BrandSkeleton(width = 120.dp)
            BrandSkeleton(width = 220.dp, height = 18.dp)
            BrandSkeleton(width = 160.dp)
        }
        return
    }
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
        Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
            // Un voyage sans destination nommée garde sa pastille d'état : la
            // ligne ne se vide pas, elle se décale.
            trip.destination?.let { DestinationLabel(it) }
            Spacer(Modifier.weight(1f))
            StageBadge(trip.stage)
        }

        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            BrandText(trip.title, MemoBookFont.cardTitle)
            trip.dateRangeLabel?.let { BrandText(it, MemoBookFont.label, color = MemoBookColor.inkMuted) }
        }

        Box(
            Modifier
                .fillMaxWidth()
                .height(1.dp)
                .background(MemoBookColor.hairline)
                .clearAndSetSemantics {},
        )

        TripStatsRow(trip.stats)
    }
}

/** Les quatre coins de maintien de la photo. Purement décoratifs. */
@Composable
private fun CornerMounts(modifier: Modifier) {
    val color = MemoBookColor.beige.copy(alpha = 0.85f)
    Canvas(modifier.clearAndSetSemantics {}) {
        val side = 17.dp.toPx()
        val right = size.width
        val bottom = size.height
        fun triangle(a: Offset, b: Offset, c: Offset) {
            drawPath(
                Path().apply {
                    moveTo(a.x, a.y)
                    lineTo(b.x, b.y)
                    lineTo(c.x, c.y)
                    close()
                },
                color,
            )
        }
        // Le coin, puis les deux points qui ferment l'équerre, comme sur iOS.
        triangle(Offset(0f, 0f), Offset(side, 0f), Offset(0f, side))
        triangle(Offset(right, 0f), Offset(right, side), Offset(right - side, 0f))
        triangle(Offset(0f, bottom), Offset(0f, bottom - side), Offset(side, bottom))
        triangle(Offset(right, bottom), Offset(right - side, bottom), Offset(right, bottom - side))
    }
}

// MARK: - Une option d'exemplaire

/**
 * Une option du carnet, avec son interrupteur. La « toggle-card » de la
 * maquette de l'étape 3.
 *
 * **Toute la carte bascule l'option**, et pas seulement l'interrupteur : la
 * cible est la ligne entière, comme la ligne à interrupteur de `BrandRowGroup`,
 * et TalkBack y lit un seul interrupteur nommé par l'option.
 */
@Composable
internal fun OrderToggleCard(title: String, isOn: Boolean, onIsOnChange: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(MemoBookSpacing.controlCornerRadius)
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = MemoBookSpacing.minimumTapTarget)
            .background(MemoBookColor.surface, shape)
            .border(1.dp, MemoBookColor.hairline, shape)
            .toggleable(
                value = isOn,
                interactionSource = null,
                indication = null,
                role = Role.Switch,
                onValueChange = onIsOnChange,
            )
            .padding(horizontal = MemoBookSpacing.s, vertical = MemoBookSpacing.snug),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BrandText(title, MemoBookFont.body, Modifier.weight(1f))
        BrandSwitch(isOn, onIsOnChange, isTapTarget = false)
    }
}

// MARK: - Aperçus

@Preview(locale = "fr-rFR", name = "Carte du voyage", widthDp = 390)
@Composable
private fun OrderTripCardPreview() {
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.l),
    ) {
        OrderTripCard(trip = OrderContext.fixture.trip, isLoading = false)
        OrderTripCard(trip = null, isLoading = true)
    }
}

@Preview(locale = "fr-rFR", name = "Lignes de prix", widthDp = 390)
@Composable
private fun OrderPriceRowPreview() {
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        OrderPriceRow("Prix unitaire", amount = BigDecimal("129.50"))
        OrderPriceRow("Exemplaires", detail = "x2", amount = BigDecimal("259.00"))
        OrderPriceRow("Total", amount = null, isProminent = true)
        OrderToggleCard("Quiz intégrés à l’histoire", isOn = true, onIsOnChange = {})
    }
}
