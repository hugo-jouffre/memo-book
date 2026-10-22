@file:OptIn(ExperimentalCoroutinesApi::class)

package com.memobook.feature

import android.content.ContextWrapper
import com.memobook.core.ChatAuthor
import com.memobook.core.ChatContext
import com.memobook.core.ChatDelivery
import com.memobook.core.ChatMessage
import com.memobook.core.ChatMessageBody
import com.memobook.core.ChatPhotoUpload
import com.memobook.core.ChatThread
import com.memobook.core.ChatThreadUpdate
import com.memobook.core.ChatTurnReceipt
import com.memobook.core.ChatTurnStatus
import com.memobook.core.DailyCredit
import com.memobook.core.HomeFeed
import com.memobook.core.PhotoAttachment
import com.memobook.core.Traveller
import com.memobook.core.Trip
import com.memobook.core.TripDraft
import com.memobook.core.TripStage
import com.memobook.core.VoiceNote
import com.memobook.feature.chat.ChatAudio
import com.memobook.feature.chat.ChatModel
import com.memobook.feature.chat.ChatSendOutcome
import com.memobook.feature.chat.ChatTransport
import com.memobook.feature.chat.ChatTurnDelivery
import com.memobook.feature.chat.ChatTurnState
import com.memobook.feature.chat.OutgoingTurn
import com.memobook.feature.chat.PreviewChatBox
import com.memobook.feature.recording.RecordingHandoff
import com.memobook.feature.recording.RecordingModel
import com.memobook.networking.ApiError
import com.memobook.networking.Connectivity
import com.memobook.recording.AudioRecorder
import com.memobook.recording.PendingRecordingStore
import com.memobook.recording.PendingTurn
import com.memobook.recording.RecordedAudio
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * La promesse écrite dans la boîte d'information de l'accueil : « tes vocaux
 * enregistrés hors ligne sont bien conservés, ils seront envoyés dès ta
 * reconnexion » — et celle de `docs/conversation.md` § 9 : ce qu'on envoie
 * depuis la conversation sans réseau reste « en cours d'envoi » dans le fil et
 * part au retour du réseau, dans l'ordre, sans doublon.
 *
 * C'est une promesse sur des données que personne d'autre n'a — un vocal qui
 * n'est pas parti n'existe qu'ici. Elle se vérifie donc, et sans émulateur hors
 * ligne : la file reçoit un faux réseau qu'on coupe et qu'on rétablit à la main.
 *
 * Porté de `RecordingOutboxTests.swift`, cas pour cas, sauf :
 * - les cas de l'accueil (`HomeModel`, `HomeNotice` : la boîte d'information, le
 *   bac à sable), qui se porteront avec leur écran ; les deux cas de la bulle
 *   qui suit la file sont repris ici **sur la file**, par l'envoi que
 *   `HomeModel.upload` fait — les deux de la conversation (`ChatModel` : la
 *   bulle posée, les messages dits hors ligne depuis le fil) sont ici, avec
 *   elle ;
 * - les deux cas du cache (`ContentCache`), déjà portés dans `ContentCacheTest` ;
 * - la fiche du disque (`PendingTurn`), testée avec elle dans `:recording`
 *   (`PendingRecordingStoreTest`).
 */
class RecordingOutboxTest {
    private val dispatcher = StandardTestDispatcher()

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(dispatcher)
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    // MARK: - Hors ligne

    @Test
    fun aVocalRecordedOfflineWaitsInsteadOfFailing() = runTest(dispatcher) {
        val sender = Sender()
        val outbox = outbox(sender)
        outbox.debugSetOffline(true)

        val outcome = outbox.submit(testTurn(), "trip-1")

        assertEquals(RecordingOutbox.Delivery.Queued, outcome)
        assertEquals(1, outbox.pending.value)
        assertTrue(sender.sent.isEmpty(), "Rien ne doit partir tant qu'il n'y a pas de réseau.")
    }

    @Test
    fun theQueueLeavesOnItsOwnWhenTheConnectionComesBack() = runTest(dispatcher) {
        val sender = Sender()
        val network = Channel<Boolean>(Channel.UNLIMITED)
        val outbox = outbox(sender, connectivity = Connectivity { network.receiveAsFlow() })
        outbox.start()

        network.send(false)
        until("la file se sait hors ligne") { !outbox.isOnline.value }

        outbox.submit(testTurn(), "trip-1")
        assertEquals(1, outbox.pending.value)

        // Personne n'appuie sur rien : c'est le retour du réseau qui déclenche
        // l'envoi.
        network.send(true)
        until("la file se vide") { outbox.pending.value == 0 }

        assertEquals(listOf("trip-1"), sender.sent)
        assertEquals(1, outbox.justDelivered.value, "L'arrivée se dit, le temps d'être lue.")
    }

    /** Le cas qui compte vraiment : l'app a été fermée entre les deux. */
    @Test
    fun aVocalSurvivesTheAppBeingClosed() = runTest(dispatcher) {
        val directory = File(System.getProperty("java.io.tmpdir"), UUID.randomUUID().toString())
        val sender = Sender()

        val beforeQuitting = outbox(sender, store = PendingRecordingStore(directory, Dispatchers.Unconfined))
        beforeQuitting.debugSetOffline(true)
        beforeQuitting.submit(testTurn(), "trip-1")

        // Une autre file, sur le même dossier : c'est ce que voit le lancement
        // suivant, qui n'a rien gardé en mémoire.
        val afterRelaunching = outbox(sender, store = PendingRecordingStore(directory, Dispatchers.Unconfined))
        afterRelaunching.flush()

        assertEquals(listOf("trip-1"), sender.sent)
        assertEquals(0, afterRelaunching.pending.value)
    }

