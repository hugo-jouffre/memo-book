package com.memobook.recording

import com.memobook.core.MemoBookJson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import java.io.File
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * La file sur le disque : ce qui n'existe nulle part ailleurs. Le dernier cas
 * de `RecordingOutboxTests.swift` (la fiche et sa marque du crédit), et ce que
 * la file promet de son disque — `PendingRecordingStore.swift` n'a pas de
 * suite à lui sur iOS : la file s'y vérifie à travers `RecordingOutbox`.
 */
class PendingRecordingStoreTest {
    private fun directory() = File(System.getProperty("java.io.tmpdir"), "PendingRecordings-${UUID.randomUUID()}")

    private fun voice(id: String = UUID.randomUUID().toString(), queuedAt: Instant = Instant.now()) = PendingTurn(
        id = id,
        tripId = "trip-1",
        kind = PendingTurn.Kind.Voice,
        filenames = listOf("memo.m4a"),
        mimeTypes = listOf(VoiceNoteFormat.MIME_TYPE),
        duration = 4.0,
        levels = listOf(0.2, 0.8),
        recordedAt = Instant.parse("2026-10-03T10:00:00Z"),
        queuedAt = queuedAt,
    )

    /** La fiche d'avant le crédit du jour se relit sans marque ; la marque, elle, survit à l'aller-retour sur le disque. */
    @Test
    fun thePendingTurnKeepsItsCreditMarkOnDisk() {
        val until = Instant.ofEpochSecond(1_790_000_000)
        val turn = PendingTurn(id = "t", tripId = "trip", kind = PendingTurn.Kind.Text, text = "Bonsoir", recordedAt = until, waitingForCreditUntil = until)

        val decoded = MemoBookJson.decodeFromString(PendingTurn.serializer(), MemoBookJson.encodeToString(PendingTurn.serializer(), turn))
        assertEquals(until, decoded.waitingForCreditUntil)
        assertFalse(decoded.waitingForUnlimited)

        val tooLong = PendingTurn(id = "l", tripId = "trip", kind = PendingTurn.Kind.Text, text = "…", recordedAt = until, waitingForUnlimited = true)
        val decodedTooLong = MemoBookJson.decodeFromString(PendingTurn.serializer(), MemoBookJson.encodeToString(PendingTurn.serializer(), tooLong))
        assertTrue(decodedTooLong.waitingForUnlimited, "L'attente de l'illimité survit à une relance.")
        assertTrue(decodedTooLong.isOnHold(at = Instant.MAX))

        val legacy = """{"id":"t","tripId":"trip","kind":"text","text":"Bonsoir","filenames":[],"mimeTypes":[],"levels":[],"recordedAt":"2026-10-03T10:00:00Z","queuedAt":"2026-10-03T10:00:00Z"}"""
        assertNull(MemoBookJson.decodeFromString(PendingTurn.serializer(), legacy).waitingForCreditUntil)
        assertFalse(MemoBookJson.decodeFromString(PendingTurn.serializer(), legacy).waitingForUnlimited)
    }

    /** Une fiche d'un tour ordinaire ne dit rien de l'illimité : écrit seulement quand il est vrai. */
    @Test
    fun anOrdinaryTurnDoesNotWriteTheUnlimitedMark() {
        val json = MemoBookJson.encodeToString(PendingTurn.serializer(), voice())
        assertFalse(json.contains("waitingForUnlimited"))
        assertFalse(json.contains("waitingForCreditUntil"))
    }

    /** Une date d'attente illisible ne garde pas le tour en otage : il repart. */
    @Test
    fun anUnreadableWaitLetsTheTurnGo() {
        val json = """{"id":"t","tripId":"trip","kind":"text","text":"Bonsoir","recordedAt":"2026-10-03T10:00:00Z","queuedAt":"2026-10-03T10:00:00Z","waitingForCreditUntil":"demain"}"""
        val turn = MemoBookJson.decodeFromString(PendingTurn.serializer(), json)
        assertNull(turn.waitingForCreditUntil)
        assertFalse(turn.isOnHold())
    }

