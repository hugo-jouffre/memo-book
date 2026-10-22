package com.memobook.feature.tripsettings

import com.memobook.core.TripSettings
import com.memobook.feature.home.TripDates
import java.time.ZoneId
import java.util.Locale

// Mise en forme des données du parcours « carnet » : paramètres du voyage,
// aperçu PDF. Jumeau de `TripSettings/BookFormatting.swift`.
//
// Tout passe par les formats de la langue du téléphone (`TripDates`) plutôt
// que par des chaînes assemblées à la main — même parti pris que
// `TripFormatting` : c'est ce qui donne « 26 août – 15 sept. 2026 » en
// français et « Aug 26 – Sep 15, 2026 » en anglais, sans qu'un écran
// connaisse une seule règle de langue.

/**
 * La ligne de dates du voyage — « 26 août – 15 sept. 2026 ».
 *
 * `null` quand le voyage n'a aucune date : c'est la vue qui décide alors quoi
 * écrire, et elle pose le tiret de `BookCopy.Settings.noValue`. Une ligne de
 * réglage vide se lirait comme une valeur qui n'a pas chargé.
 */
internal val TripSettings.dateRangeLabel: String?
    get() = dateRangeLabel(Locale.getDefault(), ZoneId.systemDefault())

/** [dateRangeLabel], à une locale et un fuseau donnés — ceux du téléphone dans l'app, fixés dans les tests. */
internal fun TripSettings.dateRangeLabel(locale: Locale, zone: ZoneId): String? {
    val start = startDate
    val end = endDate
    return when {
        start != null && end != null && start < end -> TripDates.interval(start, end, locale, zone)
        // Un voyage commencé qui n'a pas de fin : le cas courant d'un carnet
        // ouvert, pas une donnée manquante.
        start != null -> TripDates.day(start, locale, zone)
        end != null -> TripDates.day(end, locale, zone)
        else -> null
    }
}
