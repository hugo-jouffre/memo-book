package com.memobook.feature.tripsettings

import androidx.annotation.DrawableRes
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.core.BookCopy
import com.memobook.design.BrandHeaderAction
import com.memobook.design.BrandScreenHeader
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandText
import com.memobook.design.ErrorBanner
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.isReduceMotionEnabled
import com.memobook.design.scaled
import com.memobook.feature.BookCustomisationIntent
import kotlinx.coroutines.launch

/**
 * Les personnalisations du carnet : ce qui décide de sa mise en page. Jumeau de
 * `TripSettings/BookCustomisationView.swift`.
 *
 * On y arrive par la ligne « Style du carnet » des paramètres du voyage.
 * **C'est la V3 de la maquette** (`3595:23801` à `3595:24027`, Hugo,
 * 29/09/2026) : les deux pages du carnet et cinq pastilles de catégorie sont
 * **fixes en tête**, et c'est le réglage de la catégorie choisie qui défile sous
 * elles — ratio média, nombre de pages, décorations, typographies, extras. Il y
 * avait avant une liste de lignes ouvrant chacune sa feuille ; on réglait sans
 * voir, et on rouvrait une feuille par réglage.
 *
 * **Le contenu passe derrière la tête et s'y estompe** (`3595:23846`) : un voile
 * crème sous les pastilles, qui fond sur les premiers points du défilement. Ce
 * qui est derrière n'existe plus ; ce qui approche s'éteint.
 *
 * **Un réglage part dès qu'il est touché**, comme partout dans les réglages :
 * pas de « Valider ». Les feuilles en avaient un, qui ne faisait que fermer.
 */
@Composable
fun BookCustomisationView(
    model: BookCustomisationModel,
    onIntent: (BookCustomisationIntent) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val state by model.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val reduceMotion = isReduceMotionEnabled()
    val scroll = rememberScrollState()
    val density = LocalDensity.current

    // La catégorie ouverte. Le ratio média d'abord, comme la maquette.
    var category by rememberSaveable { mutableStateOf(BookCustomisationCategory.Ratio) }

    // La hauteur de la tête fixe, mesurée : c'est de là que le contenu part.
    var headerHeight by remember { mutableIntStateOf(0) }

    LaunchedEffect(model) { model.load() }

    // Changer de catégorie ramène en haut : un panneau court hériterait sinon du
    // défilement du panneau long qu'on vient de quitter, et resterait à moitié
    // derrière la tête.
    var shownCategory by remember { mutableStateOf(category) }
    LaunchedEffect(category) {
        if (category == shownCategory) return@LaunchedEffect
        shownCategory = category
        if (reduceMotion) scroll.scrollTo(0) else scroll.animateScrollTo(0, SwiftMotion.smooth(0.3f))
    }

    Box(modifier.fillMaxSize().background(MemoBookColor.background)) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(scroll)
                .navigationBarsPadding()
                .padding(horizontal = MemoBookSpacing.screenMargin)
                .padding(bottom = MemoBookSpacing.l),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        ) {
            // La place de la tête, qui est posée par-dessus.
            Spacer(Modifier.height(with(density) { headerHeight.toDp() }))

            AnimatedContent(
                category,
                transitionSpec = {
                    val enter = if (reduceMotion) fadeIn() else fadeIn() + slideInVertically(SwiftMotion.smooth(0.3f)) { it }
                    val exit = if (reduceMotion) fadeOut() else fadeOut() + slideOutVertically(SwiftMotion.smooth(0.3f)) { it }
                    (enter togetherWith exit).using(SizeTransform(clip = false))
                },
                label = "panneau",
            ) { shown ->
                when (shown) {
                    BookCustomisationCategory.Ratio -> BookRatioPanel(model)
                    BookCustomisationCategory.Pages -> BookPagesPanel(model)
                    BookCustomisationCategory.Decorations -> BookDecorationsPanel(model)
                    BookCustomisationCategory.Fonts -> BookFontsPanel(model)
                    BookCustomisationCategory.Extras -> BookExtrasPanel(model)
                }
            }

            state.errorMessage?.let { message ->
                // Le constat, le conseil, et les deux gestes — comme sur les
                // paramètres du voyage (Hugo, 15/09/2026).
                ErrorBanner(
                    message = message,
                    advice = state.errorAdvice,
                    retry = { scope.launch { model.load() } },
                    help = { onIntent(BookCustomisationIntent.OpenHelp) },
                )
            }
        }

        Header(
            state = state,
            category = category,
            onCategoryChange = { category = it },
            onIntent = onIntent,
            onBack = onBack,
            modifier = Modifier.onSizeChanged { headerHeight = it.height },
        )
    }

    // Le changement de nombre de pages cible, quand il compte : une seule
    // feuille, dont le modèle fait avancer le contenu. La refermer au glissé,
    // c'est « Annuler » ou « OK » — sauf pendant un envoi : on ne saurait plus
    // si la cible a changé.
    BrandSheetHost(
        item = state.pageTargetChange,
        onDismissRequest = model::dismissPageTargetChange,
        dismissDisabled = state.pageTargetChange?.isWorking == true,
    ) {
        PageTargetChangeSheet(model)
    }

    // La cible personnalisée hors d'atteinte (18/10/2026).
    BrandSheetHost(item = state.pageTargetReach, onDismissRequest = model::dismissPageTargetReach) { reach ->
        PageTargetReachSheet(reach, model)
    }
}

