package com.memobook.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.builtins.ListSerializer
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Le back-end sérialise ses dates avec `toISOString()`, qui inclut les
 * millisecondes. Ces tests verrouillent le décodage, sans quoi tout l'écran se
 * vide silencieusement. Mêmes cas que `DecodingTests.swift`.
 */
class DecodingTest {
    private val decoder = MemoBookJson

    @Serializable
    private data class Wrapper(val status: Status)

    @Test
    fun decodesDateWithFractionalSeconds() {
        val json = """
            {
              "id": "r1",
              "memoId": "m1",
              "status": "ready",
              "pdfUrl": "https://example.test/a.pdf",
              "error": null,
              "createdAt": "2026-08-08T12:48:25.295Z",
              "updatedAt": "2026-08-08T12:48:28.990Z"
            }
        """.trimIndent()

        val render = decoder.decodeFromString(Render.serializer(), json)

        assertEquals(Status.Ready, render.status)
        assertEquals(
            MemoBookDate.parse("2026-08-08T12:48:25.295Z")!!.toEpochMilli() / 1000.0,
            render.createdAt.toEpochMilli() / 1000.0,
            absoluteTolerance = 0.001,
        )
    }

    @Test
    fun decodesDateWithoutFractionalSeconds() {
        val json = """
            {
              "id": "r1", "memoId": "m1", "status": "pending", "pdfUrl": null,
              "error": null,
              "createdAt": "2026-08-08T12:48:25Z", "updatedAt": "2026-08-08T12:48:25Z"
            }
        """.trimIndent()

        decoder.decodeFromString(Render.serializer(), json)
    }

    @Test
    fun rejectsUnparseableDate() {
        val json = """
            {
              "id": "r1", "memoId": "m1", "status": "pending", "pdfUrl": null,
              "error": null, "createdAt": "hier", "updatedAt": "2026-08-08T12:48:25Z"
            }
        """.trimIndent()

        assertFailsWith<SerializationException> { decoder.decodeFromString(Render.serializer(), json) }
    }

    /** Un statut ajouté côté serveur ne doit pas casser une app déjà installée. */
    @Test
    fun unknownStatusDecodesInsteadOfThrowing() {
        val wrapper = decoder.decodeFromString(Wrapper.serializer(), """{"status":"queued_for_print"}""")

        assertEquals(Status.Unknown("queued_for_print"), wrapper.status)
        assertTrue(wrapper.status.isInProgress)
    }

    @Test
    fun statusRoundTrips() {
        val serializer = ListSerializer(Status.serializer())
        for (status in listOf(Status.Pending, Status.Processing, Status.Ready, Status.Failed, Status.Unknown("autre"))) {
            val encoded = decoder.encodeToString(serializer, listOf(status))
            val decoded = decoder.decodeFromString(serializer, encoded)
            assertEquals(status, decoded.first())
        }
    }

    @Test
    fun terminalStates() {
        assertTrue(Status.Ready.isTerminal)
        assertTrue(Status.Failed.isTerminal)
        assertFalse(Status.Pending.isTerminal)
        assertFalse(Status.Processing.isTerminal)
    }

    @Test
    fun memoDetailExposesMostRecentRender() {
        val now = Instant.now()
        val recent = Render(id = "r2", memoId = "m1", status = Status.Ready, createdAt = now, updatedAt = now)
        val older = Render(
            id = "r1",
            memoId = "m1",
            status = Status.Failed,
            createdAt = now.minusSeconds(100),
            updatedAt = now.minusSeconds(100),
        )

        val memo = MemoDetail(
            id = "m1",
            title = "Carnet",
            createdAt = now,
            updatedAt = now,
            renders = listOf(recent, older),
        )

        assertEquals("r2", memo.latestRender?.id)
    }
}
