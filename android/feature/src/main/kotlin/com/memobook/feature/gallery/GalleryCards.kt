package com.memobook.feature.gallery

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.memobook.core.Gallery
import com.memobook.core.GalleryTrip
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.R
import com.memobook.design.isAccessibilityTextSize
import com.memobook.design.scaled
import com.memobook.feature.home.TripCoverPlaceholder

/**
 * Les mesures de la mosaïque. Jumeau de `GalleryMetrics` (`Gallery/GalleryCards.swift`).
 * Elles sont partagées par la grille, ses vignettes et le modèle qui les
 * répartit en colonnes : trois endroits qui doivent tomber d'accord sur la
 * hauteur d'une carte.
 */
object GalleryMetrics {
    /**
     * Deux colonnes. Ce n'est pas un réglage : à trois, un titre de voyage
     * tient sur trois lignes de deux mots.
     */
    const val columnCount = 2

    /**
     * Une seule colonne aux tailles de texte accessibles.
     *
     * À 165 de large, « De Nantes à Saint-Malo à vélo » en AX3 fait dix lignes
     * d'un mot. La mosaïque n'est pas ce qu'on protège ici : le titre l'est.
     */
    fun columnCount(isAccessibilitySize: Boolean): Int = if (isAccessibilitySize) 1 else columnCount

    /** La gouttière, verticale comme horizontale. */
    val gutter = MemoBookSpacing.xs + 4.dp

    /**
     * Les formats possibles d'une vignette, en largeur / hauteur.
     *
     * Ce sont eux qui font la mosaïque : à format unique, la grille redevient
     * deux colonnes bien sages et on ne distingue plus une carte de sa voisine.
     * Les quatre valeurs encadrent le portrait — une vignette n'est jamais plus
     * large que haute, sauf la plus courte, qui l'est à peine.
     */
    private val aspectRatios = listOf(0.78f, 1.12f, 0.86f, 1.0f)

    /**
     * Le format d'une vignette, tiré de l'identifiant du voyage.
     *
     * Même empreinte que celle des aplats de couverture — voir
     * `TripCoverPlaceholder` : djb2 sur 64 bits non signés qui débordent comme
     * ceux de Swift, pour que la grille soit la même sur les deux téléphones,
     * et ne bouge que si le contenu bouge.
     */
    fun aspectRatio(seed: String): Float {
        var hash: ULong = 5381u
        seed.codePoints().forEach { scalar -> hash = hash * 33u + scalar.toULong() }
        return aspectRatios[(hash % aspectRatios.size.toULong()).toInt()]
    }
}

/**
 * Une vignette de la galerie : un carnet de la communauté, son titre et la
 * phrase qui le résume, posés sur son image. Jumeau de `GalleryTripCard`.
 *
 * **Elle ne s'ouvre pas encore.** Les carnets des autres n'ont pas d'écran :
 * la carte est donc une image et du texte, sans bouton ni flèche — rien qui
 * promette un geste qui ne se passerait pas.
 *
 * TalkBack lit la carte d'un bloc, et nomme le pays plutôt que de laisser
 * passer un drapeau qu'il annoncerait « emoji ».
 */
@Composable
fun GalleryTripCard(trip: GalleryTrip, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(MemoBookSpacing.galleryCornerRadius)
    val label = GalleryCopy.accessibilityLabel(trip)

    // Aux tailles de texte accessibles, le titre **sort de l'image**.
    //
    // Une vignette a une hauteur fixée par son format : posé dessus, un titre
    // en AX3 en déborde par le bas, recouvre le drapeau et se superpose à celui
    // de la carte voisine. Le texte passe donc sous l'image, sur le papier de la
    // marque, où il a toute la place de s'écrire — et il y gagne l'encre
    // pleine, plus lisible que du blanc sur une photo.
    if (isAccessibilityTextSize()) {
        Column(
            modifier
                .fillMaxWidth()
                .clip(shape)
                .background(MemoBookColor.surface, shape)
                .border(1.dp, MemoBookColor.hairline, shape)
                .clearAndSetSemantics { contentDescription = label },
        ) {
            GalleryTile(trip)
            GalleryCaption(trip, MemoBookColor.ink, Modifier.padding(top = MemoBookSpacing.xs))
        }
    } else {
        Box(
            modifier
                .fillMaxWidth()
                .clip(shape)
                .clearAndSetSemantics { contentDescription = label },
        ) {
            GalleryTile(trip)
            // Le voile qui rend le texte lisible.
            //
            // Opaque en bas, transparent au tiers de la hauteur : le titre se lit
            // sur n'importe quelle photo, y compris un ciel blanc, et le haut de
            // l'image reste net. Sans lui, un titre blanc disparaît sur la moitié
            // des couvertures — et l'assombrir en entier reviendrait à cacher ce
            // qu'on vient montrer.
            Box(
                Modifier
                    .matchParentSize()
                    .background(
                        Brush.verticalGradient(
                            0.30f to Color.Black.copy(alpha = 0f),
                            0.62f to Color.Black.copy(alpha = 0.35f),
                            1f to Color.Black.copy(alpha = 0.68f),
                        ),
                    ),
            )
            GalleryCaption(trip, MemoBookColor.onAction, Modifier.align(Alignment.BottomStart))
        }
    }
}