// MARK: - La tête fixe

/** Le titre, les deux pages et les pastilles — et le voile qui éteint ce qui passe dessous. */
@Composable
private fun Header(
    state: BookCustomisationModel.State,
    category: BookCustomisationCategory,
    onCategoryChange: (BookCustomisationCategory) -> Unit,
    onIntent: (BookCustomisationIntent) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(modifier.fillMaxWidth()) {
        Column(
            Modifier
                .fillMaxWidth()
                .background(MemoBookColor.background)
                .statusBarsPadding()
                .padding(bottom = MemoBookSpacing.xs),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        ) {
            BrandScreenHeader(
                BookCopy.Customisation.title,
                onBack = onBack,
                modifier = Modifier
                    .padding(horizontal = MemoBookSpacing.screenMargin)
                    .padding(top = MemoBookSpacing.xs),
                trailing = { HeaderActions(onIntent) },
            )

            // L'aperçu de personnalisation, et non plus les pages du PDF
            // composé : c'est lui qui suit les réglages (Hugo, 02/10/2026).
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                BookCustomisationPreviewView(state.previewURL)
            }

            Categories(category, onCategoryChange)
        }

        // **L'estompe** : le contenu qui monte vers les pastilles s'éteint sur
        // ces seize points, et n'existe plus derrière. C'est le dégradé de la
        // maquette (`3595:23876`), ramené à ce qu'on en voit.
        Box(
            Modifier
                .align(Alignment.BottomCenter)
                .offset(y = MemoBookSpacing.s)
                .fillMaxWidth()
                .height(MemoBookSpacing.s)
                .background(Brush.verticalGradient(listOf(MemoBookColor.background, MemoBookColor.background.copy(alpha = 0f)))),
        )
    }
}

/**
 * **Deux commandes en haut à droite** (Hugo, 06/10/2026, T197 et T224) : les
 * couvertures, et l'aperçu PDF.
 *
 * Plus rien ne menait aux couvertures depuis cet écran (la V3 ne dessine pas
 * leur ligne), et l'aperçu — ce que les réglages vont changer — était à deux
 * écrans. Les deux prennent la forme des commandes d'en-tête de l'app : une
 * icône cerclée de 2.75 rem, son nom dit à TalkBack. L'aperçu porte
 * **l'imprimante**, comme sur l'accueil du voyage et la conversation : la même
 * destination, le même signe — et l'ouvrir lance la composition, comme partout.
 *
 * ⚠️ « Au plus une action » en tête d'écran, dit `BrandScreenHeader` : l'écart
 * est demandé. Côte à côte et non empilées, parce que la tête est fixe —
 * empilées, elles prendraient au réglage une ligne de hauteur ; le titre, lui,
 * passe à la ligne (deux lignes sur un petit téléphone).
 */
@Composable
private fun HeaderActions(onIntent: (BookCustomisationIntent) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
        BrandHeaderAction(R.drawable.icon_picture_frame, BookCopy.Preview.configureCovers) {
            onIntent(BookCustomisationIntent.OpenCovers)
        }
        BrandHeaderAction(R.drawable.icon_printer, BookCopy.Settings.pdfPreview) {
            onIntent(BookCustomisationIntent.OpenBookPreview)
        }
    }
}

