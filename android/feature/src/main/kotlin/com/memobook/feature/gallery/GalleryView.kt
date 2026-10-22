package com.memobook.feature.gallery

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Density
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.memobook.core.Gallery
import com.memobook.design.BrandButton
import com.memobook.design.BrandFilterChip
import com.memobook.design.BrandRefreshFlash
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandText
import com.memobook.design.DeviceScreen
import com.memobook.design.ErrorBanner
import com.memobook.design.LucideIcon
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.Refreshable
import com.memobook.design.brandFooterScrim
import com.memobook.design.brandHorizontalFade
import com.memobook.design.isAccessibilityTextSize
import com.memobook.feature.HomeIntent
import com.memobook.feature.home.NewNotebookSheet
import kotlinx.coroutines.launch
import kotlin.math.min

/**
 * Les carnets de la communauté : à quoi ressemble un MemoBook terminé, avant
 * d'en avoir un à soi. Jumeau de `Gallery/GalleryView.swift`.
 *
 * **L'écran ne contient aucun contenu.** Titres, phrases de résumé, pays,
 * catégories et jusqu'au pictogramme de chaque pastille viennent de la
 * `Gallery` que porte [GalleryModel]. Ce qui est écrit ici, ce sont les seuls
 * libellés qui appartiennent à l'interface : le titre de l'écran, la pastille
 * « Tout », les deux formulations du bouton et les états vides.
 *
 * **Le bouton du bas ne défile pas.** Même construction que l'accueil : un
 * voile qui dissout le contenu, et un appel à l'action posé par-dessus, dont le
 * contenu se réserve la place.
 *
 * **Les vignettes ne s'ouvrent pas.** Un carnet de la communauté n'a pas
 * d'écran : elles ne sont donc pas des boutons, et ne promettent rien.
 *
 * L'écran dessine son propre en-tête, comme le profil : la flèche et le titre
 * partagent une ligne, à la marge de la colonne.
 */
