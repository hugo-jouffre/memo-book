package com.memobook.feature.home

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.memobook.core.Companion
import com.memobook.core.Trip
import com.memobook.core.TripStage
import com.memobook.design.BrandFonts
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.feature.trip.dimmedWhileAwaitingServer

/**
 * La photo de couverture d'un voyage, et les co-voyageurs posés dessus.
 * Jumeau de `Home/TripCover.swift`.
 *
 * Tant qu'il n'y a pas d'URL — c'est le cas de tout le jeu d'essai, et ce sera
 * le cas d'un voyage sans photo — la couverture n'est pas un rectangle gris :
 * c'est un aplat de marque. Un vide dessiné, pas un vide subi.
 *
 * @param aspectRatio rapport largeur / hauteur de la vignette. Les voyages en
 *   cours sont montrés en 16:9, les carnets terminés dans une bande plus basse.
 */
@Composable
fun TripCover(
    trip: Trip,
    aspectRatio: Float,
    modifier: Modifier = Modifier,
    showsCompanions: Boolean = true,
) {
    Box(
        modifier
            .fillMaxWidth()
            .aspectRatio(aspectRatio)
            .clearAndSetSemantics {},
    ) {
        Box(
            Modifier
                .matchParentSize()
                .clip(RoundedCornerShape(MemoBookSpacing.cornerRadius)),
        ) {
            // L'aplat d'abord, la photo par-dessus : il tient la place tant
            // qu'elle charge, et la remplace si elle ne vient pas — le
            // `AsyncImage` d'iOS et ses deux phases.
            TripCoverPlaceholder(trip.id, Modifier.matchParentSize())
            trip.coverPhotoUrl?.let { url ->
                AsyncImage(
                    model = url.toString(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.matchParentSize(),
                )
            }
        }
        if (showsCompanions && trip.companions.isNotEmpty()) {
            CompanionStack(
                trip.companions,
                Modifier
                    .align(Alignment.BottomEnd)
                    .padding(MemoBookSpacing.xs + 2.dp),
            )
        }
    }
}

/**
 * L'aplat de repli : deux teintes de la marque, choisies d'après l'identifiant
 * du voyage pour que deux carnets voisins ne se ressemblent pas — et que le
 * même carnet garde sa couleur d'un lancement à l'autre.
 */
@Composable
fun TripCoverPlaceholder(seed: String, modifier: Modifier = Modifier) {
    val (from, to) = TripCoverPlaceholder.palettes[TripCoverPlaceholder.index(seed)]
    // Un aplat nu, sans le M : l'écran en porte déjà un en fond, et deux
    // signes qui se superposent ne se lisent plus ni l'un ni l'autre.
    Box(modifier.background(Brush.linearGradient(listOf(from, to), start = Offset.Zero, end = Offset.Infinite)))
}

object TripCoverPlaceholder {
    /**
     * Couples de teintes, tous tirés des tokens : aucune couleur inventée.
     *
     * Le lime en est volontairement absent. C'est l'accent de l'abonnement,
     * réservé aux petites surfaces — un aplat de couverture en lime crierait
     * plus fort que la photo qu'il remplace.
     */
    internal val palettes: List<Pair<Color, Color>> = listOf(
        MemoBookColor.outline to MemoBookColor.background,
        MemoBookColor.action.copy(alpha = 0.6f) to MemoBookColor.outline,
        MemoBookColor.separator to MemoBookColor.surface,
        MemoBookColor.ink.copy(alpha = 0.5f) to MemoBookColor.outline,
    )

    /**
     * Empreinte stable de l'identifiant, plutôt que `hashCode()` : c'est le
     * même calcul que sur iOS, pour qu'un carnet ait la même teinte sur les
     * deux téléphones — et iOS l'a écrit parce que le `hashValue` de Swift
     * change à chaque lancement.
     *
     * La simple somme des points de code ne suffisait pas : deux titres de
     * même longueur tombaient trop souvent sur la même teinte. Le facteur 33
     * (djb2) mélange les rangs entre eux, sur 64 bits non signés qui débordent
     * comme ceux de Swift.
     */
    fun index(seed: String): Int {
        var hash: ULong = 5381u
        seed.codePoints().forEach { scalar -> hash = hash * 33u + scalar.toULong() }
        return (hash % palettes.size.toULong()).toInt()
    }
}

/**
 * Les co-voyageurs, en pastilles qui se chevauchent.
 *
 * @param visibleLimit au-delà de trois, les visages ne se distinguent plus : la
 *   pastille suivante compte le reste. L'en-tête d'un voyage en montre moins,
 *   parce qu'il aligne deux groupes sur la même ligne.
 * @param onAdd inviter quelqu'un. Fournie, elle ferme la pile d'une pastille
 *   « + ». Elle vit **ici** et non à côté du composant : posée en sœur dans la
 *   rangée de l'en-tête, elle se retrouvait espacée de 0.5 rem alors que les
 *   visages se recouvrent d'un cinquième — elle flottait à côté du groupe au
 *   lieu d'en faire partie. Dans la pile, elle prend le même recouvrement, et
 *   se dessine par-dessus le dernier visage puisqu'elle vient en dernier.
 * @param isAddDimmed le « + » pâlit tant que le serveur n'a pas reçu le voyage
 *   — voir [com.memobook.feature.trip.TripAwaitingServer]. Il reste tapable :
 *   [onAdd] dit pourquoi.
 * @param facesLabel ce que TalkBack annonce pour le **groupe de visages**. Posé
 *   sur les visages seuls, et non sur la pile entière : celle-ci contient un
 *   bouton, qu'une fusion à ce niveau-là aurait avalé.
 */
@Composable
fun CompanionStack(
    companions: List<Companion>,
    modifier: Modifier = Modifier,
    visibleLimit: Int = 3,
    onAdd: (() -> Unit)? = null,
    isAddDimmed: Boolean = false,
    facesLabel: String? = null,
) {
    val shown = companions.take(visibleLimit)
    val overflow = companions.size - shown.size
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(CompanionStack.overlap)) {
        Row(
            if (facesLabel != null) Modifier.clearAndSetSemantics { contentDescription = facesLabel } else Modifier,
            horizontalArrangement = Arrangement.spacedBy(CompanionStack.overlap),
        ) {
            shown.forEach { companion ->
                Box {
                    CompanionBubble { BubbleText(companion.initials) }
                    companion.avatarUrl?.let { url ->
                        // Les initiales dessinées dessous restent visibles tant
                        // que la photo charge, ou si elle ne vient pas.
                        AsyncImage(
                            model = url.toString(),
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier
                                .size(CompanionStack.diameter)
                                .clip(CircleShape)
                                .border(2.dp, MemoBookColor.surface, CircleShape),
                        )
                    }
                }
            }
            if (overflow > 0) CompanionBubble { BubbleText("+$overflow") }
        }
        if (onAdd != null) AddCompanionButton(onAdd, isAddDimmed)
    }
}