    // MARK: - Ce qui passe et ce qui manque

    /**
     * « En ligne » ne veut pas dire « l'API répond » : ce qui échoue au
     * transport retourne dans la file, et repart quand le serveur revient —
     * sous le **même** identifiant.
     */
    @Test
    fun aTurnThatFailsInTransitGoesBackToTheQueue() = runTest(dispatcher) {
        val sender = Sender()
        sender.unreachable = setOf("trip-1")
        val outbox = outbox(sender)

        val turn = testTurn()
        val outcome = outbox.submit(turn, "trip-1")

        assertEquals(RecordingOutbox.Delivery.Queued, outcome)
        assertEquals(1, outbox.pending.value)

        sender.unreachable = emptySet()
        outbox.flush()

        assertEquals(listOf(turn.id), sender.sentIds)
        assertEquals(0, outbox.pending.value)
    }

    /**
     * Tout ce qu'on dit passe par la file — un texte, un vocal, des photos — et
     * repart **dans l'ordre**, une seule fois.
     */
    @Test
    fun everythingSaidOfflineLeavesInOrderAndOnlyOnce() = runTest(dispatcher) {
        val sender = Sender()
        val outbox = outbox(sender)
        outbox.debugSetOffline(true)

        val text = OutgoingTurn(id = "t-1", body = OutgoingTurn.Body.Text("Hier soir, le Trastevere."))
        val voice = testTurn()
        val photos = OutgoingTurn(
            id = "p-3",
            body = OutgoingTurn.Body.Photos(
                listOf(ChatPhotoUpload("jpg".toByteArray(), "p-3-0.jpg", "image/jpeg")),
                capturedAt = Instant.now(),
            ),
        )
        outbox.submit(text, "trip-1")
        outbox.submit(voice, "trip-1")
        outbox.submit(photos, "trip-1")
        outbox.submit(OutgoingTurn(id = "elsewhere", body = OutgoingTurn.Body.Text("Ailleurs")), "trip-2")

        assertEquals(4, outbox.pending.value)
        val waiting = outbox.waiting("trip-1")
        assertEquals(listOf(text.id, voice.id, photos.id), waiting.map { it.id }, "Ce qui attend se relit, pour ce carnet, dans l'ordre.")
        val relived = (waiting[1].body as? OutgoingTurn.Body.Voice)?.audio ?: fail("un vocal")
        val original = (voice.body as OutgoingTurn.Body.Voice).audio
        // Le vocal relu du disque est le vocal entier — octets, durée, forme d'onde.
        assertTrue(relived.data.contentEquals(original.data))
        assertEquals(original.durationSeconds, relived.durationSeconds)
        assertEquals(original.levels, relived.levels)

        outbox.debugSetOffline(false)
        outbox.flush()
        outbox.flush()

        assertEquals(listOf(text.id, voice.id, photos.id, "elsewhere"), sender.sentIds)
        assertEquals(0, outbox.pending.value)
    }

    /**
     * Un refus du serveur n'est pas une panne de réseau : le garder, ce serait
     * promettre une arrivée qui n'aura jamais lieu.
     */
    @Test
    fun aVocalTheServerRefusesIsNotKeptForever() = runTest(dispatcher) {
        val sender = Sender()
        sender.refused = setOf("trip-1")
        val outbox = outbox(sender)

        val outcome = outbox.submit(testTurn(), "trip-1")

        assertEquals(RecordingOutbox.Delivery.Rejected("Ton vocal n’a pas pu être envoyé. Carnet introuvable."), outcome)
        assertEquals(0, outbox.pending.value)
        assertNotNull(outbox.rejection.value)
    }

    /**
     * Une session révoquée (401) n'est pas un refus du tour : il attend la
     * reconnexion au lieu d'être effacé du disque.
     */
    @Test
    fun aVocalRefusedForARevokedSessionWaitsForTheNextSignIn() = runTest(dispatcher) {
        val sender = Sender()
        sender.signedOut = setOf("trip-1")
        val outbox = outbox(sender)

        val outcome = outbox.submit(testTurn(), "trip-1")

        assertEquals(RecordingOutbox.Delivery.Queued, outcome)
        assertEquals(1, outbox.pending.value)
        assertNull(outbox.rejection.value)
    }

    // MARK: - La continuité : on raconte, et on voit son vocal partir

    /**
     * La bulle suit **la file**, pas l'écran : hors ligne elle reste sur
     * « envoi en cours », et c'est la reconnexion qui la termine. Le vocal
     * part comme `HomeModel.upload` le confie — sous l'identifiant de la bulle.
     */
    @Test
    fun theBubbleSaysSentOnlyOnceTheVocalHasReallyLeft() = runTest(dispatcher) {
        val sender = Sender()
        val network = Channel<Boolean>(Channel.UNLIMITED)
        val outbox = outbox(sender, connectivity = Connectivity { network.receiveAsFlow() })
        outbox.start()

        network.send(false)
        until("la file se sait hors ligne") { !outbox.isOnline.value }

        val handoff = RecordingHandoff(audio = silence(), levels = emptyList())
        launch { outbox.submit(OutgoingTurn.voice(handoff.audio, handoff.levels, id = handoff.id), "trip-rome") }

        until("le vocal attend sur le disque") { outbox.pending.value == 1 }
        assertEquals(handoff.id, outbox.lastDelivery.value?.id, "La file suit **cet** envoi-là, par l'identifiant de sa bulle.")
        assertEquals(ChatDelivery.Sending, outbox.lastDelivery.value?.state, "Un vocal encore sur le disque n'est pas un vocal envoyé.")

        network.send(true)
        until("le vocal part") { outbox.lastDelivery.value?.state == ChatDelivery.Sent }
        assertNotNull(outbox.lastDelivery.value?.receipt, "Le reçu du serveur voyage avec, pour que le fil fusionne ses bulles.")
        assertEquals("trip-rome", outbox.lastDelivery.value?.tripId)
    }

