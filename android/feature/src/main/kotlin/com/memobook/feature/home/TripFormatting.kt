package com.memobook.feature.home

import androidx.annotation.DrawableRes
import com.memobook.core.Trip
import com.memobook.core.TripProgress
import com.memobook.core.TripStats
import com.memobook.design.R
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

// Mise en forme des données d'un voyage. Jumeau de `Home/TripFormatting.swift`.
//
// iOS passe tout par `FormatStyle` plutôt que par des chaînes assemblées à la
// main : c'est ce qui donne « 26 août – 15 sept. 2026 », avec l'année écrite
// une seule fois, sans que l'écran ait à connaître une seule règle de langue.
// Android n'a pas de `FormatStyle` d'intervalle hors d'ICU, que les tests de la
// JVM ne voient pas : les règles d'intervalle du français (CLDR, motif
// `yMMMd`) sont donc écrites ici, une fois, sur `java.time`. L'app ne parle que
// français (`FrenchLocale`) ; la **région** du téléphone, elle, décide des
// unités et des séparateurs.

/**
 * La ligne de dates sous le titre. `null` quand le voyage n'a aucune date :
 * la vue omet alors la ligne plutôt que d'afficher un tiret seul.
 */
val Trip.dateRangeLabel: String?
    get() = dateRangeLabel(Locale.getDefault(), ZoneId.systemDefault())

/** [dateRangeLabel], à une locale et un fuseau donnés — ceux du téléphone dans l'app, fixés dans les tests. */
fun Trip.dateRangeLabel(locale: Locale, zone: ZoneId): String? {
    val start = startDate
    val end = endDate
    return when {
        start != null && end != null && start < end -> TripDates.interval(start, end, locale, zone)
        // Un voyage commencé qui n'a pas de fin : c'est le cas courant d'un
        // carnet ouvert, pas une donnée manquante.
        start != null -> TripDates.day(start, locale, zone)
        end != null -> TripDates.day(end, locale, zone)
        else -> null
    }
}

/**
 * Les dates d'un voyage, jour, mois abrégé, année — le `.dateTime.day().month(.abbreviated).year()`
 * d'iOS et son intervalle.
 */
internal object TripDates {
    private fun formatter(pattern: String, locale: Locale) = DateTimeFormatter.ofPattern(pattern, locale)

    /** « 26 août 2026 ». */
    fun day(date: Instant, locale: Locale, zone: ZoneId): String =
        formatter("d MMM y", locale).format(date.atZone(zone))

    /**
     * « 26 août – 15 sept. 2026 » : ce que les deux bornes partagent ne
     * s'écrit qu'une fois — l'année, puis le mois. Les trois motifs de CLDR
     * pour le français, ceux qu'emploie le formateur d'iOS.
     */
    fun interval(start: Instant, end: Instant, locale: Locale, zone: ZoneId): String {
        val from = start.atZone(zone)
        val to = end.atZone(zone)
        return when {
            from.year != to.year -> "${day(start, locale, zone)} – ${day(end, locale, zone)}"
            from.monthValue != to.monthValue ->
                "${formatter("d MMM", locale).format(from)} – ${formatter("d MMM y", locale).format(to)}"
            from.dayOfMonth != to.dayOfMonth -> "${from.dayOfMonth}–${formatter("d MMM y", locale).format(to)}"
            // Le même jour à deux heures différentes : une date, pas un intervalle.
            else -> day(start, locale, zone)
        }
    }
}

/**
 * « 5 souvenirs et 2/80 pages ». Deux compteurs, pas un pourcentage : on veut
 * savoir ce qu'on a raconté et ce qu'il reste de carnet à remplir.
 */
val TripProgress.summary: String
    get() {
        val memories = if (memoryCount <= 1) "$memoryCount souvenir" else "$memoryCount souvenirs"
        return "$memories et $pageCount/$targetPageCount pages"
    }

/**
 * Les compteurs, dans l'ordre de la maquette. Seuls ceux que le serveur a
 * renvoyés apparaissent.
 */
val TripStats.items: List<TripStatItem>
    get() = items(Locale.getDefault())

/** [items], à une locale donnée : c'est la région qui choisit les kilomètres ou les miles. */
fun TripStats.items(locale: Locale): List<TripStatItem> = buildList {
    dayCount?.let { add(TripStatItem(TripStatItem.Kind.Duration, TripStatLabels.day(it))) }
    distanceKilometres?.let { add(TripStatItem(TripStatItem.Kind.Distance, TripStatLabels.distance(it, locale))) }
    photoCount?.let { add(TripStatItem(TripStatItem.Kind.Photos, TripStatLabels.photo(it))) }
}

/** La même chose sur une seule ligne, pour les cartes compactes. */
val TripStats.inlineSummary: String?
    get() = items.map { it.text }.takeIf { it.isNotEmpty() }?.joinToString(" • ")

internal object TripStatLabels {
    fun day(count: Int): String = if (count <= 1) "$count jour" else "$count jours"

    fun photo(count: Int): String = if (count <= 1) "$count photo" else "$count photos"

    /**
     * Le kilomètre est l'unité de stockage, pas l'unité d'affichage : un
     * utilisateur réglé en impérial lit des miles. C'est l'usage « route » des
     * préférences d'unités de CLDR — le `usage: .road` d'iOS —, que seuls les
     * États-Unis et le Royaume-Uni comptent en miles parmi les régions où l'app
     * se lit. Arrondi au kilomètre, l'unité abrégée après une espace insécable.
     */
    fun distance(kilometres: Double, locale: Locale): String {
        val usesMiles = locale.country in ROAD_MILE_REGIONS
        val value = if (usesMiles) kilometres / KILOMETRES_PER_MILE else kilometres
        val number = NumberFormat.getNumberInstance(locale).apply {
            minimumFractionDigits = 0
            maximumFractionDigits = 0
        }.format(value)
        return number + " " + if (usesMiles) "mi" else "km"
    }

    private val ROAD_MILE_REGIONS = setOf("US", "GB", "LR", "MM")
    private const val KILOMETRES_PER_MILE = 1.609344
}

/** Un compteur prêt à afficher : son texte et l'icône qui va avec. */
data class TripStatItem(val kind: Kind, val text: String) {
    enum class Kind {
        Duration,
        Distance,
        Photos,
        ;

        /**
         * Le pictogramme du compteur, à teindre par la carte qui le pose.
         *
         * Les photos ont leur icône dans le jeu de marque. Sur iOS, la durée et
         * la distance restent sur un symbole système en attendant les leurs ;
         * SF Symbols n'existant pas ici, la durée prend le calendrier Lucide du
         * catalogue, la distance le symbole d'iOS redessiné. C'est le seul
         * endroit à changer le jour où les deux manquantes arrivent.
         */
        @get:DrawableRes
        val icon: Int
            get() = when (this) {
                Photos -> R.drawable.icon_picture_frame
                Duration -> R.drawable.icon_lucide_calendar
                Distance -> R.drawable.system_point_topleft_down_to_point_bottomright_curvepath
            }
    }

    val id: Kind get() = kind
}
