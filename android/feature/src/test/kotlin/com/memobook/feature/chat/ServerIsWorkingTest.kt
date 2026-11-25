@file:OptIn(ExperimentalCoroutinesApi::class)

package com.memobook.feature.chat

import android.content.ContextWrapper
import com.memobook.core.ChatContext
import com.memobook.core.ChatCopy
import com.memobook.core.ChatThread
import com.memobook.core.ChatThreadUpdate
import com.memobook.core.ChatTurnStatus
import com.memobook.feature.until
import com.memobook.networking.ApiError
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import java.io.File
import java.io.IOException
import java.net.SocketTimeoutException
import java.nio.file.Files
import java.time.Instant
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * **Un serveur qui travaille n'est pas une panne de réseau** (T318, Hugo,
 * 08/11/2026 — « “Hors ligne” s'affiche après un vocal alors que le réseau va
 * bien ; le serveur est simplement en train de travailler »). Porté de
 * `ServerIsWorkingTests.swift`, cas pour cas.
 *
 * Les deux situations se ressemblent de l'intérieur : l'appel n'aboutit pas,
 * le tour retombe dans la file. Elles ne se disent pourtant pas pareil —
 * l'une se répare en cherchant du réseau, l'autre en attendant.
 */
class ServerIsWorkingTest {
    private val dispatcher = StandardTestDispatcher()
    private lateinit var cacheDirectory: File

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(dispatcher)
        cacheDirectory = Files.createTempDirectory("server-is-working").toFile()
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
        cacheDirectory.deleteRecursively()
    }

    // MARK: Ce que l'erreur dit d'elle-même

    @Test fun aTimeoutIsNotALostNetwork() {
        assertTrue(ApiError.Transport(SocketTimeoutException("timeout"), url = null).isTimeout)
        assertFalse(
            ApiError.Transport(IOException("pas de réseau"), url = null).isTimeout,
            "Là, c'est vraiment le wifi.",
        )
        assertFalse(ApiError.Server(statusCode = 500, code = null, message = "Oups").isTimeout)
        // Les deux restent des pannes de transport : la file les garde pareil,
        // c'est la **phrase** qui change.
        assertTrue(ApiError.Transport(SocketTimeoutException("timeout"), url = null).isTransport)
    }

    // MARK: Ce que l'écran en dit

    private fun thread() = ChatThread(
        id = "trip",
        title = "Rome",
        context = ChatContext(tripId = "trip", stepId = null),
        messages = emptyList(),
        suggestions = emptyList(),
        now = Instant.now(),
    )

    /**
     * Un transport dont le tour part toujours dans la file, et dont on pilote
     * le moniteur réseau.
     */
    private fun model(
        isOnline: suspend () -> Boolean,
        failsLoading: Throwable? = null,
    ): ChatModel {
        val thread = thread()
        val transport = ChatTransport(
            load = { failsLoading?.let { throw it } ?: thread },
            poll = { ChatThreadUpdate(messages = emptyList(), turn = ChatTurnStatus.Idle, now = Instant.now()) },
            send = { ChatSendOutcome.Queued },
            editTranscript = { _, _ -> throw IOException("jamais") },
            media = { ByteArray(0) },
            offlineThread = { thread },
            isOnline = isOnline,
        )
        return ChatModel(transport, ChatAudio(ContextWrapper(null), cacheDirectory), io = dispatcher)
    }

    /**
     * Le cas de Hugo : le vocal retombe dans la file parce que le serveur n'a
     * pas répondu à temps, et le réseau va très bien.
     */
    @Test fun aQueuedTurnWithNetworkBlamesTheServer() = runTest {
        val model = model(isOnline = { true })
        model.load()

        model.draft = "On a marché jusqu'au Trastevere"
        model.sendDraft()

        until("le tour attend dans la file") { model.showsQueuedNotice }
        assertTrue(model.networkIsUp)
        assertEquals(ChatCopy.queuedWhileServerWorks, model.queuedNotice)
    }

    /** Et sans réseau, la phrase d'avant : celle-là était juste. */
    @Test fun aQueuedTurnWithoutNetworkStillSaysOffline() = runTest {
        val model = model(isOnline = { false })
        model.load()

        model.draft = "On a marché jusqu'au Trastevere"
        model.sendDraft()

        until("le tour attend dans la file") { model.showsQueuedNotice }
        assertFalse(model.networkIsUp)
        assertEquals(ChatCopy.queuedOffline, model.queuedNotice)
    }

    /**
     * **C'est l'état présent qui parle**, et non la raison du départ en file :
     * le réseau revenu pendant que le tour attend change la phrase.
     */
    @Test fun thePhraseFollowsTheNetworkComingBack() = runTest {
        var up = false
        val model = model(isOnline = { up })
        model.load()
        model.draft = "On a marché jusqu'au Trastevere"
        model.sendDraft()
        until("le tour attend dans la file") { model.showsQueuedNotice }
        assertEquals(ChatCopy.queuedOffline, model.queuedNotice)

        up = true
        model.refreshNetworkState()

        assertEquals(ChatCopy.queuedWhileServerWorks, model.queuedNotice)
    }

    /**
     * Le fil ouvert sans le serveur dit la même chose, en tête : ce n'est pas
     * le réseau quand le réseau est là.
     */
    @Test fun theLocalThreadDoesNotClaimToBeOffline() = runTest {
        val model = model(
            isOnline = { true },
            failsLoading = ApiError.Transport(SocketTimeoutException("timeout"), url = null),
        )

        model.load()

        assertTrue(model.isOffline, "Le fil montré est bien le fil local.")
        assertEquals(ChatCopy.threadWhileServerWorks, model.threadNotice)
    }

    /** Sans réseau, le fil local garde la phrase d'origine. */
    @Test fun theLocalThreadStillSaysOfflineWithoutNetwork() = runTest {
        val model = model(
            isOnline = { false },
            failsLoading = ApiError.Transport(IOException("pas de réseau"), url = null),
        )

        model.load()

        assertTrue(model.isOffline)
        assertEquals(ChatCopy.offline, model.threadNotice)
    }
}
