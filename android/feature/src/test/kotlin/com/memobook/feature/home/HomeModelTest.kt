@file:OptIn(ExperimentalCoroutinesApi::class)

package com.memobook.feature.home

import com.memobook.core.ChatDelivery
import com.memobook.core.ChatTurnReceipt
import com.memobook.core.ChatTurnStatus
import com.memobook.core.CreatedTrip
import com.memobook.core.DailyCredit
import com.memobook.core.HomeFeed
import com.memobook.core.Traveller
import com.memobook.core.Trip
import com.memobook.core.TripStage
import com.memobook.feature.PendingTripStore
import com.memobook.feature.RecordingOutbox
import com.memobook.feature.SandboxNetwork
import com.memobook.feature.chat.OutgoingTurn
import com.memobook.feature.recording.RecordingHandoff
import com.memobook.feature.until
import com.memobook.networking.ApiError
import com.memobook.networking.Connectivity
import com.memobook.recording.PendingRecordingStore
import com.memobook.recording.RecordedAudio
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import java.io.IOException
import java.time.Instant
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ce que l'accueil dit de la file et du crédit du jour, et ce qu'il fait d'un
 * vocal. Porté, cas pour cas, des suites iOS qui testent `HomeModel` et
 * `HomeNotice` :
 *
 * - de `RecordingOutboxTests.swift`, « Ce que l'accueil en dit » (la boîte
 *   d'information, le bac à sable) et les deux cas de « La continuité » qui
 *   passent par `HomeModel.upload` — `RecordingOutboxTest` les reprend sur la
 *   file seule ;
 * - de `ProfileModelTests.swift`, « Le crédit du jour de l'accueil »
 *   (03/10/2026).
 *
 * `HomeJoinTests` (`LastQuestionsModelTests.swift`) est porté à côté :
 * [HomeJoinTest].
 */
