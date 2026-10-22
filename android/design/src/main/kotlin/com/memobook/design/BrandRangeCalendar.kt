package com.memobook.design

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.Crossfade
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.platform.LocalLocale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.format.TextStyle
import java.time.temporal.WeekFields
import java.util.Locale

/**
 * Un mois qu'on parcourt, et une plage de jours qu'on y pose en deux gestes :
 * le départ, puis le retour. Jumeau de `BrandRangeCalendar.swift`.
 *
 * **Le sélecteur du système ne sait pas faire ça** : il choisit un jour, et un
 * seul ; deux sélecteurs côte à côte demandent quatre gestes et deux
 * calendriers pour une question que tout le monde se pose en une fois — « du
 * combien au combien ? ». Ce calendrier en est un seul, dessiné à la main, où
 * la plage se lit d'un coup : une bande entre les deux jours.
 *
 * **Les règles du geste** sont dans [DateRangeSelection]. L'écran au-dessus
 * choisit la case en cours en la touchant : on revient corriger le départ sans
 * perdre le retour. Un retour n'est jamais exigé : un voyage dont on ne connaît
 * pas la fin commence quand même.
 */
@Composable
fun BrandRangeCalendar(
    selection: DateRangeSelection,
    onSelectionChange: (DateRangeSelection) -> Unit,
    modifier: Modifier = Modifier,
) {
    val locale = calendarLocale()
    val firstDayOfWeek = remember(locale) { WeekFields.of(locale).firstDayOfWeek }
    // Le mois affiché : celui du départ à l'ouverture, ou celui d'aujourd'hui.
    var visibleMonth by rememberSaveable { mutableStateOf(YearMonth.from(selection.start ?: LocalDate.now())) }

    // On vient corriger le retour : le calendrier se met sur son mois, pas sur
    // celui où l'on était resté.
    val editing = selection.editing
    val previousEditing = remember { mutableStateOf(editing) }
    val anchor = selection.date(editing)
    LaunchedEffect(editing) {
        if (previousEditing.value == editing) return@LaunchedEffect
        previousEditing.value = editing
        if (anchor != null) visibleMonth = YearMonth.from(anchor)
    }

    Column(
        modifier
            .background(MemoBookColor.surface, RoundedCornerShape(MemoBookSpacing.largeCornerRadius))
            .padding(MemoBookSpacing.snug),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        CalendarMonthBar(visibleMonth, locale) { visibleMonth = it }
        CalendarWeekdayHeader(firstDayOfWeek, locale)
        Crossfade(visibleMonth, animationSpec = SwiftMotion.smooth(0.2f), label = "mois") { month ->
            CalendarDaysGrid(month, firstDayOfWeek) { day ->
                RangeDayCell(day, selection.role(day), locale) { onSelectionChange(selection.tap(day)) }
            }
        }
    }
}

@Composable
private fun RowScope.RangeDayCell(day: LocalDate, role: DateRangeSelection.Role, locale: Locale, onTap: () -> Unit) {
    val daySide = scaled(40.dp)
    val isToday = day == LocalDate.now()
    Box(
        Modifier
            .weight(1f)
            .heightIn(min = daySide)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, role = Role.Button, onClick = onTap)
            .semantics {
                contentDescription = calendarDayLabel(day, locale)
                stateDescription = role.accessibilityValue
                selected = role != DateRangeSelection.Role.None
            },
        contentAlignment = Alignment.Center,
    ) {
        // La plage change en fondu, comme le reste de la grille.
        Crossfade(role, Modifier.fillMaxWidth(), animationSpec = SwiftMotion.smooth(0.2f), label = "jour") { shown ->
            Box(Modifier.fillMaxWidth().heightIn(min = daySide), contentAlignment = Alignment.Center) {
                RangeDayBackground(shown, daySide)
                if (isToday && !shown.isEndpoint) CalendarTodayRing(daySide)
                CalendarDayNumber(day, isEndpoint = shown.isEndpoint)
            }
        }
    }
}

/**
 * La bande de la plage, et les deux ronds qui la bornent. Chaque case dessine
 * **sa** part de bande : la moitié droite pour le départ, la gauche pour le
 * retour, toute la largeur entre les deux. Les bords de semaine s'en trouvent
 * réglés sans rien de plus.
 */
@Composable
private fun BoxScope.RangeDayBackground(role: DateRangeSelection.Role, daySide: Dp) {
    val band = MemoBookColor.outline.copy(alpha = 0.45f)
    when (role) {
        DateRangeSelection.Role.None -> Unit
        is DateRangeSelection.Role.Start -> {
            if (role.isClosed) {
                Box(Modifier.align(Alignment.CenterEnd).fillMaxWidth(0.5f).height(daySide).background(band))
            }
            CalendarEndpoint(daySide)
        }
        DateRangeSelection.Role.End -> {
            Box(Modifier.align(Alignment.CenterStart).fillMaxWidth(0.5f).height(daySide).background(band))
            CalendarEndpoint(daySide)
        }
        DateRangeSelection.Role.Inside -> Box(Modifier.fillMaxWidth().height(daySide).background(band))
    }
}

