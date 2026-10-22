package com.memobook.feature.profile

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.memobook.core.CurrentTripStatistics
import com.memobook.core.TravelFigures
import com.memobook.core.TravelStatistics
import com.memobook.design.ActivitySpinner
import com.memobook.design.BrandRefreshFlash
import com.memobook.design.BrandSheet
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandSkeleton
import com.memobook.design.BrandText
import com.memobook.design.ErrorBanner
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.isAccessibilityTextSize
import com.memobook.design.isReduceMotionEnabled
import com.memobook.design.scaled
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.time.Duration.Companion.seconds

/**
 * Les chiffres du voyageur : tous ses voyages, puis celui en cours. Jumeau de
 * `Profile/StatisticsSheet.swift`.
 *
 * **La feuille ne calcule rien.** Chaque chiffre vient du relevé que l'agent
 * de rédaction pose sur un souvenir, additionné par le serveur ; elle les
 * dessine, les accorde, et **les relit tant que l'agent en relève** — voir
 * [StatisticsModel.watch]. Un vocal qui vient de partir se voit arriver ici :
 * la ligne du bas dit qu'il est en lecture, puis les chiffres bougent.
 *
 * Une seule carte cerclée de vert, en deux volets qui se replient chacun :
 * c'est la carte de chiffres du profil, dépliée. Les deux volets s'ouvrent
 * par défaut — on vient les lire, pas les chercher.
 */
@Composable
internal fun StatisticsSheet(model: StatisticsModel) {
    val state by model.state.collectAsStateWithLifecycle(context = Dispatchers.Main.immediate)
    val deliveries by model.deliveries.collectAsStateWithLifecycle()

    // Chaque volet se replie séparément, comme les deux chevrons de la
    // maquette le promettent. L'état appartient à la feuille, et repart ouvert
    // à chaque ouverture : un volet qu'on a replié hier n'a pas à l'être
    // encore aujourd'hui.
    var showsOverall by remember { mutableStateOf(true) }
    var showsCurrentTrip by remember { mutableStateOf(true) }

    // La veille : lit, puis relit tant qu'un relevé est attendu. L'effet meurt
    // avec la feuille, et **repart** à chaque vocal livré — c'est sa clé qui
    // le fait, sans minuterie ni notification.
    LaunchedEffect(deliveries) { model.watch() }

    BrandSheet("Statistiques") {
        // Ce que la feuille montre change sous les yeux, et elle le dit : le
        // même balayage que l'accueil, seulement quand un chiffre a vraiment
        // bougé — jamais à la relance d'une veille immobile.
        BrandRefreshFlash(state.freshness.isUpdated) {
            Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
                StatisticsCard(
                    statistics = state.statistics,
                    showsOverall = showsOverall,
                    onShowsOverallChange = { showsOverall = it },
                    showsCurrentTrip = showsCurrentTrip,
                    onShowsCurrentTripChange = { showsCurrentTrip = it },
                )

                state.errorMessage?.let { message ->
                    ErrorBanner(message, retry = { model.viewModelScope.launch { model.load() } })
                }
            }
        }
    }
}

// MARK: - La carte

@Composable
private fun StatisticsCard(
    statistics: TravelStatistics?,
    showsOverall: Boolean,
    onShowsOverallChange: (Boolean) -> Unit,
    showsCurrentTrip: Boolean,
    onShowsCurrentTripChange: (Boolean) -> Unit,
) {
    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)
    val reduceMotion = isReduceMotionEnabled()
    Column(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(MemoBookColor.surface, shape)
            .border(1.5.dp, MemoBookColor.action, shape)
            // Un seul ressort pour tout ce qui bouge dans la carte : les volets,
            // les chiffres, la ligne du bas. Deux animations de durées
            // différentes sur la même carte se lisent comme un défaut de
            // synchronisation.
            .then(if (reduceMotion) Modifier else Modifier.animateContentSize(SwiftMotion.snappy(0.32f))),
    ) {
        OverallSection(statistics, showsOverall, onShowsOverallChange)
        // Le filet entre les deux volets suit le contour de la carte, comme
        // dans `BrandRowGroup` : un trait gris dans un cadre vert se lirait
        // comme un oubli.
        Box(
            Modifier
                .padding(horizontal = MemoBookSpacing.s)
                .fillMaxWidth()
                .height(1.dp)
                .background(MemoBookColor.action)
                .clearAndSetSemantics {},
        )
        CurrentTripSection(statistics, showsCurrentTrip, onShowsCurrentTripChange)
        DetectingLine(statistics?.detectingLabel)
    }
}

