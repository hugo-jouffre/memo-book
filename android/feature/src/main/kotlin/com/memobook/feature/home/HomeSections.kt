package com.memobook.feature.home

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.memobook.core.HomeFeed
import com.memobook.core.Showcase
import com.memobook.design.BrandTagPill
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.brandDashedCard
import com.memobook.design.isAccessibilityTextSize
import com.memobook.design.scaled

// Les pièces des sections de l'accueil. Jumeau de `Home/HomeSections.swift`.

/**
 * Le titre d'une section de l'accueil, avec ses deux décorations possibles :
 * le point vert qui signale « en ce moment », et la pastille qui compte ce que
 * la section contient ([CountBadge]).
 *
 * @param onAdd ouvrir un nouveau carnet. Fournie, elle pose un « + » au bout de
 *   la ligne — sur « Ton voyage », ou sur « Voyage à venir » quand rien n'est en
 *   cours (Hugo, 15/09/2026). C'était la seule chose qui manquait à quelqu'un
 *   qui a déjà un voyage ouvert : le CTA du bas parle alors du micro, et la
 *   carte pointillée qui ouvrait la feuille n'apparaît que sans voyage.
 */
@Composable
fun HomeSectionHeading(
    title: String,
    modifier: Modifier = Modifier,
    showsLiveDot: Boolean = false,
    count: Int? = null,
    onAdd: (() -> Unit)? = null,
) {
    val dotSide = scaled(9.dp)
    val dotLift = with(LocalDensity.current) { 1.dp.roundToPx() }

    // Avec un « + », la ligne garde ses deux éléments pour TalkBack : le titre
    // en entête, et le bouton — les fondre l'aurait fait disparaître du curseur.
    val semantics = if (onAdd == null) {
        Modifier.semantics(mergeDescendants = true) { heading() }
    } else {
        Modifier
    }

    // Espacement nul : c'est le décalage de la pastille qui la place, et il la
    // fait mordre sur la dernière lettre du titre.
    Row(modifier.fillMaxWidth().then(semantics), verticalAlignment = Alignment.Top) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            if (showsLiveDot) {
                Box(
                    Modifier
                        // Le point se cale sur la hauteur d'x du titre plutôt
                        // que sur sa ligne de base, où il flotterait : son bas
                        // pose un point au-dessus de la ligne de base.
                        .alignBy { it.measuredHeight + dotLift }
                        .size(dotSide)
                        // Le vert clair, pas celui du CTA : c'est un voyant, pas
                        // une action. (`Green Lighter`, à confirmer sur le nœud
                        // Figma.)
                        .background(MemoBookColor.actionLight, CircleShape)
                        .clearAndSetSemantics {},
                )
            }

            BrandText(
                title,
                MemoBookFont.heading,
                color = MemoBookColor.ink,
                modifier = Modifier
                    .alignByBaseline()
                    .then(if (onAdd != null) Modifier.semantics { heading() } else Modifier),
            )
        }

        if (count != null && count > 0) {
            CountBadge(
                count,
                // Elle est dessinée après le titre, donc au-dessus : elle
                // chevauche la fin du mot au lieu de le suivre.
                Modifier.offset(x = (-11).dp, y = -MemoBookSpacing.xs),
            )
        }

        Spacer(Modifier.weight(1f))

        if (onAdd != null) {
            HomeAddButton(
                onAdd,
                // Le rond fait 48 de cible, le titre une ligne de 26 : la marge
                // négative le centre sur la ligne sans que la section grandisse
                // de sa moitié.
                Modifier.verticalOverhang((MemoBookSpacing.minimumTapTarget - 26.dp) / 2),
            )
        }
    }
}

/**
 * Une marge négative en haut et en bas — le `.padding(.vertical, -x)` d'iOS,
 * que Compose n'a pas : la mise en page déclare une hauteur réduite et pose le
 * contenu en retrait, qui déborde de son cadre sans le pousser.
 */
private fun Modifier.verticalOverhang(amount: Dp): Modifier = layout { measurable, constraints ->
    val inset = amount.roundToPx()
    val placeable = measurable.measure(constraints.copy(minHeight = 0, maxHeight = Constraints.Infinity))
    val height = (placeable.height - 2 * inset).coerceAtLeast(0)
    layout(placeable.width, height) { placeable.place(0, -inset) }
}

