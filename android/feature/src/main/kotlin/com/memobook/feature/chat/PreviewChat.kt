package com.memobook.feature.chat

import com.memobook.core.ChatAuthor
import com.memobook.core.ChatCallToAction
import com.memobook.core.ChatContext
import com.memobook.core.ChatCopy
import com.memobook.core.ChatDisposition
import com.memobook.core.ChatGreeting
import com.memobook.core.ChatMessage
import com.memobook.core.ChatMessageBody
import com.memobook.core.ChatPhotosTurn
import com.memobook.core.ChatTextTurn
import com.memobook.core.ChatThread
import com.memobook.core.ChatThreadUpdate
import com.memobook.core.ChatTurn
import com.memobook.core.ChatTurnReceipt
import com.memobook.core.ChatTurnStatus
import com.memobook.core.ChatVoiceTurn
import com.memobook.core.DailyCredit
import com.memobook.core.DailyCreditCopy
import com.memobook.core.Entry
import com.memobook.core.EntryKind
import com.memobook.core.EntryValidation
import com.memobook.core.HomeFeed
import com.memobook.core.LocalMemoResponder
import com.memobook.core.MemoBookDate
import com.memobook.core.MemoReply
import com.memobook.core.PhotoAttachment
import com.memobook.core.Status
import com.memobook.core.TranscriptCard
import com.memobook.core.Trip
import com.memobook.core.VoiceNote
import com.memobook.feature.PreviewApi
import com.memobook.feature.SandboxNetwork
import com.memobook.feature.home.fixture
import com.memobook.networking.ApiError
import kotlinx.coroutines.CancellationException
import java.time.Instant

// Le serveur de conversation du double d'API — le jumeau de `PreviewChat.swift`.
//
// Ce fichier expose, au module `:feature` seulement, [PreviewChatBox] (les fils
// en mémoire du bac à sable, un par voyage) et les routes de la conversation de
// `PreviewApi` (`sandboxChatThread`, `sandboxSendChatText`…), que le double
// appelle depuis ses `override`.

/**
 * Le serveur de conversation du double d'API — aperçus, tests, `previewSignedIn`.
 *
 * **Le même chemin que le vrai serveur, sans serveur.** `ChatModel` ne connaît
 * qu'un `ChatTransport` ; ici, derrière `PreviewApi`, un fil en mémoire par
 * voyage, ouvert sur le jeu d'essai, où [LocalMemoResponder] répond à la place
 * de MEMO. Ce que le vrai serveur écrit dans un job, ce double l'écrit tout de
 * suite avec une date d'un instant plus tard : le sondage
 * (`chatUpdates(since)`) le trouve au tour suivant, exactement comme il
 * trouverait la réponse d'un job.
 *
 * Un verrou et non un acteur : chaque section qui le tient est courte et ne
 * suspend pas. [send] le relâche le temps que MEMO réponde — la réentrance de
 * l'acteur d'iOS, au même endroit.
 */
internal class PreviewChatBox : ChatTransport.LocalBox {
    private val lock = Any()
    private val threads = mutableMapOf<String, ChatThread>()
    private val stamps = mutableMapOf<String, MutableMap<String, Instant>>()

    /**
     * Le répondeur **simulé** : sur iOS, `LocalMemoResponder()` l'est en Debug,
     * et le bac à sable n'existe qu'en Debug. `:feature` n'a pas de
     * `BuildConfig` pour le dire — le double, lui, sait où il tourne.
     */
    private val responder = LocalMemoResponder(LocalMemoResponder.VoiceMode.Simulated)

    /**
     * Le jour où la bulle « reviens demain » de chaque voyage a été posée : une
     * fois par voyage et par jour, comme le serveur (`limitNotifiedAt`).
     */
    private val noticedDays = mutableMapOf<String, String>()

    /** À appeler sous [lock]. */
    private fun thread(tripId: String): ChatThread {
        threads[tripId]?.let { return it }
        var fresh = ChatThread.fixture(tripId = tripId)
        if (fresh.isEmpty && fresh.suggestions.isEmpty()) {
            fresh = fresh.copy(suggestions = responder.opening(fresh.context).suggestions)
        }
        threads[tripId] = fresh
        stamps[tripId] = fresh.messages.associate { it.id to distantPast }.toMutableMap()
        return fresh
    }

    /** À appeler sous [lock]. */
    private fun stamp(message: ChatMessage, tripId: String, date: Instant) {
        stamps.getOrPut(tripId) { mutableMapOf() }[message.id] = date
    }

