package com.memobook.feature.home

import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.Image
import androidx.compose.foundation.IndicationNodeFactory
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.InteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.node.DelegatableNode
import androidx.compose.ui.node.DrawModifierNode
import androidx.compose.ui.node.invalidateDraw
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.memobook.core.Destination
import com.memobook.core.HomeFeed
import com.memobook.core.Trip
import com.memobook.core.TripStage
import com.memobook.core.TripStats
import com.memobook.design.BrandButton
import com.memobook.design.BrandProgressBar
import com.memobook.design.BrandTagPill
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.isAccessibilityTextSize
import com.memobook.design.scaled
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

// Les trois cartes de l'accueil. Jumeau de `Home/TripCards.swift`. Elles
// partagent la même coque — surface blanche, rayon 20, filet discret — et ne
// diffèrent que par ce qu'elles mettent dedans : la couverture pleine pour le
// voyage du moment, une ligne pour les autres voyages en cours, une bande pour
// les carnets terminés.
//
// Chaque carte reçoit un `modifier` posé **sur son nœud tapable** : c'est là
// que `BrandSwipeDrawer` attache les actions que TalkBack lit (voir son
// en-tête) — posé à côté, il ferait une étape muette de plus.

/**
 * Le voyage du moment : couverture, pays, état, titre, dates et compteurs.
 */
@Composable
fun FeaturedTripCard(trip: Trip, modifier: Modifier = Modifier, onOpen: () -> Unit) {
    Box {
        Column(
            modifier
                .fillMaxWidth()
                .homeCard()
                .cardButton(onOpen),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        ) {
            TripCover(trip, aspectRatio = 16f / 9f, modifier = Modifier.padding(MemoBookSpacing.xs))

            Column(
                Modifier
                    .padding(horizontal = MemoBookSpacing.s)
                    .padding(bottom = MemoBookSpacing.s),
                verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
            ) {
                FeaturedTripHeader(trip)
                TripTitleAndDates(trip, titleStyle = MemoBookFont.heading, spacing = 2.dp)
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(1.dp)
                        .background(MemoBookColor.hairline),
                )
                TripStatsRow(trip.stats)

                trip.progress?.let { progress ->
                    BrandProgressBar(
                        progress.fraction,
                        modifier = Modifier.padding(top = MemoBookSpacing.xs / 2),
                        label = progress.summary,
                    )
                }
            }
        }

        // Un bout de scotch collé en haut de la carte, comme sur une page de
        // carnet.
        //
        // Trois choses le font lire comme du scotch et pas comme un onglet : il
        // est **par-dessus** la carte et non derrière, il est **translucide** —
        // on voit le bord de la carte au travers, c'est ce qui trahit un
        // adhésif — et il est **de travers**. Ses coins sont à peine adoucis :
        // une bande coupée aux ciseaux n'a pas de rayon.
        CardTape(
            color = MemoBookColor.separator.copy(alpha = 0.55f),
            width = 64.dp,
            height = 22.dp,
            degrees = -5f,
            // Il chevauche le bord haut : une moitié sur la carte, une moitié
            // dans le vide.
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(start = 56.dp)
                .offset(y = (-9).dp),
        )
    }
}

/**
 * Le pays à gauche, l'état à droite — sauf en taille accessible, où la
 * pastille prend toute la largeur et ne laisserait au nom du pays que de quoi
 * le couper en deux.
 */
@Composable
private fun FeaturedTripHeader(trip: Trip) {
    if (isAccessibilityTextSize()) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            trip.destination?.let { DestinationLabel(it) }
            StageBadge(trip.stage)
        }
    } else {
        Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            trip.destination?.let { DestinationLabel(it, Modifier.alignByBaseline()) }
            Spacer(Modifier.weight(1f))
            Box(Modifier.alignByBaseline()) { StageBadge(trip.stage) }
        }
    }
}

/** Le titre d'un voyage et ses dates, l'un sous l'autre. */
@Composable
private fun TripTitleAndDates(trip: Trip, titleStyle: androidx.compose.ui.text.TextStyle, spacing: Dp, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(spacing)) {
        BrandText(trip.title, titleStyle, color = MemoBookColor.ink)
        trip.dateRangeLabel?.let { dates ->
            BrandText(dates, MemoBookFont.label, color = MemoBookColor.inkMuted)
        }
    }
}