/** L'image, à son format, avec le drapeau posé dans le coin. */
@Composable
private fun GalleryTile(trip: GalleryTrip) {
    Box(
        Modifier
            .fillMaxWidth()
            .aspectRatio(GalleryMetrics.aspectRatio(trip.id))
            .clip(RoundedCornerShape(MemoBookSpacing.galleryCornerRadius)),
    ) {
        // L'image **remplit** le cadre et déborde par son plus grand côté.
        // C'est ce qui garantit qu'aucune vignette ne montre de bande vide, quel
        // que soit le format de la photo — et c'est la carte qui rogne ce qui
        // dépasse, pas l'image qui se déforme. Sans photo remontée du serveur,
        // l'aplat de marque des couvertures fait l'affaire, et donne à la grille
        // ses couleurs.
        TripCoverPlaceholder(trip.id, Modifier.fillMaxSize())
        trip.coverPhotoUrl?.let { url ->
            AsyncImage(
                model = url.toString(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }
        GalleryOriginMark(trip, Modifier.align(Alignment.TopStart))
    }
}

/** Le titre et sa phrase. La couleur vient de l'appelant : blanc sur l'image, encre sur le papier. */
@Composable
private fun GalleryCaption(trip: GalleryTrip, color: Color, modifier: Modifier = Modifier) {
    Column(
        modifier
            .fillMaxWidth()
            .padding(MemoBookSpacing.xs + 4.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        BrandText(trip.title, MemoBookFont.bodySemibold, color = color)
        trip.subtitle?.let { subtitle ->
            // Une nuance en dessous, jamais un gris franc : sur une photo il
            // devient sale, sur le papier il refroidit le crème.
            BrandText(subtitle, MemoBookFont.label, color = color, modifier = Modifier.alpha(0.85f))
        }
    }
}

/**
 * D'où vient le carnet : le drapeau du pays, ou le globe dès qu'il y en a
 * plusieurs.
 *
 * Choisir un drapeau parmi dix désignerait le premier pays comme *le* pays du
 * voyage, ce qu'un tour du monde n'a pas. Le globe le dit sans mentir — et
 * c'est aussi ce qu'on montre quand le pays n'a pas de code exploitable.
 */
@Composable
private fun GalleryOriginMark(trip: GalleryTrip, modifier: Modifier = Modifier) {
    Box(
        modifier
            .padding(MemoBookSpacing.xs)
            .background(MemoBookColor.surface.copy(alpha = 0.9f), CircleShape)
            .padding(4.dp),
        contentAlignment = Alignment.Center,
    ) {
        val flag = trip.flag
        if (flag != null) {
            BrandText(flag, MemoBookFont.caption)
        } else {
            Image(
                painterResource(R.drawable.icon_globe_duo),
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier.size(scaled(14.dp)),
            )
        }
    }
}

/**
 * La place d'une vignette qui n'est pas encore arrivée.
 *
 * La grille se dessine **tout de suite**, à sa forme définitive : l'écran
 * s'ouvre sur une mosaïque qui se remplit, et non sur un crème vide qui saute
 * d'un coup. Les formats sont ceux des vraies vignettes, tirés d'un rang.
 */
@Composable
fun GalleryCardPlaceholder(rank: Int, modifier: Modifier = Modifier) {
    val seed = "placeholder-$rank"
    Box(
        modifier
            .fillMaxWidth()
            .aspectRatio(GalleryMetrics.aspectRatio(seed))
            .clip(RoundedCornerShape(MemoBookSpacing.galleryCornerRadius))
            .clearAndSetSemantics {},
    ) {
        TripCoverPlaceholder(seed, Modifier.fillMaxSize().alpha(0.5f))
    }
}

/** Ce que TalkBack lit d'une vignette. */
internal object GalleryCopy {
    /**
     * Le titre, la phrase, les pays — en liste à la française : « Italie,
     * France et Espagne », le `.formatted(.list(type: .and))` d'iOS.
     */
    fun accessibilityLabel(trip: GalleryTrip): String =
        listOfNotNull(trip.title, trip.subtitle, countries(trip.destinations.map { it.name }))
            .joinToString(", ")

    fun countries(names: List<String>): String? = when (names.size) {
        0 -> null
        1 -> names.first()
        else -> names.dropLast(1).joinToString(", ") + " et " + names.last()
    }
}

// MARK: - Aperçus

@Preview(locale = "fr-rFR", name = "Vignettes de la galerie", widthDp = 390, heightDp = 700)
@Composable
private fun GalleryCardsPreview() {
    val trips = Gallery.fixture.trips
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(GalleryMetrics.gutter),
    ) {
        trips.take(2).forEach { GalleryTripCard(it) }
        GalleryCardPlaceholder(rank = 0)
    }
}