@Composable
fun GalleryView(
    model: GalleryModel,
    onIntent: (HomeIntent) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val state by model.state.collectAsStateWithLifecycle()
    val density = LocalDensity.current
    val isAccessibilitySize = isAccessibilityTextSize()

    // La feuille « Nouveau carnet », la même que celle de l'accueil. Une feuille
    // ne navigue pas, elle propose : ce qu'on y choisit redevient une
    // [HomeIntent] que `RootView` route.
    var isCreatingNotebook by remember { mutableStateOf(false) }

    // La hauteur du bouton, que le contenu se réserve.
    var callToActionHeight by remember { mutableIntStateOf(0) }

    // Le nombre de colonnes est la seule chose que la vue apprenne à son
    // modèle : il dépend de la taille de texte, que seule la composition
    // connaît. Une fois à l'ouverture, et à chaque changement du réglage.
    LaunchedEffect(isAccessibilitySize) { model.use(GalleryMetrics.columnCount(isAccessibilitySize)) }
    LaunchedEffect(model) { model.load() }

    BrandRefreshFlash(isUpdated = state.freshness.isUpdated, modifier = modifier.fillMaxSize()) {
        Box(
            Modifier
                .fillMaxSize()
                .background(MemoBookColor.background),
        ) {
            // L'en-tête et la barre de filtres restent en haut pendant que la
            // mosaïque défile dessous : c'est la barre qui commande la grille,
            // elle ne doit pas partir avec elle.
            //
            // ⚠️ **Au-dessus du défilement, pas dans lui** (Hugo, 30/09/2026).
            // Posée dans la zone de geste du défilement vertical, la barre
            // faisait aussi monter ou descendre la mosaïque, et tirer vers le bas
            // lançait le rafraîchissement. Une pile, et chaque doigt n'a plus
            // qu'un seul défilement sous lui.
            Column(Modifier.fillMaxSize()) {
                Column(
                    Modifier
                        .padding(top = DeviceScreen.topSafeInset() + MemoBookSpacing.xs)
                        .padding(bottom = MemoBookSpacing.xs),
                    verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
                ) {
                    GalleryHeader(onBack)
                    GalleryFilters(state, onSelect = model::select)
                }

                Box(Modifier.weight(1f)) {
                    // ⚠️ **Sur la grille seule**, pas sur l'écran : la bande
                    // horizontale des filtres ne doit pas prendre le geste du
                    // rafraîchissement — c'était le défilement vertical parasite
                    // d'iOS (Hugo, 30/09/2026).
                    Refreshable(onRefresh = { model.load() }, modifier = Modifier.fillMaxSize()) {
                        Column(
                            Modifier
                                .fillMaxSize()
                                .verticalScroll(rememberScrollState())
                                // L'écart de l'ancien encart (16) plus la marge
                                // du contenu (8).
                                .padding(top = MemoBookSpacing.s + MemoBookSpacing.xs)
                                // Le bouton est dessiné par la pile, pas ici :
                                // cette marge ne sert qu'à lui **réserver sa
                                // place**, pour que la dernière vignette puisse
                                // défiler jusqu'au-dessus de lui.
                                .padding(bottom = with(density) { callToActionHeight.toDp() } + MemoBookSpacing.m),
                            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
                        ) {
                            state.errorMessage?.let { message ->
                                ErrorBanner(
                                    message,
                                    modifier = Modifier.padding(horizontal = MemoBookSpacing.screenMargin),
                                    retry = { model.viewModelScope.launch { model.load() } },
                                )
                            }

                            GalleryGrid(state, isAccessibilitySize, onShowAll = { model.select(null) })
                        }
                    }

                    // Le voile du haut : les vignettes s'y **dissolvent** en
                    // passant sous la barre de filtres, au lieu de disparaître
                    // sur un trait net.
                    //
                    // Court — une gouttière et demie. Le voile du bas doit
                    // effacer un bloc de texte entier derrière un bouton ;
                    // celui-ci n'a qu'à adoucir un bord, et plus haut il
                    // mangerait la première rangée de la mosaïque.
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .height(MemoBookSpacing.m)
                            .background(Brush.verticalGradient(listOf(MemoBookColor.background, MemoBookColor.background.copy(alpha = 0f))))
                            .clearAndSetSemantics {},
                    )
                }
            }

            // Le même voile que sous le CTA de l'accueil, et pour la même
            // raison : deux écrans qui portent le même bouton au même endroit ne
            // peuvent pas se dissoudre différemment — voir `BrandFooterScrim`.
            GalleryCallToAction(
                resumableTripId = state.resumableTripId,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .onSizeChanged { callToActionHeight = it.height },
            ) {
                val tripId = state.resumableTripId
                if (tripId != null) onIntent(HomeIntent.OpenTrip(tripId)) else isCreatingNotebook = true
            }
        }
    }

    BrandSheetHost(isPresented = isCreatingNotebook, onDismissRequest = { isCreatingNotebook = false }) {
        // Aucun carnet à reprendre ici : quand il y en a un, c'est le bouton
        // lui-même qui y mène et cette feuille ne s'ouvre pas.
        NewNotebookSheet(resumableTrip = null, onIntent = onIntent)
    }
}

// MARK: - En-tête

@Composable
private fun GalleryHeader(onBack: () -> Unit) {
    Row(
        Modifier.padding(horizontal = MemoBookSpacing.screenMargin),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(MemoBookSpacing.minimumTapTarget)
                .clickable(interactionSource = null, indication = PlainButtonIndication, role = Role.Button, onClick = onBack)
                .semantics { contentDescription = "Retour" },
            contentAlignment = Alignment.Center,
        ) {
            // La bichrome, en bleu : c'est le seul retour de l'écran, comme sur
            // le profil.
            Image(
                painterResource(R.drawable.icon_arrow_duo),
                contentDescription = null,
                modifier = Modifier.size(MemoBookSpacing.navigationIcon),
            )
        }

        BrandText(
            "Exemples de carnets",
            MemoBookFont.h2,
            color = MemoBookColor.ink,
            modifier = Modifier
                .weight(1f)
                .semantics { heading() },
        )
    }
}

