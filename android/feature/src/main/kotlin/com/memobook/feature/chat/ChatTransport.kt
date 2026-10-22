package com.memobook.feature.chat

import com.memobook.core.ChatAuthor
import com.memobook.core.ChatDelivery
import com.memobook.core.ChatDisposition
import com.memobook.core.ChatMessage
import com.memobook.core.ChatMessageBody
import com.memobook.core.ChatPhotoUpload
import com.memobook.core.ChatPhotosTurn
import com.memobook.core.ChatTextTurn
import com.memobook.core.ChatThread
import com.memobook.core.ChatThreadUpdate
import com.memobook.core.ChatTurnReceipt
import com.memobook.core.ChatVoiceTurn
import com.memobook.core.DailyCredit
import com.memobook.core.Entry
import com.memobook.core.EntryEdit
import com.memobook.core.EntryKind
import com.memobook.core.PhotoAttachment
import com.memobook.core.Status
import com.memobook.core.VoiceNote
import com.memobook.networking.ApiError
import com.memobook.networking.MemoBookApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import java.net.URI
import java.time.Instant
import java.util.UUID
import kotlin.math.roundToInt

/**
 * Un tour que le voyageur envoie — ce que [ChatTransport.send] reçoit. Jumeau
 * de `OutgoingTurn` (`ChatTransport.swift`).
 *
 * L'identifiant est **fabriqué par l'app** et devient celui du message côté
 * serveur : la bulle optimiste et la bulle servie sont la même, et un renvoi
 * après une panne de transport tombe sur l'existant au lieu d'un doublon.
 *
 * @property waitingForCreditUntil le tour attend, sur le disque de la file,
 *   que le crédit du jour se recharge — `PendingTurn.waitingForCreditUntil`.
 *   `null` pour un tour qu'on vient de dire, ou qui n'attend que le réseau.
 *   C'est ce qui fait rouvrir le fil sur une bulle « Partira demain » plutôt
 *   que sur « en cours d'envoi ».
 * @property waitingForUnlimited le tour attend, sur le disque de la file, que
 *   le compte passe en illimité : il coûte plus qu'une journée entière de
 *   crédit — `PendingTurn.waitingForUnlimited`. Le fil se rouvre alors sur une
 *   bulle « Trop long pour une journée ».
 */
data class OutgoingTurn(
    val id: String = UUID.randomUUID().toString().lowercase(),
    val stepId: String? = null,
    val body: Body,
    val waitingForCreditUntil: Instant? = null,
    val waitingForUnlimited: Boolean = false,
) {
    sealed interface Body {
        /**
         * Un texte libre, ou une puce ([suggestionId]), ou une commande
         * silencieuse. [entryId] vise le souvenir de « Ça me convient ».
         */
        data class Text(val text: String, val suggestionId: String? = null, val entryId: String? = null) : Body

        data class Voice(val audio: RecordedTurnAudio) : Body

        data class Photos(val photos: List<ChatPhotoUpload>, val capturedAt: Instant) : Body
    }

    /**
     * Le tour est retenu sur le disque — par le crédit de demain, ou par
     * l'illimité. Ni l'un ni l'autre n'entame le crédit d'aujourd'hui.
     *
     * **Une attente échue ne retient plus rien** (03/10/2026) : refusé hier à
     * 22 h jusqu'à minuit, le tour repart au prochain vidage, sur le crédit du
     * jour où il part — comme `PendingTurn.isOnHold` côté disque. Lu sans la
     * date, il se rouvrait le lendemain en « Partira demain », hors du
     * décompte du jour, alors que la file l'enverrait dès la reconnexion.
     */
    val isOnHold: Boolean get() = waitingForUnlimited || isWaitingForCredit()

    /** Le tour attend encore le crédit du jour à cet instant. */
    fun isWaitingForCredit(at: Instant = Instant.now()): Boolean {
        val until = waitingForCreditUntil ?: return false
        return until > at
    }

    /**
     * Ce que ce tour coûtera au crédit du jour, d'après ce que l'app en sait
     * — l'estimation qu'elle tient entre deux réponses du serveur, qui tranche
     * (`services/dailyCredit.ts`). Un vocal, sa durée ; un texte libre, ses
     * caractères ; une puce ou une commande silencieuse (`suggestionId`), rien
     * — le serveur ne fait payer qu'un texte qui n'est pas exactement son
     * libellé, et l'app envoie toujours le libellé ; des photos, rien.
     */
    fun creditCost(credit: DailyCredit): Int = when (body) {
        is Body.Text -> if (body.suggestionId == null) credit.cost(ofText = body.text) else 0
        is Body.Voice -> (body.audio.durationSeconds * 1000).roundToInt()
        is Body.Photos -> 0
    }

    /**
     * Le tour coûte **plus qu'une journée entière** de crédit : le serveur le
     * refusera même pot plein — un vocal au-delà de la limite et de la
     * tolérance, un texte libre au-delà de la limite. Attendre demain ne
     * servirait à rien (03/10/2026). Jamais une puce ni des photos.
     */
    fun exceedsAWholeDay(credit: DailyCredit): Boolean {
        if (credit.isUnlimited) return false
        return creditCost(credit) > credit.limitWithTolerance(forVoice = body is Body.Voice)
    }

    /** Pour les fabriques posées ailleurs — `OutgoingTurn.voice` (`RecordingOutbox.kt`). */
    companion object
}

