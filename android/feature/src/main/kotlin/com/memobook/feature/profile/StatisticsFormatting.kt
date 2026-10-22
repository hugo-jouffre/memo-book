package com.memobook.feature.profile

import com.memobook.core.CurrentTripStatistics
import com.memobook.core.TravelFigures
import com.memobook.core.TravelStatistics
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.time.chrono.IsoChronology
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeFormatterBuilder
import java.time.format.FormatStyle
import java.util.Locale

// Mise en forme des chiffres de la feuille « Statistiques ». Jumeau de
// `Profile/StatisticsFormatting.swift`. Les règles vivent ici, pas dans la vue,
// et elles se testent sans émulateur : un accord raté (« 1 personnes ») se lit
// sur chaque ligne de la feuille.

/** L'espace insécable qui lie un nombre à son mot. */
private const val NO_BREAK_SPACE = ' '

/**
 * Un nombre et son mot, accordés : « 6 pays », « 1 région », « 13 villes ».
 *
 * Les deux formes écrites plutôt qu'un « s » collé : « pays » ne bouge pas,
 * « vocal » fait « vocaux ». Le nombre passe par le formateur du système, qui
 * sait qu'un français sépare les milliers d'une espace fine.
 *
 * **Zéro prend le singulier**, comme un : « 0 jour validé », pas « 0 jours
 * validés ». C'est la règle du français, et c'est la ligne que la feuille
 * écrit le plus souvent au début d'un voyage.
 *
 * **Le nombre tient à son mot** (T161, recette sur iPhone SE, 07/10/2026) :
 * une espace insécable les lie. Sur l'écran étroit, la ligne « Transports »
 * se coupait en « 1 avion, 2 / trains, scooter » — le chiffre d'un côté, ce
 * qu'il compte de l'autre. La ligne ne se coupe plus qu'après une virgule.
 */
internal fun counted(count: Int, singular: String, plural: String, locale: Locale = Locale.getDefault()): String {
    val number = NumberFormat.getIntegerInstance(locale).apply { isGroupingUsed = true }.format(count)
    return if (count <= 1) "$number$NO_BREAK_SPACE$singular" else "$number$NO_BREAK_SPACE$plural"
}

/**
 * Une part d'une énumération, d'un seul tenant : « 2 trains », « à pied »
 * ne se coupent pas en fin de ligne. Voir [counted].
 */
internal fun unbroken(part: String): String = part.replace(' ', NO_BREAK_SPACE)

/**
 * « 6 pays, 8 régions, 13 villes » — la ligne « Étapes » de la feuille.
 *
 * **Une part à zéro s'omet.** La maquette n'écrit que des chiffres pleins ;
 * « 2 pays, 0 région, 7 villes » lirait un manque là où l'agent n'a
 * simplement rien relevé encore. Tout à zéro, la ligne le dit en clair
 * plutôt que de rester vide.
 */
internal val TravelFigures.placesLabel: String
    get() {
        val parts = listOfNotNull(
            if (countries > 0) counted(countries, "pays", "pays") else null,
            if (regions > 0) counted(regions, "région", "régions") else null,
            if (cities > 0) counted(cities, "ville", "villes") else null,
        )
        return if (parts.isEmpty()) StatisticsCopy.nothingYet else parts.joinToString(", ")
    }

/** « 406 personnes » — la ligne « Rencontres ». */
internal val TravelFigures.encountersLabel: String
    get() = if (encounters > 0) counted(encounters, "personne", "personnes") else StatisticsCopy.nothingYet

/**
 * « 2 280 km » — la ligne « Km parcourus ».
 *
 * La maquette écrit « 2.280km », collé et avec un point. On passe par le
 * formateur du système, comme pour les euros du profil : c'est lui qui
 * sait comment la région de l'utilisateur sépare les milliers, et l'unité
 * prend son espace comme le veut `agents/agent-transcription.md` § 8.6.
 * L'écart est signalé dans la fiche écran.
 */
internal val TravelFigures.distanceLabel: String
    get() = distanceLabel(Locale.getDefault())

internal fun TravelFigures.distanceLabel(locale: Locale): String =
    "${NumberFormat.getIntegerInstance(locale).apply { isGroupingUsed = true }.format(distanceKilometres)}${NO_BREAK_SPACE}km"

/**
 * « 10/12/2026 - 02/01/2027 », le sous-titre de la carte du voyage en
 * cours — le même format que la ligne du profil.
 */
internal val CurrentTripStatistics.dateRangeLabel: String?
    get() = numericRangeLabel(from = startDate, to = endDate)

/**
 * « Tu es actuellement à Rome. »
 *
 * La maquette vouvoie (« Vous êtes actuellement à Rome. ») ; R9 tutoie,
 * toujours, et c'est ce que le reste de l'écran fait déjà. Signalé dans
 * la fiche. `null` tant qu'aucun souvenir ni aucune destination ne situe
 * le voyageur : on ne dit pas où il est si on ne le sait pas.
 */