// MARK: - La plage

/**
 * Un départ, un retour éventuel, et le geste qui les pose.
 *
 * Des `LocalDate` : un voyage sait un jour de départ, pas une heure. Deux dates
 * du même jour sont donc **égales** par construction — ce qu'iOS obtient en les
 * ramenant à minuit à l'entrée. Immuable : chaque geste rend la plage suivante,
 * que l'écran garde.
 *
 * @property editing la case que le prochain geste remplit.
 */
data class DateRangeSelection(
    val start: LocalDate? = null,
    val end: LocalDate? = null,
    val editing: Slot = Slot.Start,
) {
    /** Les deux cases de la plage. */
    enum class Slot { Start, End }

    val isEmpty: Boolean get() = start == null

    fun date(slot: Slot): LocalDate? = when (slot) {
        Slot.Start -> start
        Slot.End -> end
    }

    /**
     * Le geste. Le jour touché va dans la case en cours ; poser le départ passe
     * au retour ; un retour avant le départ devient le nouveau départ.
     */
    fun tap(day: LocalDate): DateRangeSelection = when (editing) {
        // Un retour qui ne suit plus le départ n'a plus de sens.
        Slot.Start -> copy(start = day, end = end?.takeIf { it > day }, editing = Slot.End)
        Slot.End -> when {
            // Pas de retour sans départ : le jour touché est le départ.
            start == null -> copy(start = day)
            day > start -> copy(end = day)
            day < start -> copy(start = day, end = null)
            else -> this
        }
    }

    /** Vide une case. Effacer le départ emporte le retour : il n'a plus rien à suivre. */
    fun clear(slot: Slot): DateRangeSelection = when (slot) {
        Slot.Start -> copy(start = null, end = null, editing = Slot.Start)
        Slot.End -> copy(end = null, editing = Slot.End)
    }

    /** Ce qu'un jour est pour la plage : rien, une borne, ou dedans. */
    sealed interface Role {
        data object None : Role

        /** `isClosed` : un retour existe, la bande part de cette case. */
        data class Start(val isClosed: Boolean) : Role

        data object End : Role

        data object Inside : Role

        val isEndpoint: Boolean get() = this is Start || this == End

        /** Ce que TalkBack dit de la case. */
        val accessibilityValue: String
            get() = when (this) {
                None -> ""
                is Start -> "Départ"
                End -> "Retour"
                Inside -> "Pendant le voyage"
            }
    }

    fun role(day: LocalDate): Role {
        val start = start ?: return Role.None
        if (day == start) return Role.Start(isClosed = end != null && end != start)
        val end = end ?: return Role.None
        if (day == end) return Role.End
        return if (day > start && day < end) Role.Inside else Role.None
    }
}

// MARK: - Le mois en grille

/**
 * Les jours du mois, précédés d'autant de `null` qu'il faut pour que le premier
 * tombe dans sa colonne de semaine.
 */
internal fun YearMonth.monthGrid(firstDayOfWeek: DayOfWeek): List<LocalDate?> {
    val first = atDay(1)
    val leading = (first.dayOfWeek.value - firstDayOfWeek.value + 7) % 7
    return List(leading) { null } + (1..lengthOfMonth()).map { atDay(it) }
}

// MARK: - Les pièces du calendrier, partagées avec BrandDateField

/** La langue des noms de mois et de jours : celle du téléphone, comme le `locale` de l'environnement SwiftUI. */
@Composable
internal fun calendarLocale(): Locale = LocalLocale.current.platformLocale

/** « Septembre 2026 », avec sa majuscule : le format du système la laisse en minuscule. */
internal fun calendarMonthTitle(month: YearMonth, locale: Locale): String =
    month.format(DateTimeFormatter.ofPattern("LLLL yyyy", locale)).replaceFirstChar { it.titlecase(locale) }

/** « mardi 22 septembre 2026 » : ce que TalkBack lit d'une case. */
internal fun calendarDayLabel(day: LocalDate, locale: Locale): String =
    day.format(DateTimeFormatter.ofPattern("EEEE d MMMM yyyy", locale))

/** « 22 septembre 2026 » : une date dite en entier, le `.long` d'iOS. */
internal fun calendarLongDate(day: LocalDate, locale: Locale): String =
    day.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.LONG).withLocale(locale))