/**
 * Le vocal d'un tour : les octets, et ce qu'il faut pour les décompter et les
 * dessiner. Jumeau de `RecordedTurnAudio`.
 *
 * Les octets se comparent par contenu, comme les `Data` d'iOS.
 *
 * @property durationSeconds en secondes, comme le `TimeInterval` d'iOS.
 */
data class RecordedTurnAudio(
    val data: ByteArray,
    val filename: String,
    val mimeType: String,
    val capturedAt: Instant,
    val durationSeconds: Double,
    val levels: List<Double>,
    val placeLabel: String? = null,
) {
    override fun equals(other: Any?): Boolean =
        other is RecordedTurnAudio && data.contentEquals(other.data) && filename == other.filename &&
            mimeType == other.mimeType && capturedAt == other.capturedAt && durationSeconds == other.durationSeconds &&
            levels == other.levels && placeLabel == other.placeLabel

    override fun hashCode(): Int =
        listOf(data.contentHashCode(), filename, mimeType, capturedAt, durationSeconds, levels, placeLabel).hashCode()
}

/**
 * Ce qu'un envoi a donné : le serveur a reçu — voici les bulles écrites —, ou
 * le tour attend le réseau sur le disque et partira tout seul. Ce second cas
 * **n'est pas un échec** : la bulle reste « en cours d'envoi », et c'est la
 * file qui la terminera ([ChatTransport.deliveries]).
 */
sealed interface ChatSendOutcome {
    data class Received(val receipt: ChatTurnReceipt) : ChatSendOutcome
    data object Queued : ChatSendOutcome
}

/**
 * Le sort d'un tour parti par la file, suivi de bout en bout par son
 * identifiant. Le carnet est là pour que la conversation d'un autre voyage n'y
 * touche pas ; le reçu voyage avec, pour que le fil fusionne ce que le serveur
 * a écrit et se mette à attendre MEMO.
 *
 * @property credit le crédit du jour que le serveur a rendu avec un refus faute
 *   de crédit ([ChatDelivery.WaitingForCredit]) : la barre passe à « épuisé »
 *   sans attendre de relire le fil. `null` le reste du temps — un reçu porte
 *   le sien.
 * @property isReplay ce mot n'est pas nouveau : la file le **rejoue** à qui se
 *   met à l'écoute (`RecordingOutbox.turnDeliveries`), pour qu'un écran ouvert
 *   après l'arrivée d'un vocal ne l'attende pas pour rien. Son état vaut
 *   toujours pour la bulle ; son crédit, lui, peut dater de l'envoi d'il y a
 *   des heures — il ne remplace jamais celui que le fil vient de lire
 *   (03/10/2026).
 */