internal val CurrentTripStatistics.whereaboutsLabel: String?
    get() = currentPlace?.let { "Tu es actuellement à $it." }

/**
 * « 9 % écrit (2 jours validés sur 21) ».
 *
 * Le pourcentage passe par le formateur, qui pose l'espace fine devant le
 * signe en français ; la maquette le colle. L'accord suit le nombre de
 * jours validés — « 1 jour validé ».
 */
internal val CurrentTripStatistics.writtenLabel: String
    get() = writtenLabel(Locale.getDefault())

internal fun CurrentTripStatistics.writtenLabel(locale: Locale): String {
    val days = counted(validatedDays, "jour validé", "jours validés", locale)
    return "${writtenPercentLabel(locale)} écrit ($days sur $dayCount)"
}

/** « 9 % » seul, au centre de l'anneau. */
internal val CurrentTripStatistics.writtenPercentLabel: String
    get() = writtenPercentLabel(Locale.getDefault())

internal fun CurrentTripStatistics.writtenPercentLabel(locale: Locale): String =
    NumberFormat.getPercentInstance(locale).apply { maximumFractionDigits = 0 }.format(writtenFraction)

/** « 300 vocaux » — la ligne « Enregistrements ». */
internal val CurrentTripStatistics.recordingsLabel: String
    get() = if (recordings > 0) counted(recordings, "vocal", "vocaux") else StatisticsCopy.nothingYet

/**
 * « 1 avion, 2 trains, scooter » — la ligne « Transports », dans l'ordre
 * où le serveur les rend : les plus fréquents d'abord.
 */
internal val CurrentTripStatistics.transportsLabel: String
    get() = if (transports.isEmpty()) {
        StatisticsCopy.nothingYet
    } else {
        transports.joinToString(", ") { unbroken(it.label) }
    }

/**
 * La part des pays du compte que ce voyage couvre, pour le second anneau.
 * Un voyage qui couvre deux des six pays visités remplit un tiers.
 */
internal fun CurrentTripStatistics.countryFraction(overall: TravelFigures): Double {
    if (overall.countries <= 0) return if (figures.countries > 0) 1.0 else 0.0
    return minOf(1.0, figures.countries.toDouble() / overall.countries.toDouble())
}

/** « 5 voyages », en tête de la première carte. */
internal val TravelStatistics.tripCountLabel: String
    get() = counted(tripCount, "voyage", "voyages")

/**
 * La ligne qui dit que l'agent travaille : « 3 souvenirs en cours de
 * lecture ». `null` quand rien n'attend — la ligne disparaît.
 */
internal val TravelStatistics.detectingLabel: String?
    get() {
        if (pendingDetections <= 0) return null
        return if (pendingDetections == 1) {
            "1 souvenir en cours de lecture"
        } else {
            "$pendingDetections souvenirs en cours de lecture"
        }
    }

/**
 * « 10/12/2026 - 02/01/2027 » : deux dates **numériques** sur une ligne,
 * dans l'ordre de la région — le `Date.numericRangeLabel(from:to:)` d'iOS.
 * Partagé par la ligne « Voyage en cours » du profil et par la carte de la
 * feuille des statistiques.
 *
 * Le jour et le mois sur deux chiffres des deux côtés, et l'année entière :
 * le motif court de la région, dont seules les largeurs sont forcées — sans
 * ça, le mois en toutes lettres ne tiendrait pas en bout de ligne.
 */
internal fun numericRangeLabel(
    from: Instant?,
    to: Instant?,
    locale: Locale = Locale.getDefault(),
    zone: ZoneId = ZoneId.systemDefault(),
): String? {
    val numeric = numericDateFormatter(locale)
    fun format(date: Instant) = numeric.format(date.atZone(zone))
    return when {
        from != null && to != null -> "${format(from)} - ${format(to)}"
        from != null -> format(from)
        to != null -> format(to)
        else -> null
    }
}

/** Le motif court de la région, jour et mois sur deux chiffres, l'année entière. */
private fun numericDateFormatter(locale: Locale): DateTimeFormatter {
    val pattern = DateTimeFormatterBuilder.getLocalizedDateTimePattern(FormatStyle.SHORT, null, IsoChronology.INSTANCE, locale)
        .replace(Regex("d+"), "dd")
        .replace(Regex("M+"), "MM")
        .replace(Regex("[yu]+"), "yyyy")
    return DateTimeFormatter.ofPattern(pattern, locale)
}

/** Les libellés de la feuille qui n'appartiennent pas aux données. */
internal object StatisticsCopy {
    /**
     * Ce qu'une ligne écrit tant que l'agent n'a rien relevé pour elle. En
     * clair et non un tiret : un tiret se lit comme une panne.
     */
    const val nothingYet = "Pas encore relevé"
}
