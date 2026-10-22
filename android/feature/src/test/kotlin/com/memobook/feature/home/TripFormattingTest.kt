package com.memobook.feature.home

import com.memobook.core.Trip
import com.memobook.core.TripProgress
import com.memobook.core.TripStage
import com.memobook.core.TripStats
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * La mise en forme d'un voyage (`TripFormatting.kt`). iOS n'a pas de test de
 * ces règles — le `FormatStyle` du système en tient lieu ; ici, c'est l'app qui
 * les écrit, et ces cas les tiennent.
 */
class TripFormattingTest {
    private val paris = ZoneId.of("Europe/Paris")
    private val french = Locale.FRANCE

    private fun day(year: Int, month: Int, dayOfMonth: Int) = LocalDate.of(year, month, dayOfMonth).atTime(12, 0).atZone(paris).toInstant()

    private fun trip(start: LocalDate?, end: LocalDate?) = Trip(
        id = "rome",
        title = "Rome",
        stage = TripStage.Ongoing,
        startDate = start?.atTime(12, 0)?.atZone(paris)?.toInstant(),
        endDate = end?.atTime(12, 0)?.atZone(paris)?.toInstant(),
    )

    /** Ce que les deux bornes partagent ne s'écrit qu'une fois : l'année, puis le mois. */
    @Test fun theIntervalWritesWhatItSharesOnce() {
        assertEquals("26 août – 15 sept. 2026", trip(LocalDate.of(2026, 8, 26), LocalDate.of(2026, 9, 15)).dateRangeLabel(french, paris))
        assertEquals("3–10 août 2026", trip(LocalDate.of(2026, 8, 3), LocalDate.of(2026, 8, 10)).dateRangeLabel(french, paris))
        assertEquals("28 déc. 2025 – 3 janv. 2026", trip(LocalDate.of(2025, 12, 28), LocalDate.of(2026, 1, 3)).dateRangeLabel(french, paris))
    }

    /** Un voyage commencé sans fin : sa seule date, et non une donnée manquante. Sans date : pas de ligne. */
    @Test fun aSingleDateOrNone() {
        assertEquals("26 août 2026", trip(LocalDate.of(2026, 8, 26), null).dateRangeLabel(french, paris))
        assertEquals("15 sept. 2026", trip(null, LocalDate.of(2026, 9, 15)).dateRangeLabel(french, paris))
        assertNull(trip(null, null).dateRangeLabel(french, paris))
        // Une fin avant le début ne fait pas d'intervalle : le début seul.
        assertEquals("15 sept. 2026", trip(LocalDate.of(2026, 9, 15), LocalDate.of(2026, 8, 26)).dateRangeLabel(french, paris))
        assertEquals("26 août 2026", TripDates.day(day(2026, 8, 26), french, paris))
    }

    @Test fun theProgressCountsMemoriesAndPages() {
        assertEquals("0 souvenir et 0/80 pages", TripProgress(memoryCount = 0, pageCount = 0, targetPageCount = 80).summary)
        assertEquals("1 souvenir et 2/80 pages", TripProgress(memoryCount = 1, pageCount = 2, targetPageCount = 80).summary)
        assertEquals("5 souvenirs et 2/80 pages", TripProgress(memoryCount = 5, pageCount = 2, targetPageCount = 80).summary)
    }

    /** Seuls les compteurs servis apparaissent, dans l'ordre de la maquette. */
    @Test fun theStatsKeepTheOrderAndAgree() {
        val items = TripStats(dayCount = 1, distanceKilometres = 42.4, photoCount = 3).items(french)
        assertEquals(listOf(TripStatItem.Kind.Duration, TripStatItem.Kind.Distance, TripStatItem.Kind.Photos), items.map { it.kind })
        assertEquals(listOf("1 jour", "42 km", "3 photos"), items.map { it.text })

        assertEquals(listOf("12 jours"), TripStats(dayCount = 12).items(french).map { it.text })
        assertEquals(listOf("1 photo"), TripStats(photoCount = 1).items(french).map { it.text })
        assertEquals("2 jours", TripStats(dayCount = 2).inlineSummary)
        assertNull(TripStats().inlineSummary)
    }

    /** Le kilomètre est l'unité de stockage, pas d'affichage : aux États-Unis, la route se compte en miles. */
    @Test fun theDistanceFollowsTheRegion() {
        assertEquals("10 mi", TripStatLabels.distance(16.09344, Locale.Builder().setLanguage("fr").setRegion("US").build()))
        assertEquals("16 km", TripStatLabels.distance(16.09344, Locale.Builder().setLanguage("fr").setRegion("CA").build()))
    }

    /**
     * La teinte de repli d'un voyage est la même que sur iPhone : le même
     * calcul (djb2 sur 64 bits), les mêmes rangs — relevés avec le calcul
     * d'iOS.
     */
    @Test fun thePlaceholderTintMatchesTheIPhone() {
        assertEquals(1, TripCoverPlaceholder.index(""))
        assertEquals(0, TripCoverPlaceholder.index("rome"))
        assertEquals(3, TripCoverPlaceholder.index("lisbonne"))
        assertEquals(1, TripCoverPlaceholder.index("new-york"))
        assertEquals(3, TripCoverPlaceholder.index("été à Séville"))
    }
}