/** Un autre voyage en cours : titre et compteurs sur une ligne, sans photo. */
@Composable
fun CompactTripCard(trip: Trip, modifier: Modifier = Modifier, onOpen: () -> Unit) {
    Column(
        modifier
            .fillMaxWidth()
            .homeCard()
            .cardButton(onOpen)
            .padding(MemoBookSpacing.s),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s), verticalAlignment = Alignment.CenterVertically) {
            TripTitleAndDates(trip, titleStyle = MemoBookFont.bodySemibold, spacing = 2.dp, modifier = Modifier.weight(1f))

            Image(
                painterResource(R.drawable.icon_arrow_right),
                contentDescription = null,
                colorFilter = ColorFilter.tint(MemoBookColor.ink),
                modifier = Modifier
                    // Le rond reste à 48 : le dessin grandit, pas la cible.
                    .background(MemoBookColor.background, CircleShape)
                    .padding(MemoBookSpacing.xs - 2.dp)
                    .size(MemoBookSpacing.contentIcon),
            )
        }

        trip.progress?.let { progress ->
            BrandProgressBar(progress.fraction)
        }
    }
}

/**
 * Un voyage à venir (`3125:33113`) : une photo d'attente floutée, le compte à
 * rebours du départ, le titre et les dates — et le scotch qui dépasse en haut.
 *
 * **La photo est toujours la même** (Clara, 26/09/2026) : un voyage qui n'a pas
 * commencé n'a pas encore de photo à lui, et une couverture vide se lit comme
 * un manque. C'est celle de la maquette, exportée de Figma
 * (`assets/illustrations/Upcoming Trip Photo.jpg`), et floutée **ici** plutôt
 * qu'à l'export : une retouche du flou ne demande pas un nouvel export.
 *
 * Les coins photo (`PhotoCornerMounts`) viennent du même nœud : quatre petits
 * triangles d'encre à 15 %, comme les coins collés d'un album.
 *
 * @param today aujourd'hui, pour le compte à rebours. Un paramètre pour les
 *   aperçus et les tests : le jour qui passe n'a pas à être deviné par la vue.
 */
@Composable
fun UpcomingTripCard(trip: Trip, modifier: Modifier = Modifier, today: Instant = Instant.now(), onOpen: () -> Unit) {
    Box {
        Column(
            modifier
                .fillMaxWidth()
                .homeCard()
                .cardButton(onOpen)
                .padding(MemoBookSpacing.s),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        ) {
            UpcomingTripPhoto(UpcomingTripCopy.daysUntilDeparture(trip.startDate, today))
            TripTitleAndDates(trip, titleStyle = MemoBookFont.heading, spacing = 4.dp)
        }

        // Le bout de scotch **centré** qui dépasse du bord haut — celui de la
        // maquette : droit, translucide, le vert de la marque à 18 % (relevé
        // sur l'export). Même grammaire que ceux de [FeaturedTripCard] et de
        // [UpcomingTripInvite] : par-dessus la carte, à cheval sur son bord.
        CardTape(
            color = MemoBookColor.action.copy(alpha = 0.18f),
            width = 64.dp,
            height = 17.dp,
            degrees = 0f,
            modifier = Modifier
                .align(Alignment.TopCenter)
                .offset(y = (-7).dp),
        )
    }
}

/**
 * La photo d'attente, son voile et son compte à rebours.
 *
 * Sur iOS, la photo est posée en `overlay` d'un cadre vide : `scaledToFill` ne
 * s'y laisse pas contraindre en largeur. Ici, le cadre a son rapport, et la
 * photo le remplit en débordant.
 */
