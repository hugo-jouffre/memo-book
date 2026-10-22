package com.memobook.feature.trip

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.memobook.core.TripStep
import com.memobook.core.TripTransport
import com.memobook.design.BrandButton
import com.memobook.design.BrandFilterChip
import com.memobook.design.BrandOptionGroup
import com.memobook.design.BrandOptionRow
import com.memobook.design.BrandSheet
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandSwipeAction
import com.memobook.design.BrandSwipeDrawer
import com.memobook.design.BrandText
import com.memobook.design.LucideIcon
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.R
import com.memobook.design.brandHorizontalFade
import com.memobook.design.isAccessibilityTextSize
import com.memobook.design.scaled
import com.memobook.feature.home.TripCoverPlaceholder
import com.memobook.feature.home.homeCard
import com.memobook.feature.home.TripDates
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.ZoneId
import java.util.Locale
import com.memobook.feature.home.CardPressStyle

/**
 * Les étapes du voyage, et les deux filtres qui les trient. Jumeau de
 * `Trip/TripStepsSection.swift`.
 *
 * Sur iOS, chaque filtre est un `Menu` portant un `Picker` : la liste
 * déroulante, les coches et l'annonce VoiceOver viennent du système. Compose
 * n'a de menu déroulant que dans Material : ici, la pastille ouvre une
 * [BrandSheet] de choix ([BrandOptionGroup]), qui se referme d'elle-même une
 * fois la coche vue. La pastille n'en est que l'étiquette — voir
 * [BrandFilterChip].
 *
 * **Deux filtres, pas trois.** Il y a eu un filtre « Étapes », lu comme le
 * filtre littéral qu'il annonçait : ne garder qu'une étape de la liste.
 * Retiré par Hugo, 14/09/2026 (T30) — « pour le moment » : filtrer une liste
 * sur un seul de ses éléments n'a pas trouvé son sens.
 *
 * @param onDeleteStep la croix du tiroir : l'écran demande confirmation (T235).
 */
@Composable
internal fun TripStepsSection(
    model: TripHomeModel,
    state: TripHomeModel.State,
    onOpenStep: (TripStep) -> Unit,
    onValidateStep: (TripStep) -> Unit,
    onDeleteStep: (TripStep) -> Unit = {},
) {
    // Le voyage a au moins une étape. **Sans étape, pas de filtres** : deux
    // pastilles présentes mais inertes disaient « appuie ici » à quelqu'un qui
    // n'avait rien à trier — logique, et désagréable (Hugo, 14/09/2026). Elles
    // arrivent avec la première étape.
    val hasSteps = !state.detail?.steps.isNullOrEmpty()

    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
        if (hasSteps) Filters(model, state)
        Steps(model, state, onOpenStep, onValidateStep, onDeleteStep)
    }
}

/** Le filtre dont la feuille de choix est ouverte. */
private enum class TripStepsFilter { Country, Transport }

internal object TripStepsFilterIcons {
    /**
     * Le drapeau des pays. iOS pose le symbole système « flag » ; SF Symbols
     * n'existant pas ici, le globe du jeu Lucide — celui du catalogue du design
     * system pour la même pastille.
     */
    val country: Int = R.drawable.icon_lucide_globe
}

// MARK: - Filtres

/**
 * Une bande qui défile : sur un petit écran, deux pastilles, leurs chevrons
 * et « Tout afficher » ne tiennent pas toujours sur une ligne, et les serrer
 * les rendrait illisibles.
 */