data class ChatTurnDelivery(
    val id: String,
    val tripId: String,
    val state: ChatDelivery,
    val receipt: ChatTurnReceipt? = null,
    val credit: DailyCredit? = null,
    val isReplay: Boolean = false,
) {
    /** Le même mot, marqué comme rejoué. */
    val replayed: ChatTurnDelivery get() = copy(isReplay = true)
}

/**
 * Ce que `ChatModel` sait faire avec le monde extérieur, sous forme de
 * **fonctions-sources** — la préférence n° 1 de `ios/CLAUDE.md`, comme les
 * fonctions de `TripSettingsModel`. Jumeau de `ChatTransport.swift`.
 *
 * Deux constructeurs, **un seul chemin de code dans le modèle** : [remote]
 * parle au serveur par [MemoBookApi] ; [local] rejoue le même contrat en
 * mémoire avec le moteur de règles, pour les aperçus, les tests et
 * `previewSignedIn`. Le modèle ne sait pas lequel il tient.
 *
 * Les `var` du `struct` Swift, que `AppDependencies` réaffecte une à une, sont
 * ici des `val` d'une `data class` : on les remplace par [copy].
 *
 * @property load le fil entier, tel que le serveur le sert.
 * @property poll la suite du fil depuis un instant — le `now` de la lecture précédente.
 * @property send un tour de parole. Rend le reçu — les bulles écrites, l'état
 *   du tour — ou dit que le tour attend le réseau.
 * @property editTranscript « À la main » : le texte corrigé fait autorité
 *   (`PATCH /v1/entries/:id`).
 * @property media le fichier d'un vocal ou d'une photo, avec la session.
 * @property waiting ce qui attend le réseau sur le disque **pour ce fil** — les
 *   tours que la file n'a pas encore fait partir. Le modèle les pose en bulles
 *   « en cours d'envoi » à l'ouverture : un texte dit dans le métro ne
 *   disparaît pas du fil parce qu'on a quitté l'écran et qu'on y revient
 *   (`docs/conversation.md` § 9). Vide sans file.
 * @property deliveries le sort des tours partis par la file, au fil de l'eau —
 *   le vocal de l'accueil, un message d'ici qui attendait le réseau. Un flux et
 *   non une valeur observée : deux tours qui partent dans la même seconde font
 *   deux événements, et une bulle ne doit rater ni l'un ni l'autre. Commence
 *   par le dernier connu, pour l'écran ouvert après l'arrivée. Se tait sans
 *   file.
 * @property offlineThread le fil à ouvrir quand [load] a échoué — sans réseau,
 *   ou pour un voyage créé hors ligne que le serveur n'a pas encore reçu.
 *   `null` : il n'y en a pas, et l'échec se dit. Le modèle reçoit l'erreur pour
 *   que la décision reste ici : une panne du serveur ne se cache pas derrière
 *   un fil local.
 * @property discard oublie un tour qui attend sur le disque — « Supprimer »,
 *   sous une bulle qui attend l'illimité (03/10/2026) : sans abonnement, rien
 *   ne le ferait jamais partir, et sa bulle se reposerait à chaque ouverture.
 *   `false` quand la file ne le retient pas — il n'y est pas, ou il est en
 *   train de partir. Rien sans file.
 * @property remember garde sur le téléphone ce que le fil vient de lire — ses
 *   derniers messages arrivés —, pour le rouvrir sans réseau (08/10/2026).
 *   Rien sans cache.
 */