// MARK: Tous les voyages

@Composable
private fun OverallSection(statistics: TravelStatistics?, isExpanded: Boolean, onExpandedChange: (Boolean) -> Unit) {
    Column(Modifier.padding(MemoBookSpacing.s), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
        SectionHeader(title = "Statistiques", detail = statistics?.tripCountLabel, isExpanded = isExpanded, onExpandedChange = onExpandedChange)

        Folding(isExpanded) {
            Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
                StatisticLine("Étapes", statistics?.overall?.placesLabel)
                StatisticLine("Rencontres", statistics?.overall?.encountersLabel)
                StatisticLine("Km parcourus", statistics?.overall?.distanceLabel)
            }
        }
    }
}

// MARK: Le voyage en cours

@Composable
private fun CurrentTripSection(statistics: TravelStatistics?, isExpanded: Boolean, onExpandedChange: (Boolean) -> Unit) {
    val trip = statistics?.currentTrip
    Column(Modifier.padding(MemoBookSpacing.s), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
        SectionHeader(
            title = "Voyage en cours",
            // Sans voyage en cours, la carte reste et le dit — sa disparition
            // ferait sauter la feuille d'une hauteur de volet.
            detail = statistics?.let { it.currentTrip?.dateRangeLabel ?: "Aucun pour l’instant" },
            isExpanded = isExpanded,
            onExpandedChange = onExpandedChange,
        )

        Folding(isExpanded && (statistics == null || trip != null)) {
            CurrentTripBody(trip, overall = statistics?.overall)
        }
    }
}

/** Un volet qui se replie : il glisse du haut en apparaissant. */
@Composable
private fun Folding(visible: Boolean, content: @Composable () -> Unit) {
    val reduceMotion = isReduceMotionEnabled()
    AnimatedVisibility(
        visible = visible,
        enter = if (reduceMotion) fadeIn() else fadeIn(SwiftMotion.snappy(0.32f)) + expandVertically(SwiftMotion.snappy(0.32f), expandFrom = Alignment.Top),
        exit = if (reduceMotion) fadeOut() else fadeOut(SwiftMotion.snappy(0.32f)) + shrinkVertically(SwiftMotion.snappy(0.32f), shrinkTowards = Alignment.Top),
    ) { content() }
}

/**
 * Les deux anneaux à gauche, les phrases et les lignes à droite. Aux tailles
 * accessibles, les anneaux passent au-dessus : deux colonnes de texte de 30 pt
 * ne tiennent pas côte à côte.
 */
@Composable
private fun CurrentTripBody(trip: CurrentTripStatistics?, overall: TravelFigures?) {
    val rings: @Composable () -> Unit = {
        StatisticRing(
            fraction = trip?.writtenFraction ?: 0.0,
            value = trip?.writtenPercentLabel,
            caption = "du voyage",
            accessibilityLabel = "Part du voyage écrite",
        )
        StatisticRing(
            fraction = trip?.countryFraction(overall ?: TravelFigures.empty) ?: 0.0,
            value = trip?.let { "${it.figures.countries}" },
            caption = "pays",
            accessibilityLabel = "Pays de ce voyage",
        )
    }

    val text: @Composable (Modifier) -> Unit = { modifier ->
        Column(modifier, verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            Whereabouts(trip)

            StatisticLine("Étapes", trip?.figures?.placesLabel)
            StatisticLine("Rencontres", trip?.figures?.encountersLabel)
            StatisticLine("Km parcourus", trip?.figures?.distanceLabel)
            StatisticLine("Enregistrements", trip?.recordingsLabel)
            StatisticLine("Transports", trip?.transportsLabel)
        }
    }

    // Les anneaux grandissent avec le texte, mais pas jusqu'aux tailles
    // accessibles : à AX3, deux anneaux de 76 au corps de 53 feraient 240
    // chacun et déborderaient de l'écran — en emmenant toute la feuille. Ils
    // s'arrêtent au cran d'avant ; le texte qu'ils accompagnent, lui,
    // continue.
    val density = LocalDensity.current
    val ringDensity = Density(density.density, density.fontScale.coerceAtMost(RING_MAXIMUM_FONT_SCALE))

    if (isAccessibilityTextSize()) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
            CompositionLocalProvider(LocalDensity provides ringDensity) {
                Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) { rings() }
            }
            text(Modifier.fillMaxWidth())
        }
    } else {
        Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s), verticalAlignment = Alignment.Top) {
            CompositionLocalProvider(LocalDensity provides ringDensity) {
                Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) { rings() }
            }
            text(Modifier.weight(1f))
        }
    }
}