@Composable
private fun Filters(model: TripHomeModel, state: TripHomeModel.State) {
    var openFilter by remember { mutableStateOf<TripStepsFilter?>(null) }
    val scope = rememberCoroutineScope()
    val countries = state.detail?.countries.orEmpty()
    val transports = state.detail?.transports.orEmpty()

    // La bande prend toute la largeur de l'écran et ses pastilles s'alignent
    // sur la colonne : la dernière peut donc sortir par le bord au lieu de
    // buter sur une marge. Ce qui sort de la bande est **rogné** — le
    // `contentMargins` d'iOS : une marge posée **dans** le défilement —, et
    // s'efface au bord au lieu d'être tranché à la verticale (voir
    // `brandHorizontalFade`).
    Row(
        Modifier
            .fillMaxWidth()
            .brandHorizontalFade()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = MemoBookSpacing.screenMargin),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        FilterChip(
            title = state.country ?: "Pays",
            icon = TripStepsFilterIcons.country,
            isActive = state.country != null,
            isEnabled = countries.isNotEmpty(),
        ) { openFilter = TripStepsFilter.Country }

        FilterChip(
            title = state.transport?.displayName ?: "Transports",
            // Un train, et non le symbole système « bifurcation » qui tenait la
            // place sur iOS : celui-ci ne se dessinait tout simplement pas.
            // Aucune icône de transport dans le jeu de marque — voir `LucideIcon`.
            icon = LucideIcon.image("train-front"),
            isActive = state.transport != null,
            isEnabled = transports.isNotEmpty(),
        ) { openFilter = TripStepsFilter.Transport }

        if (state.hasActiveFilter) {
            BrandButton("Tout afficher", style = BrandButton.Style.Link, action = model::clearFilters)
        }
    }

    /** Pose le choix, laisse voir la coche, puis referme la feuille. */
    fun choose(apply: () -> Unit) {
        apply()
        scope.launch {
            delay(BrandOptionRow.lingerBeforeDismiss)
            openFilter = null
        }
    }

    BrandSheetHost(item = openFilter, onDismissRequest = { openFilter = null }) { filter ->
        when (filter) {
            TripStepsFilter.Country -> FilterSheet(
                title = "Pays",
                options = listOf<Pair<String?, String>>(null to "Tous les pays") +
                    countries.map { destination -> destination.name to (destination.flag?.let { "$it  ${destination.name}" } ?: destination.name) },
                selection = state.country,
            ) { choose { model.country = it } }

            TripStepsFilter.Transport -> FilterSheet(
                title = "Transports",
                options = listOf<Pair<TripTransport?, String>>(null to "Tous les transports") + transports.map { it to it.displayName },
                selection = state.transport,
            ) { choose { model.transport = it } }
        }
    }
}

@Composable
private fun FilterChip(title: String, icon: Int, isActive: Boolean, isEnabled: Boolean, onClick: () -> Unit) {
    BrandFilterChip(
        title,
        Modifier
            // Le `.disabled` du `Menu` d'iOS, qui pâlit son étiquette.
            .alpha(if (isEnabled) 1f else 0.4f)
            .clip(RoundedCornerShape(percent = 50))
            .clickable(enabled = isEnabled, role = Role.DropdownList, onClick = onClick),
        icon = painterResource(icon),
        isActive = isActive,
    )
}

/** La liste du `Picker` d'iOS : « Tous … » d'abord, puis chaque valeur, la choisie cochée. */
@Composable
private fun <T> FilterSheet(title: String, options: List<Pair<T?, String>>, selection: T?, onSelect: (T?) -> Unit) {
    BrandSheet(title) {
        BrandOptionGroup(Modifier.fillMaxWidth()) {
            options.forEach { (value, label) ->
                BrandOptionRow(label, isSelected = value == selection) { onSelect(value) }
            }
        }
    }
}

// MARK: - La liste

@Composable
private fun Steps(
    model: TripHomeModel,
    state: TripHomeModel.State,
    onOpenStep: (TripStep) -> Unit,
    onValidateStep: (TripStep) -> Unit,
    onDeleteStep: (TripStep) -> Unit,
) {
    val visible = state.visibleSteps

    if (visible.isEmpty()) {
        // Deux vides très différents : un voyage qui n'a rien à raconter, et
        // un filtre qui ne laisse rien passer. Aucun des deux n'est
        // maquetté — voir la fiche écran.
        if (state.hasActiveFilter) {
            TripStepsEmptyState(
                title = "Aucune étape ne correspond",
                message = "Enlève un filtre pour revoir tout le voyage.",
                action = "Tout afficher" to model::clearFilters,
            )
        } else {
            TripStepsEmptyState(
                title = "Le voyage commence ici",
                message = "Raconte ta première journée : MemoBook en fera une étape.",
                action = null,
            )
        }
    } else {
        // Une colonne et non une liste paresseuse : l'écran entier défile déjà,
        // photo comprise, et une liste paresseuse ne se pose pas dans un
        // défilement de même sens.
        Column(
            Modifier.padding(horizontal = MemoBookSpacing.screenMargin),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        ) {
            visible.forEach { step ->
                key(step.id) {
                    TripStepCard(
                        step = step,
                        onOpen = { onOpenStep(step) },
                        onValidate = { onValidateStep(step) },
                        onDelete = if (model.canDeleteMemories(step)) ({ onDeleteStep(step) }) else null,
                    )
                }
            }
        }
    }
}

