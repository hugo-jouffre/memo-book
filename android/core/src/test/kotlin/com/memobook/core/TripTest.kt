package com.memobook.core

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ce que l'accueil déduit de ses données. Trois règles s'y jouent : le drapeau
 * se dérive du code pays plutôt que d'être stocké, les voyages se rangent
 * d'après leur étape et non d'après l'ordre reçu, et un état inconnu du
 * serveur ne fait disparaître personne de l'écran. Mêmes cas que `TripTests.swift`.
 */
class TripTest {

    // Drapeau

    @Test
    fun countryCodeGivesTheFlag() {
        assertEquals("🇮🇹", Destination(name = "Italie", countryCode = "IT").flag)
        assertEquals("🇵🇭", Destination(name = "Philippines", countryCode = "PH").flag)
    }

    @Test
    fun countryCodeIsReadWhateverItsCase() {
        assertEquals("🇵🇹", Destination(name = "Portugal", countryCode = "pt").flag)
    }

    @Test
    fun withoutACodeThereIsNoFlag() {
        assertNull(Destination(name = "Nulle part").flag)
    }

    /** Un code mal formé doit donner *rien*, jamais un carré blanc ou une
     *  lettre isolée : c'est ce que produirait un décalage Unicode aveugle. */
    @Test
    fun malformedCodesGiveNothing() {
        for (code in listOf("F", "FRA", "F1", "??", "", "é!")) {
            assertNull(
                Destination(name = "Test", countryCode = code).flag,
                "le code « $code » ne devrait pas produire de drapeau",
            )
        }
    }

    // Initiales

    @Test
    fun initialsTakeAtMostTwoWords() {
        assertEquals("CN", Companion(id = "1", name = "Claire Nguyen").initials)
        assertEquals("G", Companion(id = "1", name = "gus").initials)
        assertEquals("JM", Companion(id = "1", name = "Jean Michel Dupont").initials)
        assertEquals("", Companion(id = "1", name = "").initials)
    }

    // Rangement

    @Test
    fun ongoingTripsComeFirstMostRecentlyStarted() {
        val feed = makeFeed(
            listOf(
                trip("ancien", TripStage.Ongoing, start = day(-30)),
                trip("récent", TripStage.Ongoing, start = day(-2)),
                trip("fini", TripStage.Past, start = day(-90), end = day(-80)),
            ),
        )

        assertEquals(listOf("récent", "ancien"), feed.ongoingTrips.map { it.id })
        assertEquals(listOf("fini"), feed.pastTrips.map { it.id })
    }

    /** Parti en premier, rentré en dernier : c'est le retour qui décide de la
     *  place dans « Tes voyages précédents ». */
    @Test
    fun pastTripsAreSortedOnTheirEndNotTheirStart() {
        val feed = makeFeed(
            listOf(
                trip("long", TripStage.Past, start = day(-100), end = day(-10)),
                trip("court", TripStage.Past, start = day(-60), end = day(-55)),
            ),
        )

        assertEquals(listOf("long", "court"), feed.pastTrips.map { it.id })
    }

    @Test
    fun anUnknownStageStaysVisibleWithTheOngoingTrips() {
        val feed = makeFeed(listOf(trip("futur", TripStage.Unknown("upcoming"), start = day(10))))

        assertEquals(listOf("futur"), feed.ongoingTrips.map { it.id })
        assertTrue(feed.pastTrips.isEmpty())
    }

    @Test
    fun aTripWithoutDatesIsStillListed() {
        val feed = makeFeed(
            listOf(
                trip("sans date", TripStage.Ongoing, start = null),
                trip("daté", TripStage.Ongoing, start = day(-1)),
            ),
        )

        assertEquals(2, feed.ongoingTrips.size)
        assertEquals("daté", feed.ongoingTrips.first().id)
    }

    // Décodage de l'étape

    @Test
    fun knownStagesRoundTrip() {
        for (stage in listOf(TripStage.Ongoing, TripStage.Past)) {
            val data = MemoBookJson.encodeToString(TripStage.serializer(), stage)
            assertEquals(stage, MemoBookJson.decodeFromString(TripStage.serializer(), data))
        }
    }

    /** Même raison que `Status.Unknown` : une étape ajoutée côté serveur ne
     *  doit pas faire échouer le décodage d'une app déjà installée. */
    @Test
    fun aStageAddedByTheServerDecodesAsUnknown() {
        // « upcoming » a été un état inconnu jusqu'à ce qu'il devienne un vrai
        // cas : c'est justement ce que ce test protège, un serveur qui prend de
        // l'avance sur l'app.
        assertEquals(TripStage.Unknown("cancelled"), MemoBookJson.decodeFromString(TripStage.serializer(), "\"cancelled\""))
    }