    /** Un vocal mis de côté se relit, octets compris, par une file qui n'a rien gardé en mémoire — le lancement suivant. */
    @Test
    fun aTurnSurvivesTheNextLaunch() = runTest {
        val directory = directory()
        val turn = voice()
        PendingRecordingStore(directory, Dispatchers.Unconfined).enqueue(turn, listOf("un vocal".toByteArray()))

        val relaunched = PendingRecordingStore(directory, Dispatchers.Unconfined)
        val reread = relaunched.all()
        assertEquals(listOf(turn.id), reread.map { it.id })
        assertContentEquals("un vocal".toByteArray(), relaunched.files(reread.first()).first())
    }

    /** Le renvoi d'un même message n'est pas un second message. */
    @Test
    fun theSameTurnIsNotQueuedTwice() = runTest {
        val store = PendingRecordingStore(directory(), Dispatchers.Unconfined)
        val turn = voice()
        store.enqueue(turn, listOf(byteArrayOf(1)))
        store.enqueue(turn, listOf(byteArrayOf(1)))
        assertEquals(1, store.count())
    }

    /** Le plus ancien d'abord : c'est l'ordre dans lequel ils repartiront. */
    @Test
    fun theOldestLeavesFirst() = runTest {
        val directory = directory()
        val store = PendingRecordingStore(directory, Dispatchers.Unconfined)
        val now = Instant.now()
        store.enqueue(voice(id = "second", queuedAt = now), listOf(byteArrayOf(2)))
        store.enqueue(voice(id = "premier", queuedAt = now.minusSeconds(60)), listOf(byteArrayOf(1)))

        assertEquals(listOf("premier", "second"), PendingRecordingStore(directory, Dispatchers.Unconfined).all().map { it.id })
    }

    /**
     * Une fiche illisible — disque abîmé — est jetée plutôt que de faire échouer
     * la lecture entière ; une fiche qui promet un fichier absent aussi.
     */
    @Test
    fun aDamagedRecordDoesNotBlockTheOthers() = runTest {
        val directory = directory()
        val store = PendingRecordingStore(directory, Dispatchers.Unconfined)
        val kept = voice(id = "garde")
        val orphan = voice(id = "orphelin")
        store.enqueue(kept, listOf(byteArrayOf(1)))
        store.enqueue(orphan, listOf(byteArrayOf(2)))
        File(directory, "orphelin.audio").delete()
        File(directory, "abime.json").writeText("{pas du json")

        val reread = PendingRecordingStore(directory, Dispatchers.Unconfined).all()
        assertEquals(listOf("garde"), reread.map { it.id })
        assertFalse(File(directory, "abime.json").exists())
        assertFalse(File(directory, "orphelin.json").exists())
    }

    /** Arrivé, le tour quitte le disque — fiche et fichiers. */
    @Test
    fun aDeliveredTurnLeavesNothingBehind() = runTest {
        val directory = directory()
        val store = PendingRecordingStore(directory, Dispatchers.Unconfined)
        val turn = voice()
        store.enqueue(turn, listOf(byteArrayOf(1)))
        store.remove(turn)

        assertTrue(store.all().isEmpty())
        assertTrue(directory.listFiles().orEmpty().isEmpty())
    }

    /** Une fiche réécrite — marquée « attend le crédit » — se relit marquée. */
    @Test
    fun anUpdatedRecordIsReadBackUpdated() = runTest {
        val directory = directory()
        val store = PendingRecordingStore(directory, Dispatchers.Unconfined)
        val turn = voice()
        store.enqueue(turn, listOf(byteArrayOf(1)))
        val until = Instant.parse("2026-10-04T00:00:00Z")
        store.update(turn.copy(waitingForCreditUntil = until))

        assertEquals(until, store.all().first().waitingForCreditUntil)
        assertEquals(until, PendingRecordingStore(directory, Dispatchers.Unconfined).all().first().waitingForCreditUntil)
    }
}
