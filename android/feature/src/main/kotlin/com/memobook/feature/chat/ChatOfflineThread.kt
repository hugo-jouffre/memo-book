package com.memobook.feature.chat

import com.memobook.core.ChatContext
import com.memobook.core.ChatCopy
import com.memobook.core.ChatDelivery
import com.memobook.core.ChatGreeting
import com.memobook.core.ChatSuggestion
import com.memobook.core.ChatThread
import com.memobook.core.ChatTurnStatus
import com.memobook.core.DailyCredit
import com.memobook.core.Traveller
import com.memobook.core.Trip
import java.time.Instant

// Le fil qu'on ouvre sans le serveur. Jumeau de `ChatOfflineThread.swift` — une
// extension de `ChatThread` sur iOS, des extensions de son compagnon ici.

/**
 * Le fil qu'on ouvre **sans le serveur** : l'accueil de MEMO, et rien de ce
 * qu'il a déjà dit.
 *
 * Deux cas, et les deux veulent qu'on puisse raconter quand même (Hugo,
 * 01/10/2026) : un voyage créé hors ligne, que le serveur ne connaît pas
 * encore ; et un voyage qu'on ouvre sans réseau. Ce qu'on y dit part dans la
 * file et se pose en bulles « en cours d'envoi » — [ChatModel] les ajoute
 * depuis [ChatTransport.waiting].
 *
 * Un voyage déjà ouvert ici rouvre plutôt **ses derniers messages gardés**
 * ([offline] `(cached, trip)`, 08/10/2026) ; celui-ci ne sert qu'à un voyage
 * dont le téléphone n'a encore rien lu. L'écran dit qu'il est hors ligne, et
 * le vrai fil revient avec le réseau.
 *
 * **Le crédit du jour** suit le voyage tel que l'accueil l'a gardé
 * ([Trip.dailyCredit]) : dans le métro, la barre continue de compter au lieu
 * de laisser parler sans limite jusqu'à un refus. Passé sa recharge, il repart
 * **plein** ([DailyCredit.refreshed], 03/10/2026) plutôt que de ne plus rien
 * dire : un fil ouvert le lendemain dans l'avion coupe toujours à la limite,
 * au lieu de laisser dicter un vocal que le serveur refuserait chaque jour.
 * Sans heure de recharge — un cache d'avant —, on ne sait pas de quel jour il
 * est : il n'en dit rien.
 *
 * @param isNew le voyage vient d'être créé et n'a rien raconté. Il s'ouvre
 *   alors comme le serveur l'ouvrirait, sur la puce du contexte — celle qu'un
 *   carnet neuf propose en premier (`SUGGESTION_SETS.opening` côté serveur).
 *   Sur un voyage déjà raconté, on ne sait pas où en est la conversation :
 *   aucune puce, plutôt qu'une puce hors de propos.
 */
fun ChatThread.Companion.offline(trip: Trip, traveller: Traveller?, isNew: Boolean): ChatThread {
    val initials = traveller?.firstName?.firstOrNull()?.toString()?.uppercase()
    val destination = trip.destination

    return ChatThread(
        id = trip.id,
        title = trip.title,
        avatarUrl = trip.coverPhotoUrl,
        destination = destination,
        greeting = ChatGreeting(
            title = destination?.let { ChatCopy.greetingTitle(place = it.city ?: it.name, flag = it.flag) }
                ?: ChatCopy.greetingTitleWithoutPlace,
            message = ChatCopy.greetingMessage,
        ),
        context = ChatContext(
            tripId = trip.id,
            tripTitle = trip.title,
            travellerFirstName = traveller?.firstName,
            travellerInitials = initials,
            travellerAvatarUrl = traveller?.avatarUrl,
        ),
        suggestions = if (isNew) {
            listOf(
                ChatSuggestion(
                    id = "context",
                    label = ChatCopy.Suggest.tellContext,
                    symbol = ChatCopy.Suggest.tellContextSymbol,
                    intent = ChatSuggestion.Intent.Send,
                ),
            )
        } else {
            emptyList()
        },
        // Personne ne peut effacer un fil qu'on ne tient pas.
        canClear = false,
        dailyCredit = trip.offlineCredit(),
    )
}

/**
 * Combien de messages le téléphone garde d'un fil : de quoi relire où on en
 * était — la dernière fiche, la question de MEMO —, pas de quoi rejouer le
 * voyage entier.
 */
val ChatThread.Companion.cachedMessageCount: Int get() = 30

/**
 * Ce que le téléphone garde du fil (08/10/2026) : ses
 * [cachedMessageCount] derniers messages **arrivés chez le serveur**.
 *
 * Ni ce qui est en route — la file des envois le garde déjà, et le repose en
 * bulles « en cours d'envoi » à l'ouverture —, ni les bulles que l'app pose
 * seule (le « reviens demain » hors ligne) : relues le lendemain, elles
 * mentiraient. Pas de puces non plus : sans le serveur, rien ne répondrait à
 * celle qu'on toucherait.
 */
fun ChatThread.forOfflineCache(): ChatThread = copy(
    messages = messages
        .filter { it.delivery == ChatDelivery.Sent && !it.id.startsWith(ChatModel.localNoticePrefix) }
        .takeLast(ChatThread.cachedMessageCount),
    suggestions = emptyList(),
    turn = ChatTurnStatus.Idle,
)

/**
 * Le fil **gardé**, rouvert sans réseau (08/10/2026) : ses derniers messages,
 * sous le bandeau « hors ligne ». Le crédit du jour est celui du voyage tel que
 * l'accueil l'a gardé, comme pour [offline] `(trip, traveller, isNew)` — celui
 * du fil gardé date de sa dernière lecture.
 */
fun ChatThread.Companion.offline(cached: ChatThread, trip: Trip): ChatThread = ChatThread(
    id = cached.id,
    title = cached.title,
    avatarUrl = cached.avatarUrl,
    destination = cached.destination,
    greeting = cached.greeting,
    preview = cached.preview,
    context = cached.context,
    messages = cached.messages,
    suggestions = emptyList(),
    tripContext = cached.tripContext,
    turn = ChatTurnStatus.Idle,
    // Personne ne peut effacer un fil qu'on ne tient pas.
    canClear = false,
    now = cached.now,
    dailyCredit = trip.offlineCredit(),
)

/** Le crédit gardé du voyage, rechargé s'il date d'hier ; rien sans heure de recharge. */
private fun Trip.offlineCredit(now: Instant = Instant.now()): DailyCredit? {
    val credit = dailyCredit ?: return null
    if (credit.resetsAt == null) return null
    return credit.refreshed(now = now)
}
