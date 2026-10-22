package com.memobook.feature.profile

import com.memobook.core.CurrentTripStatistics
import com.memobook.core.TransportUsage
import com.memobook.core.TravelFigures
import com.memobook.core.TravelStatistics
import kotlinx.coroutines.test.runTest
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.time.Duration.Companion.seconds

/**
 * La feuille « Statistiques » : ses accords (`StatisticsFormatting.kt`) et sa
 * veille (`StatisticsModel`). iOS n'a pas de suite à elle ; ces cas tiennent
 * les règles que ses commentaires énoncent.
 */
class StatisticsModelTest {
    private val paris = ZoneId.of("Europe/Paris")

    /** Les espaces insécables du français, ramenées à des espaces pour la lecture. */
    private fun plain(text: String) = text.replace(' ', ' ').replace(' ', ' ')

    /** Deux dates numériques, jour et mois sur deux chiffres, l'année entière. */
    @Test
    fun aRangeIsTwoNumericDates() {
        val start = Instant.parse("2026-12-10T10:00:00Z")
        val end = Instant.parse("2027-01-02T10:00:00Z")
        assertEquals("10/12/2026 - 02/01/2027", numericRangeLabel(start, end, Locale.FRANCE, paris))
        assertEquals("10/12/2026", numericRangeLabel(start, null, Locale.FRANCE, paris))
        assertEquals("02/01/2027", numericRangeLabel(null, end, Locale.FRANCE, paris))
        assertNull(numericRangeLabel(null, null, Locale.FRANCE, paris))
    }

    /** Zéro prend le singulier, et le nombre tient à son mot. */
    @Test
    fun aCountAgreesAndHoldsToItsWord() {
        assertEquals("0 jour validé", counted(0, "jour validé", "jours validés", Locale.FRANCE))
        assertEquals("1 vocal", counted(1, "vocal", "vocaux", Locale.FRANCE))
        assertEquals("2 280 vocaux", plain(counted(2_280, "vocal", "vocaux", Locale.FRANCE)))
    }

    /** Une part à zéro s'omet ; tout à zéro, la ligne le dit en clair. */
    @Test
    fun aZeroPartIsLeftOut() {
        assertEquals("2 pays, 7 villes", plain(TravelFigures(countries = 2, cities = 7).placesLabel))
        assertEquals(StatisticsCopy.nothingYet, TravelFigures().placesLabel)
        assertEquals(StatisticsCopy.nothingYet, TravelFigures().encountersLabel)
        assertEquals("2 280 km", plain(TravelFigures(distanceKilometres = 2_280).distanceLabel(Locale.FRANCE)))
    }

    @Test
    fun theCurrentTripReadsAsTheMockupSaysIt() {
        val trip = CurrentTripStatistics(
            id = "rome",
            currentPlace = "Rome",
            dayCount = 21,
            validatedDays = 2,
            transports = listOf(TransportUsage(TransportUsage.Kind.Plane, 1), TransportUsage(TransportUsage.Kind.Train, 2)),
        )
        assertEquals("Tu es actuellement à Rome.", trip.whereaboutsLabel)
        assertEquals("10 % écrit (2 jours validés sur 21)", plain(trip.writtenLabel(Locale.FRANCE)))
        assertEquals("1 avion, 2 trains", plain(trip.transportsLabel))
        assertEquals(StatisticsCopy.nothingYet, trip.recordingsLabel)
        assertNull(trip.copy(currentPlace = null).whereaboutsLabel)
    }

    @Test
    fun theCountryRingFillsWithTheTripShare() {
        val trip = CurrentTripStatistics(id = "rome", figures = TravelFigures(countries = 2))
        assertEquals(1.0 / 3.0, trip.countryFraction(TravelFigures(countries = 6)), 0.0001)
        assertEquals(1.0, trip.countryFraction(TravelFigures()))
        assertEquals(0.0, CurrentTripStatistics(id = "rome").countryFraction(TravelFigures()))
    }

    @Test
    fun theDetectingLineAgrees() {
        assertNull(TravelStatistics().detectingLabel)
        assertEquals("1 souvenir en cours de lecture", TravelStatistics(pendingDetections = 1).detectingLabel)
        assertEquals("3 souvenirs en cours de lecture", TravelStatistics(pendingDetections = 3).detectingLabel)
    }

    /** Rien n'attend : une lecture, et la veille s'arrête. */
    @Test
    fun theWatchStopsWhenNothingIsPending() = runTest {
        var reads = 0
        val model = StatisticsModel(source = {
            reads += 1
            TravelStatistics(tripCount = 1)
        }, pollInterval = 1.seconds)

        model.watch()

        assertEquals(1, reads)
    }

    /** Un relevé attendu fait relire, jusqu'à ce que la file soit vide. */
    @Test
    fun theWatchRereadsUntilTheQueueIsEmpty() = runTest {
        var reads = 0
        val model = StatisticsModel(source = {
            reads += 1
            TravelStatistics(tripCount = reads, pendingDetections = if (reads < 3) 1 else 0)
        }, pollInterval = 1.seconds)

        model.watch()

        assertEquals(3, reads)
        assertEquals(0, model.state.value.statistics?.pendingDetections)
    }

    /** Un relevé bloqué : la veille lâche après ses relectures sans changement. */
    @Test
    fun aStuckDetectionIsLetGo() = runTest {
        var reads = 0
        val model = StatisticsModel(source = {
            reads += 1
            TravelStatistics(tripCount = 1, pendingDetections = 2)
        }, pollInterval = 1.seconds)

        model.watch()

        assertEquals(1 + StatisticsModel.MAX_UNCHANGED_POLLS, reads)
    }
}