/**
 * Le « + » d'une section de voyages : ouvrir un nouveau carnet.
 *
 * Le même rond que celui qui invite un co-voyageur en tête d'un voyage
 * ([CompanionStack]) — 34 de dessin, 48 de cible —, cerné de bleu ici parce
 * qu'il se pose sur le crème et non sur une photo : blanc sur crème sans filet,
 * il n'aurait pas l'air d'un bouton.
 */
@Composable
fun HomeAddButton(onClick: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(MemoBookSpacing.minimumTapTarget)
            .clip(CircleShape)
            .clickable(interactionSource = null, indication = PlainButtonIndication, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = "Ouvrir un nouveau carnet" },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(CompanionStack.diameter)
                .background(MemoBookColor.surface, CircleShape)
                .border(1.5.dp, MemoBookColor.outline, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Image(
                painterResource(R.drawable.icon_plus),
                contentDescription = null,
                colorFilter = ColorFilter.tint(MemoBookColor.ink),
                // Le glyphe n'occupe que la moitié de sa boîte — voir
                // `MemoBookSpacing.contentIcon` : 22 de boîte font 12 d'encre.
                modifier = Modifier.size(MemoBookSpacing.s + 6.dp),
            )
        }
    }
}

/**
 * La pastille qui compte les carnets d'une section.
 *
 * **Bleue à contour**, et non lime : la maquette montrait les deux, et Hugo a
 * tranché (14/09/2026, T36) — le lime ne parle que de l'abonnement, un compte
 * de voyages n'en parle pas. Elle compte les voyages **de la liste** qu'elle
 * coiffe, dont toutes les cartes sont visibles ; le « ×8 » d'une maquette à
 * carte unique était une erreur (T15).
 */
@Composable
fun CountBadge(count: Int, modifier: Modifier = Modifier) {
    BrandTagPill(
        "×$count",
        modifier.clearAndSetSemantics { contentDescription = "$count au total" },
        tone = BrandTagPill.Tone.Info,
    )
}

/**
 * La carte de découverte : un carnet d'exemple, pour comprendre où tout ça
 * mène avant d'avoir enregistré quoi que ce soit.
 *
 * Le pointillé la distingue des cartes de contenu : ce n'est pas un de tes
 * voyages, c'est une porte vers autre chose. L'image, elle, va **jusqu'au bord
 * droit** — elle n'est pas une vignette posée dans la carte, elle en est le
 * flanc.
 */
@Composable
fun ShowcaseCard(showcase: Showcase, modifier: Modifier = Modifier, onOpen: () -> Unit) {
    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)
    val minimumHeight = scaled(104.dp)

    Box(
        modifier
            .fillMaxWidth()
            .background(MemoBookColor.outline.copy(alpha = 0.22f), shape)
            // L'image touche les bords : c'est la carte qui la rogne.
            .clip(shape)
            .brandDashedCard(color = MemoBookColor.outline)
            .cardButton(onOpen),
    ) {
        // En taille accessible le texte a besoin de toute la largeur : l'image
        // passe dessous plutôt que de lui voler la moitié de la carte.
        if (isAccessibilityTextSize()) {
            Column(
                Modifier.heightIn(min = minimumHeight),
                verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
            ) {
                ShowcaseText(showcase, Modifier.padding(top = MemoBookSpacing.s).padding(horizontal = MemoBookSpacing.s))
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(minimumHeight),
                ) {
                    ShowcaseArtwork(showcase, Modifier.fillMaxSize())
                    ShowcaseArrow(Modifier.align(Alignment.BottomEnd).padding(MemoBookSpacing.xs + 4.dp))
                }
            }
        } else {
            ShowcaseRow(
                minimumHeight = minimumHeight,
                text = { ShowcaseText(showcase, Modifier.padding(MemoBookSpacing.s)) },
                artwork = {
                    Box {
                        ShowcaseArtwork(showcase, Modifier.fillMaxSize())
                        ShowcaseArrow(Modifier.align(Alignment.BottomEnd).padding(MemoBookSpacing.xs + 4.dp))
                    }
                },
            )
        }
    }
}

/**
 * Le texte à gauche, l'illustration sur toute la hauteur à droite — la
 * hauteur du texte, au moins [minimumHeight]. Une mise en page à elle : la
 * hauteur de l'image dépend de celle du texte, qu'une `Row` ne donne pas à ses
 * voisins.
 *
 * L'illustration fait 124 de large : assez étroit pour que le titre tienne sur
 * une ligne à la largeur de référence, assez large pour qu'on distingue les
 * carnets sur la photo.
 */