    /** Un refus du serveur se lit sur la bulle, avec le mot du serveur. */
    @Test
    fun aRefusalShowsOnTheBubble() = runTest(dispatcher) {
        val sender = Sender()
        val outbox = outbox(sender)

        sender.refused = setOf("trip-rome")
        val handoff = RecordingHandoff(audio = silence(), levels = emptyList())
        launch { outbox.submit(OutgoingTurn.voice(handoff.audio, handoff.levels, id = handoff.id), "trip-rome") }

        until("le refus arrive à la bulle") { outbox.lastDelivery.value?.state?.hasFailed == true }
    }

    /**
     * La conversation pose la bulle, et **ne décide pas** de son envoi : c'est
     * la file qui le dit, même quand MEMO a déjà répondu.
     */
    @Test
    fun theConversationPostsTheVocalWithoutOwningItsDelivery() = runTest(dispatcher) {
        val handoff = RecordingHandoff(audio = silence(), levels = listOf(0.3, 0.7))

        val chat = ChatModel(ChatTransport.local(tripId = "trip-rome", box = PreviewChatBox()), chatAudio(), io = dispatcher)
        chat.expect(handoff)
        chat.load()

        val bubble = assertNotNull(chat.messages.firstOrNull { it.id == handoff.id })
        assertEquals(ChatAuthor.Traveller, bubble.author)
        assertEquals(
            ChatDelivery.Sending,
            bubble.delivery,
            "Tant que la file n'a rien dit, la bulle ne peut pas se déclarer arrivée.",
        )

        // Le fil est chargé et au repos : la bulle reste sur l'état que la file
        // donne — le chat ne l'envoie pas lui-même, elle est déjà partie.
        assertEquals(ChatTurnState.Idle, chat.turn)
        assertEquals(ChatDelivery.Sending, chat.messages.firstOrNull { it.id == handoff.id }?.delivery)

        // C'est la file, et elle seule, qui la termine — et pas celle d'un autre
        // voyage.
        chat.markDelivery(ChatTurnDelivery(id = handoff.id, tripId = "trip-lisbonne", state = ChatDelivery.Sent))
        assertEquals(ChatDelivery.Sending, chat.messages.firstOrNull { it.id == handoff.id }?.delivery)
        chat.markDelivery(ChatTurnDelivery(id = handoff.id, tripId = "trip-rome", state = ChatDelivery.Sent))
        assertEquals(ChatDelivery.Sent, chat.messages.firstOrNull { it.id == handoff.id }?.delivery)
    }

    /**
     * `docs/conversation.md` § 9, de bout en bout : deux messages dits sans
     * réseau depuis la conversation restent « en cours d'envoi », le composeur
     * se rouvre entre les deux, on quitte et on revient — ils sont encore là —,
     * et le retour du réseau les fait partir dans l'ordre, une fois, avec la
     * bulle qui passe « envoyée » toute seule.
     */
    @Test
    fun messagesSentOfflineFromTheConversationStayAndLeaveInOrder() = runTest(dispatcher) {
        val sender = Sender()
        val network = Channel<Boolean>(Channel.UNLIMITED)
        val outbox = outbox(sender, connectivity = Connectivity { network.receiveAsFlow() })
        outbox.start()
        network.send(false)
        until("la file se sait hors ligne") { !outbox.isOnline.value }

        val chat = ChatModel(transport(through = outbox, tripId = "trip-1"), chatAudio(), io = dispatcher)
        chat.load()

        chat.draft = "Un"
        chat.sendDraft()
        until("le premier attend") { outbox.pending.value == 1 }
        until("le composeur se rouvre") { chat.turn == ChatTurnState.Idle }
        chat.draft = "Deux"
        chat.sendDraft()
        until("le second attend") { outbox.pending.value == 2 }

        val ids = chat.messages.map { it.id }
        assertEquals(2, ids.size)
        assertTrue(chat.messages.all { it.delivery == ChatDelivery.Sending }, "Attendre le réseau n'est pas échouer.")
        assertNull(chat.errorMessage)

        // On quitte, on revient : ce qui attend est encore dans le fil.
        chat.teardown()
        val reopened = ChatModel(transport(through = outbox, tripId = "trip-1"), chatAudio(), io = dispatcher)
        reopened.load()
        assertEquals(ids, reopened.messages.map { it.id })
        assertTrue(reopened.messages.all { it.delivery == ChatDelivery.Sending })

        network.send(true)
        until("la file se vide") { outbox.pending.value == 0 }
        until("les bulles passent envoyées", timeoutMs = 3_000) { reopened.messages.all { it.delivery == ChatDelivery.Sent } }

        assertEquals(ids, sender.sentIds, "Dans l'ordre, et une seule fois.")
        assertEquals(listOf(1, 2), reopened.messages.mapNotNull { it.seq }, "Le rang que le serveur leur a donné.")
    }

