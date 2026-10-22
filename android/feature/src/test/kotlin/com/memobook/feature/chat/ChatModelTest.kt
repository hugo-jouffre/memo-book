@file:OptIn(ExperimentalCoroutinesApi::class)

package com.memobook.feature.chat

import android.content.ContextWrapper
import com.memobook.core.ChatAuthor
import com.memobook.core.ChatCallToAction
import com.memobook.core.ChatCallToActionState
import com.memobook.core.ChatContext
import com.memobook.core.ChatCopy
import com.memobook.core.ChatDelivery
import com.memobook.core.ChatMessage
import com.memobook.core.ChatMessageBody
import com.memobook.core.ChatSuggestion
import com.memobook.core.ChatThread
import com.memobook.core.ChatThreadUpdate
import com.memobook.core.ChatTurnReceipt
import com.memobook.core.ChatTurnStatus
import com.memobook.core.DailyCredit
import com.memobook.core.DailyCreditCopy
import com.memobook.core.Entry
import com.memobook.core.EntryKind
import com.memobook.core.Status
import com.memobook.core.TranscriptCard
import com.memobook.core.Trip
import com.memobook.core.TripStage
import com.memobook.feature.PaywallVariant
import com.memobook.feature.SubscriptionSession
import com.memobook.feature.recording.RecordingHandoff
import com.memobook.feature.until
import com.memobook.networking.ApiError
import com.memobook.recording.RecordedAudio
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.time.Instant
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail
import kotlin.time.Duration.Companion.milliseconds

/**
 * Le déroulé d'un tour, avec un transport scripté : ce que le modèle fait du
 * reçu, du sondage et du rythme — `docs/conversation.md` § 8. Porté de
 * `ChatModelTests.swift`, cas pour cas.
 *
 * Le temps est **virtuel** (`runTest`) : le sondage de deux secondes et les
 * silences de MEMO passent sans attendre, dans l'ordre où ils tomberaient.
 * Le micro, le lecteur et la voix sont les vrais, sur un contexte vide — rien
 * n'y tourne, et le modèle n'y touche pas dans ces cas.
 */