// MARK: - Les filtres

/**
 * La barre de catégories : « Tout », puis une pastille par catégorie de la
 * base.
 *
 * Un seul filtre à la fois. Retoucher la pastille cochée revient à « Tout » :
 * c'est le geste qu'on fait spontanément pour défaire un filtre, et l'écran n'a
 * pas de bouton « Tout afficher » — sa première pastille en tient lieu.
 *
 * La bande prend toute la largeur de l'écran et son contenu s'aligne sur la
 * colonne : la dernière pastille peut donc sortir par le bord au lieu de buter
 * sur une marge — et ce qui en sort s'y **efface** au lieu d'être tranché à la
 * verticale (`brandHorizontalFade`).
 */
@Composable
private fun GalleryFilters(state: GalleryModel.State, onSelect: (String?) -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .brandHorizontalFade()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = MemoBookSpacing.screenMargin),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        // Les trois traits du filtre ne sont plus là : la maquette les dessinait
        // sans action, l'app les rendait décoratifs (T39), et un pictogramme
        // qu'on ne peut pas toucher en tête d'une ligne de pastilles déroutait
        // plus qu'il n'annonçait (Clara, 17/09/2026). La première pastille,
        // « Tout », ouvre la ligne.
        GalleryChip("Tout", icon = null, isActive = state.selectedCategoryId == null) { onSelect(null) }

        state.categories.forEach { category ->
            val isActive = state.selectedCategoryId == category.id
            GalleryChip(category.name, icon = LucideIcon.image(category.iconKey), isActive = isActive) {
                onSelect(if (isActive) null else category.id)
            }
        }
    }
}

/**
 * Une pastille de la barre.
 *
 * Un vrai bouton : c'est lui qui donne le geste à TalkBack, à l'Accès via
 * bouton et au clavier externe. `selected` dit **laquelle est cochée**, ce que
 * le vert seul ne dit qu'à ceux qui le voient.
 */
@Composable
private fun GalleryChip(title: String, icon: Int?, isActive: Boolean, select: () -> Unit) {
    BrandFilterChip(
        title,
        Modifier
            .clickable(interactionSource = null, indication = PlainButtonIndication, role = Role.Button, onClick = select)
            .semantics { selected = isActive },
        icon = icon?.let { painterResource(it) },
        kind = BrandFilterChip.Kind.Toggle,
        isActive = isActive,
    )
}

// MARK: - La mosaïque

@Composable
private fun GalleryGrid(state: GalleryModel.State, isAccessibilitySize: Boolean, onShowAll: () -> Unit) {
    when {
        state.isLoading -> GalleryPlaceholders(GalleryMetrics.columnCount(isAccessibilitySize))
        state.isEmpty -> GalleryEmptyState(isFiltered = state.selectedCategoryId != null, onShowAll = onShowAll)
        else -> Row(
            Modifier.padding(horizontal = MemoBookSpacing.screenMargin),
            horizontalArrangement = Arrangement.spacedBy(GalleryMetrics.gutter),
            verticalAlignment = Alignment.Top,
        ) {
            state.columns.forEach { column ->
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(GalleryMetrics.gutter)) {
                    column.forEach { trip -> GalleryTripCard(trip) }
                }
            }
        }
    }
}

/** La grille d'attente : les mêmes colonnes, les mêmes gouttières, des vignettes vides. */
@Composable
private fun GalleryPlaceholders(count: Int) {
    Row(
        Modifier.padding(horizontal = MemoBookSpacing.screenMargin),
        horizontalArrangement = Arrangement.spacedBy(GalleryMetrics.gutter),
        verticalAlignment = Alignment.Top,
    ) {
        for (column in 0 until count) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(GalleryMetrics.gutter)) {
                for (rank in column until 6 step count) GalleryCardPlaceholder(rank)
            }
        }
    }
}

/**
 * Deux vides très différents : une galerie qui n'a encore rien, et une
 * catégorie qui ne range rien. Aucun des deux n'est maquetté — voir la fiche
 * écran.
 */