class HomeModelTest {
    private val dispatcher = StandardTestDispatcher()

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(dispatcher)
    }

    @AfterTest
    fun tearDown() {
        // `debugSetOffline` coupe aussi le double de l'API, pour toute l'app.
        SandboxNetwork.isOffline = false
        Dispatchers.resetMain()
    }

    // MARK: - Ce que l'accueil en dit

    @Test
    fun theNoticeSaysTheMostUsefulThingFirst() = runTest(dispatcher) {
        val outbox = outbox(ChatServer())
        val model = HomeModel(source = { HomeFeed.fixture }, outbox = outbox)
        model.load()

        assertNull(model.notice, "En ligne et sans rien en vol, la boîte ne s'affiche pas.")

        outbox.debugSetOffline(true)
        assertEquals(HomeNotice.Offline, model.notice)

        // Un vocal enregistré hors ligne : la boîte cesse de parler du réseau
        // pour parler de ce qui attend, qui est l'inquiétude du moment.
        model.upload(debugSilence())
        assertEquals(HomeNotice.WaitingForConnection(1), model.notice)

        outbox.debugSetOffline(false)
        until("le vocal arrive") { model.notice == HomeNotice.Delivered(1) }
    }

    /**
     * Le bouton « + vocal en attente » du bac à sable. Il emprunte le même
     * chemin qu'un vrai vocal — jusqu'au fichier sur le disque —, sinon il
     * montrerait une boîte d'information qui ne prouve rien.
     */
    @Test
    fun theSandboxQueuesARealRecording() = runTest(dispatcher) {
        val outbox = outbox(ChatServer())
        val model = HomeModel(source = { HomeFeed.fixture }, outbox = outbox)
        model.load()
        outbox.debugSetOffline(true)

        model.debugQueueRecording()

        assertEquals(1, outbox.pending.value)
        assertEquals(HomeNotice.WaitingForConnection(1), model.notice)
        assertNull(model.errorMessage)
    }

    @Test
    fun everyNoticeSpeaksWithoutItsMarkup() {
        val notices = listOf(
            HomeNotice.Offline,
            HomeNotice.WaitingForConnection(1),
            HomeNotice.WaitingForConnection(3),
            HomeNotice.Sending(1),
            HomeNotice.Sending(2),
            HomeNotice.Delivered(1),
            HomeNotice.Delivered(4),
        )

        for (notice in notices) {
            assertTrue(notice.message.contains("**"), "$notice : rien n'est mis en avant.")
            assertFalse(notice.spokenMessage.contains("*"), "$notice : TalkBack lirait des étoiles.")
        }
    }

    @Test
    fun theSingularIsNotWrittenAsAPlural() {
        assertTrue(HomeNotice.Delivered(1).message.contains("Ton vocal"))
        assertTrue(HomeNotice.Delivered(5).message.contains("Tes 5 vocaux"))
    }

    // MARK: - La continuité : on raconte, et on voit son vocal partir

    /**
     * La bulle suit **la file**, pas l'écran : hors ligne elle reste sur
     * « envoi en cours », et c'est la reconnexion qui la termine.
     */
    @Test
    fun theBubbleSaysSentOnlyOnceTheVocalHasReallyLeft() = runTest(dispatcher) {
        val network = Channel<Boolean>(Channel.UNLIMITED)
        val outbox = outbox(ChatServer(), connectivity = Connectivity { network.receiveAsFlow() })
        outbox.start()
        val model = HomeModel(source = { HomeFeed.fixture }, outbox = outbox)
        model.load()

        network.send(false)
        until("la file se sait hors ligne") { !outbox.isOnline.value }

        val handoff = RecordingHandoff(audio = debugSilence(), levels = emptyList())
        launch { model.upload(debugSilence(), handoffId = handoff.id) }

        until("le vocal attend sur le disque") { outbox.pending.value == 1 }
        assertEquals(handoff.id, outbox.lastDelivery.value?.id, "La file suit **cet** envoi-là, par l'identifiant de sa bulle.")
        assertEquals(ChatDelivery.Sending, outbox.lastDelivery.value?.state, "Un vocal encore sur le disque n'est pas un vocal envoyé.")

        network.send(true)
        until("le vocal part") { outbox.lastDelivery.value?.state == ChatDelivery.Sent }
        assertNotNull(outbox.lastDelivery.value?.receipt, "Le reçu du serveur voyage avec, pour que le fil fusionne ses bulles.")
        assertEquals(model.ongoingTrips.first().id, outbox.lastDelivery.value?.tripId)
    }

    /** Un refus du serveur se lit sur la bulle, avec le mot du serveur. */
    @Test
    fun aRefusalShowsOnTheBubble() = runTest(dispatcher) {
        val server = ChatServer()
        val outbox = outbox(server)
        val model = HomeModel(source = { HomeFeed.fixture }, outbox = outbox)
        model.load()

        server.refused = model.ongoingTrips.map { it.id }.toSet()
        val handoff = RecordingHandoff(audio = debugSilence(), levels = emptyList())
        launch { model.upload(debugSilence(), handoffId = handoff.id) }

        until("le refus arrive à la bulle") { outbox.lastDelivery.value?.state?.hasFailed == true }
    }

    // MARK: - Le crédit du jour de l'accueil (03/10/2026)

    /**
     * Épuisé hier soir, relu du cache ce matin hors ligne : le micro de
     * l'accueil s'ouvre, le crédit s'est rechargé à minuit.
     */
    @Test
    fun yesterdaysExhaustedCreditIsRechargedFromTheCache() = runTest(dispatcher) {
        val yesterday = DailyCredit(
            usedMs = DailyCredit.Catalog.limitMs,
            day = "2026-10-02",
            resetsAt = Instant.now().minusSeconds(3_600),
        )
        val cached = homeFeed(yesterday)
        val model = HomeModel(source = { throw offline }, cached = { cached }, outbox = outbox(ChatServer()))

        model.load()

        assertEquals(false, model.ongoingTripCredit?.isExhausted)
        assertEquals(DailyCredit.Catalog.limitMs, model.ongoingTripCredit?.remainingMs)
    }

    /** Le crédit d'aujourd'hui, lui, reste épuisé jusqu'à minuit. */
    @Test
    fun todaysExhaustedCreditStaysExhausted() = runTest(dispatcher) {
        val today = DailyCredit(usedMs = DailyCredit.Catalog.limitMs, resetsAt = Instant.now().plusSeconds(3_600))
        val served = homeFeed(today)
        val model = HomeModel(source = { served }, outbox = outbox(ChatServer()))

        model.load()

        assertEquals(true, model.ongoingTripCredit?.isExhausted)
    }

    /**
     * Un vocal de l'accueil mis en file compte tout de suite : le suivant ne
     * part pas d'un reste trop haut.
     */
    @Test
    fun aQueuedHomeVoiceCountsAtOnce() = runTest(dispatcher) {
        val fresh = DailyCredit(resetsAt = Instant.now().plusSeconds(3_600))
        val served = homeFeed(fresh)
        val outbox = outbox(ChatServer().apply { unreachable = true })
        val model = HomeModel(source = { served }, outbox = outbox)
        model.load()

        model.upload(voice(seconds = 90.0))

        assertEquals(90_000, model.ongoingTripCredit?.usedMs)
    }

    /**
     * Arrivé, le vocal rapporte le crédit d'après son tour : c'est lui qui fait
     * foi, même si la relecture de l'accueil échoue ensuite.
     */
    @Test
    fun aDeliveredHomeVoiceTakesTheCreditOfItsReceipt() = runTest(dispatcher) {
        val fresh = DailyCredit(resetsAt = Instant.now().plusSeconds(3_600))
        val served = homeFeed(fresh)
        var reads = 0
        val outbox = outbox(ChatServer().apply { receiptCredit = DailyCredit(usedMs = 200_000) })
        val model = HomeModel(
            source = {
                reads += 1
                if (reads > 1) throw ApiError.Transport(IOException("délai dépassé"), url = null)
                served
            },
            outbox = outbox,
        )
        model.load()

        model.upload(voice(seconds = 30.0))

        assertEquals(200_000, model.ongoingTripCredit?.usedMs)
    }

    /**
     * Hors ligne, la relecture de l'accueil — au retour de la conversation qui
     * suit chaque vocal — rend le cache **sans lever**, comme `cachedSource`
     * dans l'app : le vocal en file reste décompté, et le suivant part du bon
     * reste. Relu deux fois, il ne compte qu'une fois.
     */
    @Test
    fun aQueuedHomeVoiceStillCountsWhenTheReadReturnsTheCache() = runTest(dispatcher) {
        val fresh = DailyCredit(resetsAt = Instant.now().plusSeconds(3_600))
        val cachedFeed = homeFeed(fresh)
        val outbox = outbox(ChatServer().apply { unreachable = true })
        val model = HomeModel(source = { cachedFeed }, outbox = outbox)
        model.load()

        model.upload(voice(seconds = 180.0))
        model.load()
        assertEquals(180_000, model.ongoingTripCredit?.usedMs)

        model.load()
        assertEquals(180_000, model.ongoingTripCredit?.usedMs)
    }

    // MARK: - Le rappel de fin de voyage (Android seulement)

    /**
     * **Sans jumeau sur iOS**, où « Résilier » ouvre toujours la feuille
     * d'Apple : sur Android, le rappel ne s'ouvre que pour un abonnement que
     * Google Play tient — un abonnement de l'App Store ne se gère pas d'ici. Ne
     * pas savoir qui le tient, c'est attendre la prochaine lecture.
     */
    @Test
    fun theTripEndReminderOnlyOpensForAGooglePlaySubscription() = runTest(dispatcher) {
        assertTrue(HomeModel(subscriptionIsManagedByAppStore = { false }).tripEndReminderCanOpenHere(), "Google Play : la page des abonnements s'ouvre.")
        assertFalse(HomeModel(subscriptionIsManagedByAppStore = { true }).tripEndReminderCanOpenHere(), "L'App Store : rien à résilier d'ici.")
        assertFalse(HomeModel(subscriptionIsManagedByAppStore = { null }).tripEndReminderCanOpenHere(), "On ne sait pas : on attend.")
        assertFalse(HomeModel(subscriptionIsManagedByAppStore = { throw offline }).tripEndReminderCanOpenHere(), "Hors ligne : on attend.")
        assertTrue(HomeModel().tripEndReminderCanOpenHere(), "En aperçu, l'alerte se montre comme sur iOS.")
    }

    @Test
    fun theTripEndReminderDayIsTheUniversalDay() {
        // Le `.iso8601.year().month().day()` d'iOS écrit le jour en GMT : à
        // 0 h 30 à Paris, c'est encore la veille.
        assertEquals("2026-10-02", TripEndReminder.today(Instant.parse("2026-10-02T22:30:00Z")))
        assertTrue(TripEndReminder.playSubscriptionsUrl.contains("sku=com.memobook.app.subscription.monthly"))
        assertTrue(TripEndReminder.playSubscriptionsUrl.endsWith("package=com.memobook.app"))
    }

    // MARK: - Outils

    private val offline = ApiError.Transport(IOException("hors ligne"), url = null)

    private fun homeFeed(credit: DailyCredit): HomeFeed = HomeFeed(
        traveller = Traveller(id = "camille", firstName = "Camille"),
        trips = listOf(Trip(id = "rome", title = "Rome", stage = TripStage.Ongoing, dailyCredit = credit)),
    )

    private fun voice(seconds: Double): RecordedAudio =
        RecordedAudio(byteArrayOf(0), "vocal.m4a", "audio/m4a", duration = seconds, recordedAt = Instant.now())

    private fun TestScope.outbox(server: ChatServer, connectivity: Connectivity = Connectivity.online): RecordingOutbox =
        RecordingOutbox(
            store = PendingRecordingStore.temporary(Dispatchers.Unconfined),
            trips = PendingTripStore.temporary(Dispatchers.Unconfined),
            connectivity = connectivity,
            send = { turn, tripId -> server.send(turn, tripId) },
            scope = backgroundScope,
        )

    /** Le serveur de la conversation, vu de la file : il accepte, il est injoignable, ou il refuse. */
    private class ChatServer {
        var unreachable = false
        var refused: Set<String> = emptySet()

        /** Le crédit que le reçu rapporte, ce tour compté. */
        var receiptCredit: DailyCredit? = null

        fun send(@Suppress("UNUSED_PARAMETER") turn: OutgoingTurn, tripId: String): ChatTurnReceipt {
            if (unreachable) throw ApiError.Transport(IOException("hors ligne"), url = null)
            if (tripId in refused) throw ApiError.Server(statusCode = 404, code = null, message = "Carnet introuvable.")
            return ChatTurnReceipt(messages = emptyList(), turn = ChatTurnStatus.Idle, now = Instant.now(), dailyCredit = receiptCredit)
        }
    }
}

/** « Rejoins une aventure » : ce que l'accueil fait d'un code. Porté de `HomeJoinTests`. */
class HomeJoinTest {
    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun aKnownCodeOpensTheTrip() = runTest {
        val trip = HomeFeed.fixture.trips[0]
        val model = HomeModel(join = { CreatedTrip(trip = trip, accessCode = "JHKFDA") })
        val outcome = model.join("JHKFDA")
        assertEquals(JoinOutcome.Joined(trip.id), outcome)
    }

    @Test
    fun anUnknownCodeAsksForTheAlert() = runTest {
        val model = HomeModel(join = {
            throw ApiError.Server(statusCode = 404, code = "trip_not_found", message = "Aucun voyage.")
        })
        val outcome = model.join("ZZZZZZ")
        assertEquals(JoinOutcome.NotFound, outcome)
    }

    @Test
    fun anyOtherRefusalKeepsTheServerSentence() = runTest {
        val model = HomeModel(join = {
            throw ApiError.Server(statusCode = 403, code = "member_removed", message = "Tu ne fais plus partie de ce voyage.")
        })
        val outcome = model.join("JHKFDA")
        assertEquals(JoinOutcome.Failed("Tu ne fais plus partie de ce voyage."), outcome)
    }
}