    /**
     * Le relevé du micro qui part avec le vocal est **celui du vocal entier**, et
     * non la frise des quarante dernières barres.
     */
    @Test
    fun theWaveformIsTheWholeRecording() {
        val recording = RecordingModel(AudioRecorder(ContextWrapper(null)))
        assertTrue(recording.capturedLevels.isEmpty())
        assertTrue(recording.levels.value.isEmpty())
    }

    // MARK: - Le crédit du jour

    /**
     * Un `429 daily_credit_exhausted` n'est pas un refus définitif : le tour
     * reste sur le disque, marqué jusqu'à la recharge, sans bandeau d'erreur ;
     * sa bulle dit « Partira demain » — et le code a traversé jusqu'à elle.
     */
    @Test
    fun aCreditRefusalKeepsTheTurnForTomorrow() = runTest(dispatcher) {
        val sender = Sender()
        // À la seconde : la fiche passe par l'ISO 8601 du disque.
        val resetsAt = Instant.now().plusSeconds(3_600).truncatedTo(ChronoUnit.SECONDS)
        sender.setOutOfCredit(listOf("trip-1"), resetsAt = resetsAt)
        val store = temporaryStore()
        val outbox = outbox(sender, store = store)

        val outcome = outbox.submit(testTurn(), "trip-1")

        assertEquals(RecordingOutbox.Delivery.Queued, outcome, "Il attend, comme sous un tunnel — plus longtemps.")
        assertNull(outbox.rejection.value, "Rien de raté : pas de bandeau d'erreur sur l'accueil.")
        assertEquals(1, outbox.waitingForCredit.value)
        assertEquals(0, outbox.pending.value, "Il n'attend pas le réseau : la boîte de l'accueil ne promet rien pour lui.")
        assertEquals(ChatDelivery.WaitingForCredit(resetsAt), outbox.lastDelivery.value?.state)
        assertEquals(true, outbox.lastDelivery.value?.credit?.isExhausted, "Le solde du refus voyage jusqu'à la bulle.")
        assertEquals(resetsAt, store.all().first().waitingForCreditUntil, "Marqué sur la fiche : une app relancée le sait.")

        // Un vidage avant la recharge ne le renvoie pas au même refus.
        sender.refill()
        outbox.flush()
        assertTrue(sender.sent.isEmpty())
        assertEquals(1, outbox.waitingForCredit.value)
    }

    /**
     * Passé l'heure de la recharge, le tour repart tout seul au vidage suivant ;
     * ce qui attend encore reste de côté.
     */
    @Test
    fun aTurnWaitingForCreditLeavesOnceTheCreditReturns() = runTest(dispatcher) {
        val sender = Sender()
        val store = temporaryStore()
        val due = PendingTurn(
            id = "due",
            tripId = "trip-1",
            kind = PendingTurn.Kind.Text,
            text = "Hier soir, un dernier verre.",
            recordedAt = Instant.now(),
            waitingForCreditUntil = Instant.now().minusSeconds(60),
        )
        val later = PendingTurn(
            id = "later",
            tripId = "trip-2",
            kind = PendingTurn.Kind.Text,
            text = "Pas encore.",
            recordedAt = Instant.now(),
            waitingForCreditUntil = Instant.now().plusSeconds(3_600),
        )
        store.enqueue(due, emptyList())
        store.enqueue(later, emptyList())
        val outbox = outbox(sender, store = store)

        outbox.flush()

        assertEquals(listOf("due"), sender.sentIds)
        assertEquals(1, outbox.waitingForCredit.value)
        assertEquals(0, outbox.pending.value)
    }

    /**
     * Le dernier mot de la file se rejoue à qui se met à l'écoute, **marqué
     * comme tel** : son reçu peut dater du matin. Ce qui suit est neuf.
     */
    @Test
    fun theLastWordIsReplayedAsSuch() = runTest(dispatcher) {
        val outbox = outbox(Sender())
        outbox.submit(testTurn(), "trip-1")
        assertEquals(false, outbox.lastDelivery.value?.isReplay)

        val deliveries = outbox.turnDeliveries()
        outbox.submit(OutgoingTurn(id = "suivant", body = OutgoingTurn.Body.Text("Et après")), "trip-1")
        val words = first(3, deliveries) { true }
        assertEquals(listOf(true, false, false), words.map { it.isReplay })
        assertEquals(ChatDelivery.Sent, words.first().state)
        assertEquals(listOf(ChatDelivery.Sending, ChatDelivery.Sent), words.drop(1).map { it.state })
    }

    /**
     * Une fiche dont l'attente est échue se relit **sans** sa date : la
     * conversation rouvre le tour « en cours d'envoi » et le décompte du jour où
     * il partira. Une attente à venir, elle, se relit telle quelle.
     */
    @Test
    fun aTurnWhoseWaitIsOverIsReadBackWithoutIt() = runTest(dispatcher) {
        val store = temporaryStore()
        val tomorrow = Instant.now().plusSeconds(3_600).truncatedTo(ChronoUnit.SECONDS)
        store.enqueue(
            PendingTurn(
                id = "due", tripId = "trip-1", kind = PendingTurn.Kind.Text, text = "Hier soir", recordedAt = Instant.now(),
                waitingForCreditUntil = Instant.now().minusSeconds(60),
            ),
            emptyList(),
        )
        store.enqueue(
            PendingTurn(
                id = "later", tripId = "trip-1", kind = PendingTurn.Kind.Text, text = "Ce soir", recordedAt = Instant.now(),
                waitingForCreditUntil = tomorrow,
            ),
            emptyList(),
        )
        val outbox = outbox(Sender(), store = store)
        outbox.debugSetOffline(true)

        val waiting = outbox.waiting("trip-1")
        assertEquals(listOf("due", "later"), waiting.map { it.id })
        assertNull(waiting[0].waitingForCreditUntil)
        assertFalse(waiting[0].isOnHold, "Échue : il ne retient plus rien.")
        assertEquals(tomorrow, waiting[1].waitingForCreditUntil)
        assertTrue(waiting[1].isOnHold)
    }

