package com.memobook.feature

import com.memobook.core.HomeFeed
import com.memobook.feature.home.fixture
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Le bac à sable s'ouvre derrière son accueil : c'est la raison d'être du
 * lancement `previewSignedIn` (voir `FixtureTripId`).
 */
class PreviewSupportTest {
    /**
     * `RootView` n'ouvre qu'un identifiant de ressource — un UUID. Avec des
     * identifiants lisibles, aucun voyage du bac à sable ne s'ouvrait.
     */
    @Test fun everyFixtureTripHasAResourceId() {
        for (trip in HomeFeed.fixture.trips) {
            assertTrue(RootState.isResourceId(trip.id), "« ${trip.title} » : ${trip.id} n'est pas un UUID.")
        }
    }

    /** L'accueil, puis pour chaque voyage son écran, son fil et ses réglages — sans lever. */
    @Test fun thePreviewApiOpensEveryFixtureTrip() = runTest {
        val api = PreviewApi()
        val feed = api.homeFeed()
        assertEquals(HomeFeed.fixture.trips.map { it.id }, feed.trips.map { it.id })

        for (trip in feed.trips) {
            val detail = api.tripDetail(trip.id)
            assertEquals(trip.id, detail.trip.id, "Le voyage ouvert est celui de la carte.")

            val thread = api.chatThread(trip.id)
            assertEquals(trip.id, thread.id)
            assertTrue(thread.dailyCredit != null, "Le fil arrive avec son crédit du jour.")

            val settings = api.tripSettings(trip.id)
            assertTrue(settings.dailyCredit != null, "Les réglages arrivent avec le crédit du jour.")
        }
    }
}
