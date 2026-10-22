package com.memobook.feature.tripsettings

import com.memobook.core.DailyCredit
import com.memobook.core.TripSettings
import com.memobook.feature.chat.OutgoingTurn
import com.memobook.feature.chat.RecordedTurnAudio
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import java.time.Instant
import java.util.UUID
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Le crédit du jour des réglages du voyage : **seul l'envoyé compte** (Hugo,
 * 06/10/2026). Le crédit servi, moins ce qui a été envoyé et attend la file —
 * comme la conversation et l'accueil —, et rien d'autre. Porté de
 * `TripSettingsCreditTests.swift`, cas pour cas.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class TripSettingsCreditTest {
    private fun settings(usedMs: Int, isUnlimited: Boolean = false): TripSettings =
        TripSettings.fixture.copy(dailyCredit = DailyCredit(isUnlimited = isUnlimited, usedMs = usedMs))

    private fun voice(seconds: Double, id: String = UUID.randomUUID().toString()): OutgoingTurn =
        OutgoingTurn(
            id = id,
            body = OutgoingTurn.Body.Voice(
                RecordedTurnAudio(
                    data = ByteArray(0),
                    filename = "vocal.m4a",
                    mimeType = "audio/mp4",
                    capturedAt = Instant.now(),
                    durationSeconds = seconds,
                    levels = emptyList(),
                ),
            ),
        )

    @BeforeTest fun setUp() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @AfterTest fun tearDown() {
        Dispatchers.resetMain()
    }

    /**
     * Rien en file : le crédit servi, tel quel — un vocal en cours ou en pause
     * n'est envoyé nulle part, il n'existe pas ici.
     */
    @Test fun nothingSentNothingCounted() = runTest {
        val model = TripSettingsModel(
            tripId = "rome",
            source = { settings(usedMs = 60_000) },
            waitingTurns = { emptyList() },
        )
        model.load()
        assertEquals(240_000, model.dailyCredit?.remainingMs)
    }

    /** Un vocal envoyé hors ligne compte, comme dans la conversation. */
    @Test fun aSentTurnWaitingForTheNetworkCounts() = runTest {
        val turn = voice(seconds = 90.0)
        val model = TripSettingsModel(
            tripId = "rome",
            source = { settings(usedMs = 60_000) },
            waitingTurns = { listOf(turn) },
        )
        model.load()
        assertEquals(150_000, model.dailyCredit?.remainingMs)
    }

    /** Un tour retenu pour demain prendra le crédit de demain. */
    @Test fun aTurnHeldForTomorrowDoesNotCountToday() = runTest {
        val held = OutgoingTurn(
            body = OutgoingTurn.Body.Text("Hier soir"),
            waitingForCreditUntil = Instant.now().plusSeconds(3_600),
        )
        val model = TripSettingsModel(
            tripId = "rome",
            source = { settings(usedMs = 60_000) },
            waitingTurns = { listOf(held) },
        )
        model.load()
        assertEquals(240_000, model.dailyCredit?.remainingMs)
    }
}