    /**
     * Ouvre le fil d'un voyage créé dans le bac à sable : **vide**, sur l'accueil
     * de MEMO et la puce du contexte, comme le serveur ouvre celui d'un carnet
     * neuf — et non sur l'histoire de Rome du jeu d'essai.
     *
     * Le titre, l'accueil et le contexte sont ceux que
     * `ChatThread.offline(trip, traveller, isNew = true)` poserait
     * (`ChatOfflineThread.swift`, qui se porte avec la conversation) : iOS n'en
     * garde que ces trois-là, recopiés ici.
     */
    fun open(trip: Trip): Unit = synchronized(lock) {
        if (threads[trip.id] != null) return
        val traveller = HomeFeed.fixture.traveller
        val destination = trip.destination
        val context = ChatContext(
            tripId = trip.id,
            tripTitle = trip.title,
            travellerFirstName = traveller.firstName,
            travellerInitials = traveller.firstName.firstOrNull()?.toString()?.uppercase(),
            travellerAvatarUrl = traveller.avatarUrl,
        )
        threads[trip.id] = ChatThread(
            id = trip.id,
            title = trip.title,
            greeting = ChatGreeting(
                title = destination?.let { ChatCopy.greetingTitle(place = it.city ?: it.name, flag = it.flag) }
                    ?: ChatCopy.greetingTitleWithoutPlace,
                message = ChatCopy.greetingMessage,
            ),
            context = context,
            suggestions = responder.opening(context).suggestions,
        )
        stamps[trip.id] = mutableMapOf()
    }

    override suspend fun read(tripId: String): ChatThread = synchronized(lock) { thread(tripId).stamped(now = Instant.now()) }

    override suspend fun updates(tripId: String, since: Instant): ChatThreadUpdate = synchronized(lock) {
        val thread = thread(tripId)
        val changed = thread.messages.filter { (stamps[tripId]?.get(it.id) ?: distantPast) > since }
        ChatThreadUpdate(
            messages = changed,
            suggestions = thread.suggestions,
            preview = thread.preview,
            turn = ChatTurnStatus.Idle,
            now = Instant.now(),
        )
    }

    /**
     * Pose la bulle du voyageur, fait répondre MEMO, et date ses bulles
     * **après** le reçu : c'est ce qui les fait arriver au sondage suivant.
     */
    override suspend fun send(tripId: String, message: ChatMessage): ChatTurnReceipt {
        val now = Instant.now()
        val written = mutableListOf<ChatMessage>()
        val (pending, history) = synchronized(lock) {
            val thread = thread(tripId)
            val messages = thread.messages.toMutableList()

            if (thread.isEmpty) {
                for (beat in responder.opening(thread.context).beats) {
                    val opening = beat.message.stamped(sentAt = now, stepId = null, pause = beat.pauseMilliseconds)
                    messages += opening
                    stamp(opening, tripId, now)
                    written += opening
                }
            }

            val history = messages.toList()
            messages += message
            stamp(message, tripId, now)
            written += message
            thread.copy(messages = messages, suggestions = emptyList()) to history
        }

        val reply = try {
            responder.reply(ChatTurn(message = message, history = history, context = pending.context))
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            MemoReply(beats = emptyList(), suggestions = emptyList())
        }

        synchronized(lock) {
            val later = now.plusMillis(1)
            val messages = pending.messages.toMutableList()
            for (beat in reply.beats) {
                var bubble = beat.message.stamped(sentAt = later, stepId = message.stepId, pause = beat.pauseMilliseconds)
                // Une fiche vient avec l'identifiant de son souvenir, comme sur le
                // serveur : c'est elle qu'on valide et qu'on corrige.
                val body = bubble.body
                if (body is ChatMessageBody.Transcript && body.card.entryId == null) {
                    bubble = bubble.copy(body = ChatMessageBody.Transcript(body.card.identified(entryId = "entry-${message.id}")))
                }
                messages += bubble
                stamp(bubble, tripId, later)
            }
            threads[tripId] = pending.copy(
                messages = messages,
                suggestions = reply.suggestions,
                preview = reply.preview ?: pending.preview,
            )
        }

        return ChatTurnReceipt(messages = written, turn = ChatTurnStatus.Replying(messageId = message.id), now = now)
    }