    /**
     * Le refus au vidage marque la fiche et publie « Partira demain ». Les tours
     * suivants du même voyage qui ne tiennent plus dans le reste sont marqués
     * aussi, sans un aller-retour pour le même refus — sinon l'accueil les
     * compterait « hors ligne » alors qu'on est en ligne. Ce qui ne consomme
     * rien — une puce, des photos — part quand même.
     */
    @Test
    fun aCreditRefusalWhileDrainingHoldsTheRestOfThatTrip() = runTest(dispatcher) {
        val sender = Sender()
        val store = temporaryStore()
        val outbox = outbox(sender, store = store)
        outbox.debugSetOffline(true)

        val voice = testTurn()
        val text = OutgoingTurn(body = OutgoingTurn.Body.Text("Et ensuite ?"))
        val chip = OutgoingTurn(body = OutgoingTurn.Body.Text("Ça me convient", suggestionId = "accept", entryId = "e1"))
        val photos = OutgoingTurn(
            body = OutgoingTurn.Body.Photos(listOf(ChatPhotoUpload(byteArrayOf(1), "p.jpg", "image/jpeg")), capturedAt = Instant.now()),
        )
        outbox.submit(voice, "trip-1")
        outbox.submit(text, "trip-1")
        outbox.submit(chip, "trip-1")
        outbox.submit(photos, "trip-1")

        val deliveries = outbox.turnDeliveries()
        sender.setOutOfCredit(listOf("trip-1"), resetsAt = null, exceptFreeTurns = true)
        outbox.debugSetOffline(false)
        until("le vidage est passé") { outbox.sending.value == 0 && outbox.waitingForCredit.value == 2 }

        assertEquals(listOf(chip.id, photos.id), sender.sentIds, "La puce et les photos passent ; le texte attend demain.")
        assertEquals(0, outbox.pending.value, "Rien n'attend le réseau : on est en ligne.")
        val stored = store.all()
        assertEquals(listOf(voice.id, text.id), stored.map { it.id })
        assertNotNull(stored.first { it.id == voice.id }.waitingForCreditUntil)
        assertNotNull(stored.first { it.id == text.id }.waitingForCreditUntil, "Marqué tout de suite : il ne tient pas dans un reste nul.")

        // Sa bulle le dit, elle aussi.
        val held = first(2, deliveries) { it.state.isWaitingForCredit }
        assertEquals(listOf(voice.id, text.id), held.map { it.id })
    }

    /**
     * Derrière un refus, au vidage, un tour plus long qu'une journée n'est pas
     * annoncé « Partira demain » : il attend l'illimité tout de suite, sans un
     * aller-retour pour l'apprendre — et le vocal court refusé, lui, attend
     * bien demain.
     */
    @Test
    fun aTurnLongerThanADayBehindARefusalWaitsForUnlimited() = runTest(dispatcher) {
        val sender = Sender()
        val store = temporaryStore()
        val outbox = outbox(sender, store = store)
        outbox.debugSetOffline(true)

        val short = OutgoingTurn.voice(
            RecordedAudio("court".toByteArray(), "court.m4a", "audio/m4a", duration = 120.0, recordedAt = Instant.now()),
            levels = emptyList(),
        )
        val long = OutgoingTurn.voice(
            RecordedAudio("long".toByteArray(), "long.m4a", "audio/m4a", duration = 420.0, recordedAt = Instant.now()),
            levels = emptyList(),
        )
        outbox.submit(short, "trip-1")
        outbox.submit(long, "trip-1")

        val deliveries = outbox.turnDeliveries()
        sender.setOutOfCredit(listOf("trip-1"), resetsAt = Instant.now().plusSeconds(3_600), usedMs = 240_000)
        outbox.debugSetOffline(false)
        until("le vidage est passé") {
            outbox.sending.value == 0 && outbox.waitingForCredit.value == 1 && outbox.waitingForUnlimited.value == 1
        }

        assertTrue(sender.sentIds.isEmpty())
        assertEquals(listOf(short.id), sender.attempts, "Le vocal de 7 minutes n'est pas essayé pour le même refus.")
        val stored = store.all()
        assertNotNull(stored.first { it.id == short.id }.waitingForCreditUntil, "Le court attend demain.")
        val marked = stored.first { it.id == long.id }
        assertTrue(marked.waitingForUnlimited)
        assertNull(marked.waitingForCreditUntil, "Pas « demain » : l'illimité.")
        assertEquals(0, outbox.pending.value)

        val held = first(2, deliveries) { !it.isReplay && it.state != ChatDelivery.Sending }
        assertEquals(listOf(short.id, long.id), held.map { it.id })
        assertEquals(ChatDelivery.WaitingForUnlimited, held.last().state)
    }