@Composable
private fun ShowcaseRow(minimumHeight: Dp, text: @Composable () -> Unit, artwork: @Composable () -> Unit) {
    Layout(contents = listOf(text, artwork)) { (textMeasurables, artworkMeasurables), constraints ->
        val artworkWidth = 124.dp.roundToPx()
        val gap = MemoBookSpacing.xs.roundToPx()
        val width = constraints.maxWidth
        val textWidth = (width - artworkWidth - gap).coerceAtLeast(0)
        val textPlaceables = textMeasurables.map { it.measure(Constraints(maxWidth = textWidth)) }
        val textHeight = textPlaceables.maxOfOrNull { it.height } ?: 0
        val height = maxOf(textHeight, minimumHeight.roundToPx(), constraints.minHeight)
        val artworkPlaceables = artworkMeasurables.map { it.measure(Constraints.fixed(artworkWidth, height)) }
        layout(width, height) {
            textPlaceables.forEach { it.place(0, (height - it.height) / 2) }
            artworkPlaceables.forEach { it.place(width - artworkWidth, 0) }
        }
    }
}

@Composable
private fun ShowcaseText(showcase: Showcase, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        BrandText(showcase.title, MemoBookFont.bodySemibold, color = MemoBookColor.blueText)
        // Le même bleu que le titre, un cran plus petit et plus léger : la
        // hiérarchie se fait au corps et à la graisse, pas avec un second bleu
        // — il n'y en a que trois dans la palette (T12).
        BrandText(showcase.subtitle, MemoBookFont.label, color = MemoBookColor.blueText)
    }
}

/**
 * Le flanc illustré : les carnets terminés.
 *
 * L'illustration est **livrée avec l'app** tant que le serveur n'en fournit
 * pas : c'est une image de marque, pas un contenu qui change avec les données.
 * Le jour où une campagne veut la sienne, `Showcase.imageUrl` la remplace sans
 * toucher à la vue.
 *
 * **L'image s'efface par la gauche, elle ne se recouvre pas.** L'app peignait
 * le fondu par-dessus — le crème de l'écran, puis le bleu à 22 % de la carte.
 * Mais l'illustration est détourée : ce crème opaque remplissait ses vides, et
 * cachait le motif de la marque qui passe sous la carte translucide. Une bande
 * beige coupait donc l'image à gauche (Hugo, 30/09/2026). Un masque d'opacité
 * ne pose aucune couleur : l'image devient transparente, et c'est la carte qui
 * se voit au travers. L'export du 19/09 fait 444 × 340 px pour un cadre de
 * 124 dp — net jusqu'en 3×.
 */
@Composable
private fun ShowcaseArtwork(showcase: Showcase, modifier: Modifier = Modifier) {
    val fallback = painterResource(R.drawable.showcase_carnets)
    val imageModifier = modifier
        .clearAndSetSemantics {}
        .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)
        .drawWithContent {
            drawContent()
            // Jusqu'où le fondu mord sur l'image : un peu moins de la moitié.
            drawRect(
                Brush.horizontalGradient(
                    0f to Color.Transparent,
                    0.5f to Color.Black.copy(alpha = 0.4f),
                    1f to Color.Black,
                    startX = 0f,
                    endX = size.width * ShowcaseFadeEnd,
                ),
                blendMode = BlendMode.DstIn,
            )
        }
    val url = showcase.imageUrl
    if (url == null) {
        Image(fallback, contentDescription = null, contentScale = ContentScale.Crop, modifier = imageModifier)
    } else {
        AsyncImage(
            model = url.toString(),
            contentDescription = null,
            placeholder = fallback,
            error = fallback,
            fallback = fallback,
            contentScale = ContentScale.Crop,
            modifier = imageModifier,
        )
    }
}

/** Jusqu'où le fondu mord sur l'image : un peu moins de la moitié. */
private const val ShowcaseFadeEnd = 0.45f

/**
 * Rond blanc cerclé de bleu, posé à cheval sur l'image.
 *
 * `IconArrowRight` et non `IconArrow` : celle du jeu de marque pointe à
 * **gauche**, c'est une flèche de retour.
 */
@Composable
private fun ShowcaseArrow(modifier: Modifier = Modifier) {
    Image(
        painterResource(R.drawable.icon_arrow_right),
        contentDescription = null,
        colorFilter = ColorFilter.tint(MemoBookColor.blueText),
        modifier = modifier
            .background(MemoBookColor.surface, CircleShape)
            .border(1.5.dp, MemoBookColor.blueText, CircleShape)
            // Le rond garde ses 40 : c'est le dessin qui grandit dedans, pas le
            // rond — voir `MemoBookSpacing.contentIcon`.
            .padding(MemoBookSpacing.xs / 2)
            .size(MemoBookSpacing.contentIcon)
            .clearAndSetSemantics {},
    )
}