    /**
     * **La bulle « reviens demain »** (03/10/2026), posée comme le serveur la
     * pose : quand un tour fait tomber le crédit du jour à zéro, ou quand un tour
     * est refusé faute de crédit. Une fois par voyage et par jour ; `null` quand
     * elle l'est déjà. Datée d'un instant plus tard que le tour, pour que le
     * sondage la trouve après lui.
     */
    fun noteCreditExhausted(tripId: String, credit: DailyCredit): ChatMessage? = synchronized(lock) {
        val now = Instant.now()
        val day = credit.day ?: MemoBookDate.format(now).take(10)
        if (noticedDays[tripId] == day) return null
        noticedDays[tripId] = day

        val thread = thread(tripId)
        val later = now.plusMillis(2)
        val notice = ChatMessage(
            id = "memo-daily-credit-$tripId-$day",
            author = ChatAuthor.Memo,
            body = ChatMessageBody.Text(DailyCreditCopy.exhaustedMessage),
            sentAt = later,
            pauseMilliseconds = 900,
            callToAction = ChatCallToAction.dailyCreditSubscribe,
        )
        threads[tripId] = thread.copy(messages = thread.messages + notice)
        stamp(notice, tripId, later)
        notice
    }

    override suspend fun validate(entryId: String): Boolean = synchronized(lock) {
        var found = false
        for ((tripId, thread) in threads.toMap()) {
            val messages = thread.messages.map { message ->
                val body = message.body
                if (body !is ChatMessageBody.Transcript || body.card.entryId != entryId) return@map message
                found = true
                message.copy(body = ChatMessageBody.Transcript(body.card.validated())).also {
                    stamp(it, tripId, Instant.now())
                }
            }
            threads[tripId] = thread.copy(messages = messages)
        }
        found
    }

    /** « À la main » : le texte corrigé remplace celui de la fiche, qui reste prête. */
    override suspend fun edit(entryId: String, text: String): Unit = synchronized(lock) {
        for ((tripId, thread) in threads.toMap()) {
            val messages = thread.messages.map { message ->
                val body = message.body
                if (body !is ChatMessageBody.Transcript || body.card.entryId != entryId) return@map message
                message.copy(body = ChatMessageBody.Transcript(body.card.filled(text = text, isSimulated = false))).also {
                    stamp(it, tripId, Instant.now())
                }
            }
            threads[tripId] = thread.copy(messages = messages)
        }
    }

    fun clear(tripId: String): Unit = synchronized(lock) {
        val thread = thread(tripId).cleared()
        val now = Instant.now()
        val opening = responder.opening(thread.context)
        val messages = opening.beats.map { beat ->
            beat.message.stamped(sentAt = now, stepId = null, pause = beat.pauseMilliseconds).also {
                stamp(it, tripId, now)
            }
        }
        threads[tripId] = thread.copy(messages = messages, suggestions = opening.suggestions)
    }

    private companion object {
        /** Le `.distantPast` d'iOS : avant tout `since` qu'un sondage enverra. */
        val distantPast: Instant = Instant.parse("0001-01-01T00:00:00Z")
    }
}

// region Les routes de la conversation du double
//
// Le crédit du jour voyage avec le fil, ses mises à jour et chaque reçu, comme
// sur le serveur — voir `SandboxCredit` (PreviewSupport.kt). Sur iOS, une
// extension de `PreviewAPI` ; ici, des fonctions que ses `override` appellent :
// Kotlin n'implémente pas une interface par extension.

internal suspend fun PreviewApi.sandboxChatThread(tripId: String): ChatThread {
    SandboxNetwork.failIfOffline()
    return chat.read(tripId).copy(dailyCredit = sandboxCredit(tripId))
}

internal suspend fun PreviewApi.sandboxChatUpdates(tripId: String, since: Instant): ChatThreadUpdate {
    SandboxNetwork.failIfOffline()
    return chat.updates(tripId, since).copy(dailyCredit = sandboxCredit(tripId))
}

internal suspend fun PreviewApi.sandboxSendChatText(tripId: String, turn: ChatTextTurn): ChatTurnReceipt {
    val credit = chargingCredit(tripId) {
        chargeSandboxText(turn.text, suggestionId = turn.suggestionId, turnId = turn.id, tripId = tripId)
    }
    val message = ChatMessage(
        id = turn.id,
        author = ChatAuthor.Traveller,
        body = ChatMessageBody.Text(turn.text),
        sentAt = Instant.now(),
        stepId = turn.stepId,
        disposition = if (turn.suggestionId == null) ChatDisposition.Memory else ChatDisposition.Command,
    )
    val entryId = turn.entryId
    if (turn.suggestionId == "accept" && entryId != null) chat.validate(entryId)
    return receipt(chat.send(tripId, message), tripId, credit)
}

