@file:OptIn(ExperimentalCoroutinesApi::class)

package com.memobook.feature.tripcreation

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import java.time.Instant
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * T246 : l'étape « Notifications » de la création se retient sur l'appareil,
 * choisie ou passée — c'est ce qui fait paraître la bulle de la conversation.
 *
 * La moitié « création » du troisième cas de `NotificationsNudgeTests.swift`
 * (`testTheStepIsRememberedWhetherChosenOrSkipped`) : l'autre moitié — ce que
 * `NotificationsNudge` retient — est portée avec lui
 * (`chat/NotificationsNudgeTest.kt`). Ici, le modèle prévient au bon moment,
 * et une seule fois par passage.
 */
class TripCreationNotificationsStepTest {
    private val dispatcher = StandardTestDispatcher()

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(dispatcher)
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun theStepIsRememberedWhetherChosenOrSkipped() = runTest(dispatcher) {
        var passed = 0
        val model = TripCreationModel(notificationsStepPassed = { passed += 1 })
        model.draft = model.draft.copy(title = "Lisbonne")
        model.validate()
        model.draft = model.draft.copy(startDate = Instant.now())
        model.validate()
        assertEquals(0, passed, "Le nom et les dates ne sont pas l'étape des notifications.")

        model.skip()
        assertEquals(1, passed)
    }
}