/** Le cran de texte où les anneaux s'arrêtent de grandir — le `xxLarge` d'iOS. */
private const val RING_MAXIMUM_FONT_SCALE = 1.3f

/**
 * « Tu es actuellement à Rome. » puis « 9 % écrit (2 jours validés sur 21) ».
 * Les deux phrases de la maquette, l'une à l'encre, l'autre au vert d'action :
 * la seconde commente la première.
 */
@Composable
private fun Whereabouts(trip: CurrentTripStatistics?) {
    Column(
        Modifier
            .padding(bottom = MemoBookSpacing.xs)
            .semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        if (trip != null) {
            trip.whereaboutsLabel?.let { RollingText(it, MemoBookFont.bodySemibold, MemoBookColor.ink) }
            RollingText(trip.writtenLabel, MemoBookFont.label, MemoBookColor.action)
        } else {
            BrandSkeleton(width = 200.dp)
            BrandSkeleton(width = 150.dp)
        }
    }
}

// MARK: L'agent travaille

/**
 * La ligne qui dit que des souvenirs sont en lecture. Elle n'existe que
 * pendant : la faire rester à « 0 souvenir » serait une ligne de plus à lire
 * pour rien.
 */
@Composable
private fun DetectingLine(label: String?) {
    val reduceMotion = isReduceMotionEnabled()
    AnimatedVisibility(
        visible = label != null,
        enter = if (reduceMotion) fadeIn() else fadeIn() + slideInVertically { it },
        exit = if (reduceMotion) fadeOut() else fadeOut() + slideOutVertically { it },
    ) {
        // La dernière phrase reste le temps de disparaître.
        val shown = remember { mutableStateOf("") }
        label?.let { shown.value = it }
        Row(
            Modifier
                .padding(start = MemoBookSpacing.s, end = MemoBookSpacing.s, bottom = MemoBookSpacing.snug)
                .semantics(mergeDescendants = true) {},
            horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            ActivitySpinner(MemoBookColor.action, size = 14.dp)
            RollingText(shown.value, MemoBookFont.caption, MemoBookColor.inkMuted)
        }
    }
}

// MARK: - Morceaux de la carte

/**
 * La ligne de tête d'un volet : le surtitre en capitales vertes, le détail à
 * droite, et le chevron qui dit si le volet est ouvert. **Toute la ligne se
 * touche**, pas seulement le chevron.
 *
 * @param detail « 5 voyages », « 10/12/2026 - 02/01/2027 ». `null` tant que ça
 *   n'est pas arrivé : la barre d'attente prend la place.
 */
@Composable
private fun SectionHeader(title: String, detail: String?, isExpanded: Boolean, onExpandedChange: (Boolean) -> Unit) {
    val isLarge = isAccessibilityTextSize()
    Box(
        Modifier
            .fillMaxWidth()
            .heightIn(min = MemoBookSpacing.minimumTapTarget - MemoBookSpacing.s)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = PlainButtonIndication,
                role = Role.Button,
            ) { onExpandedChange(!isExpanded) }
            .semantics(mergeDescendants = true) {
                heading()
                contentDescription = title
                stateDescription = detail?.let { "$it, " + if (isExpanded) "déplié" else "replié" } ?: ""
            },
        contentAlignment = Alignment.CenterStart,
    ) {
        // Aux tailles accessibles, le détail passe sous le surtitre :
        // « 26/08/2026 - 15/09/2026 » ne tient plus à côté de « VOYAGE EN
        // COURS », et le tronquer effacerait la moitié de la date.
        if (isLarge) {
            Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
                Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
                    Overline(title, Modifier.weight(1f))
                    Chevron(isExpanded)
                }
                SectionDetail(detail, wraps = true)
            }
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
                Overline(title)
                Spacer(Modifier.weight(1f))
                SectionDetail(detail, wraps = false)
                Chevron(isExpanded)
            }
        }
    }
}

@Composable
private fun Overline(title: String, modifier: Modifier = Modifier) {
    // Un seul mot — « STATISTIQUES » — se resserre plutôt que de se couper en
    // plein mot sur un écran étroit (T161, SE en AX5).
    val isOneWord = !title.contains(' ')
    BrandText(
        title.uppercase(),
        MemoBookFont.sectionOverline,
        modifier,
        color = MemoBookColor.action,
        maxLines = if (isOneWord) 1 else Int.MAX_VALUE,
        minimumScaleFactor = if (isOneWord) 0.6f else 1f,
    )
}