/**
 * Une étape : sa vignette, son rang, ses dates, et qui y était.
 *
 * **Son tiroir** — le glissé vers la gauche, le même que les cartes de
 * l'accueil ([BrandSwipeDrawer]) — porte deux gestes :
 *
 * - **la croix**, en premier sous le doigt comme sur l'accueil : elle efface
 *   les souvenirs de l'étape, après confirmation (T235, Hugo, 06/10/2026) ;
 * - **« Valider cette étape »**, tant qu'elle ne l'est pas. Une fois validée,
 *   une coche discrète le dit à la place — même parti pris que « Ça me
 *   convient » sur un souvenir (`ChatBubbles`).
 *
 * @param onDelete `null` : rien à effacer qu'on sache désigner — pas de croix.
 */
@Composable
internal fun TripStepCard(
    step: TripStep,
    onOpen: () -> Unit,
    onValidate: () -> Unit,
    onDelete: (() -> Unit)? = null,
) {
    val actions = buildList {
        if (onDelete != null) {
            add(BrandSwipeAction(R.drawable.icon_cross, MemoBookColor.error, DeleteStepCopy.action(step.title), action = onDelete))
        }
        if (step.validatedAt == null) {
            add(BrandSwipeAction(R.drawable.icon_lucide_check, MemoBookColor.valid, "Valider cette étape", action = onValidate))
        }
    }

    BrandSwipeDrawer(actions) { accessibility ->
        Box(
            Modifier
                .fillMaxWidth()
                .homeCard()
                .then(accessibility)
                .clickable(interactionSource = null, indication = CardPressStyle, role = Role.Button, onClick = onOpen)
                .padding(MemoBookSpacing.xs + 2.dp),
        ) {
            StepContent(step)
        }
    }
}

@Composable
private fun StepContent(step: TripStep) {
    val thumbnailSide = scaled(76.dp)
    // En taille accessible, la vignette passe au-dessus : lui garder sa
    // colonne ne laisserait au texte que deux mots de large.
    if (isAccessibilityTextSize()) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            Thumbnail(step, thumbnailSide)
            StepText(step)
            OpenMark()
        }
    } else {
        Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s), verticalAlignment = Alignment.CenterVertically) {
            Thumbnail(step, thumbnailSide)
            StepText(step, Modifier.weight(1f))
            OpenMark()
        }
    }
}

@Composable
private fun Thumbnail(step: TripStep, side: Dp) {
    Box(Modifier.size(side).clearAndSetSemantics {}) {
        Box(
            Modifier
                .size(side)
                .clip(RoundedCornerShape(MemoBookSpacing.cornerRadius)),
        ) {
            TripCoverPlaceholder(step.id, Modifier.size(side))
            step.photoUrl?.let { url ->
                AsyncImage(model = url.toString(), contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.size(side))
            }
        }
        // Le drapeau du pays, posé dans le coin de la vignette. Il se déduit du
        // code pays — aucun serveur n'a d'emoji à stocker.
        step.destination?.flag?.let { flag ->
            BrandText(
                flag,
                MemoBookFont.caption,
                Modifier
                    .padding(5.dp)
                    .background(MemoBookColor.surface.copy(alpha = 0.9f), CircleShape)
                    .padding(3.dp),
            )
        }
    }
}