class ChatModelTest {
    private val dispatcher = StandardTestDispatcher()
    private lateinit var cacheDirectory: File

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(dispatcher)
        cacheDirectory = Files.createTempDirectory("chat-model").toFile()
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
        cacheDirectory.deleteRecursively()
    }

    /** Un transport dont on écrit les réponses d'avance, et qui note ce qu'on lui a envoyé. */
    private class Script(var thread: ChatThread) {
        /** Le reçu se fabrique **à partir du tour** : c'est lui qui porte l'identifiant que le serveur reprend. */
        var receiptFor: ((OutgoingTurn) -> ChatTurnReceipt)? = null
        val updates = ArrayDeque<ChatThreadUpdate>()
        val sent = mutableListOf<OutgoingTurn>()
        val edited = mutableListOf<Pair<String, String>>()
        var polls = 0
        var failsSending: Throwable? = null
        var failsEditing: Throwable? = null

        /** Le tour met ce temps à monter — un vocal en 3G. */
        var sendDelayMs: Long? = null

        /** La file dit que le tour attend le réseau, au lieu de le livrer. */
        var queuesSends = false

        /** Le serveur est injoignable : le fil s'ouvre en local. */
        var isOffline = false

        /** Ce qui attend sur le disque pour ce fil. */
        var waiting: List<OutgoingTurn> = emptyList()

        /** Les tours que l'écran a demandé à la file d'oublier. */
        val discarded = mutableListOf<String>()

        /** La file, telle que le modèle l'écoute. */
        val deliveries = Channel<ChatTurnDelivery>(Channel.UNLIMITED)

        suspend fun send(turn: OutgoingTurn): ChatSendOutcome {
            sent += turn
            sendDelayMs?.let { delay(it) }
            failsSending?.let { throw it }
            if (queuesSends) return ChatSendOutcome.Queued
            return ChatSendOutcome.Received(
                receiptFor?.invoke(turn) ?: ChatTurnReceipt(messages = emptyList(), turn = ChatTurnStatus.Idle, now = Instant.now()),
            )
        }

        fun deliver(delivery: ChatTurnDelivery) {
            deliveries.trySend(delivery)
        }

        fun poll(): ChatThreadUpdate {
            polls += 1
            return updates.removeFirstOrNull() ?: ChatThreadUpdate(messages = emptyList(), turn = ChatTurnStatus.Idle, now = Instant.now())
        }

        fun edit(entryId: String, text: String): Entry {
            edited += entryId to text
            failsEditing?.let { throw it }
            val now = Instant.now()
            return Entry(
                id = entryId,
                memoId = "trip",
                kind = EntryKind.Audio,
                status = Status.Ready,
                redactionStatus = Status.Ready,
                editedText = text,
                editedAt = now,
                capturedAt = now,
                createdAt = now,
            )
        }

        fun goOnline(thread: ChatThread) {
            isOffline = false
            this.thread = thread
        }
    }

    private fun transport(script: Script): ChatTransport = ChatTransport(
        load = {
            if (script.isOffline) throw ApiError.Transport(IOException("hors ligne"), url = null)
            script.thread
        },
        poll = { script.poll() },
        send = { turn -> script.send(turn) },
        editTranscript = { entryId, text -> script.edit(entryId, text) },
        media = { ByteArray(0) },
        waiting = { script.waiting },
        deliveries = { script.deliveries.receiveAsFlow() },
        offlineThread = { if (script.isOffline) script.thread else null },
        discard = { id ->
            script.discarded += id
            true
        },
    )

    /** Le micro, le lecteur et la voix, sur un contexte vide : rien n'y tourne dans ces cas. */
    private fun audio(): ChatAudio = ChatAudio(ContextWrapper(null), cacheDirectory)

    private fun model(
        script: Script,
        memory: ChatCallToActionMemory = ChatCallToActionMemory.inMemory(),
    ): ChatModel = ChatModel(transport(script), audio(), callToActionMemory = memory, io = dispatcher)

    private fun thread(
        messages: List<ChatMessage> = emptyList(),
        suggestions: List<ChatSuggestion> = emptyList(),
        credit: DailyCredit? = null,
    ): ChatThread = ChatThread(
        id = "trip",
        title = "Rome 2026",
        context = ChatContext(tripId = "trip", stepId = "step-3"),
        messages = messages,
        suggestions = suggestions,
        now = Instant.now(),
        dailyCredit = credit,
    )

    /** Un crédit du jour dont il reste `remainingMs`. */
    private fun credit(remainingMs: Int, isUnlimited: Boolean = false): DailyCredit = DailyCredit(
        isUnlimited = isUnlimited,
        usedMs = DailyCredit.Catalog.limitMs - remainingMs,
        day = "2026-10-03",
        resetsAt = Instant.now().plusSeconds(3_600),
    )

    private fun memo(id: String, text: String, seq: Int, pause: Int = 450): ChatMessage =
        ChatMessage(id = id, author = ChatAuthor.Memo, body = ChatMessageBody.Text(text), sentAt = Instant.now(), seq = seq, pauseMilliseconds = pause)

    private fun card(id: String, entryId: String, text: String?, phase: TranscriptCard.Phase, seq: Int, validated: Boolean = false): ChatMessage =
        ChatMessage(
            id = id,
            author = ChatAuthor.Memo,
            body = ChatMessageBody.Transcript(
                TranscriptCard(
                    title = "Retranscription du contexte",
                    capturedAt = Instant.now(),
                    text = text,
                    entryId = entryId,
                    phase = phase,
                    isValidated = validated,
                ),
            ),
            sentAt = Instant.now(),
            seq = seq,
        )

    private fun traveller(id: String, text: String, seq: Int): ChatMessage =
        ChatMessage(id = id, author = ChatAuthor.Traveller, body = ChatMessageBody.Text(text), sentAt = Instant.now(), seq = seq)

    // MARK: - Envoyer

    /**
     * La bulle se pose avant le réseau, et passe « envoyée » au reçu — sous le
     * **même** identifiant, avec le rang que le serveur lui donne.
     */
    @Test
    fun theBubbleIsPostedBeforeTheNetworkAndConfirmedByTheReceipt() = runTest(dispatcher) {
        val script = Script(thread())
        script.receiptFor = { turn ->
            ChatTurnReceipt(
                messages = listOf(
                    ChatMessage(id = "opening", author = ChatAuthor.Memo, body = ChatMessageBody.Text("Bonjour 👋"), sentAt = Instant.now(), seq = 1, pauseMilliseconds = 700),
                    traveller(turn.id, "Une longue journée à Rome.", seq = 2),
                ),
                turn = ChatTurnStatus.Replying(messageId = turn.id),
                now = Instant.now(),
            )
        }
        val model = model(script)
        model.load()

        model.draft = "Une longue journée à Rome."
        model.sendDraft()

        val posted = assertNotNull(model.messages.lastOrNull())
        assertEquals(ChatDelivery.Sending, posted.delivery, "La bulle est là avant le réseau.")
        assertNull(posted.seq)
        val sentId = posted.id

        until("le reçu confirme la bulle") { model.messages.firstOrNull { it.id == sentId }?.delivery == ChatDelivery.Sent }
        assertEquals(listOf("opening", sentId), model.messages.map { it.id }, "L'ouverture passe devant, par son rang.")
        assertEquals(2, model.messages.last().seq)
        assertEquals(ChatTurnState.Thinking, model.turn, "MEMO réfléchit : le reçu dit qu'un tour est en vol.")
        assertEquals(listOf(sentId), script.sent.map { it.id })
    }

    /**
     * Les bulles de MEMO arrivent **dans l'ordre et espacées** : l'indicateur
     * se rallume entre deux, et les puces ne reviennent qu'à la fin.
     */
    @Test
    fun memoBeatsArriveInOrderWithTheirPauses() = runTest(dispatcher) {
        val script = Script(thread())
        val model = model(script)
        model.load()

        script.receiptFor = { turn ->
            ChatTurnReceipt(
                messages = listOf(traveller(turn.id, "Coucou", seq = 1)),
                turn = ChatTurnStatus.Replying(messageId = turn.id),
                now = Instant.now(),
            )
        }
        script.updates += ChatThreadUpdate(
            messages = listOf(memo("b", "Deuxième", seq = 3), memo("a", "Première", seq = 2)),
            suggestions = listOf(ChatSuggestion(id = "voice", label = "Je te raconte à l’oral")),
            turn = ChatTurnStatus.Idle,
            now = Instant.now(),
        )

        model.draft = "Coucou"
        model.sendDraft()

        until("la première bulle", timeoutMs = 4_000) { model.messages.size == 2 }
        assertEquals("a", model.messages.last().id, "Le rang du serveur, pas l'ordre du tableau.")
        assertEquals(ChatTurnState.Thinking, model.turn, "L'indicateur reste allumé entre deux bulles.")
        assertTrue(model.visibleSuggestions.isEmpty())

        until("la seconde bulle", timeoutMs = 4_000) { model.messages.size == 3 }
        until("le repos") { model.turn == ChatTurnState.Idle }
        val id = assertNotNull(script.sent.firstOrNull()).id
        assertEquals(listOf(id, "a", "b"), model.messages.map { it.id })
        assertEquals(listOf("voice"), model.visibleSuggestions.map { it.id })
    }

    /**
     * Une fiche qui mûrit se remplace **sans pause** — ce n'est pas une bulle
     * qui arrive, c'est la même qui change —, et le sondage s'arrête quand elle
     * est prête.
     */
    @Test
    fun aSettlingCardIsReplacedInPlaceAndPollingStopsWhenReady() = runTest(dispatcher) {
        val script = Script(thread(messages = listOf(card("c", entryId = "e1", text = null, phase = TranscriptCard.Phase.Listening, seq = 1))))
        val model = model(script)
        script.updates += ChatThreadUpdate(
            messages = listOf(card("c", entryId = "e1", text = "brut", phase = TranscriptCard.Phase.Writing, seq = 1)),
            turn = ChatTurnStatus.Idle,
            now = Instant.now(),
        )
        script.updates += ChatThreadUpdate(
            messages = listOf(card("c", entryId = "e1", text = "rédigé", phase = TranscriptCard.Phase.Ready, seq = 1)),
            turn = ChatTurnStatus.Idle,
            now = Instant.now(),
        )

        model.load()
        assertEquals(ChatTurnState.Idle, model.turn, "Une fiche qui mûrit ne bloque pas le composeur.")

        until("le brut", timeoutMs = 4_000) { (model.messages.firstOrNull()?.body as? ChatMessageBody.Transcript)?.card?.text == "brut" }
        assertEquals(1, model.messages.size)

        until("le rédigé", timeoutMs = 4_000) {
            (model.messages.firstOrNull()?.body as? ChatMessageBody.Transcript)?.card?.phase == TranscriptCard.Phase.Ready
        }
        val pollsAtReady = script.polls
        delay(2_500)
        assertEquals(pollsAtReady, script.polls, "Plus rien à attendre : le sondage s'est tu.")
    }

    // MARK: - Valider, corriger

    /** « Ça me convient » vise la dernière fiche du fil, par son souvenir. */
    @Test
    fun acceptSendsTheSuggestionWithTheLatestCardEntry() = runTest(dispatcher) {
        val script = Script(
            thread(
                messages = listOf(
                    card("c1", entryId = "e1", text = "hier", phase = TranscriptCard.Phase.Ready, seq = 1),
                    card("c2", entryId = "e2", text = "aujourd’hui", phase = TranscriptCard.Phase.Ready, seq = 2),
                ),
                suggestions = listOf(ChatSuggestion(id = "accept", label = "Ça me convient")),
            ),
        )
        val model = model(script)
        model.load()

        model.choose(ChatSuggestion(id = "accept", label = "Ça me convient"), addPhotos = { fail("pas de photos") })

        until("l'envoi") { script.sent.size == 1 }
        val body = assertIs<OutgoingTurn.Body.Text>(script.sent[0].body, "un texte")
        assertEquals("Ça me convient", body.text)
        assertEquals("accept", body.suggestionId)
        assertEquals("e2", body.entryId)
    }

    /**
     * La bande de suggestions garde sa place pendant le tour : ses puces
     * s'effacent, sa hauteur reste — sinon le fil se tassait sous le message
     * qu'on venait de poser (T207, 30/09/2026).
     */
    @Test
    fun theSuggestionRailKeepsItsPlaceWhileMemoAnswers() = runTest(dispatcher) {
        val script = Script(thread(suggestions = listOf(ChatSuggestion(id = "accept", label = "Ça me convient"))))
        script.receiptFor = { turn ->
            ChatTurnReceipt(
                messages = listOf(traveller(turn.id, "Ça me convient", seq = 1)),
                turn = ChatTurnStatus.Replying(messageId = turn.id),
                now = Instant.now(),
            )
        }
        val model = model(script)
        model.load()
        assertFalse(model.reservesSuggestionRail, "Au repos, la bande montre ses puces.")

        model.choose(ChatSuggestion(id = "accept", label = "Ça me convient"), addPhotos = { fail("pas de photos") })
        until("le tour") { model.turn != ChatTurnState.Idle }

        assertTrue(model.visibleSuggestions.isEmpty(), "Les puces s'effacent pendant le tour.")
        assertTrue(model.reservesSuggestionRail, "Mais la bande garde sa hauteur.")
    }

    /** Sans puces au départ du tour, il n'y a pas de place à garder. */
    @Test
    fun noRailSpaceIsKeptWhenThereWereNoSuggestions() = runTest(dispatcher) {
        val script = Script(thread())
        script.receiptFor = { turn -> ChatTurnReceipt(messages = emptyList(), turn = ChatTurnStatus.Replying(messageId = turn.id), now = Instant.now()) }
        val model = model(script)
        model.load()

        model.draft = "Une journée à Rome."
        model.sendDraft()
        until("le tour") { model.turn != ChatTurnState.Idle }

        assertFalse(model.reservesSuggestionRail)
    }

    /**
     * « À la main » : le texte de la fiche est dans le champ ; envoyer corrige
     * le souvenir, redessine la fiche, puis fait accuser réception à MEMO.
     */
    @Test
    fun editingByHandPatchesTheEntryThenAcknowledges() = runTest(dispatcher) {
        val script = Script(thread(messages = listOf(card("c", entryId = "e1", text = "le texte de MEMO", phase = TranscriptCard.Phase.Ready, seq = 1))))
        val model = model(script)
        model.load()

        model.choose(
            ChatSuggestion(id = "edit-hand", label = "À la main", intent = ChatSuggestion.Intent.SendThenEditTranscript),
            addPhotos = { fail("pas de photos") },
        )
        assertEquals("le texte de MEMO", model.draft)
        assertTrue(model.isEditingTranscript)
        assertEquals(ChatComposerMode.Writing, model.composer)
        // Le temps de taper : la puce part avant que la correction n'arrive. Sur
        // iOS, la tâche annulée par la correction s'exécute quand même jusqu'à
        // sa première vérification ; une coroutine annulée avant d'avoir
        // démarré, elle, ne s'exécute pas — et l'app, sur le fil principal,
        // l'aurait déjà lancée.
        runCurrent()

        model.draft = "ma version"
        model.sendDraft()

        until("la correction") { script.edited.size == 1 }
        assertEquals("e1", script.edited.first().first)
        assertEquals("ma version", script.edited.first().second)
        until("l'accusé") { script.sent.size == 2 }
        val acknowledgement = assertIs<OutgoingTurn.Body.Text>(script.sent[1].body, "un texte")
        assertEquals("transcript_edited", acknowledgement.suggestionId)
        assertEquals("e1", acknowledgement.entryId)

        val card = assertIs<ChatMessageBody.Transcript>(model.messages.first().body, "une fiche").card
        assertEquals("ma version", card.text)
        assertFalse(model.isEditingTranscript)
    }

    // MARK: - Hors ligne

    /**
     * Un tour qui attend le réseau **n'a pas échoué** : la bulle reste « en
     * cours d'envoi », le composeur se rouvre, et c'est la file qui la termine —
     * par son identifiant, avec le reçu du serveur, dont le fil prend les
     * bulles et le tour en vol. Un tour d'un autre voyage ne touche à rien.
     */
    @Test
    fun aQueuedTurnStaysSendingUntilTheQueueSaysItLeft() = runTest(dispatcher) {
        val script = Script(thread())
        script.queuesSends = true
        val model = model(script)
        model.load()

        model.draft = "Dit dans le métro."
        model.sendDraft()
        val id = assertNotNull(model.messages.lastOrNull()).id

        until("le tour est confié à la file") { script.sent.size == 1 }
        until("le composeur se rouvre") { model.turn == ChatTurnState.Idle }
        assertEquals(ChatDelivery.Sending, model.messages.last().delivery)
        assertNull(model.errorMessage)

        script.deliver(ChatTurnDelivery(id = id, tripId = "ailleurs", state = ChatDelivery.Failed("non")))
        delay(100)
        assertEquals(ChatDelivery.Sending, model.messages.last().delivery, "Le sort d'un tour d'un autre voyage ne regarde pas ce fil.")

        script.deliver(
            ChatTurnDelivery(
                id = id,
                tripId = "trip",
                state = ChatDelivery.Sent,
                receipt = ChatTurnReceipt(
                    messages = listOf(traveller(id, "Dit dans le métro.", seq = 7)),
                    turn = ChatTurnStatus.Replying(messageId = id),
                    now = Instant.now(),
                ),
            ),
        )
        until("la bulle est envoyée") { model.messages.last().delivery == ChatDelivery.Sent }
        assertEquals(7, model.messages.last().seq, "Le rang du serveur, pris dans le reçu.")
        assertEquals(ChatTurnState.Thinking, model.turn, "Le reçu dit que MEMO répond : on l'attend.")
        assertEquals(1, model.messages.size)
    }

    /**
     * La file a vu le serveur refuser un tour parti d'ici : la bulle passe « non
     * envoyée », et « Réessayer » le renvoie **sous le même identifiant** — même
     * si le modèle ne le tenait plus en main.
     */
    @Test
    fun aRefusalFromTheQueueIsRetriedUnderTheSameId() = runTest(dispatcher) {
        val script = Script(thread())
        script.queuesSends = true
        val model = model(script)
        model.load()

        model.draft = "Refusé plus tard."
        model.sendDraft()
        val id = assertNotNull(model.messages.lastOrNull()).id
        until("le composeur se rouvre") { model.turn == ChatTurnState.Idle }

        script.deliver(ChatTurnDelivery(id = id, tripId = "trip", state = ChatDelivery.Failed("Quota atteint.")))
        until("la bulle est non envoyée") { model.messages.last().delivery.hasFailed }

        script.queuesSends = false
        model.retry()
        until("le renvoi aboutit") { model.messages.last().delivery == ChatDelivery.Sent }
        assertEquals(listOf(id, id), script.sent.map { it.id })
        assertEquals(1, model.messages.size)
    }

    /**
     * Ce qui attend sur le disque pour ce fil se pose en bulles « en cours
     * d'envoi » à l'ouverture — et pas deux fois quand on recharge.
     */
    @Test
    fun whatWaitsOnDiskIsPostedAsSendingBubbles() = runTest(dispatcher) {
        val script = Script(thread(messages = listOf(memo("opening", "Bonjour 👋", seq = 1))))
        script.waiting = listOf(
            OutgoingTurn(id = "w-1", body = OutgoingTurn.Body.Text("Hier soir")),
            OutgoingTurn(id = "w-2", body = OutgoingTurn.Body.Text("Ce matin")),
        )
        val model = model(script)
        model.load()

        assertEquals(listOf("opening", "w-1", "w-2"), model.messages.map { it.id }, "Après le fil, dans l'ordre de la file.")
        assertEquals(listOf<ChatDelivery>(ChatDelivery.Sending, ChatDelivery.Sending), model.messages.drop(1).map { it.delivery })
        assertEquals(ChatTurnState.Idle, model.turn)

        model.load()
        assertEquals(3, model.messages.size, "Recharger ne double pas ce qui attend.")
    }

    // MARK: - Échouer

    /**
     * Une panne laisse la bulle « non envoyée », et [ChatModel.retry] la renvoie
     * sous le même identifiant — jamais une seconde bulle.
     */
    @Test
    fun aFailureKeepsTheBubbleAndRetryResendsTheSameId() = runTest(dispatcher) {
        val script = Script(thread())
        script.failsSending = ApiError.Transport(IOException("hors ligne"), url = null)
        val model = model(script)
        model.load()

        model.draft = "Une longue journée à Rome."
        model.sendDraft()

        until("l'échec") { model.messages.lastOrNull()?.delivery?.hasFailed == true }
        val failed = assertIs<ChatTurnState.Failed>(model.turn, "un échec")
        assertEquals(model.messages.last().id, failed.messageId)
        assertTrue(model.isComposerEnabled, "On ne piège personne derrière un message qui ne passe pas.")

        script.failsSending = null
        model.retry()
        until("le renvoi") { model.messages.last().delivery == ChatDelivery.Sent }
        assertEquals(1, model.messages.size)
        val resent = script.sent.map { it.id }
        assertEquals(2, resent.size)
        assertEquals(1, resent.toSet().size)
    }

    // MARK: - Le crédit du jour

    /**
     * Le crédit du fil se décompte **à l'envoi**, sans attendre le reçu — un
     * texte, 75 ms par caractère ; une puce, rien —, et le reçu remet le
     * chiffre du serveur.
     */
    @Test
    fun theCreditIsSpentLocallyThenTakenFromTheReceipt() = runTest(dispatcher) {
        val script = Script(thread(credit = credit(remainingMs = 200_000)))
        script.queuesSends = true
        val model = model(script)
        model.load()
        assertEquals(200_000, model.dailyCredit?.remainingMs)

        model.draft = "Dix lettres"
        model.sendDraft()
        assertEquals(200_000 - 11 * 75, model.dailyCredit?.remainingMs, "Onze caractères, décomptés tout de suite.")

        model.choose(ChatSuggestion(id = "later", label = "Plus tard", symbol = null, intent = ChatSuggestion.Intent.Send), addPhotos = {})
        assertEquals(200_000 - 11 * 75, model.dailyCredit?.remainingMs, "Une puce ne coûte rien.")

        script.queuesSends = false
        val served = credit(remainingMs = 150_000)
        script.receiptFor = { ChatTurnReceipt(messages = emptyList(), turn = ChatTurnStatus.Idle, now = Instant.now(), dailyCredit = served) }
        model.draft = "Encore"
        model.sendDraft()
        // Le chiffre du serveur, moins le premier texte — toujours en file : le
        // serveur ne l'a pas reçu, son crédit ne le compte pas.
        until("le reçu remet le chiffre du serveur") { model.dailyCredit?.remainingMs == 150_000 - 11 * 75 }
    }

    /**
     * Un brouillon plus long que le reste du jour ne part pas : l'envoi pâlit et
     * la boîte dit combien il reste. Sous une minute de crédit, un brouillon qui
     * passe porte le rappel discret des caractères.
     */
    @Test
    fun aDraftLongerThanTheCreditCannotBeSent() = runTest(dispatcher) {
        val script = Script(thread(credit = credit(remainingMs = 1_500))) // 20 caractères
        val model = model(script)
        model.load()
        model.composer = ChatComposerMode.Writing

        model.draft = "a".repeat(30)
        assertTrue(model.draftExceedsCredit)
        assertFalse(model.canSendDraft)
        assertEquals(ChatCreditTextNotice.TooLong(DailyCreditCopy.textTooLong(charactersLeft = 20)), model.creditTextNotice)
        model.sendDraft()
        runCurrent()
        assertTrue(script.sent.isEmpty(), "Le serveur le refuserait en entier : l'app l'en empêche avant.")
        assertEquals(30, model.draft.length, "Le brouillon reste, rien n'est perdu.")

        model.draft = "Court"
        assertTrue(model.canSendDraft)
        assertEquals(ChatCreditTextNotice.Reminder(ChatCopy.Credit.charactersLeft(20)), model.creditTextNotice)
    }

    /**
     * Crédit épuisé : le micro et le clavier ne s'ouvrent pas, ils font paraître
     * le bandeau « épuisé » — qui **passe** : il s'efface au geste suivant, ou
     * de lui-même. Les puces, gratuites, restent là ; « Raconter à l'oral », qui
     * n'armerait qu'un micro fermé, se tait.
     */
    @Test
    fun anExhaustedCreditShowsTheBannerInsteadOfOpeningTheMicrophone() = runTest(dispatcher) {
        val accept = ChatSuggestion(id = "accept", label = "Ça me convient", intent = ChatSuggestion.Intent.Send)
        val speak = ChatSuggestion(id = "edit-voice", label = "Je raconte à l’oral", intent = ChatSuggestion.Intent.SendThenSpeak)
        val script = Script(thread(suggestions = listOf(accept, speak), credit = credit(remainingMs = 0)))
        val model = model(script)
        model.load()

        assertTrue(model.isCreditExhausted)
        assertNull(model.creditBanner, "Rien tant qu'on n'a rien touché.")
        assertEquals(listOf("accept"), model.visibleSuggestions.map { it.id }, "Pas de micro à armer.")

        model.tapMicrophone()
        assertEquals(ChatComposerMode.Tools, model.composer, "Le micro ne s'arme pas.")
        assertFalse(model.recorder.isRecording)
        assertEquals(DailyCreditBanner.Exhausted, model.creditBanner)
        assertEquals(listOf("accept"), model.visibleSuggestions.map { it.id }, "Les puces restent à portée de doigt.")

        // Le geste suivant l'emporte : une puce.
        model.choose(accept, addPhotos = {})
        assertNull(model.creditBanner)

        // Et seul, il s'en va aussi.
        model.exhaustedNoticeLinger = 50.milliseconds
        assertFalse(model.tapKeyboard(), "Le clavier ne s'ouvre pas sur un texte qui ne partirait pas.")
        assertEquals(DailyCreditBanner.Exhausted, model.creditBanner)
        until("le bandeau s'efface de lui-même") { model.creditBanner == null }
    }

    /** Un abonné ne voit rien de tout ça : ni bandeau, ni limite de texte. */
    @Test
    fun aSubscriberSeesNoneOfIt() = runTest(dispatcher) {
        val script = Script(thread(credit = credit(remainingMs = 0, isUnlimited = true)))
        val model = model(script)
        model.load()
        model.composer = ChatComposerMode.Writing
        model.draft = "a".repeat(10_000)

        assertFalse(model.isCreditExhausted)
        assertFalse(model.draftExceedsCredit)
        assertNull(model.creditTextNotice)
        assertNull(model.creditBanner)
        assertTrue(model.canSendDraft)
    }

    /**
     * La file a vu le serveur refuser faute de crédit : la bulle attend demain —
     * pas de « Non envoyé », pas de renvoi en boucle — et la barre passe à
     * « épuisé ».
     */
    @Test
    fun aCreditRefusalWaitsForTomorrowInsteadOfFailing() = runTest(dispatcher) {
        val script = Script(thread(credit = credit(remainingMs = 2_000)))
        script.queuesSends = true
        val model = model(script)
        model.load()

        model.draft = "Un mot"
        model.sendDraft()
        val id = assertNotNull(model.messages.lastOrNull()).id
        until("le composeur se rouvre") { model.turn == ChatTurnState.Idle }

        val tomorrow = Instant.now().plusSeconds(7_200)
        script.deliver(
            ChatTurnDelivery(id = id, tripId = "trip", state = ChatDelivery.WaitingForCredit(until = tomorrow), credit = credit(remainingMs = 0)),
        )
        until("la bulle attend demain") { model.messages.last().delivery.isWaitingForCredit }
        assertFalse(model.messages.last().delivery.hasFailed)
        assertTrue(model.isCreditExhausted)

        model.retry()
        delay(100)
        assertEquals(1, script.sent.size, "Rien à réessayer : la file le renverra à la recharge.")
    }

    /**
     * Un transport sans file — les aperçus — rend le refus tel quel : la bulle
     * attend demain plutôt que d'échouer.
     */
    @Test
    fun aDirectCreditRefusalIsNotAFailure() = runTest(dispatcher) {
        val script = Script(thread(credit = credit(remainingMs = 1_000)))
        script.failsSending = ApiError.DailyCreditExhausted(message = "Épuisé.", credit = credit(remainingMs = 0))
        val model = model(script)
        model.load()

        model.draft = "Un"
        model.sendDraft()
        until("la bulle attend demain") { model.messages.lastOrNull()?.delivery?.isWaitingForCredit == true }
        assertEquals(ChatTurnState.Idle, model.turn)
        assertTrue(model.isCreditExhausted)
    }

    /**
     * Ce qui attend le crédit de demain sur le disque se rouvre en « Partira
     * demain », et ne se décompte pas du crédit d'aujourd'hui.
     */
    @Test
    fun aTurnWaitingForCreditReopensAsLeavingTomorrow() = runTest(dispatcher) {
        val tomorrow = Instant.now().plusSeconds(3_600)
        val script = Script(thread(credit = credit(remainingMs = 60_000)))
        script.waiting = listOf(
            OutgoingTurn(id = "w-1", body = OutgoingTurn.Body.Text("Hier soir"), waitingForCreditUntil = tomorrow),
            OutgoingTurn(id = "w-2", body = OutgoingTurn.Body.Text("Ce matin")),
        )
        val model = model(script)
        model.load()

        assertEquals(listOf(ChatDelivery.WaitingForCredit(until = tomorrow), ChatDelivery.Sending), model.messages.map { it.delivery })
        assertEquals(60_000 - 8 * 75, model.dailyCredit?.remainingMs, "Seul « Ce matin » entame aujourd'hui.")
    }

    /**
     * Refusé hier soir jusqu'à minuit, rouvert ce matin : l'attente est échue.
     * La bulle n'est plus « Partira demain » — la file l'enverra dès la
     * reconnexion —, et son coût entame le crédit d'aujourd'hui, celui du jour
     * où il part.
     */
    @Test
    fun aTurnWhoseWaitIsOverReopensAsSendingAndCountsToday() = runTest(dispatcher) {
        val midnight = Instant.now().minusSeconds(8 * 3_600)
        val script = Script(thread(credit = credit(remainingMs = 300_000)))
        script.waiting = listOf(OutgoingTurn(id = "hier", body = OutgoingTurn.Body.Text("a".repeat(2_400)), waitingForCreditUntil = midnight))
        val model = model(script)
        model.load()

        assertEquals(listOf<ChatDelivery>(ChatDelivery.Sending), model.messages.map { it.delivery }, "Plus « Partira demain » : il part à la reconnexion.")
        assertEquals(120_000, model.dailyCredit?.remainingMs, "Trois minutes de texte, comptées aujourd'hui.")
    }

    /**
     * Le reçu du tour qui vide le crédit apporte la bulle « reviens demain » et
     * son bouton ; touché ou ignoré, c'est retenu par bulle, d'un écran à
     * l'autre.
     */
    @Test
    fun theExhaustedNoticeCarriesACallToActionWhoseStateIsRemembered() = runTest(dispatcher) {
        val script = Script(thread(credit = credit(remainingMs = 1_000)))
        script.receiptFor = { turn ->
            ChatTurnReceipt(
                messages = listOf(
                    traveller(turn.id, "Fin", seq = 1),
                    ChatMessage(
                        id = "notice",
                        author = ChatAuthor.Memo,
                        body = ChatMessageBody.Text(DailyCreditCopy.exhaustedMessage),
                        sentAt = Instant.now(),
                        seq = 2,
                        callToAction = ChatCallToAction.dailyCreditSubscribe,
                    ),
                ),
                turn = ChatTurnStatus.Idle,
                now = Instant.now(),
                dailyCredit = DailyCredit(usedMs = DailyCredit.Catalog.limitMs),
            )
        }
        val memory = ChatCallToActionMemory.inMemory()
        val model = model(script, memory)
        model.load()

        model.draft = "Fin"
        model.sendDraft()
        until("la bulle de MEMO arrive") { model.messages.any { it.id == "notice" } }
        assertEquals(ChatCallToAction.dailyCreditSubscribe, model.messages.last().callToAction)
        assertTrue(model.isCreditExhausted)
        assertEquals(ChatCallToActionState.Pending, model.callToActionState("notice"))

        model.followCallToAction("notice")
        assertEquals(ChatCallToActionState.Followed, model.callToActionState("notice"))

        val reopened = model(script, memory)
        assertEquals(ChatCallToActionState.Followed, reopened.callToActionState("notice"), "Retenu sur l'appareil, pas sur l'écran.")
        reopened.dismissCallToAction("notice")
        assertEquals(ChatCallToActionState.Dismissed, memory.state("notice"))
    }

    /**
     * Hors ligne, le vocal de l'accueil coupé par la limite arrive avec la
     * bulle « reviens demain » de l'app ; celle du serveur la remplace au retour
     * — une seule, et la vraie.
     */
    @Test
    fun theLocalNoticeIsReplacedByTheServers() = runTest(dispatcher) {
        // Un voyage à part : le dernier crédit connu de chaque voyage se garde le
        // temps que l'app vive, et les autres tests en laissent sur « trip ».
        val offlineThread = ChatThread(
            id = "trip-offline",
            title = "Rome 2026",
            context = ChatContext(tripId = "trip-offline", stepId = null),
            now = Instant.now(),
            dailyCredit = credit(remainingMs = 4_000),
        )
        val script = Script(offlineThread)
        script.isOffline = true
        val model = model(script)
        val audio = RecordedAudio(data = "vocal".toByteArray(), filename = "v.m4a", mimeType = "audio/mp4", duration = 4.0, recordedAt = Instant.now())
        val handoff = RecordingHandoff(audio = audio, levels = emptyList(), stoppedAtLimit = true)
        model.expect(handoff)
        model.load()

        assertTrue(model.isOffline)
        assertEquals(handoff.id, model.messages.firstOrNull()?.id)
        val local = assertNotNull(model.messages.lastOrNull())
        assertTrue(local.id.startsWith(ChatModel.localNoticePrefix))
        assertEquals(ChatCallToAction.dailyCreditSubscribe, local.callToAction)
        assertTrue(model.isCreditExhausted, "Le vocal coupé a vidé le crédit.")

        // Le réseau revient : le vocal arrive, avec la bulle du serveur.
        val serverNotice = ChatMessage(
            id = "server-notice",
            author = ChatAuthor.Memo,
            body = ChatMessageBody.Text(DailyCreditCopy.exhaustedMessage),
            sentAt = Instant.now(),
            seq = 9,
            callToAction = ChatCallToAction.dailyCreditSubscribe,
        )
        script.goOnline(offlineThread.copy(messages = listOf(serverNotice)))
        script.deliver(
            ChatTurnDelivery(
                id = handoff.id,
                tripId = "trip-offline",
                state = ChatDelivery.Sent,
                receipt = ChatTurnReceipt(messages = listOf(serverNotice), turn = ChatTurnStatus.Idle, now = Instant.now()),
            ),
        )
        until("la bulle du serveur chasse celle de l'app") {
            model.messages.any { it.id == "server-notice" } && model.messages.none { it.id.startsWith(ChatModel.localNoticePrefix) }
        }
    }

    // MARK: - Le crédit servi et le crédit estimé

    /**
     * Rouvrir le fil hors ligne repart du dernier crédit **servi**, moins ce qui
     * attend dans la file — une fois. Le décompte n'est pas retenu : trois
     * réouvertures ne retirent pas trois fois le même texte.
     */
    @Test
    fun reopeningOfflineDoesNotSpendTheQueueTwice() = runTest(dispatcher) {
        val tripId = "trip-reopened-offline"
        val offline = ChatThread(
            id = tripId,
            title = "Rome 2026",
            context = ChatContext(tripId = tripId, stepId = null),
            now = Instant.now(),
            dailyCredit = credit(remainingMs = 300_000),
        )
        for (opening in 1..3) {
            // Un transport neuf à chaque ouverture, comme l'écran en reçoit un
            // d'`AppDependencies` ; le dernier crédit servi, lui, se garde d'un
            // écran à l'autre.
            val script = Script(offline)
            script.isOffline = true
            // Mille six cents caractères : deux minutes de crédit.
            script.waiting = listOf(OutgoingTurn(id = "queued", body = OutgoingTurn.Body.Text("a".repeat(1_600))))
            val model = model(script)
            model.load()
            assertTrue(model.isOffline)
            assertEquals(180_000, model.dailyCredit?.remainingMs, "Ouverture n° $opening : le texte en file, une fois.")
            model.load()
            assertEquals(180_000, model.dailyCredit?.remainingMs, "Recharger le même écran non plus.")
            model.teardown()
        }
    }

    /**
     * Hors ligne, le dernier crédit retenu par un fil ne passe plus devant un
     * cache plus récent : retenu à 9 h (rien consommé), il cède devant celui
     * que l'accueil a relu à 14 h, après les 4 minutes d'un co-voyageur.
     */
    @Test
    fun offlineTheFresherOfRememberedAndCachedCreditWins() = runTest(dispatcher) {
        val tripId = "trip-retenu-puis-relu"
        ChatModel.forgetRememberedCredits()
        val online = ChatThread(
            id = tripId,
            title = "Rome 2026",
            context = ChatContext(tripId = tripId, stepId = null),
            now = Instant.now(),
            dailyCredit = credit(remainingMs = 300_000),
        )
        val morning = model(Script(online))
        morning.load()
        assertEquals(300_000, morning.dailyCredit?.remainingMs)
        morning.teardown()

        // Dans le métro : le fil local porte le crédit des caches, plus avancé.
        val script = Script(online.copy(dailyCredit = credit(remainingMs = 60_000)))
        script.isOffline = true
        val afternoon = model(script)
        afternoon.load()
        assertTrue(afternoon.isOffline)
        assertEquals(60_000, afternoon.dailyCredit?.remainingMs, "Le plus consommé du jour, pas le premier retenu.")
    }

    /**
     * Le crédit retenu appartient au compte qui l'a lu : déconnecté, il est
     * oublié. B, connecté après A (abonné) sur le même téléphone, ne se croit
     * pas illimité hors ligne, et sa session n'apprend rien.
     */
    @Test
    fun theRememberedCreditDoesNotFollowTheNextAccount() = runTest(dispatcher) {
        val tripId = "trip-partage-entre-comptes"
        ChatModel.forgetRememberedCredits()
        val thread = ChatThread(
            id = tripId,
            title = "Rome 2026",
            context = ChatContext(tripId = tripId, stepId = null),
            now = Instant.now(),
            dailyCredit = credit(remainingMs = 300_000, isUnlimited = true),
        )
        val alice = model(Script(thread))
        alice.load()
        assertEquals(true, alice.credit?.isUnlimited)
        alice.teardown()

        // A se déconnecte — ce que fait `AppDependencies.forgetAccountContent()`.
        ChatModel.forgetRememberedCredits()

        val script = Script(thread.copy(dailyCredit = credit(remainingMs = 180_000)))
        script.isOffline = true
        val session = SubscriptionSession()
        val bob = model(script)
        bob.subscription = session
        bob.load()

        assertEquals(false, bob.credit?.isUnlimited, "Le fil de B compte.")
        assertEquals(180_000, bob.credit?.remainingMs)
        assertNull(session.known, "La session de B n'apprend pas l'abonnement de A.")
        assertEquals(PaywallVariant.FirstTime, session.paywallVariant)
    }

    /**
     * Une lecture du fil pendant qu'un tour monte ne rend pas son coût : le
     * serveur ne l'a pas encore reçu, son chiffre ne le compte pas. Le reçu,
     * lui, remet le chiffre du serveur.
     */
    @Test
    fun aReadDuringASendKeepsTheTurnCounted() = runTest(dispatcher) {
        val script = Script(thread(credit = credit(remainingMs = 200_000)))
        script.sendDelayMs = 400
        val cost = 11 * 75
        val afterTheTurn = credit(remainingMs = 200_000 - cost)
        script.receiptFor = { ChatTurnReceipt(messages = emptyList(), turn = ChatTurnStatus.Idle, now = Instant.now(), dailyCredit = afterTheTurn) }
        script.updates += ChatThreadUpdate(messages = emptyList(), turn = ChatTurnStatus.Idle, now = Instant.now(), dailyCredit = credit(remainingMs = 200_000))
        val model = model(script)
        model.load()

        model.draft = "Dix lettres"
        model.sendDraft()
        assertEquals(200_000 - cost, model.dailyCredit?.remainingMs)

        // Une lecture pendant que le tour monte : le chiffre servi, sans lui.
        model.refreshAfterSubscribing()
        until("la lecture est passée") { script.polls == 1 }
        delay(50)
        assertEquals(200_000 - cost, model.dailyCredit?.remainingMs, "La barre ne remonte pas de ce qui est en route.")

        until("le reçu") { model.messages.last().delivery == ChatDelivery.Sent }
        assertEquals(200_000 - cost, model.dailyCredit?.remainingMs, "Le reçu le compte, une fois.")
    }

    /**
     * Une correction « à la main » refusée — faute de crédit, ou autrement —
     * garde son brouillon : le texte revient dans le champ, sur la même fiche,
     * et le renvoyer la corrige bien.
     */
    @Test
    fun aRefusedHandEditKeepsItsDraft() = runTest(dispatcher) {
        val script = Script(
            thread(
                messages = listOf(card("c", entryId = "e1", text = "le texte de MEMO", phase = TranscriptCard.Phase.Ready, seq = 1)),
                credit = credit(remainingMs = 60_000),
            ),
        )
        script.failsEditing = ApiError.DailyCreditExhausted(message = "Épuisé.", credit = credit(remainingMs = 0))
        val model = model(script)
        model.load()

        model.edit(model.messages[0])
        model.draft = "le texte de MEMO, et la suite que j’ai tapée"
        model.sendDraft()

        until("le refus") { model.errorMessage != null }
        assertEquals("le texte de MEMO, et la suite que j’ai tapée", model.draft, "Rien de ce qu'on a tapé ne se perd.")
        assertTrue(model.isEditingTranscript)
        assertEquals(ChatComposerMode.Writing, model.composer)
        assertTrue(model.isCreditExhausted, "Le solde du refus fait foi.")

        // Le crédit revient (un abonnement, minuit) : le même brouillon corrige
        // la même fiche.
        script.failsEditing = null
        script.updates += ChatThreadUpdate(messages = emptyList(), turn = ChatTurnStatus.Idle, now = Instant.now(), dailyCredit = credit(remainingMs = 60_000))
        model.refreshAfterSubscribing()
        until("le crédit revient") { !model.isCreditExhausted }
        model.sendDraft()
        until("la correction repart") { script.edited.size == 2 }
        assertEquals("e1", script.edited.last().first)
    }

    /**
     * La file rejoue son dernier mot à chaque fil qui s'ouvre — ici le reçu d'un
     * tour parti ce matin. Le fil vient de lire un crédit plus frais : le vieux
     * reçu ne le défait pas. Un refus rejoué ne retire pas non plus l'illimité
     * que le fil vient de lire.
     */
    @Test
    fun aReplayedReceiptDoesNotUndoAFresherCredit() = runTest(dispatcher) {
        val script = Script(thread(credit = credit(remainingMs = 30_000)))
        val model = model(script)
        model.load()
        assertEquals(30_000, model.dailyCredit?.remainingMs)

        val morning = ChatTurnReceipt(
            messages = emptyList(),
            turn = ChatTurnStatus.Idle,
            now = Instant.now().minusSeconds(5 * 3_600),
            dailyCredit = credit(remainingMs = 240_000),
        )
        script.deliver(ChatTurnDelivery(id = "matin", tripId = "trip", state = ChatDelivery.Sent, receipt = morning).replayed)
        delay(100)
        assertEquals(30_000, model.dailyCredit?.remainingMs, "Le reçu de 10 h ne rend pas 4:00 à 15 h.")

        // Le même mot, s'il était neuf, ferait foi : c'est le rejeu seul qui ne
        // passe pas.
        script.deliver(
            ChatTurnDelivery(
                id = "neuf",
                tripId = "trip",
                state = ChatDelivery.Sent,
                receipt = ChatTurnReceipt(messages = emptyList(), turn = ChatTurnStatus.Idle, now = Instant.now(), dailyCredit = credit(remainingMs = 20_000)),
            ),
        )
        until("le reçu neuf fait foi") { model.dailyCredit?.remainingMs == 20_000 }
    }

    /**
     * Hors ligne, le fil n'a pas lu le serveur : un mot rejoué se fond dans ce
     * qu'il tient — le plus consommé du jour, et l'illimité s'il est su.
     */
    @Test
    fun aReplayedWordMergesIntoTheOfflineCredit() = runTest(dispatcher) {
        val tripId = "trip-rejeu-hors-ligne"
        ChatModel.forgetRememberedCredits()
        val offline = ChatThread(
            id = tripId,
            title = "Rome 2026",
            context = ChatContext(tripId = tripId, stepId = null),
            dailyCredit = credit(remainingMs = 30_000, isUnlimited = true),
        )
        val script = Script(offline)
        script.isOffline = true
        val model = model(script)
        model.load()
        assertTrue(model.isOffline)

        script.deliver(
            ChatTurnDelivery(
                id = "refus",
                tripId = tripId,
                state = ChatDelivery.WaitingForCredit(until = Instant.now().plusSeconds(3_600)),
                credit = credit(remainingMs = 0),
            ).replayed,
        )
        delay(100)
        assertEquals(true, model.dailyCredit?.isUnlimited, "Un refus rejoué ne retire pas l'illimité.")
        assertEquals(0, model.dailyCredit?.remainingMs, "Le plus consommé du jour.")
    }

    // MARK: - Trop long pour une journée

    /**
     * La file dit qu'un tour coûte plus qu'une journée : sa bulle propose
     * l'illimité, ne se décompte pas, et le crédit d'aujourd'hui n'est pas
     * déclaré épuisé pour autant.
     */
    @Test
    fun aTurnLongerThanADayWaitsForUnlimited() = runTest(dispatcher) {
        val script = Script(thread(credit = credit(remainingMs = 240_000)))
        script.queuesSends = true
        val model = model(script)
        model.load()

        model.draft = "a".repeat(3_000) // 3:45, dans le reste
        model.sendDraft()
        val id = assertNotNull(model.messages.lastOrNull()).id
        until("le composeur se rouvre") { model.turn == ChatTurnState.Idle }

        script.deliver(ChatTurnDelivery(id = id, tripId = "trip", state = ChatDelivery.WaitingForUnlimited, credit = credit(remainingMs = 240_000)))
        until("la bulle attend l'illimité") { model.messages.last().delivery == ChatDelivery.WaitingForUnlimited }
        assertFalse(model.isCreditExhausted)
        assertEquals(240_000, model.dailyCredit?.remainingMs, "Il ne part pas aujourd'hui : il ne coûte rien aujourd'hui.")

        // L'abonnement le libère : la file le dit, la bulle repart.
        script.deliver(ChatTurnDelivery(id = id, tripId = "trip", state = ChatDelivery.Sending))
        until("la bulle repart") { model.messages.last().delivery == ChatDelivery.Sending }
    }

    /** Ce qui attend l'illimité sur le disque se rouvre comme tel ; un refus direct « trop long » — sans file — aussi. */
    @Test
    fun aTurnWaitingForUnlimitedReopensAsSuch() = runTest(dispatcher) {
        val script = Script(thread(credit = credit(remainingMs = 60_000)))
        script.waiting = listOf(OutgoingTurn(id = "long", body = OutgoingTurn.Body.Text("…"), waitingForUnlimited = true))
        script.failsSending = ApiError.Server(statusCode = 422, code = ApiError.DAILY_CREDIT_TOO_LONG_CODE, message = "Trop long.")
        val model = model(script)
        model.load()

        assertEquals(listOf<ChatDelivery>(ChatDelivery.WaitingForUnlimited), model.messages.map { it.delivery })
        assertEquals(60_000, model.dailyCredit?.remainingMs)

        model.draft = "Encore"
        model.sendDraft()
        until("la bulle attend l'illimité") { model.messages.last().delivery == ChatDelivery.WaitingForUnlimited }
        assertEquals(ChatTurnState.Idle, model.turn)
        assertNull(model.errorMessage, "Pas un échec à réessayer.")
        assertEquals(60_000, model.dailyCredit?.remainingMs)
    }

    /**
     * « Supprimer », sous une bulle qui attend l'illimité, une fois confirmé :
     * la bulle quitte le fil, et la file oublie le tour. Une bulle qui attend le
     * réseau — peut-être déjà en route — ne se supprime pas d'ici.
     */
    @Test
    fun aTurnWaitingForUnlimitedCanBeDiscarded() = runTest(dispatcher) {
        val script = Script(thread(credit = credit(remainingMs = 60_000)))
        script.waiting = listOf(
            OutgoingTurn(id = "long", body = OutgoingTurn.Body.Text("…"), waitingForUnlimited = true),
            OutgoingTurn(id = "metro", body = OutgoingTurn.Body.Text("Dans le métro")),
        )
        val model = model(script)
        model.load()

        model.discardWaitingTurn("metro")
        assertEquals(listOf("long", "metro"), model.messages.map { it.id }, "Une bulle en route ne se supprime pas.")

        model.discardWaitingTurn("long")
        assertEquals(listOf("metro"), model.messages.map { it.id })
        until("la file l'oublie") { script.discarded == listOf("long") }
    }

    /**
     * Hors ligne, sans rien savoir du crédit — un voyage que les caches ne
     * chiffrent pas —, l'écran plafonne au pot du catalogue, moins ce qui attend
     * dans la file : un vocal coupe à la limite, un texte trop long ne part pas.
     * Un abonné que la session connaît ne compte rien ; en ligne, sans crédit
     * servi, rien non plus.
     */
    @Test
    fun offlineWithoutAKnownCreditCapsAtTheCatalogue() = runTest(dispatcher) {
        val tripId = "trip-sans-credit"
        ChatModel.forgetRememberedCredits()
        val unknown = ChatThread(id = tripId, title = "Rome 2026", context = ChatContext(tripId = tripId, stepId = null))
        val script = Script(unknown)
        script.isOffline = true
        script.waiting = listOf(OutgoingTurn(id = "queued", body = OutgoingTurn.Body.Text("a".repeat(800))))
        val model = model(script)
        model.load()

        assertTrue(model.isOffline)
        assertNull(model.dailyCredit, "Rien de servi.")
        assertEquals(240_000, model.credit?.remainingMs, "Cinq minutes, moins la minute qui attend.")
        assertEquals(false, model.credit?.isUnlimited)
        model.composer = ChatComposerMode.Writing
        model.draft = "a".repeat(3_201)
        assertTrue(model.draftExceedsCredit)
        model.draft = "Court"
        assertFalse(model.draftExceedsCredit)

        val session = SubscriptionSession()
        session.learn(isUnlimited = true, hasSubscribedBefore = true)
        model.subscription = session
        assertNull(model.credit, "Un abonné connu de la session ne compte rien.")

        val online = model(Script(unknown))
        online.load()
        assertFalse(online.isOffline)
        assertNull(online.credit, "En ligne, un serveur qui ne sert pas de crédit ne fait pas compter.")
    }

    /**
     * Le fil hors ligne reprend le crédit que l'accueil a gardé — rechargé s'il
     * date d'hier : épuisé la veille, il est plein ce matin.
     */
    @Test
    fun theOfflineThreadRefreshesYesterdaysCredit() {
        val yesterday = DailyCredit(usedMs = DailyCredit.Catalog.limitMs, resetsAt = Instant.now().minusSeconds(3_600))
        val trip = Trip(id = "trip-hier", title = "Rome 2026", stage = TripStage.Ongoing, dailyCredit = yesterday)
        val offline = ChatThread.offline(trip = trip, traveller = null, isNew = false)
        assertEquals(false, offline.dailyCredit?.isExhausted)
        assertEquals(DailyCredit.Catalog.limitMs, offline.dailyCredit?.remainingMs)

        val today = DailyCredit(usedMs = 120_000, resetsAt = Instant.now().plusSeconds(3_600))
        val tripToday = Trip(id = "trip-jour", title = "Rome 2026", stage = TripStage.Ongoing, dailyCredit = today)
        assertEquals(today, ChatThread.offline(trip = tripToday, traveller = null, isNew = false).dailyCredit)
    }
}
