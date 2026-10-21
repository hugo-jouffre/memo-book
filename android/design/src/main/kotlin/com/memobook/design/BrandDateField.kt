package com.memobook.design

import androidx.compose.animation.Crossfade
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.time.temporal.WeekFields
import java.util.Locale

/**
 * Une date qui se règle : la ligne qui la montre, et le calendrier qui monte du
 * bas pour la changer. Jumeau de `BrandDateField.swift`.
 *
 * **Le calendrier monte du bas.** Il se dépliait auparavant *dans* la ligne, et
 * ça ne tient plus : une feuille de réglages fait déjà sa hauteur, un calendrier
 * de 320 qui s'y ajoute la pousse au plafond. Monté du bas, il se pose
 * **par-dessus la feuille**, en pleine largeur, là où le pouce l'attend.
 *
 * **Il se referme dès qu'une date est choisie.** C'est un sélecteur, pas un
 * formulaire : il n'a rien à valider. Il ne reste ouvert que si l'on retouche
 * la date déjà affichée — rien n'a changé —, et le glissé le range alors.
 *
 * iOS y montre le calendrier graphique du système ; Compose Foundation n'en a
 * pas, et celui d'Android ne prend pas les couleurs de la marque. C'est donc la
 * grille de [BrandRangeCalendar], réduite à un jour.
 *
 * ```kotlin
 * BrandDateField("Date de début", start, { start = it }, range = LocalDate.MIN..(end ?: LocalDate.MAX))
 * ```
 *
 * @param range les jours qu'on peut choisir. Une date de début est bornée
 *   **au-delà** (`LocalDate.MIN..fin`), une date de fin **en deçà**
 *   (`début..LocalDate.MAX`) — les deux formes de bornes partielles d'iOS.
 * @param isClearable la croix qui efface la date. Faux là où une date posée se
 *   **change** mais ne se retire plus — les dates d'un voyage, dans ses réglages
 *   (Clara, 26/09/2026). La ligne porte alors **un crayon** à la place de la
 *   croix (Hugo, 29/09/2026), qui dit « ça se corrige » sans rien retirer.
 */
@Composable
fun BrandDateField(
    label: String,
    date: LocalDate?,
    onDateChange: (LocalDate?) -> Unit,
    range: ClosedRange<LocalDate>,
    modifier: Modifier = Modifier,
    isClearable: Boolean = true,
) {
    var isPicking by rememberSaveable { mutableStateOf(false) }
    val iconSide = scaled(MemoBookSpacing.m)
    val rowHeight = scaled(MemoBookSpacing.controlHeight)
    val locale = calendarLocale()
    val shape = RoundedCornerShape(MemoBookSpacing.controlCornerRadius)
    // Ce que la ligne affiche : la date choisie, ou l'intitulé en gris.
    val text = date?.format(DateTimeFormatter.ofPattern("d MMMM yyyy", locale)) ?: label

    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = rowHeight)
            .background(MemoBookColor.surface, shape)
            .border(1.dp, MemoBookColor.hairline, shape)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, role = Role.Button) {
                // Une date est posée **à l'ouverture** quand il n'y en avait pas :
                // le calendrier s'ouvre sur quelque chose, et « aujourd'hui » se
                // choisit d'un seul geste.
                if (date == null) onDateChange(LocalDate.now())
                isPicking = true
            }
            .semantics {
                contentDescription = label
                stateDescription = date?.let { calendarLongDate(it, locale) } ?: "Non définie"
            }
            .padding(horizontal = MemoBookSpacing.s, vertical = MemoBookSpacing.snug),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(
            painter = painterResource(R.drawable.icon_lucide_calendar),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.ink),
            modifier = Modifier.size(iconSide),
        )
        BrandText(
            text,
            MemoBookFont.body,
            Modifier
                .weight(1f)
                .clearAndSetSemantics {},
            color = if (date == null) MemoBookColor.inkMuted else MemoBookColor.ink,
        )
        Spacer(Modifier.width(MemoBookSpacing.xs))
        if (date != null && isClearable) {
            DateClearButton(label) { onDateChange(null) }
        } else if (!isClearable) {
            DatePencil()
        }
    }

    // Une feuille « du système », et non une `BrandSheetHost` : elle n'annonce rien
    // au compteur de recul, donc la feuille de réglages dessous ne rapetisse pas.
    // Un sélecteur de date n'est pas une étape de plus dans un chemin, c'est un
    // accessoire de la ligne qu'on touche.
    SheetPresentation(
        isPresented = isPicking,
        onDismissRequest = { isPicking = false },
        dismissDisabled = false,
        reportsToCounter = false,
    ) {
        DatePickerSheet(label, date ?: LocalDate.now(), range, locale) { picked ->
            // C'est le choix qui referme la feuille, dans le même geste.
            if (picked != date) {
                onDateChange(picked)
                isPicking = false
            }
        }
    }
}

