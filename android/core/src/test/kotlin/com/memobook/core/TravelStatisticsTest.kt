package com.memobook.core

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ce que la feuille « Statistiques » déduit de ce que le serveur rend : la part
 * du voyage écrite, l'accord d'un moyen de transport, et un décodage qui survit
 * à un serveur plus ancien ou à un transport que l'app ne connaît pas. Mêmes cas
 * que `TravelStatisticsTests.swift`.
 */
class TravelStatisticsTest {
    private fun decode(json: String): TravelStatistics = MemoBookJson.decodeFromString(TravelStatistics.serializer(), json)

    private val sample = TravelStatistics(
        tripCount = 2,
        overall = TravelFigures(countries = 2, regions = 1, cities = 3, encounters = 4, distanceKilometres = 120),
        currentTrip = CurrentTripStatistics(id = "rome", dayCount = 10, validatedDays = 1),
        pendingDetections = 0,
        updatedAt = Instant.ofEpochSecond(0),
    )

    // MARK: - Ce qui se déduit

    @Test
    fun writtenFractionIsValidatedDaysOverDayCount() {
        val trip = CurrentTripStatistics(id = "t", dayCount = 21, validatedDays = 2)
        assertEquals(2.0 / 21.0, trip.writtenFraction, absoluteTolerance = 0.0001)
    }

    /** Un pourcentage d'une durée inconnue ne veut rien dire : zéro, et pas une division par zéro. */
    @Test
    fun writtenFractionIsZeroWithoutDayCount() {
        assertEquals(0.0, CurrentTripStatistics(id = "t", dayCount = 0, validatedDays = 3).writtenFraction)
    }

    /** Plus de jours validés que de jours de voyage — un voyage prolongé sans que
     *  la fiche le sache — reste à 100 %, pas au-delà. */
    @Test
    fun writtenFractionIsCapped() {
        assertEquals(1.0, CurrentTripStatistics(id = "t", dayCount = 3, validatedDays = 5).writtenFraction)
    }

    @Test
    fun transportLabelsAgreeWithTheirCount() {
        assertEquals("1 avion", TransportUsage(kind = TransportUsage.Kind.Plane, count = 1).label)
        assertEquals("2 trains", TransportUsage(kind = TransportUsage.Kind.Train, count = 2).label)
        assertEquals("3 bateaux", TransportUsage(kind = TransportUsage.Kind.Boat, count = 3).label)
        // Sans nombre relevé, le mot seul — « scooter », comme la maquette.
        assertEquals("scooter", TransportUsage(kind = TransportUsage.Kind.Scooter).label)
        // La marche ne se compte jamais.
        assertEquals("à pied", TransportUsage(kind = TransportUsage.Kind.Walk, count = 4).label)
    }

    /** Deux lectures à quelques secondes d'écart ne diffèrent que par leur
     *  horodatage : la feuille ne doit pas les prendre pour un changement. */
    @Test
    fun sameFiguresIgnoreTheTimestamp() {
        var first = sample
        val second = first.copy(updatedAt = Instant.ofEpochSecond(10))
        assertTrue(first.hasSameFigures(second))

        first = first.copy(overall = first.overall.copy(cities = first.overall.cities + 1))
        assertFalse(first.hasSameFigures(second))
    }

    // MARK: - Décodage

    @Test
    fun decodesTheServerShape() {
        val statistics = decode(
            """
            {
              "tripCount": 3,
              "overall": { "countries": 3, "regions": 1, "cities": 4, "encounters": 6, "distanceKilometres": 129 },
              "currentTrip": {
                "id": "rome",
                "startDate": "2026-08-26T00:00:00.000Z",
                "endDate": "2026-09-15T00:00:00.000Z",
                "currentPlace": "Rome",
                "dayCount": 13,
                "validatedDays": 2,
                "figures": { "countries": 1, "regions": 1, "cities": 2, "encounters": 6, "distanceKilometres": 87 },
                "recordings": 4,
                "transports": [{ "kind": "train", "count": 2 }, { "kind": "scooter", "count": null }]
              },
              "pendingDetections": 1,
              "updatedAt": "2026-09-17T14:11:19.003Z"
            }
            """,
        )

        assertEquals(3, statistics.tripCount)
        assertEquals(129, statistics.overall.distanceKilometres)
        assertTrue(statistics.isDetecting)
        val trip = assertNotNull(statistics.currentTrip)
        assertEquals("Rome", trip.currentPlace)
        assertEquals(
            listOf(
                TransportUsage(kind = TransportUsage.Kind.Train, count = 2),
                TransportUsage(kind = TransportUsage.Kind.Scooter, count = null),
            ),
            trip.transports,
        )
    }

    /** Un moyen de transport que cette version ne connaît pas est sauté, pas
     *  fatal : l'agent peut apprendre un mot avant l'app. */
    @Test
    fun skipsUnknownTransportsInsteadOfFailing() {
        val statistics = decode(
            """
            {
              "tripCount": 1,
              "overall": { "countries": 1, "regions": 0, "cities": 1, "encounters": 0, "distanceKilometres": 0 },
              "currentTrip": {
                "id": "rome",
                "transports": [{ "kind": "helicopter", "count": 1 }, { "kind": "bus", "count": 1 }]
              },
              "pendingDetections": 0
            }
            """,
        )
        assertEquals(listOf(TransportUsage(kind = TransportUsage.Kind.Bus, count = 1)), statistics.currentTrip?.transports)
        // Les champs que ce serveur ne sert pas tombent sur leur zéro.
        assertEquals(0, statistics.currentTrip?.dayCount)
        assertEquals(TravelFigures.empty, statistics.currentTrip?.figures)
    }

    /** Un serveur plus ancien, qui ne connaît pas encore la route, rend un objet
     *  vide : la feuille s'ouvre quand même, à zéro. */
    @Test
    fun decodesAnEmptyObject() {
        val statistics = decode("{}")
        assertEquals(0, statistics.tripCount)
        assertNull(statistics.currentTrip)
        assertFalse(statistics.isDetecting)
    }
}
