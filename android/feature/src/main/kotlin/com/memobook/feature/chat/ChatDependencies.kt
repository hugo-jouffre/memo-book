package com.memobook.feature.chat

import com.memobook.core.ChatThread
import com.memobook.core.ChatTurnReceipt
import com.memobook.core.ChatTurnStatus
import com.memobook.core.HomeFeed
import com.memobook.core.Trip
import com.memobook.core.TripDetail
import com.memobook.core.TripDraft
import com.memobook.core.TripStage
import com.memobook.feature.AppDependencies
import com.memobook.feature.ContentCache
import com.memobook.feature.RecordingOutbox
import com.memobook.networking.ApiError
import java.util.Collections
import java.util.WeakHashMap

/**
 * La conversation avec MEMO — `docs/conversation.md`. Jumeau de
 * `AppDependencies.chatModel(tripId:stepId:)`.
 *
 * Le fil vit sur le serveur (`GET`/`POST`/`DELETE /v1/trips/:id/chat`) et MEMO
 * y répond dans un job : le modèle reçoit un [ChatTransport] qui relie ces
 * routes, et **rien d'autre** — il ne sait pas s'il tient le serveur ou le
 * moteur local des aperçus, qui offre le même contrat ([ChatTransport.local]).
 * Pas de cache pour le fil, et c'est voulu : « un fil périmé se lit comme un
 * message perdu ».
 *
 * **Le bac à sable n'a pas de transport à lui** : sous `previewSignedIn`,
 * [AppDependencies.api] est `PreviewApi`, qui sert les routes du fil depuis
 * ses fils en mémoire (`PreviewChat.kt`) — le même chemin qu'iOS, file
 * comprise. « Passer hors ligne » y coupe aussi le fil (`SandboxNetwork`), et
 * c'est le fil local qui s'ouvre.
 *
 * **L'envoi passe par la file**, comme le vocal de l'accueil : hors ligne, un
 * tour attend sur le disque au lieu d'échouer, et la bulle reste « en cours
 * d'envoi » jusqu'à ce que la file dise qu'il est parti
 * ([RecordingOutbox.turnDeliveries]). Le modèle ne voit qu'un
 * [ChatSendOutcome], ce qui attend, et ce qui part.
 *
 * @param audio le micro, le lecteur et la voix, construits par la porte
 *   d'entrée sur le contexte de l'application — voir [ChatAudio]. Sur iOS, le
 *   modèle les crée lui-même : ici, ni lui ni `AppDependencies` ne tiennent de
 *   `Context`.
 */
fun AppDependencies.chatModel(tripId: String, stepId: String? = null, audio: ChatAudio): ChatModel {
    forgetsRememberedCreditsWithTheAccount()

    var transport = ChatTransport.remote(api, tripId)
    transport = transport.copy(
        send = { turn ->
            when (val delivery = outbox.submit(turn, tripId)) {
                // Sans reçu — réponse illisible —, le tour est arrivé quand
                // même : on dit au modèle qu'une réponse est en vol, et le
                // sondage relira ce que le serveur a écrit, depuis le curseur
                // qu'il tenait déjà.
                is RecordingOutbox.Delivery.Delivered -> ChatSendOutcome.Received(
                    delivery.receipt
                        ?: ChatTurnReceipt(messages = emptyList(), turn = ChatTurnStatus.Replying(messageId = turn.id), now = ChatModel.distantPast),
                )
                RecordingOutbox.Delivery.Queued -> ChatSendOutcome.Queued
                is RecordingOutbox.Delivery.Rejected -> throw RecordingOutbox.Rejection(message = delivery.message)
            }
        },
        waiting = { outbox.waiting(tripId) },
        deliveries = { outbox.turnDeliveries() },
        // « Supprimer », sous une bulle qui attend l'illimité : le tour quitte
        // la file, fiche et fichiers.
        discard = { id -> outbox.discardTurn(id) },
        // Les derniers messages arrivés, gardés pour rouvrir le fil sans réseau
        // (Hugo, 08/10/2026) — voir [forOfflineCache].
        remember = { thread -> content.write(ContentCache.Slot.Chat(tripId), thread.forOfflineCache()) },
        // Sans réseau, ou pour un voyage que le serveur n'a pas encore reçu :
        // un fil **local** — les derniers messages gardés s'il y en a, sinon
        // l'accueil de MEMO —, et ce qui attend d'être envoyé.
        offlineThread = { error -> offlineThread(tripId, error) },
    )
    return ChatModel(
        transport = transport,
        audio = audio,
        focusStepId = stepId,
        callToActionMemory = ChatCallToActionMemory(settings),
    )
}

/** Le fil local d'un voyage — voir [chatModel]. `null` : l'échec se dit. */
private suspend fun AppDependencies.offlineThread(tripId: String, error: Throwable): ChatThread? {
    val home = content.read<HomeFeed>(ContentCache.Slot.Home)
    val traveller = home?.traveller
    outbox.localTrip(tripId)?.let { waiting ->
        // Un voyage neuf a son pot plein : le fil compte dès le premier vocal
        // dicté dans l'avion, illimité si l'accueil gardé dit que le compte
        // l'est (03/10/2026).
        val trip = RecordingOutbox.withFreshCredit(waiting.trip, isUnlimited = traveller?.isUnlimited ?: false)
        return ChatThread.offline(trip = trip, traveller = traveller, isNew = true)
    }
    if ((error as? ApiError)?.isTransport != true) return null
    // Le titre du voyage, depuis ce qu'on en a gardé : l'écran du voyage, à
    // défaut l'accueil. **Le crédit du jour, le plus avancé des deux**
    // (`DailyCredit.merged`, 03/10/2026) : le serveur sert le crédit d'un
    // voyage en cours sur l'un comme sur l'autre, et chacun date de sa
    // dernière lecture. Le premier trouvé gagnait — celui de l'écran du voyage,
    // souvent le plus vieux : lu le matin à 5:00, il passait devant l'accueil
    // relu après un vocal de 4 minutes.
    val homeTrip = home?.trips?.firstOrNull { it.id == tripId }
    val known = content.read<TripDetail>(ContentCache.Slot.Trip(tripId))?.trip ?: homeTrip
    val detailCredit = known?.dailyCredit
    val trip = known?.copy(dailyCredit = detailCredit?.merged(with = homeTrip?.dailyCredit) ?: homeTrip?.dailyCredit)
        ?: Trip(id = tripId, title = TripDraft.untitled, stage = TripStage.Ongoing)
    // Le fil déjà lu ici : on le rouvre sur ce qu'on s'était dit.
    content.read<ChatThread>(ContentCache.Slot.Chat(tripId))?.let { cached ->
        return ChatThread.offline(cached = cached, trip = trip)
    }
    return ChatThread.offline(trip = trip, traveller = traveller, isNew = false)
}

/**
 * Le dernier crédit du jour que chaque conversation a lu porte l'abonnement de
 * ce compte : il ne suit pas le prochain. Sur iOS,
 * `AppDependencies.forgetAccountContent()` appelle
 * `ChatModel.forgetRememberedCredits()` ; ici, la conversation s'y inscrit
 * elle-même ([AppDependencies.onForgetAccount]) — une fois par assemblage, à la
 * première conversation ouverte : avant elle, il n'y a rien à oublier.
 */
private fun AppDependencies.forgetsRememberedCreditsWithTheAccount() {
    if (registeredForgetters.add(this)) onForgetAccount { ChatModel.forgetRememberedCredits() }
}

private val registeredForgetters: MutableSet<AppDependencies> = Collections.synchronizedSet(Collections.newSetFromMap(WeakHashMap()))
