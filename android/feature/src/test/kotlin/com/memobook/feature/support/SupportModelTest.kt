package com.memobook.feature.support

import com.memobook.core.Faq
import com.memobook.core.FaqVote
import com.memobook.core.SupportCopy
import com.memobook.core.SupportMessage
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
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * T226 (Hugo, 06/10/2026) : « Envoyer » attendait 600 ms puis disait
 * « envoyé », et rien ne partait. Le message part désormais au serveur, et
 * « envoyé » ne se dit qu'après sa réponse ; les votes aussi. Porté de
 * `SupportModelTests.swift`, cas pour cas.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class SupportModelTest {
    /** Ce que le double du serveur a reçu. */
    private class Inbox {
        val messages = mutableListOf<SupportMessage>()
        val votes = mutableListOf<Pair<String, Boolean>>()
    }

    private fun backend(inbox: Inbox, failure: Exception? = null, served: List<FaqVote> = emptyList()) = SupportBackend(
        send = { message ->
            if (failure != null) throw failure
            inbox.messages += message
        },
        vote = { questionId, isHelpful ->
            if (failure != null) throw failure
            inbox.votes += questionId to isHelpful
        },
        loadVotes = { served },
    )

    private val offline = ApiError.Transport(IOException("hors ligne"), url = null)

    @BeforeTest fun setUp() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @AfterTest fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test fun theMessageReachesTheServerBeforeItIsSent() = runTest {
        val inbox = Inbox()
        val model = SupportModel()
        model.connect(backend(inbox))

        model.send("  Bonjour  ", source = SupportMessage.Source.FoundersNote, topicId = "faq.aide.suggestion", tripId = "trip")

        assertEquals(SupportModel.SendState.Sent, model.sendState)
        assertEquals(1, inbox.messages.size)
        val received = inbox.messages.first()
        assertEquals("Bonjour", received.message)
        assertEquals(SupportMessage.Source.FoundersNote, received.source)
        assertEquals("faq.aide.suggestion", received.topicId)
        assertEquals("trip", received.tripId)
        assertNotNull(received.diagnostics)
    }

    @Test fun offlineSaysSoAndKeepsTheForm() = runTest {
        val model = SupportModel()
        model.connect(backend(Inbox(), failure = offline))

        model.send("Bonjour")

        assertEquals(SupportModel.SendState.Failed(SupportCopy.Contact.sendOffline), model.sendState)
    }

    @Test fun tooManyMessagesSaysSo() = runTest {
        val model = SupportModel()
        model.connect(
            backend(Inbox(), failure = ApiError.Server(statusCode = 429, code = "support_rate_limited", message = "Trop")),
        )

        model.send("Bonjour")

        assertEquals(SupportModel.SendState.Failed(SupportCopy.Contact.sendRateLimited), model.sendState)
    }

    @Test fun aVoteIsThankedOnceReceived() = runTest {
        val inbox = Inbox()
        val model = SupportModel()
        model.connect(backend(inbox))
        val entry = assertNotNull(Faq.entry("faq.carnet.pages"))

        model.vote(true, entry)

        assertEquals(true, model.votes[entry.id])
        assertEquals(listOf(entry.id), inbox.votes.map { it.first })
    }

    @Test fun aVoteThatDidNotLeaveKeepsTheThumbs() = runTest {
        val model = SupportModel()
        model.connect(backend(Inbox(), failure = offline))
        val entry = assertNotNull(Faq.entry("faq.carnet.pages"))

        model.vote(false, entry)

        assertNull(model.votes[entry.id])
        assertEquals(entry.id, model.voteFailure?.questionId)
        assertEquals(SupportCopy.Answer.voteOffline, model.voteFailure?.message)
    }

    /** Les votes déjà donnés reviennent du serveur ; ceux d'un autre compte s'effacent. */
    @Test fun theVotesFollowTheAccount() = runTest {
        val model = SupportModel()
        model.connect(backend(Inbox(), served = listOf(FaqVote(questionId = "faq.carnet.pages", isHelpful = true))))
        assertEquals(true, model.votes["faq.carnet.pages"])

        model.connect(backend(Inbox()))
        assertTrue(model.votes.isEmpty())
    }
}