/**
 * Les cinq pastilles, en bande qui défile : « Décorations & stickers » ne tient
 * pas sur une largeur de téléphone avec les quatre autres, et la maquette la
 * laisse sortir par le bord droit.
 */
@Composable
private fun Categories(selection: BookCustomisationCategory, onSelect: (BookCustomisationCategory) -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .semantics {
                isTraversalGroup = true
                contentDescription = "Catégories de personnalisation"
            }
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = MemoBookSpacing.screenMargin),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        BookCustomisationCategory.entries.forEach { item ->
            BookCategoryChip(item, isSelected = item == selection) { onSelect(item) }
        }
    }
}

// MARK: - Les catégories

/** Les cinq pastilles de la tête, dans l'ordre de la maquette. */
internal enum class BookCustomisationCategory(val rawValue: String) {
    Ratio("ratio"),
    Pages("pages"),
    Decorations("decorations"),
    Fonts("fonts"),
    Extras("extras"),
    ;

    val id: String get() = rawValue

    /**
     * Le libellé, **au caractère près** (R8) : « Typos » ; « Nombre de pages »
     * en entier depuis T214.
     */
    val title: String
        get() = when (this) {
            Ratio -> BookCopy.Customisation.categoryRatio
            Pages -> BookCopy.Customisation.categoryPages
            Decorations -> BookCopy.Customisation.categoryDecorations
            Fonts -> BookCopy.Customisation.categoryFonts
            Extras -> BookCopy.Customisation.categoryExtras
        }

    /**
     * Le pictogramme de la pastille, exporté du nœud (`3595:23807`) dans
     * `assets/icons/brand-icons/Category *.svg` — cinq tracés d'encre, à teindre.
     */
    @get:DrawableRes
    val icon: Int
        get() = when (this) {
            Ratio -> R.drawable.icon_category_ratio
            Pages -> R.drawable.icon_category_pages
            Decorations -> R.drawable.icon_category_decorations
            Fonts -> R.drawable.icon_category_typos
            Extras -> R.drawable.icon_category_extras
        }
}

/**
 * Une pastille de catégorie : le pictogramme et le mot, en capsule — bleue quand
 * elle est choisie, papier sinon (`3595:23808`).
 */
@Composable
private fun BookCategoryChip(category: BookCustomisationCategory, isSelected: Boolean, action: () -> Unit) {
    val iconSide = scaled(MemoBookSpacing.snug)
    val fill by animateColorAsState(
        if (isSelected) MemoBookColor.outline else MemoBookColor.surface,
        SwiftMotion.snappy(0.2f),
        label = "pastille",
    )

    // La cible reste à 48, la pastille dessinée plus basse (R7).
    Box(
        Modifier
            .heightIn(min = MemoBookSpacing.minimumTapTarget)
            .selectable(
                selected = isSelected,
                role = Role.Tab,
                interactionSource = null,
                indication = PlainButtonIndication,
                onClick = action,
            ),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            Modifier
                .background(fill, RoundedCornerShape(percent = 50))
                .padding(MemoBookSpacing.snug),
            horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Image(
                painterResource(category.icon),
                contentDescription = null,
                colorFilter = ColorFilter.tint(MemoBookColor.ink),
                modifier = Modifier.size(iconSide),
            )
            BrandText(category.title, MemoBookFont.overline, maxLines = 1)
        }
    }
}

@Preview(locale = "fr-rFR", name = "Personnalisations du carnet", widthDp = 390, heightDp = 844)
@Composable
private fun BookCustomisationViewPreview() {
    BookCustomisationView(remember { BookCustomisationModel(tripId = "preview") }, onIntent = {}, onBack = {})
}

@Preview(locale = "fr-rFR", name = "Personnalisations — police à 200 %", widthDp = 390, heightDp = 844, fontScale = 2f)
@Composable
private fun BookCustomisationViewLargeTextPreview() {
    BookCustomisationView(remember { BookCustomisationModel(tripId = "preview") }, onIntent = {}, onBack = {})
}