/**
 * L'invitation à préparer le prochain voyage, quand il n'y en a aucun en
 * cours.
 *
 * Un **pointillé** et non une carte pleine : ce cadre n'est pas un contenu,
 * c'est une place qui attend d'être remplie. C'est la même grammaire que le
 * bloc des voyages passés vides, et elle ne sert qu'à ça dans l'app.
 *
 * @param subtitle la seconde ligne : ce que le doigt déclenche. Elle change
 *   avec l'endroit où la carte est posée — ouvrir un carnet depuis l'accueil,
 *   voir les carnets de la communauté depuis la feuille des commandes.
 */
@Composable
fun UpcomingTripInvite(
    modifier: Modifier = Modifier,
    subtitle: String = "Clique ici pour ouvrir ton prochain carnet",
    onOpen: () -> Unit,
) {
    Box(modifier) {
        Column(
            Modifier
                .fillMaxWidth()
                .brandDashedCard(color = MemoBookColor.action)
                .cardButton(onOpen)
                .padding(MemoBookSpacing.s),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        ) {
            // Le carnet MemoBook fini, posé sur sa plaque beige.
            //
            // La plaque est **plus étroite que la carte** et l'illustration la
            // remplit jusqu'aux bords : c'est ce qui la fait lire comme une photo
            // posée dans le cadre, et non comme un fond de carte de plus. Le
            // beige, lui, ne sert qu'à ça — voir `MemoBookColor.beige`.
            Image(
                painterResource(R.drawable.empty_trip_illustration),
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .fillMaxWidth()
                    .background(MemoBookColor.beige, RoundedCornerShape(MemoBookSpacing.cornerRadius))
                    // De l'air au-dessus, rien en dessous : le carnet **pose**
                    // sur le bas de la plaque au lieu de flotter au milieu. La
                    // plaque se règle donc sur la hauteur de l'illustration, elle
                    // ne la centre pas.
                    .padding(top = MemoBookSpacing.s)
                    .padding(horizontal = MemoBookSpacing.xs),
            )

            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                BrandText("Commence à planifier ton prochain voyage", MemoBookFont.bodySemibold, color = MemoBookColor.ink)

                // La phrase suit la destination : elle dit ce que le doigt
                // déclenche, et rien d'autre. Sur l'accueil, la carte menait aux
                // carnets de la communauté et ouvre désormais la feuille
                // « Nouveau carnet » — à reprendre dans Figma.
                BrandText(subtitle, MemoBookFont.label, color = MemoBookColor.inkMuted)
            }
        }

        // Le bout de scotch qui déborde en haut du cadre.
        //
        // Même grammaire que celui de [FeaturedTripCard] : par-dessus la carte,
        // translucide — on voit le pointillé au travers — et de travers. C'est
        // ce débordement qui rattache le cadre à la page au lieu de le laisser
        // flotter dedans. Une moitié sur la carte, une moitié dans le vide, et à
        // distance du coin arrondi — posé dessus, il se lirait comme une
        // étiquette.
        CardTape(
            color = MemoBookColor.action.copy(alpha = 0.18f),
            width = 72.dp,
            height = 26.dp,
            degrees = -4f,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(end = MemoBookSpacing.l)
                .offset(y = (-11).dp),
        )
    }
}

/** La place que prendront les carnets terminés. */
@Composable
fun PastTripsPlaceholder(modifier: Modifier = Modifier) {
    BrandText(
        "Tes voyages passés s’afficheront ici",
        MemoBookFont.body,
        color = MemoBookColor.inkMuted,
        modifier = modifier
            .fillMaxWidth()
            .brandDashedCard()
            .padding(vertical = MemoBookSpacing.s)
            .padding(MemoBookSpacing.s),
    )
}

// MARK: - Aperçus

@Preview(locale = "fr-rFR", name = "Sections de l’accueil", widthDp = 390, heightDp = 900)
@Composable
private fun HomeSectionsPreview() {
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
    ) {
        HomeSectionHeading("Ton voyage", showsLiveDot = true, onAdd = {})
        HomeSectionHeading("Voyages précédents", count = 3)
        UpcomingTripInvite {}
        PastTripsPlaceholder()
        HomeFeed.fixture.showcase?.let { ShowcaseCard(it) {} }
    }
}