/** Le mois, et les deux chevrons qui en changent. */
@Composable
internal fun CalendarMonthBar(month: YearMonth, locale: Locale, onMonthChange: (YearMonth) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
        CalendarMonthButton("Mois précédent", isForward = false) { onMonthChange(month.minusMonths(1)) }
        // Le titre roule vers le haut quand on avance, vers le bas quand on recule —
        // la `numericText` d'iOS.
        AnimatedContent(
            targetState = month,
            modifier = Modifier.weight(1f),
            transitionSpec = {
                val forward = targetState > initialState
                (slideInVertically(SwiftMotion.smooth(0.2f)) { if (forward) it else -it } + fadeIn(SwiftMotion.smooth(0.2f)))
                    .togetherWith(slideOutVertically(SwiftMotion.smooth(0.2f)) { if (forward) -it else it } + fadeOut(SwiftMotion.smooth(0.2f)))
            },
            contentAlignment = Alignment.Center,
            label = "titre du mois",
        ) { shown ->
            BrandText(
                calendarMonthTitle(shown, locale),
                MemoBookFont.sectionTitle,
                Modifier
                    .fillMaxWidth()
                    .semantics { heading() },
                textAlign = TextAlign.Center,
            )
        }
        CalendarMonthButton("Mois suivant", isForward = true) { onMonthChange(month.plusMonths(1)) }
    }
}

@Composable
private fun CalendarMonthButton(label: String, isForward: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .size(MemoBookSpacing.minimumTapTarget)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        // Le chevron du jeu de marque, là où iOS pose `chevron.left` / `chevron.right`
        // à 15 pt : son glyphe n'occupe qu'une part de son carré, d'où 28.
        Image(
            painter = painterResource(R.drawable.icon_chevron),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.action),
            modifier = Modifier
                .size(28.dp)
                .rotate(if (isForward) 0f else 180f),
        )
    }
}

/** « L M M J V S D », dans l'ordre où la région compte les semaines. */
@Composable
internal fun CalendarWeekdayHeader(firstDayOfWeek: DayOfWeek, locale: Locale) {
    Row(Modifier.fillMaxWidth().clearAndSetSemantics {}) {
        repeat(7) { offset ->
            BrandText(
                firstDayOfWeek.plus(offset.toLong()).getDisplayName(TextStyle.NARROW_STANDALONE, locale),
                MemoBookFont.caption,
                Modifier.weight(1f),
                color = MemoBookColor.inkMuted,
                textAlign = TextAlign.Center,
            )
        }
    }
}

/** Les semaines du mois, sept cases par ligne, les cases vides à la hauteur d'un jour. */
@Composable
internal fun CalendarDaysGrid(
    month: YearMonth,
    firstDayOfWeek: DayOfWeek,
    dayCell: @Composable RowScope.(LocalDate) -> Unit,
) {
    val daySide = scaled(40.dp)
    val weeks = remember(month, firstDayOfWeek) { month.monthGrid(firstDayOfWeek).chunked(7) }
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2)) {
        weeks.forEach { week ->
            Row(Modifier.fillMaxWidth()) {
                week.forEach { day ->
                    if (day != null) dayCell(day) else Spacer(Modifier.weight(1f).height(daySide))
                }
                // La dernière semaine garde ses colonnes.
                repeat(7 - week.size) { Spacer(Modifier.weight(1f).height(daySide)) }
            }
        }
    }
}

/** Le rond plein d'une borne. */
@Composable
internal fun CalendarEndpoint(daySide: Dp) {
    Box(Modifier.size(daySide).background(MemoBookColor.action, CircleShape))
}

/** Le cercle d'aujourd'hui, quand il n'est pas une borne. */
@Composable
internal fun CalendarTodayRing(daySide: Dp) {
    Box(Modifier.size(daySide).border(1.dp, MemoBookColor.action, CircleShape))
}

/** Le numéro du jour, en chiffres à chasse fixe pour que la grille ne danse pas. */
@Composable
internal fun CalendarDayNumber(day: LocalDate, isEndpoint: Boolean) {
    BrandText(
        day.dayOfMonth.toString(),
        (if (isEndpoint) MemoBookFont.bodySemibold else MemoBookFont.body).copy(fontFeatureSettings = "tnum"),
        color = if (isEndpoint) MemoBookColor.onAction else MemoBookColor.ink,
    )
}

@Preview(locale = "fr-rFR", name = "Plage", widthDp = 390, heightDp = 520)
@Composable
private fun BrandRangeCalendarPreview() {
    // Une plage fixe, passée : la capture de référence ne change pas avec le
    // jour, et l'anneau d'aujourd'hui n'y paraît jamais.
    val day = LocalDate.of(2026, 7, 14)
    var selection by remember {
        mutableStateOf(DateRangeSelection(start = day, end = day.plusDays(9)))
    }
    val locale = calendarLocale()
    Column(
        Modifier
            .fillMaxSize()
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        BrandRangeCalendar(selection, { selection = it })
        BrandText(
            "${selection.start?.let { calendarLongDate(it, locale) } ?: "—"} → ${selection.end?.let { calendarLongDate(it, locale) } ?: "—"}",
            MemoBookFont.caption,
        )
    }
}