@Composable
private fun UpcomingTripPhoto(daysUntilDeparture: Int?) {
    val shape = RoundedCornerShape(MemoBookSpacing.cornerRadius)

    Box(
        Modifier
            .fillMaxWidth()
            // Le rapport de la photo dans la maquette : 310 × 193,75.
            .aspectRatio(UpcomingTripCopy.photoRatio),
    ) {
        Box(Modifier.matchParentSize().clip(shape)) {
            Image(
                painterResource(R.drawable.photo_upcoming_trip),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .matchParentSize()
                    // Un flou large, qui fond la rue en une matière brune comme
                    // sur la maquette — relevé sur son export. Bords
                    // rectangulaires : le `opaque` d'iOS, sans quoi le flou fait
                    // entrer du transparent par les bords, et la photo
                    // s'éclaircit en liseré. ⚠️ Android ne floute qu'à partir
                    // d'Android 12 : avant, la photo reste nette sous son voile.
                    .blur(16.dp, BlurredEdgeTreatment.Rectangle),
            )
            // Le voile qui fait lire le blanc du compte à rebours.
            Box(Modifier.matchParentSize().background(Color.Black.copy(alpha = 0.18f)))
            UpcomingTripCountdown(daysUntilDeparture, Modifier.align(Alignment.Center))
        }
        Image(
            painterResource(R.drawable.photo_corner_mounts),
            contentDescription = null,
            contentScale = ContentScale.FillBounds,
            modifier = Modifier.matchParentSize(),
        )
    }
}

/** « À VENIR », puis « Départ dans » et le nombre de jours. */
@Composable
private fun UpcomingTripCountdown(days: Int?, modifier: Modifier = Modifier) {
    Column(
        modifier.padding(MemoBookSpacing.s),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        BrandText(
            UpcomingTripCopy.badge.uppercase(),
            MemoBookFont.microBadge,
            color = MemoBookColor.onAction,
            textAlign = TextAlign.Center,
            maxLines = 1,
            minimumScaleFactor = 0.6f,
            modifier = Modifier
                .border(1.dp, MemoBookColor.onAction, RoundedCornerShape(MemoBookSpacing.xs / 2))
                .padding(horizontal = MemoBookSpacing.xs, vertical = 2.dp),
        )

        if (days != null) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                BrandText(
                    UpcomingTripCopy.lead,
                    MemoBookFont.headingLight,
                    color = MemoBookColor.onAction,
                    textAlign = TextAlign.Center,
                    maxLines = 1,
                    minimumScaleFactor = 0.6f,
                )
                BrandText(
                    UpcomingTripCopy.days(days),
                    // Les chiffres à chasse fixe : le compte qui descend ne
                    // fait pas danser la ligne.
                    MemoBookFont.h1.copy(fontFeatureSettings = "tnum"),
                    color = MemoBookColor.onAction,
                    textAlign = TextAlign.Center,
                    maxLines = 1,
                    minimumScaleFactor = 0.6f,
                )
            }
        }
    }
}

/** Les mots de la carte d'un voyage à venir, recopiés de `3125:33113` (R8). */
object UpcomingTripCopy {
    const val badge = "À venir"
    const val lead = "Départ dans"

    /** Le rapport de la photo dans la maquette : 310 × 193,75. */
    internal const val photoRatio = 1.6f

    fun days(count: Int): String = if (count == 1) "1 jour" else "$count jours"

    /**
     * Les jours pleins jusqu'au départ, comptés d'un minuit à l'autre : un
     * départ demain matin est « dans 1 jour », même à 23 h. `null` sans date de
     * départ, ou si elle est déjà passée — la pastille parle seule.
     */
    fun daysUntilDeparture(start: Instant?, today: Instant, zone: ZoneId = ZoneId.systemDefault()): Int? {
        start ?: return null
        val days = ChronoUnit.DAYS.between(LocalDate.ofInstant(today, zone), LocalDate.ofInstant(start, zone)).toInt()
        return days.takeIf { it > 0 }
    }
}

/**
 * Un carnet terminé : sa bande de couverture, son titre, et de quoi le faire
 * imprimer quand il est prêt.
 */
@Composable
fun PastTripCard(trip: Trip, modifier: Modifier = Modifier, onOpen: () -> Unit, onOrderPrint: () -> Unit) {
    Column(
        modifier
            .fillMaxWidth()
            .homeCard()
            .cardButton(onOpen),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        TripCover(trip, aspectRatio = 5f / 2f, modifier = Modifier.padding(MemoBookSpacing.xs), showsCompanions = false)
        PastTripCaption(
            trip,
            onOrderPrint,
            Modifier
                .padding(horizontal = MemoBookSpacing.s)
                .padding(bottom = if (trip.isPrintable) 0.dp else MemoBookSpacing.s),
        )
    }
}