/** Le crayon d'une date qui se change sans s'effacer. Décoratif : c'est la ligne entière qui ouvre le calendrier. */
@Composable
private fun DatePencil() {
    Box(Modifier.size(MemoBookSpacing.minimumTapTarget).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
        Image(
            painter = painterResource(R.drawable.icon_pen),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.inkMuted),
            modifier = Modifier.size(MemoBookSpacing.s),
        )
    }
}

@Composable
private fun DateClearButton(label: String, onClear: () -> Unit) {
    Box(
        Modifier
            .size(MemoBookSpacing.minimumTapTarget)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, role = Role.Button, onClick = onClear)
            .semantics { contentDescription = "Effacer $label" },
        contentAlignment = Alignment.Center,
    ) {
        Image(
            painter = painterResource(R.drawable.icon_cross),
            contentDescription = null,
            colorFilter = ColorFilter.tint(MemoBookColor.inkMuted),
            modifier = Modifier.size(MemoBookSpacing.snug + 2.dp),
        )
    }
}

/**
 * Le calendrier dans sa feuille : la poignée, l'intitulé, le mois. Au moins 420
 * de haut comme le cran d'iOS — et davantage aux grandes tailles de texte, où
 * le cran fixe d'iOS rognerait la dernière semaine.
 */
@Composable
private fun DatePickerSheet(
    label: String,
    selected: LocalDate,
    range: ClosedRange<LocalDate>,
    locale: Locale,
    onPick: (LocalDate) -> Unit,
) {
    val shape = brandSheetShape()
    Column(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 420.dp)
            .brandShadow(MemoBookShadow.Raised, shape)
            .clip(shape)
            .background(MemoBookColor.surface)
            .semantics { paneTitle = label }
            .windowInsetsPadding(WindowInsets.navigationBars.only(WindowInsetsSides.Bottom)),
    ) {
        BrandSheetHandle()
        BrandText(
            label,
            MemoBookFont.sectionTitle,
            Modifier
                .fillMaxWidth()
                .padding(horizontal = MemoBookSpacing.screenMargin)
                .semantics { heading() },
        )
        DayPickerCalendar(selected, range, locale, onPick, Modifier.padding(horizontal = MemoBookSpacing.s))
    }
}

/** Un mois, et un jour qu'on y touche. Les jours hors des bornes pâlissent et ne se choisissent pas. */
@Composable
private fun DayPickerCalendar(
    selected: LocalDate,
    range: ClosedRange<LocalDate>,
    locale: Locale,
    onPick: (LocalDate) -> Unit,
    modifier: Modifier = Modifier,
) {
    val firstDayOfWeek = remember(locale) { WeekFields.of(locale).firstDayOfWeek }
    var visibleMonth by rememberSaveable { mutableStateOf(YearMonth.from(selected)) }
    Column(modifier.padding(vertical = MemoBookSpacing.snug), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
        CalendarMonthBar(visibleMonth, locale) { visibleMonth = it }
        CalendarWeekdayHeader(firstDayOfWeek, locale)
        Crossfade(visibleMonth, animationSpec = SwiftUISpring.smooth(200), label = "mois") { month ->
            CalendarDaysGrid(month, firstDayOfWeek) { day ->
                PickerDayCell(day, isSelected = day == selected, isInRange = day in range, locale) { onPick(day) }
            }
        }
    }
}

@Composable
private fun RowScope.PickerDayCell(day: LocalDate, isSelected: Boolean, isInRange: Boolean, locale: Locale, onPick: () -> Unit) {
    val daySide = scaled(40.dp)
    Box(
        Modifier
            .weight(1f)
            .heightIn(min = daySide)
            // Comme dans le calendrier du système : un jour hors des bornes n'est pas un choix.
            .alpha(if (isInRange) 1f else 0.4f)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                enabled = isInRange,
                role = Role.Button,
                onClick = onPick,
            )
            .semantics {
                contentDescription = calendarDayLabel(day, locale)
                selected = isSelected
            },
        contentAlignment = Alignment.Center,
    ) {
        if (isSelected) CalendarEndpoint(daySide)
        if (day == LocalDate.now() && !isSelected) CalendarTodayRing(daySide)
        CalendarDayNumber(day, isEndpoint = isSelected)
    }
}

@Preview(name = "Dates", widthDp = 390, heightDp = 260)
@Composable
private fun BrandDateFieldPreview() {
    var start by remember { mutableStateOf<LocalDate?>(null) }
    var end by remember { mutableStateOf<LocalDate?>(LocalDate.now()) }
    Column(
        Modifier
            .fillMaxSize()
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug),
    ) {
        BrandDateField("Date de début", start, { start = it }, range = LocalDate.MIN..(end ?: LocalDate.MAX))
        BrandDateField("Date de fin (optionnel)", end, { end = it }, range = (start ?: LocalDate.MIN)..LocalDate.MAX)
        BrandDateField("Date de départ", LocalDate.now(), {}, range = LocalDate.MIN..LocalDate.MAX, isClearable = false)
    }
}