    @Test
    fun theThreeKnownStagesDecodeAsThemselves() {
        assertEquals(TripStage.Upcoming, MemoBookJson.decodeFromString(TripStage.serializer(), "\"upcoming\""))
        assertEquals(TripStage.Ongoing, MemoBookJson.decodeFromString(TripStage.serializer(), "\"ongoing\""))
        assertEquals(TripStage.Past, MemoBookJson.decodeFromString(TripStage.serializer(), "\"past\""))
    }

    /** Un voyage à venir n'est **pas** un voyage en cours : il n'a rien à
     *  raconter, et il ne doit donc pas remonter dans la section du haut. */
    @Test
    fun anUpcomingTripIsNeitherOngoingNorPast() {
        val feed = makeFeed(
            listOf(
                trip("à-venir", TripStage.Upcoming, start = day(30)),
                trip("en-cours", TripStage.Ongoing, start = day(-2)),
                trip("passé", TripStage.Past, start = day(-60), end = day(-50)),
            ),
        )

        assertEquals(listOf("à-venir"), feed.upcomingTrips.map { it.id })
        assertEquals(listOf("en-cours"), feed.ongoingTrips.map { it.id })
        assertEquals(listOf("passé"), feed.pastTrips.map { it.id })
    }

    // Avancement

    @Test
    fun progressIsBoundedAtBothEnds() {
        assertEquals(0.0, TripProgress(memoryCount = 0, pageCount = 0, targetPageCount = 80).fraction)
        assertEquals(0.5, TripProgress(memoryCount = 9, pageCount = 40, targetPageCount = 80).fraction)

        // Un carnet qui dépasse sa cible ne fait pas déborder sa barre.
        assertEquals(1.0, TripProgress(memoryCount = 9, pageCount = 120, targetPageCount = 80).fraction)

        // Et une cible absente ne divise pas par zéro.
        assertEquals(0.0, TripProgress(memoryCount = 9, pageCount = 12, targetPageCount = 0).fraction)
    }

    // Le crédit du jour (Hugo, 03/10/2026)

    /** Le serveur sert le crédit sur chaque voyage **en cours** de l'accueil :
     *  c'est celui que vise le vocal de l'accueil. */
    @Test
    fun anOngoingTripCarriesItsDailyCredit() {
        val json = """
        {
          "id": "rome", "title": "Rome", "stage": "ongoing",
          "stats": { "dayCount": 3, "distanceKilometres": 0, "photoCount": 0 },
          "companions": [], "isPrintable": false,
          "dailyCredit": { "isUnlimited": false, "limitMs": 300000, "usedMs": 270000, "remainingMs": 30000,
                           "textMsPerCharacter": 75, "warningRemainingMs": 30000, "urgentRemainingMs": 5000,
                           "day": "2026-10-03", "resetsAt": "2026-10-03T22:00:00.000Z" }
        }
        """
        val trip = MemoBookJson.decodeFromString(Trip.serializer(), json)
        assertEquals(30_000, trip.dailyCredit?.remainingMs)
        assertEquals(DailyCredit.Phase.Warning, trip.dailyCredit?.phase)
    }

    /** Un voyage passé, ou un serveur d'avant le crédit : pas de crédit, et le
     *  voyage se décode comme avant. */
    @Test
    fun aTripWithoutCreditStillDecodes() {
        val json = """
        {
          "id": "rome", "title": "Rome", "stage": "past",
          "stats": { "dayCount": 3, "distanceKilometres": 0, "photoCount": 0 },
          "companions": [], "isPrintable": true
        }
        """
        val trip = MemoBookJson.decodeFromString(Trip.serializer(), json)
        assertNull(trip.dailyCredit)
        // Ni `canDelete` : la croix reste montrée, et c'est le serveur qui
        // refusera (T233).
        assertTrue(trip.isDeletable)
    }

    /** T233 : un co-voyageur ne voit pas « Supprimer le voyage ». */
    @Test
    fun aCompanionsTripIsNotDeletable() {
        val json = """
        {
          "id": "rome", "title": "Rome", "stage": "past",
          "stats": { "dayCount": 3, "distanceKilometres": 0, "photoCount": 0 },
          "companions": [], "isPrintable": true, "canDelete": false
        }
        """
        val trip = MemoBookJson.decodeFromString(Trip.serializer(), json)
        assertFalse(trip.isDeletable)
        // Un voyage créé hors ligne appartient à son créateur.
        assertTrue(Trip.local(TripDraft(title = "Lisbonne"), id = "l").isDeletable)
    }

    // Fabriques

    private fun makeFeed(trips: List<Trip>): HomeFeed =
        HomeFeed(traveller = Traveller(id = "t", firstName = "Camille"), trips = trips)

    private fun trip(id: String, stage: TripStage, start: Instant?, end: Instant? = null): Trip =
        Trip(id = id, title = id, stage = stage, startDate = start, endDate = end)

    /** Une date fixe décalée de `offset` jours : les tests ne doivent pas
     *  dépendre du moment où on les lance. */
    private fun day(offset: Int): Instant = Instant.ofEpochSecond(1_700_000_000L + offset * 86_400L)
}