@Composable
private fun StepText(step: TripStep, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2), verticalAlignment = Alignment.CenterVertically) {
            BrandText(step.title, MemoBookFont.bodySemibold, color = MemoBookColor.ink)
            if (step.validatedAt != null) {
                Image(
                    painterResource(R.drawable.icon_lucide_check),
                    contentDescription = null,
                    colorFilter = ColorFilter.tint(MemoBookColor.valid),
                    modifier = Modifier.size(MemoBookSpacing.s),
                )
            }
        }

        step.dateRangeLabel?.let { BrandText(it, MemoBookFont.label, color = MemoBookColor.inkMuted) }
        step.companionsLabel?.let { BrandText(it, MemoBookFont.label, color = MemoBookColor.inkMuted) }
    }
}

/** Le rond fléché de la carte de découverte, repris tel quel : c'est déjà le signe « ça s'ouvre » de l'app. */
@Composable
private fun OpenMark() {
    Image(
        painterResource(R.drawable.icon_arrow_right),
        contentDescription = null,
        colorFilter = ColorFilter.tint(MemoBookColor.ink),
        modifier = Modifier
            .background(MemoBookColor.background, CircleShape)
            .padding(MemoBookSpacing.xs + 2.dp)
            .size(MemoBookSpacing.m),
    )
}

/** Ce qu'on montre quand la liste est vide. Non maquetté : une phrase qui dit quoi faire vaut mieux qu'un trou. */
@Composable
private fun TripStepsEmptyState(title: String, message: String, action: Pair<String, () -> Unit>?) {
    Column(
        Modifier
            .padding(horizontal = MemoBookSpacing.screenMargin)
            .fillMaxWidth()
            .homeCard()
            .padding(vertical = MemoBookSpacing.l, horizontal = MemoBookSpacing.s),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        BrandText(title, MemoBookFont.bodySemibold, color = MemoBookColor.ink, textAlign = TextAlign.Center)
        BrandText(message, MemoBookFont.label, color = MemoBookColor.inkMuted, textAlign = TextAlign.Center)
        if (action != null) {
            BrandButton(action.first, Modifier.padding(top = MemoBookSpacing.xs), style = BrandButton.Style.Link, action = action.second)
        }
    }
}

// MARK: - Mise en forme

/**
 * « Etape n°1 » tant que l'étape n'a pas de titre à elle.
 *
 * ⚠️ Sans accent sur le E : c'est la copie de la maquette, recopiée telle
 * quelle (R8). Signalée dans la fiche écran.
 */
internal val TripStep.title: String get() = "Etape n°$number"

/** Les dates de l'étape, avec l'année écrite une seule fois. Même règle que celles d'un voyage. */
internal val TripStep.dateRangeLabel: String?
    get() = dateRangeLabel(Locale.getDefault(), ZoneId.systemDefault())

internal fun TripStep.dateRangeLabel(locale: Locale, zone: ZoneId): String? {
    val start = startDate
    val end = endDate
    return when {
        start != null && end != null && start < end -> TripDates.interval(start, end, locale, zone)
        start != null -> TripDates.day(start, locale, zone)
        end != null -> TripDates.day(end, locale, zone)
        else -> null
    }
}

/**
 * « avec Mila », « avec Léa et Tom ». Sur iOS, la liste est assemblée par le
 * système (`.list(type: .and)`) ; l'app ne parlant que français, la règle est
 * écrite ici — [frenchList].
 */
internal val TripStep.companionsLabel: String?
    get() {
        if (companions.isEmpty()) return null
        return "avec ${frenchList(companions.map { it.name.firstNameOnly })}"
    }

/**
 * Le prénom seul : sur une carte d'étape, « avec Mila Fontaine et Tom
 * Marchand » prend deux lignes pour ne rien dire de plus.
 */
private val String.firstNameOnly: String
    get() = split(' ').firstOrNull { it.isNotEmpty() } ?: this

/** « Léa », « Léa et Tom », « Léa, Tom et Mila » — le `.formatted(.list(type: .and))` d'iOS, en français. */
internal fun frenchList(items: List<String>): String = when (items.size) {
    0 -> ""
    1 -> items[0]
    else -> items.dropLast(1).joinToString(", ") + " et " + items.last()
}