/** Le bouton d'impression descend sous le titre dès que le texte a besoin de toute la largeur. */
@Composable
private fun PastTripCaption(trip: Trip, onOrderPrint: () -> Unit, modifier: Modifier) {
    if (isAccessibilityTextSize()) {
        Column(
            modifier.padding(bottom = if (trip.isPrintable) MemoBookSpacing.s else 0.dp),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        ) {
            PastTripTitle(trip)
            PastTripPrintButton(trip, onOrderPrint)
        }
    } else {
        Row(
            modifier.padding(bottom = if (trip.isPrintable) MemoBookSpacing.xs else 0.dp),
            horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            PastTripTitle(trip, Modifier.weight(1f))
            PastTripPrintButton(trip, onOrderPrint)
        }
    }
}

@Composable
private fun PastTripTitle(trip: Trip, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            trip.destination?.flag?.let { BrandText(it, MemoBookFont.body) }
            BrandText(trip.title, MemoBookFont.bodySemibold, color = MemoBookColor.ink)
        }
        trip.dateRangeLabel?.let { dates ->
            BrandText(dates, MemoBookFont.label, color = MemoBookColor.inkMuted)
        }
    }
}

@Composable
private fun PastTripPrintButton(trip: Trip, onOrderPrint: () -> Unit) {
    if (!trip.isPrintable) return
    // Icône de la marque en attendant l'export Figma de cet écran.
    BrandButton(
        icon = painterResource(R.drawable.icon_printer),
        style = BrandButton.Style.Soft,
        size = BrandButton.Size.Small,
        contentDescription = "Prévisualiser et commander « ${trip.title} »",
        action = onOrderPrint,
    )
}

// MARK: - Pièces communes

/** La pastille d'état d'un voyage. */
@Composable
fun StageBadge(stage: TripStage, modifier: Modifier = Modifier) {
    when (stage) {
        TripStage.Ongoing, is TripStage.Unknown -> BrandTagPill("En cours", modifier, tone = BrandTagPill.Tone.Outlined, isUppercased = true)
        TripStage.Upcoming -> BrandTagPill("À venir", modifier, tone = BrandTagPill.Tone.Info, isUppercased = true)
        TripStage.Past -> Unit
    }
}

/** Le drapeau et le pays, en capitales. */
@Composable
fun DestinationLabel(destination: Destination, modifier: Modifier = Modifier) {
    Row(
        modifier.clearAndSetSemantics { contentDescription = destination.name },
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        destination.flag?.let { BrandText(it, MemoBookFont.overline) }
        BrandText(
            destination.name.uppercase(),
            MemoBookFont.overline.copy(letterSpacing = MemoBookFont.tracking),
            color = MemoBookColor.ink,
        )
    }
}

/**
 * Durée, distance, photos.
 *
 * Deux emplois, un seul composant : réparti sur la largeur d'une carte de
 * l'accueil, ou serré à gauche et teinté de blanc sur la photo d'un voyage.
 * Les règles qui comptent — pluriels, unités, empilement en taille accessible
 * — sont les mêmes des deux côtés, et c'est bien pour ça qu'il n'y en a qu'un.
 *
 * @param tint teinte unique de l'icône **et** du texte. `null` garde le
 *   deux-tons de la carte : icône estompée, texte en encre pleine.
 * @param isSpread répartis sur toute la largeur, ou serrés les uns contre les
 *   autres.
 */