@Composable
private fun SectionDetail(detail: String?, wraps: Boolean) {
    if (detail == null) {
        BrandSkeleton(width = 96.dp)
        return
    }
    // Une ligne à côté du surtitre, où il se resserre plutôt que de renvoyer
    // le chevron ; sous le surtitre, aux tailles accessibles, il a toute la
    // largeur et s'enroule.
    RollingText(
        detail,
        MemoBookFont.label,
        MemoBookColor.action,
        maxLines = if (wraps) Int.MAX_VALUE else 1,
        minimumScaleFactor = 0.85f,
    )
}

/**
 * Le chevron du jeu de marque, tourné comme celui d'une `BrandDisclosureCard` :
 * vers le bas quand le volet est replié, vers le haut quand il est ouvert.
 */
@Composable
private fun Chevron(isExpanded: Boolean) {
    val angle by animateFloatAsState(if (isExpanded) -90f else 90f, SwiftMotion.snappy(0.32f), label = "chevron")
    Image(
        painterResource(R.drawable.icon_chevron),
        contentDescription = null,
        colorFilter = ColorFilter.tint(MemoBookColor.action),
        modifier = Modifier
            .size(scaled(22.dp))
            .rotate(angle),
    )
}

/**
 * Une ligne de la carte : l'intitulé effacé à gauche, la valeur à l'encre à
 * droite. Plus serrée qu'une `BrandRow` — on lit une liste de chiffres, on ne
 * touche rien —, et la valeur **roule** quand elle change.
 *
 * @param value `null` tant que la valeur n'est pas arrivée.
 */
@Composable
private fun StatisticLine(title: String, value: String?) {
    // « Enregistrements » se coupait en « Enregistremen / ts » sur SE aux
    // tailles accessibles (T161) : un mot seul se resserre.
    val isOneWord = !title.contains(' ')
    val label: @Composable (Modifier) -> Unit = { modifier ->
        BrandText(
            title,
            MemoBookFont.body,
            modifier,
            color = MemoBookColor.inkMuted,
            maxLines = if (isOneWord) 1 else Int.MAX_VALUE,
            minimumScaleFactor = if (isOneWord) 0.6f else 1f,
        )
    }
    val valueText: @Composable (TextAlign) -> Unit = { alignment ->
        if (value != null) {
            // Le chiffre roule vers sa nouvelle valeur au lieu de sauter :
            // c'est ce qui fait voir qu'un relevé vient d'arriver.
            RollingText(value, MemoBookFont.body, MemoBookColor.ink, textAlign = alignment)
        } else {
            BrandSkeleton(width = 120.dp)
        }
    }

    // Aux tailles accessibles la valeur passe sous son intitulé : « 1 avion,
    // 2 trains, scooter » à 30 pt ne tient sur aucune ligne.
    if (isAccessibilityTextSize()) {
        Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            label(Modifier)
            valueText(TextAlign.Start)
        }
    } else {
        Row(
            Modifier
                .fillMaxWidth()
                .semantics(mergeDescendants = true) {},
            horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        ) {
            // L'intitulé garde sa ligne : c'est la valeur qui s'enroule,
            // jamais « Enregistrements » coupé en deux parce que « Pas encore
            // relevé » est large.
            label(Modifier)
            Box(Modifier.weight(1f), contentAlignment = Alignment.TopEnd) { valueText(TextAlign.End) }
        }
    }
}

/**
 * Un anneau de progression : l'arc vert sur un rail effacé, le chiffre au
 * centre et son mot dessous. Il se lit, il ne se règle pas — comme
 * `BrandGauge`, dont il reprend les deux couleurs.
 *
 * **L'arc se dessine à l'arrivée du chiffre**, de zéro à sa valeur, puis suit
 * chaque changement : c'est l'animation la plus visible de la feuille.
 *
 * @param value « 9 % », « 2 ». `null` tant que ça n'est pas arrivé.
 */