    /**
     * Un tour qui coûte plus qu'une journée entière n'attend pas demain, qui
     * donnerait le même refus : il attend l'illimité, sans réveil à minuit, sans
     * retenir les autres tours du voyage — et repart dès que le compte passe en
     * illimité.
     */
    @Test
    fun aTurnLongerThanADayWaitsForUnlimited() = runTest(dispatcher) {
        val sender = Sender()
        val store = temporaryStore()
        // Il reste 4 minutes : un vocal de 6 minutes 40 ne tiendra jamais.
        sender.setOutOfCredit(listOf("trip-1"), resetsAt = Instant.now().plusSeconds(3_600), usedMs = 60_000)
        val outbox = outbox(sender, store = store)

        val long = OutgoingTurn.voice(
            RecordedAudio("long".toByteArray(), "long.m4a", "audio/m4a", duration = 400.0, recordedAt = Instant.now()),
            levels = emptyList(),
        )
        val outcome = outbox.submit(long, "trip-1")

        assertEquals(RecordingOutbox.Delivery.Queued, outcome, "Gardé : le jeter, ce serait perdre sept minutes de souvenir.")
        assertNull(outbox.rejection.value)
        assertEquals(ChatDelivery.WaitingForUnlimited, outbox.lastDelivery.value?.state)
        assertEquals(1, outbox.waitingForUnlimited.value)
        assertEquals(0, outbox.waitingForCredit.value, "Pas « demain ».")
        assertEquals(0, outbox.pending.value, "Pas « dès ta reconnexion » non plus.")
        assertEquals(true, store.all().first().waitingForUnlimited)
        assertNull(store.all().first().waitingForCreditUntil)

        // Le lendemain, pot plein : toujours pas renvoyé au même refus.
        sender.refill()
        outbox.flush()
        assertTrue(sender.sentIds.isEmpty())

        // L'abonnement le libère.
        outbox.releaseCreditHolds()
        assertEquals(listOf(long.id), sender.sentIds)
        assertEquals(0, outbox.waitingForUnlimited.value)
        assertTrue(store.all().isEmpty())
    }

    /**
     * Le serveur dit lui-même « trop long pour une journée »
     * (`daily_credit_too_long`) — ou refuse pot plein un tour que l'app croyait
     * court : même attente de l'illimité.
     */
    @Test
    fun theServerCanSayATurnIsTooLongForADay() = runTest(dispatcher) {
        val sender = Sender()
        sender.tooLong = setOf("trip-1")
        val outbox = outbox(sender)

        val text = OutgoingTurn(body = OutgoingTurn.Body.Text("Un récit sans fin"))
        val first = outbox.submit(text, "trip-1")
        assertEquals(RecordingOutbox.Delivery.Queued, first)
        assertEquals(ChatDelivery.WaitingForUnlimited, outbox.lastDelivery.value?.state)
        assertNull(outbox.rejection.value, "Rien de raté : il attend.")

        // Pot plein (rien consommé aujourd'hui) et refusé quand même : la mesure
        // du serveur fait foi, pas la durée que l'app a notée.
        sender.tooLong = emptySet()
        sender.setOutOfCredit(listOf("trip-2"), resetsAt = Instant.now().plusSeconds(3_600), usedMs = 0)
        val second = outbox.submit(testTurn(), "trip-2")
        assertEquals(RecordingOutbox.Delivery.Queued, second)
        assertEquals(ChatDelivery.WaitingForUnlimited, outbox.lastDelivery.value?.state)
        assertEquals(2, outbox.waitingForUnlimited.value)
    }

    /**
     * « Supprimer » : un tour qui attend l'illimité quitte le disque et les
     * compteurs. Un tour qui n'attend que le réseau — peut-être en train de
     * partir — ne se supprime pas ; un tour déjà oublié non plus.
     */
    @Test
    fun aTurnWaitingForUnlimitedCanBeDiscarded() = runTest(dispatcher) {
        val sender = Sender()
        val store = temporaryStore()
        sender.tooLong = setOf("trip-1")
        val outbox = outbox(sender, store = store)
        val long = OutgoingTurn(body = OutgoingTurn.Body.Text("Un récit sans fin"))
        outbox.submit(long, "trip-1")
        assertEquals(1, outbox.waitingForUnlimited.value)

        outbox.debugSetOffline(true)
        val metro = OutgoingTurn(body = OutgoingTurn.Body.Text("Dans le métro"))
        outbox.submit(metro, "trip-1")
        assertEquals(1, outbox.pending.value)

        assertFalse(outbox.discardTurn(metro.id), "Il n'attend que le réseau : il peut être en route.")
        assertTrue(outbox.discardTurn(long.id))
        assertEquals(0, outbox.waitingForUnlimited.value)
        assertEquals(1, outbox.pending.value)
        assertEquals(listOf(metro.id), store.all().map { it.id })
        assertFalse(outbox.discardTurn(long.id), "Déjà oublié.")
    }