object CompanionStack {
    /**
     * Taille figée, contrairement au reste de l'écran. Ces ronds sont une
     * décoration posée sur une photo au format fixe, masquée à TalkBack : les
     * faire grandir avec le texte ne rend rien de plus lisible et finit par
     * couvrir la couverture entière.
     *
     * **Partagée**, parce que d'autres ronds viennent se poser sur cette file —
     * le « + » qui invite, dans l'en-tête d'un voyage. Un second 34 écrit à
     * côté, et les deux auraient fini par diverger.
     */
    val diameter: Dp = 34.dp

    /**
     * Un cinquième de recouvrement, pas un tiers : la pastille de droite
     * mangeait la deuxième initiale de celle de gauche.
     */
    internal val overlap: Dp = -diameter / 5
}

/**
 * La pastille « + », au bout de la pile et par-dessus elle.
 *
 * **La cible tactile fait 48, la pastille 34.** Les sept dp de chaque côté sont
 * donc repris du côté gauche : sans ça, le cadre du bouton repoussait la
 * pastille et le recouvrement tombait à rien. Le dessin suit les visages, la
 * cible reste réglementaire. (Compose n'a pas de marge négative : la mise en
 * page déclare une largeur réduite et pose le bouton en retrait.)
 */
@Composable
private fun AddCompanionButton(onAdd: () -> Unit, isDimmed: Boolean) {
    val inset = (MemoBookSpacing.minimumTapTarget - CompanionStack.diameter) / 2
    Box(
        Modifier
            .layout { measurable, constraints ->
                val shift = inset.roundToPx()
                val placeable = measurable.measure(constraints)
                layout(placeable.width - shift, placeable.height) { placeable.place(-shift, 0) }
            }
            .size(MemoBookSpacing.minimumTapTarget)
            .dimmedWhileAwaitingServer(isDimmed)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = PlainButtonIndication,
                role = Role.Button,
                onClick = onAdd,
            )
            .semantics { contentDescription = "Inviter quelqu’un à raconter ce voyage" },
        contentAlignment = Alignment.Center,
    ) {
        CompanionBubble(fill = MemoBookColor.surface) {
            Image(
                painterResource(R.drawable.icon_plus),
                contentDescription = null,
                colorFilter = ColorFilter.tint(MemoBookColor.ink),
                modifier = Modifier.size(MemoBookSpacing.s),
            )
        }
    }
}

/** Un rond de la pile, cerné de papier. */
@Composable
private fun CompanionBubble(fill: Color = MemoBookColor.outline, content: @Composable () -> Unit) {
    Box(
        Modifier
            .size(CompanionStack.diameter)
            .background(fill, CircleShape)
            .border(2.dp, MemoBookColor.surface, CircleShape),
        contentAlignment = Alignment.Center,
    ) { content() }
}

/** Les initiales, en General Sans demi-gras de 12 — à taille fixe, comme le rond. */
@Composable
private fun BubbleText(text: String) {
    val size = with(LocalDensity.current) { 12.dp.toSp() }
    BrandText(
        text,
        MemoBookFont.caption.copy(fontFamily = BrandFonts.generalSans, fontWeight = FontWeight.SemiBold, fontSize = size),
        maxLines = 1,
    )
}

@Preview(locale = "fr-rFR", name = "Couverture et co-voyageurs", widthDp = 390)
@Composable
private fun TripCoverPreview() {
    val companions = listOf("Camille Martin", "Paul Fournier", "Hugo Jouffre", "Clara Moreau", "Léa Petit")
        .mapIndexed { index, name -> Companion(id = "c$index", name = name) }
    Box(Modifier.background(MemoBookColor.background).padding(MemoBookSpacing.screenMargin)) {
        TripCover(
            Trip(id = "1CE0FEED-0000-4000-A000-000000000001", title = "Rome et la Dolce Vita", stage = TripStage.Ongoing, companions = companions),
            aspectRatio = 16f / 9f,
        )
    }
}

@Preview(locale = "fr-rFR", name = "Pile des co-voyageurs, avec le « + »")
@Composable
private fun CompanionStackPreview() {
    val companions = listOf("Camille Martin", "Paul Fournier").mapIndexed { index, name -> Companion(id = "c$index", name = name) }
    Box(Modifier.background(MemoBookColor.background).padding(MemoBookSpacing.s)) {
        CompanionStack(companions, onAdd = {}, facesLabel = "Camille et Paul racontent ce voyage")
    }
}