@Composable
private fun GalleryEmptyState(isFiltered: Boolean, onShowAll: () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = MemoBookSpacing.screenMargin)
            .padding(horizontal = MemoBookSpacing.s)
            .padding(vertical = MemoBookSpacing.xl),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        BrandText(
            if (isFiltered) "Aucun carnet dans cette catégorie" else "Les premiers carnets arrivent",
            MemoBookFont.bodySemibold,
            color = MemoBookColor.ink,
            textAlign = TextAlign.Center,
        )
        BrandText(
            if (isFiltered) "Choisis « Tout » pour revoir tous les carnets." else "Reviens bientôt : la communauté partage ses carnets terminés ici.",
            MemoBookFont.label,
            color = MemoBookColor.inkMuted,
            textAlign = TextAlign.Center,
        )
        if (isFiltered) {
            BrandButton("Tout afficher", Modifier.padding(top = MemoBookSpacing.xs), style = BrandButton.Style.Link, action = onShowAll)
        }
    }
}

// MARK: - Action

/**
 * Ce que le bouton propose dépend de ce qu'il y a à faire.
 *
 * Un carnet déjà ouvert — en cours, ou un départ prévu : on y **retourne**, et
 * la flèche dit qu'on reprend le fil. Aucun : on en **crée** un, et c'est le
 * plus qui le dit. La même question que sur l'accueil, et c'est le serveur qui
 * y répond pour les deux écrans — voir `Gallery.resumableTripId`.
 *
 * Même limite que le CTA de l'accueil : au-delà de la première taille
 * accessible, une barre ancrée en bas prend la moitié de l'écran et cache ce
 * qu'elle sert à enrichir.
 */
@Composable
private fun GalleryCallToAction(resumableTripId: String?, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val density = LocalDensity.current
    val capped = Density(density.density, fontScale = min(density.fontScale, 1.5f))
    CompositionLocalProvider(LocalDensity provides capped) {
        Box(
            modifier
                .fillMaxWidth()
                .brandFooterScrim()
                .navigationBarsPadding()
                .padding(horizontal = MemoBookSpacing.screenMargin)
                .padding(top = MemoBookSpacing.s, bottom = MemoBookSpacing.xs),
        ) {
            BrandButton(
                if (resumableTripId == null) "Créer mon voyage" else "Continuer mon voyage",
                icon = painterResource(if (resumableTripId == null) R.drawable.icon_plus else R.drawable.icon_arrow_right),
                style = BrandButton.Style.Primary,
                fillsWidth = true,
                action = onClick,
            )
        }
    }
}

// MARK: - Aperçus

@Preview(locale = "fr-rFR", name = "Exemples de carnets", widthDp = 390, heightDp = 844)
@Composable
private fun GalleryViewPreview() {
    GalleryView(remember { GalleryModel() }, onIntent = {}, onBack = {})
}

@Preview(locale = "fr-rFR", name = "Exemples — aucun voyage en cours", widthDp = 390, heightDp = 844)
@Composable
private fun GalleryViewNoTripPreview() {
    GalleryView(remember { GalleryModel(source = { Gallery.emptyTravellerFixture }) }, onIntent = {}, onBack = {})
}

@Preview(locale = "fr-rFR", name = "Exemples — galerie vide", widthDp = 390, heightDp = 844)
@Composable
private fun GalleryViewEmptyPreview() {
    GalleryView(remember { GalleryModel(source = { Gallery() }) }, onIntent = {}, onBack = {})
}

@Preview(locale = "fr-rFR", name = "Exemples — erreur", widthDp = 390, heightDp = 844)
@Composable
private fun GalleryViewErrorPreview() {
    GalleryView(remember { GalleryModel(source = { throw java.io.IOException("La connexion Internet semble être désactivée.") }) }, onIntent = {}, onBack = {})
}

@Preview(locale = "fr-rFR", name = "Exemples — AX3", widthDp = 390, heightDp = 844, fontScale = 2f)
@Composable
private fun GalleryViewAccessibilityPreview() {
    GalleryView(remember { GalleryModel() }, onIntent = {}, onBack = {})
}
