@file:OptIn(ExperimentalCoroutinesApi::class)

package com.memobook.feature.trip

import com.memobook.core.Trip
import com.memobook.core.TripDetail
import com.memobook.core.TripStage
import com.memobook.core.TripStep
import com.memobook.networking.ApiError
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * T235 : la croix du tiroir d'une étape efface **tous** ses souvenirs, et
 * l'étape quitte l'écran. Sans émulateur — le modèle reçoit ses fonctions
 * comme l'app les lui branche. Porté de `TripStepDeletionTests.swift`, cas
 * pour cas.
 */
class TripStepDeletionTest {
    private val dispatcher = StandardTestDispatcher()

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(dispatcher)
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun step(id: String, entries: List<String>?): TripStep = TripStep(id = id, number = 1, entryIds = entries)

    private fun detail(steps: List<TripStep>): TripDetail =
        TripDetail(trip = Trip(id = "rome", title = "Rome", stage = TripStage.Ongoing), steps = steps)

    @Test
    fun everyMemoryOfTheStepIsDeletedThenTheStepLeaves() = runTest(dispatcher) {
        val deleted = mutableListOf<String>()
        var served = detail(listOf(step("a", listOf("e1", "e2")), step("b", listOf("e3"))))
        val model = TripHomeModel(
            tripId = "rome",
            source = { served },
            deleteEntry = { id ->
                deleted += id
                served = detail(listOf(step("b", listOf("e3"))))
            },
        )
        model.load()

        val target = served.steps[0]
        assertTrue(model.canDeleteMemories(target))
        val done = model.deleteMemories(target)

        assertTrue(done)
        assertEquals(listOf("e1", "e2"), deleted)
        assertEquals(listOf("b"), model.detail?.steps?.map { it.id })
        assertNotNull(model.confirmation)
    }

    @Test
    fun aRefusalKeepsTheSheetOpenWithTheServerSentence() = runTest(dispatcher) {
        val model = TripHomeModel(
            tripId = "rome",
            source = { detail(listOf(step("a", listOf("e1")))) },
            deleteEntry = { throw ApiError.Server(statusCode = 500, code = null, message = "Réessaie.") },
        )
        model.load()

        val done = model.deleteMemories(step("a", listOf("e1")))
        assertFalse(done)
        assertEquals("Réessaie.", model.stepDeletionError)
        assertEquals(1, model.detail?.steps?.size)
    }

    /** Un serveur qui ne dit pas quels souvenirs porte l'étape : pas de croix. */
    @Test
    fun noCrossWithoutTheMemoriesOfTheStep() {
        val model = TripHomeModel(tripId = "rome", deleteEntry = {})
        assertFalse(model.canDeleteMemories(step("a", null)))
        assertFalse(model.canDeleteMemories(step("a", emptyList())))
        assertFalse(TripHomeModel(tripId = "rome").canDeleteMemories(step("a", listOf("e1"))))
    }
}