    /**
     * Un voyage créé hors ligne porte son crédit du jour, **plein**, jusqu'au
     * minuit local : le fil et la feuille de l'accueil comptent dès le premier
     * vocal — illimité si l'accueil gardé dit que le compte l'est. Un voyage
     * qui porte déjà un crédit garde le sien.
     */
    @Test
    fun aTripCreatedOfflineCountsFromAFullPot() = runTest(dispatcher) {
        val outbox = outbox(Sender())
        outbox.debugSetOffline(true)
        val trip = outbox.saveTrip(TripDraft(title = "Lisbonne"))

        val feed = outbox.mergingLocalTrips(HomeFeed(traveller = Traveller(id = "t", firstName = "Camille"), trips = emptyList()))
        val credit = assertNotNull(feed.trips.firstOrNull { it.id == trip.id }?.dailyCredit)
        assertEquals(DailyCredit.Catalog.limitMs, credit.remainingMs)
        assertFalse(credit.isUnlimited)
        assertTrue(assertNotNull(credit.resetsAt) > Instant.now(), "Rechargé au prochain minuit, pas déjà périmé.")

        val subscriber = outbox.mergingLocalTrips(
            HomeFeed(traveller = Traveller(id = "t", firstName = "Camille", isUnlimited = true), trips = emptyList()),
        )
        assertEquals(true, subscriber.trips.firstOrNull()?.dailyCredit?.isUnlimited)

        val served = DailyCredit(usedMs = 120_000)
        val known = Trip(id = "rome", title = "Rome", stage = TripStage.Ongoing, dailyCredit = served)
        assertEquals(served, RecordingOutbox.withFreshCredit(known, isUnlimited = true).dailyCredit)
    }

    /**
     * S'abonner libère ce qui attendait le crédit de demain : il part tout de
     * suite, sans attendre minuit, et sa bulle quitte « Partira demain ».
     */
    @Test
    fun subscribingReleasesWhatWaitsForTomorrow() = runTest(dispatcher) {
        val sender = Sender()
        val store = temporaryStore()
        val held = PendingTurn(
            id = "held",
            tripId = "trip-1",
            kind = PendingTurn.Kind.Text,
            text = "Refusé à 15 h.",
            recordedAt = Instant.now(),
            waitingForCreditUntil = Instant.now().plusSeconds(3_600),
        )
        store.enqueue(held, emptyList())
        val outbox = outbox(sender, store = store)
        outbox.flush()
        assertTrue(sender.sentIds.isEmpty(), "Avant l'achat, il attend minuit.")

        val deliveries = outbox.turnDeliveries()
        outbox.releaseCreditHolds()

        assertEquals(listOf("held"), sender.sentIds)
        assertEquals(0, outbox.waitingForCredit.value)
        assertEquals(0, outbox.pending.value)
        val states = first(2, deliveries) { it.id == "held" }.map { it.state }
        assertEquals(listOf(ChatDelivery.Sending, ChatDelivery.Sent), states, "La bulle repart, puis arrive.")
    }

    /**
     * Sans `resetsAt` lisible — ou déjà passé —, le tour attend le minuit local
     * suivant : ni bloqué pour toujours, ni renvoyé en boucle.
     */
    @Test
    fun theCreditReturnsAtMidnightWhenTheServerDoesNotSay() {
        val paris = ZoneId.of("Europe/Paris")
        val now = LocalDateTime.of(2026, 10, 3, 21, 40).atZone(paris).toInstant()
        val midnight = LocalDateTime.of(2026, 10, 4, 0, 0).atZone(paris).toInstant()
        val served = now.plusSeconds(1_200)

        assertEquals(served, RecordingOutbox.creditReturns(served, now = now, zone = paris))
        assertEquals(midnight, RecordingOutbox.creditReturns(null, now = now, zone = paris))
        assertEquals(
            midnight,
            RecordingOutbox.creditReturns(now.minusSeconds(5), now = now, zone = paris),
            "Une recharge déjà passée — horloge en avance — ne garde pas le tour en otage.",
        )
    }

    // MARK: - Outils

    private fun TestScope.outbox(
        sender: Sender,
        store: PendingRecordingStore = temporaryStore(),
        connectivity: Connectivity = Connectivity.online,
    ): RecordingOutbox = RecordingOutbox(
        store = store,
        trips = PendingTripStore.temporary(Dispatchers.Unconfined),
        connectivity = connectivity,
        send = { turn, tripId -> sender.send(turn, tripId) },
        scope = backgroundScope,
    )

    /** Les entrées-sorties sur place : elles restent dans le temps virtuel du test. */
    private fun temporaryStore() = PendingRecordingStore.temporary(Dispatchers.Unconfined)

    /** Le micro, le lecteur et la voix de la conversation, sur un contexte vide : rien n'y tourne ici. */
    private fun chatAudio(): ChatAudio = ChatAudio(ContextWrapper(null), Files.createTempDirectory("chat-audio").toFile())

    /** La conversation branchée sur la file, comme `AppDependencies.chatModel` la branche. */
    private fun transport(through: RecordingOutbox, tripId: String): ChatTransport = ChatTransport(
        load = {
            ChatThread(id = tripId, title = "Rome 2026", context = ChatContext(tripId = tripId, stepId = null), now = Instant.now())
        },
        poll = { ChatThreadUpdate(messages = emptyList(), turn = ChatTurnStatus.Idle, now = Instant.now()) },
        send = { turn ->
            when (val delivery = through.submit(turn, tripId)) {
                is RecordingOutbox.Delivery.Delivered -> ChatSendOutcome.Received(
                    delivery.receipt ?: ChatTurnReceipt(messages = emptyList(), turn = ChatTurnStatus.Idle, now = Instant.now()),
                )
                RecordingOutbox.Delivery.Queued -> ChatSendOutcome.Queued
                is RecordingOutbox.Delivery.Rejected -> throw RecordingOutbox.Rejection(message = delivery.message)
            }
        },
        editTranscript = { _, _ -> throw ApiError.Server(statusCode = 0, code = null, message = "Pas ici.") },
        media = { ByteArray(0) },
        waiting = { through.waiting(tripId) },
        deliveries = { through.turnDeliveries() },
    )

