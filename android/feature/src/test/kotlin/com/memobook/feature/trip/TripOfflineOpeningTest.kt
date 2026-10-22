@file:OptIn(ExperimentalCoroutinesApi::class)

package com.memobook.feature.trip

import com.memobook.core.Trip
import com.memobook.core.TripDetail
import com.memobook.core.TripStage
import com.memobook.core.TripStep
import com.memobook.feature.ContentFreshness
import com.memobook.networking.ApiError
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import java.io.IOException
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/**
 * D11 (Hugo, 19/10/2026) : hors ligne, un voyage jamais ouvert sur ce
 * téléphone s'ouvre d'après la carte de l'accueil — et non plus sur un
 * squelette sans chemin vers la conversation. Une réponse du serveur garde
 * son écran d'erreur. Porté de `TripOfflineOpeningTests.swift`, cas pour cas.
 */
class TripOfflineOpeningTest {
    private val dispatcher = StandardTestDispatcher()
    private val card = Trip(id = "rome", title = "Rome", stage = TripStage.Ongoing)
    private val offline: ApiError get() = ApiError.Transport(IOException("hors ligne"), url = null)

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(dispatcher)
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun withoutNetworkNorCacheTheHomeCardOpensTheTrip() = runTest(dispatcher) {
        val model = TripHomeModel(
            tripId = "rome",
            source = { throw offline },
            homeCard = { card },
        )
        model.load()

        assertEquals(card, model.detail?.trip)
        assertEquals(emptyList(), model.detail?.steps)
        assertNotNull(model.errorMessage, "Le bandeau reste : la page ne prétend pas être à jour.")
        assertFalse(model.isLoading)
        assertEquals(ContentFreshness.Restored, model.freshness)
    }

    @Test
    fun aServerAnswerKeepsItsErrorScreen() = runTest(dispatcher) {
        val model = TripHomeModel(
            tripId = "rome",
            source = { throw ApiError.Server(statusCode = 404, code = null, message = "Voyage introuvable.") },
            homeCard = { card },
        )
        model.load()

        assertNull(model.detail)
        assertEquals("Voyage introuvable.", model.errorMessage)
    }

    /** Ce qu'on avait gardé de l'écran du voyage passe avant la carte : il en sait plus (les étapes). */
    @Test
    fun theTripCacheWinsOverTheHomeCard() = runTest(dispatcher) {
        val stored = TripDetail(trip = card, steps = listOf(TripStep(id = "a", number = 1)))
        val model = TripHomeModel(
            tripId = "rome",
            source = { throw offline },
            cached = { stored },
            homeCard = { Trip(id = "rome", title = "Autre", stage = TripStage.Ongoing) },
        )
        model.load()

        assertEquals(stored, model.detail)
    }

    /** Le réseau revenu, le serveur remplace la carte. */
    @Test
    fun theServerReplacesTheCardOnTheNextLoad() = runTest(dispatcher) {
        var isOnline = false
        val served = TripDetail(trip = card, steps = listOf(TripStep(id = "a", number = 1)))
        val model = TripHomeModel(
            tripId = "rome",
            source = {
                if (!isOnline) throw offline
                served
            },
            homeCard = { card },
        )
        model.load()
        isOnline = true
        model.load()

        assertEquals(served, model.detail)
        assertNull(model.errorMessage)
    }
}