data class ChatTransport(
    val load: suspend () -> ChatThread,
    val poll: suspend (since: Instant) -> ChatThreadUpdate,
    val send: suspend (OutgoingTurn) -> ChatSendOutcome,
    val editTranscript: suspend (entryId: String, text: String) -> Entry,
    val media: suspend (URI) -> ByteArray,
    val waiting: suspend () -> List<OutgoingTurn> = { emptyList() },
    val deliveries: suspend () -> Flow<ChatTurnDelivery> = { emptyFlow() },
    val offlineThread: suspend (Throwable) -> ChatThread? = { null },
    val discard: suspend (turnId: String) -> Boolean = { false },
    val remember: suspend (ChatThread) -> Unit = {},
) {
    /**
     * Ce que [local] demande au fil en mémoire du bac à sable — la
     * `PreviewChatBox` de `PreviewChat.swift`, portée avec le bac à sable
     * (A3b), qui implémente cette interface. Les cinq fonctions dont le
     * transport local se sert, sous leurs noms Swift.
     */
    interface LocalBox {
        suspend fun read(tripId: String): ChatThread
        suspend fun updates(tripId: String, since: Instant): ChatThreadUpdate

        /**
         * Pose la bulle du voyageur, fait répondre MEMO, et date ses bulles
         * **après** le reçu : c'est ce qui les fait arriver au sondage suivant.
         */
        suspend fun send(tripId: String, message: ChatMessage): ChatTurnReceipt
        suspend fun validate(entryId: String): Boolean

        /** « À la main » : le texte corrigé remplace celui de la fiche, qui reste prête. */
        suspend fun edit(entryId: String, text: String)
    }

    companion object {
        // MARK: - Le vrai serveur

        /**
         * Le transport de l'app, **sans la file** : chaque envoi part tout de
         * suite, et rien n'attend. `AppDependencies` le construit, puis pose la
         * file par-dessus `send`, `waiting` et `deliveries` (`RecordingOutbox`)
         * — hors ligne, un tour attend au lieu d'échouer.
         */
        fun remote(api: MemoBookApi, tripId: String): ChatTransport = ChatTransport(
            load = { api.chatThread(tripId) },
            poll = { since -> api.chatUpdates(tripId, since) },
            send = { turn -> ChatSendOutcome.Received(sendNow(turn, tripId, api)) },
            editTranscript = { entryId, text -> api.updateEntry(entryId, EntryEdit.text(text)) },
            media = { url ->
                // `/v1/entries/<id>/media` pour un souvenir,
                // `/v1/chat-messages/<id>/media` pour un vocal du contexte du
                // voyage, qui n'en est pas un. L'identifiant est l'avant-dernier
                // segment, la ressource celui d'avant. Une URL d'une autre forme
                // ne se télécharge pas ici.
                val parts = url.path.orEmpty().split("/").filter { it.isNotEmpty() }
                if (parts.size < 3 || parts.last() != "media") {
                    throw ApiError.Server(statusCode = 0, code = null, message = "Média inconnu.")
                }
                val id = parts[parts.size - 2]
                when (parts[parts.size - 3]) {
                    "entries" -> api.entryMedia(id)
                    "chat-messages" -> api.chatMessageMedia(id)
                    else -> throw ApiError.Server(statusCode = 0, code = null, message = "Média inconnu.")
                }
            },
        )

        /**
         * L'envoi d'un tour au serveur, tel quel — ce que la file appelle
         * quand le réseau est là.
         */
        suspend fun sendNow(turn: OutgoingTurn, tripId: String, api: MemoBookApi): ChatTurnReceipt =
            when (val body = turn.body) {
                is OutgoingTurn.Body.Text -> api.sendChatText(
                    tripId,
                    ChatTextTurn(
                        id = turn.id,
                        text = body.text,
                        stepId = turn.stepId,
                        suggestionId = body.suggestionId,
                        entryId = body.entryId,
                    ),
                )
                is OutgoingTurn.Body.Voice -> api.sendChatVoice(
                    tripId,
                    ChatVoiceTurn(
                        id = turn.id,
                        data = body.audio.data,
                        filename = body.audio.filename,
                        mimeType = body.audio.mimeType,
                        capturedAt = body.audio.capturedAt,
                        durationSeconds = body.audio.durationSeconds,
                        levels = body.audio.levels,
                        placeLabel = body.audio.placeLabel,
                        stepId = turn.stepId,
                    ),
                )
                is OutgoingTurn.Body.Photos -> api.sendChatPhotos(
                    tripId,
                    ChatPhotosTurn(id = turn.id, photos = body.photos, capturedAt = body.capturedAt, stepId = turn.stepId),
                )
            }

        // MARK: - Le moteur local

        /**
         * Le même contrat, sans serveur : le jeu d'essai du voyage et
         * `LocalMemoResponder` derrière un fil en mémoire. Aperçus, tests,
         * `previewSignedIn`.
         *
         * ⚠️ **La boîte n'a pas de valeur par défaut**, quand iOS pose une
         * `PreviewChatBox()` neuve : elle arrive avec le bac à sable (A3b), et
         * c'est à la fusion que `PreviewChatBox` implémente [LocalBox] — d'ici
         * là, l'appelant passe la sienne.
         */
        fun local(tripId: String, box: LocalBox): ChatTransport = ChatTransport(
            load = { box.read(tripId) },
            poll = { since -> box.updates(tripId, since) },
            send = { turn ->
                val message = when (val body = turn.body) {
                    is OutgoingTurn.Body.Text -> {
                        if (body.suggestionId == "accept" && body.entryId != null) box.validate(body.entryId)
                        ChatMessage(
                            id = turn.id,
                            author = ChatAuthor.Traveller,
                            body = ChatMessageBody.Text(body.text),
                            sentAt = Instant.now(),
                            stepId = turn.stepId,
                            disposition = if (body.suggestionId == null) ChatDisposition.Memory else ChatDisposition.Command,
                        )
                    }
                    is OutgoingTurn.Body.Voice -> ChatMessage(
                        id = turn.id,
                        author = ChatAuthor.Traveller,
                        body = ChatMessageBody.Voice(
                            VoiceNote(id = turn.id, duration = body.audio.durationSeconds, levels = body.audio.levels),
                        ),
                        sentAt = body.audio.capturedAt,
                        stepId = turn.stepId,
                        disposition = ChatDisposition.Memory,
                    )
                    is OutgoingTurn.Body.Photos -> ChatMessage(
                        id = turn.id,
                        author = ChatAuthor.Traveller,
                        body = ChatMessageBody.Photos(body.photos.indices.map { PhotoAttachment(id = "${turn.id}-$it") }),
                        sentAt = body.capturedAt,
                        stepId = turn.stepId,
                        disposition = ChatDisposition.Memory,
                    )
                }
                ChatSendOutcome.Received(box.send(tripId, message))
            },
            editTranscript = { entryId, text ->
                box.edit(entryId, text)
                val now = Instant.now()
                Entry(
                    id = entryId,
                    memoId = tripId,
                    kind = EntryKind.Audio,
                    status = Status.Ready,
                    redactionStatus = Status.Ready,
                    editedText = text,
                    editedAt = now,
                    capturedAt = now,
                    createdAt = now,
                )
            },
            media = { throw ApiError.Server(statusCode = 404, code = "not_found", message = "Média introuvable.") },
        )

        /**
         * Un transport qui échoue à tout — l'aperçu de l'état d'erreur, et les
         * tests qui vérifient qu'un échec garde le message.
         */
        fun failing(error: Throwable): ChatTransport = ChatTransport(
            load = { throw error },
            poll = { throw error },
            send = { throw error },
            editTranscript = { _, _ -> throw error },
            media = { throw error },
        )
    }
}