    /** Un vocal de quatre secondes, tel que l'accueil le confie. */
    private fun testTurn(): OutgoingTurn = OutgoingTurn.voice(
        RecordedAudio("un vocal".toByteArray(), "test.m4a", "audio/m4a", duration = 4.0, recordedAt = Instant.now()),
        levels = listOf(0.2, 0.8),
    )

    /** Le `RecordedAudio.debugSilence` d'iOS : un vocal d'une seconde, sans voix. */
    private fun silence() = RecordedAudio(ByteArray(16), "memo-silence.m4a", "audio/mp4", duration = 1.0, recordedAt = Instant.now())
}

/**
 * Les premiers mots de la file qui répondent à [keep] — ou ce qui est arrivé au
 * bout du délai : un mot qui manque fait échouer le test au lieu de le laisser
 * attendre pour toujours.
 */
internal suspend fun first(
    count: Int,
    stream: Flow<ChatTurnDelivery>,
    timeoutMs: Long = 2_000,
    keep: (ChatTurnDelivery) -> Boolean,
): List<ChatTurnDelivery> {
    val kept = mutableListOf<ChatTurnDelivery>()
    withTimeoutOrNull(timeoutMs) { stream.filter(keep).take(count).toList(kept) }
    return kept
}

/**
 * Attend qu'une condition devienne vraie, ou échoue en le disant. Les envois
 * partent dans leurs propres tâches : on ne peut pas les attendre directement
 * sans donner à la file une trappe qui n'existerait que pour les tests. Le
 * temps est celui, virtuel, du test.
 */
internal suspend fun TestScope.until(what: String, timeoutMs: Long = 2_000, condition: () -> Boolean) {
    val deadline = testScheduler.currentTime + timeoutMs
    while (testScheduler.currentTime < deadline) {
        if (condition()) return
        delay(10)
    }
    if (!condition()) fail("Jamais atteint : $what")
}

/**
 * Le serveur, vu de la file : il accepte — et rend le reçu, la bulle du
 * voyageur avec son rang —, il est injoignable, ou il refuse.
 */
private class Sender {
    /** Les carnets servis, dans l'ordre des envois. */
    val sent = mutableListOf<String>()

    /** Les tours servis, dans l'ordre — c'est l'ordre et l'unicité qu'on vérifie. */
    val sentIds = mutableListOf<String>()

    /** Tous les tours présentés, refusés compris : ce qu'on n'a pas eu besoin d'essayer n'y est pas. */
    val attempts = mutableListOf<String>()
    var unreachable: Set<String> = emptySet()
    var refused: Set<String> = emptySet()
    var signedOut: Set<String> = emptySet()

    /** Les carnets dont le crédit du jour est épuisé, et l'heure de recharge que le serveur annonce. */
    private var outOfCredit: Map<String, Instant?> = emptyMap()

    /** Ce que le voyage a déjà consommé au moment du refus : tout, par défaut. */
    private var usedMs = DailyCredit.Catalog.limitMs

    /** Ce qui ne consomme rien passe malgré le refus — une puce, des photos. */
    private var freeTurnsPass = false

    /** Les carnets qui refusent tout tour « plus long qu'une journée ». */
    var tooLong: Set<String> = emptySet()

    fun setOutOfCredit(
        tripIds: List<String>,
        resetsAt: Instant?,
        exceptFreeTurns: Boolean = false,
        usedMs: Int = DailyCredit.Catalog.limitMs,
    ) {
        outOfCredit = tripIds.associateWith { resetsAt }
        freeTurnsPass = exceptFreeTurns
        this.usedMs = usedMs
    }

    fun refill() {
        outOfCredit = emptyMap()
    }

    fun send(turn: OutgoingTurn, tripId: String): ChatTurnReceipt {
        attempts += turn.id
        if (tripId in unreachable) throw ApiError.Transport(IOException("hors ligne"), url = null)
        if (tripId in refused) throw ApiError.Server(statusCode = 404, code = null, message = "Carnet introuvable.")
        if (tripId in signedOut) throw ApiError.Server(statusCode = 401, code = "unauthorized", message = "Session expirée.")
        if (tripId in tooLong) {
            throw ApiError.Server(
                statusCode = 422,
                code = ApiError.DAILY_CREDIT_TOO_LONG_CODE,
                message = "C’est plus long que le crédit d’une journée entière.",
            )
        }
        val isFree = turn.creditCost(DailyCredit()) == 0
        if (tripId in outOfCredit && !(freeTurnsPass && isFree)) {
            throw ApiError.DailyCreditExhausted(
                message = "Le crédit du jour de ce voyage est épuisé.",
                credit = DailyCredit(usedMs = usedMs, resetsAt = outOfCredit[tripId]),
            )
        }
        sent += tripId
        sentIds += turn.id

        val body = when (val turnBody = turn.body) {
            is OutgoingTurn.Body.Text -> ChatMessageBody.Text(turnBody.text)
            is OutgoingTurn.Body.Voice -> ChatMessageBody.Voice(
                VoiceNote(id = turn.id, duration = turnBody.audio.durationSeconds, levels = turnBody.audio.levels),
            )
            is OutgoingTurn.Body.Photos -> ChatMessageBody.Photos(turnBody.photos.indices.map { PhotoAttachment(id = "${turn.id}-$it") })
        }
        return ChatTurnReceipt(
            messages = listOf(ChatMessage(id = turn.id, author = ChatAuthor.Traveller, body = body, sentAt = Instant.now(), seq = sentIds.size)),
            turn = ChatTurnStatus.Idle,
            now = Instant.now(),
        )
    }
}