@Composable
fun TripStatsRow(stats: TripStats, modifier: Modifier = Modifier, tint: Color? = null, isSpread: Boolean = true) {
    val items = stats.items
    if (items.isEmpty()) return
    val iconSide = scaled(16.dp)

    // En taille accessible les trois compteurs ne tiennent plus sur une ligne :
    // ils s'empilent au lieu de se tronquer.
    if (isAccessibilityTextSize()) {
        Column(modifier, verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2)) {
            items.forEach { TripStatItemView(it, tint, iconSide) }
        }
    } else {
        Row(
            modifier.then(if (isSpread) Modifier.fillMaxWidth() else Modifier),
            horizontalArrangement = Arrangement.spacedBy(if (isSpread) MemoBookSpacing.xs else MemoBookSpacing.s),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            items.forEachIndexed { index, item ->
                TripStatItemView(item, tint, iconSide)
                // Un ressort entre chaque compteur, pas après le dernier : les
                // trois se répartissent sur la largeur de la carte au lieu de se
                // tasser à gauche.
                if (isSpread && index != items.lastIndex) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun TripStatItemView(item: TripStatItem, tint: Color?, iconSide: Dp) {
    Row(
        Modifier.clearAndSetSemantics { contentDescription = item.text },
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(
            painterResource(item.kind.icon),
            contentDescription = null,
            colorFilter = ColorFilter.tint(tint ?: MemoBookColor.inkMuted),
            modifier = Modifier.size(iconSide),
        )
        BrandText(item.text, MemoBookFont.label, color = tint ?: MemoBookColor.ink)
    }
}

/** Un bout de scotch posé par-dessus une carte — voir [FeaturedTripCard]. */
@Composable
internal fun CardTape(color: Color, width: Dp, height: Dp, degrees: Float, modifier: Modifier = Modifier) {
    Box(
        modifier
            .rotate(degrees)
            .size(width, height)
            .background(color, RoundedCornerShape(2.dp))
            .clearAndSetSemantics {},
    )
}

// MARK: - Coque et retour tactile

/**
 * La carte de l'accueil : surface blanche, rayon 20, un filet pour la décoller
 * du crème du fond.
 *
 * **Toute la carte répond au doigt**, y compris là où elle ne dessine rien —
 * le `homeCardHitArea()` d'iOS, que Compose donne d'office : un `clickable`
 * couvre tout son nœud, le vide à droite d'un titre compris.
 */
fun Modifier.homeCard(): Modifier {
    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)
    return background(MemoBookColor.surface, shape).border(1.dp, MemoBookColor.hairline, shape)
}

/**
 * Le bouton d'une carte : tout son nœud, l'appui de [CardPressStyle], le rôle
 * de bouton pour TalkBack — qui lit la carte d'un bloc, avec son état, plutôt
 * que six éléments séparés.
 */
internal fun Modifier.cardButton(onClick: () -> Unit): Modifier = clickable(
    interactionSource = null,
    indication = CardPressStyle,
    role = Role.Button,
    onClick = onClick,
)

/**
 * Une carte s'enfonce légèrement sous le doigt, sans changer d'opacité : c'est
 * du papier, pas un bouton. Le `ButtonStyle` d'iOS devient une indication : la
 * coque, posée avant elle, reste en place, et seul le contenu s'enfonce — comme
 * sur iOS, où le fond est posé hors du bouton.
 */
object CardPressStyle : IndicationNodeFactory {
    override fun create(interactionSource: InteractionSource): DelegatableNode = CardPressNode(interactionSource)

    override fun equals(other: Any?): Boolean = other === this

    override fun hashCode(): Int = System.identityHashCode(this)
}

private class CardPressNode(private val source: InteractionSource) : androidx.compose.ui.Modifier.Node(), DrawModifierNode {
    private val scale = Animatable(1f)

    override fun onAttach() {
        coroutineScope.launch {
            val presses = mutableListOf<PressInteraction.Press>()
            source.interactions.collect { interaction ->
                when (interaction) {
                    is PressInteraction.Press -> presses += interaction
                    is PressInteraction.Release -> presses -= interaction.press
                    is PressInteraction.Cancel -> presses -= interaction.press
                }
                val target = if (presses.isEmpty()) 1f else 0.985f
                launch {
                    scale.animateTo(target, SwiftMotion.smooth(0.18f)) { invalidateDraw() }
                }
            }
        }
    }

    override fun ContentDrawScope.draw() {
        val value = scale.value
        if (value == 1f) {
            drawContent()
        } else {
            scale(value, pivot = Offset(size.width / 2, size.height / 2)) { this@draw.drawContent() }
        }
    }
}

// MARK: - Aperçus

@Preview(locale = "fr-rFR", name = "Cartes de l’accueil", widthDp = 390, heightDp = 1200)
@Composable
private fun TripCardsPreview() {
    val feed = HomeFeed.fixture
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
    ) {
        feed.ongoingTrips.firstOrNull()?.let { FeaturedTripCard(it) {} }
        feed.ongoingTrips.getOrNull(1)?.let { CompactTripCard(it) {} }
        UpcomingTripCard(
            Trip(id = "a-venir", title = "Kyoto au printemps", stage = TripStage.Upcoming, startDate = Instant.now().plusSeconds(12 * 86_400)),
        ) {}
        feed.pastTrips.firstOrNull()?.let { PastTripCard(it, onOpen = {}, onOrderPrint = {}) }
    }
}