internal suspend fun PreviewApi.sandboxSendChatVoice(tripId: String, turn: ChatVoiceTurn): ChatTurnReceipt {
    val credit = chargingCredit(tripId) {
        chargeSandboxVoice(seconds = turn.durationSeconds, turnId = turn.id, tripId = tripId)
    }
    val message = ChatMessage(
        id = turn.id,
        author = ChatAuthor.Traveller,
        body = ChatMessageBody.Voice(VoiceNote(id = turn.id, duration = turn.durationSeconds, levels = turn.levels)),
        sentAt = turn.capturedAt,
        stepId = turn.stepId,
        disposition = ChatDisposition.Memory,
    )
    return receipt(chat.send(tripId, message), tripId, credit)
}

/**
 * Décompte un tour ; refusé faute de crédit, la bulle « reviens demain » se
 * pose avant que le refus ne remonte — comme le serveur, qui l'écrit dans sa
 * propre petite transaction avant de lever le `429`.
 */
private fun PreviewApi.chargingCredit(tripId: String, charge: () -> DailyCredit): DailyCredit =
    try {
        charge()
    } catch (error: ApiError) {
        if (error.isDailyCreditExhausted) {
            chat.noteCreditExhausted(tripId, credit = error.dailyCredit ?: sandboxCredit(tripId))
        }
        throw error
    }

/**
 * Le reçu, le crédit compté — et, quand ce tour l'a vidé, la bulle « reviens
 * demain » avec lui, comme sur le serveur.
 */
private fun PreviewApi.receipt(receipt: ChatTurnReceipt, tripId: String, credit: DailyCredit): ChatTurnReceipt {
    val notice = if (credit.isExhausted) chat.noteCreditExhausted(tripId, credit) else null
    return ChatTurnReceipt(
        messages = receipt.messages + listOfNotNull(notice),
        turn = receipt.turn,
        now = receipt.now,
        dailyCredit = credit,
    )
}

internal suspend fun PreviewApi.sandboxSendChatPhotos(tripId: String, turn: ChatPhotosTurn): ChatTurnReceipt {
    val attachments = turn.photos.indices.map { index -> PhotoAttachment(id = "${turn.id}-$index") }
    val message = ChatMessage(
        id = turn.id,
        author = ChatAuthor.Traveller,
        body = ChatMessageBody.Photos(attachments),
        sentAt = turn.capturedAt,
        stepId = turn.stepId,
        disposition = ChatDisposition.Memory,
    )
    return chat.send(tripId, message).copy(dailyCredit = sandboxCredit(tripId))
}

internal suspend fun PreviewApi.sandboxValidateEntry(id: String): EntryValidation {
    chat.validate(id)
    val entry = try {
        entry(id)
    } catch (_: ApiError) {
        val now = Instant.now()
        Entry(
            id = id,
            memoId = "preview-memo",
            kind = EntryKind.Audio,
            status = Status.Ready,
            redactionStatus = Status.Ready,
            validatedAt = now,
            capturedAt = now,
            createdAt = now,
        )
    }
    return EntryValidation(entry = entry)
}

internal fun PreviewApi.sandboxClearChat(tripId: String) {
    chat.clear(tripId)
}

// endregion

/**
 * La bulle du répondeur local, datée et rattachée à l'étape — ce que le serveur
 * fait en l'écrivant. Le bouton que le répondeur a posé reste sur la bulle.
 */
private fun ChatMessage.stamped(sentAt: Instant, stepId: String?, pause: Int): ChatMessage =
    ChatMessage(
        id = id,
        author = author,
        body = body,
        sentAt = sentAt,
        stepId = stepId,
        pauseMilliseconds = pause,
        callToAction = callToAction,
    )

private fun ChatThread.stamped(now: Instant): ChatThread =
    ChatThread(
        id = id,
        title = title,
        avatarUrl = avatarUrl,
        destination = destination,
        greeting = greeting,
        preview = preview,
        context = context,
        messages = messages,
        suggestions = suggestions,
        turn = ChatTurnStatus.Idle,
        canClear = true,
        now = now,
    )

private fun TranscriptCard.identified(entryId: String): TranscriptCard =
    TranscriptCard(
        title = title,
        capturedAt = capturedAt,
        placeLabel = placeLabel,
        duration = duration,
        text = text,
        isSimulated = isSimulated,
        entryId = entryId,
        footnote = footnote,
        phase = phase,
        isValidated = isValidated,
    )

private fun TranscriptCard.validated(): TranscriptCard =
    TranscriptCard(
        title = title,
        capturedAt = capturedAt,
        placeLabel = placeLabel,
        duration = duration,
        text = text,
        isSimulated = isSimulated,
        entryId = entryId,
        footnote = footnote,
        phase = phase,
        isValidated = true,
    )