@Composable
private fun StatisticRing(fraction: Double, value: String?, caption: String, accessibilityLabel: String) {
    val side = scaled(76.dp)
    val stroke = scaled(7.dp)
    val reduceMotion = isReduceMotionEnabled()
    // Ce que l'arc montre, distinct de ce qu'il devrait montrer : c'est l'écart
    // entre les deux qui s'anime.
    val drawn = remember { Animatable(0f) }
    val bounded = fraction.coerceIn(0.0, 1.0).toFloat()
    LaunchedEffect(bounded, reduceMotion) {
        // Plus lent que le reste de la carte, et c'est voulu : un arc qui se
        // dessine est le geste qu'on regarde en ouvrant la feuille.
        if (reduceMotion) drawn.snapTo(bounded) else drawn.animateTo(bounded, SwiftMotion.smooth(0.8f))
    }

    Box(
        Modifier
            .size(side)
            .clearAndSetSemantics {
                contentDescription = accessibilityLabel
                stateDescription = value ?: "en attente"
            },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val width = stroke.toPx()
            val inset = width / 2
            val arcSize = Size(size.width - width, size.height - width)
            val topLeft = Offset(inset, inset)
            drawArc(
                color = MemoBookColor.separator.copy(alpha = 0.35f),
                startAngle = 0f,
                sweepAngle = 360f,
                useCenter = false,
                topLeft = topLeft,
                size = arcSize,
                style = Stroke(width),
            )
            // Le zéro en haut, et l'arc qui tourne dans le sens d'une montre :
            // c'est ce qu'on attend d'un anneau qui compte.
            drawArc(
                color = MemoBookColor.action,
                startAngle = -90f,
                sweepAngle = 360f * drawn.value,
                useCenter = false,
                topLeft = topLeft,
                size = arcSize,
                style = Stroke(width, cap = StrokeCap.Round),
            )
        }

        Column(Modifier.padding(stroke + 4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            if (value != null) {
                RollingText(value, MemoBookFont.figure, MemoBookColor.ink, maxLines = 1, minimumScaleFactor = 0.6f)
            } else {
                BrandSkeleton(width = 28.dp)
            }
            BrandText(caption, MemoBookFont.caption, color = MemoBookColor.inkMuted, maxLines = 1, minimumScaleFactor = 0.7f)
        }
    }
}

/**
 * Un texte qui **roule** vers sa nouvelle valeur — le
 * `.contentTransition(.numericText())` d'iOS : l'ancienne monte et s'efface,
 * la nouvelle arrive d'en dessous. Immobile en Reduce Motion.
 */
@Composable
private fun RollingText(
    text: String,
    style: TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
    textAlign: TextAlign? = null,
    maxLines: Int = Int.MAX_VALUE,
    minimumScaleFactor: Float = 1f,
) {
    val reduceMotion = isReduceMotionEnabled()
    AnimatedContent(
        targetState = text,
        modifier = modifier,
        transitionSpec = {
            if (reduceMotion) {
                fadeIn() togetherWith fadeOut()
            } else {
                (slideInVertically(SwiftMotion.snappy(0.32f)) { it / 2 } + fadeIn()) togetherWith
                    (slideOutVertically(SwiftMotion.snappy(0.32f)) { -it / 2 } + fadeOut())
            }
        },
        label = "chiffre",
    ) { shown ->
        BrandText(shown, style, color = color, textAlign = textAlign, maxLines = maxLines, minimumScaleFactor = minimumScaleFactor)
    }
}

// MARK: - Aperçus

@Preview(locale = "fr-rFR", name = "Statistiques", heightDp = 900)
@Composable
private fun StatisticsSheetPreview() {
    val model = remember { StatisticsModel() }
    BrandSheetHost(isPresented = true, onDismissRequest = {}) { StatisticsSheet(model) }
}

@Preview(locale = "fr-rFR", name = "Statistiques — l’agent relit", heightDp = 900)
@Composable
private fun StatisticsSheetDetectingPreview() {
    val model = remember { StatisticsModel(source = { TravelStatistics.detectingFixture }) }
    BrandSheetHost(isPresented = true, onDismissRequest = {}) { StatisticsSheet(model) }
}

@Preview(locale = "fr-rFR", name = "Statistiques — sans voyage en cours", heightDp = 700)
@Composable
private fun StatisticsSheetRestingPreview() {
    val model = remember { StatisticsModel(source = { TravelStatistics.restingFixture }) }
    BrandSheetHost(isPresented = true, onDismissRequest = {}) { StatisticsSheet(model) }
}

@Preview(locale = "fr-rFR", name = "Statistiques — en chargement", heightDp = 900)
@Composable
private fun StatisticsSheetLoadingPreview() {
    val model = remember {
        StatisticsModel(source = {
            delay(60.seconds)
            TravelStatistics.fixture
        })
    }
    BrandSheetHost(isPresented = true, onDismissRequest = {}) { StatisticsSheet(model) }
}
