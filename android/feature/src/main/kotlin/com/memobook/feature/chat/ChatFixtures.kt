package com.memobook.feature.chat

import com.memobook.core.ChatAuthor
import com.memobook.core.ChatBookPreview
import com.memobook.core.ChatCallToAction
import com.memobook.core.ChatContext
import com.memobook.core.ChatCopy
import com.memobook.core.ChatDelivery
import com.memobook.core.ChatGreeting
import com.memobook.core.ChatMessage
import com.memobook.core.ChatMessageBody
import com.memobook.core.ChatSuggestion
import com.memobook.core.ChatThread
import com.memobook.core.DailyCredit
import com.memobook.core.DailyCreditCopy
import com.memobook.core.Destination
import com.memobook.core.HomeFeed
import com.memobook.core.TranscriptCard
import com.memobook.core.Trip
import com.memobook.core.TripDetail
import com.memobook.core.VoiceNote
import com.memobook.design.BrandWaveform
import com.memobook.feature.home.fixture
import com.memobook.feature.home.fixtureDate
import com.memobook.feature.trip.fixture

// Jeu d'essai du chat — **temporaire**, comme celui de l'accueil, du profil et
// de l'accueil d'un voyage. Le jumeau de `ChatFixtures.swift`.
//
// Ce fichier expose, au module `:feature` seulement :
// - `ChatThread.fixture(tripId)` (et son ancien nom `conversationFixture`) : le
//   fil d'un voyage du jeu d'essai, une journée racontée par étape terminée ;
// - `ChatThread.creditExhaustedFixture(tripId)`, le crédit du jour épuisé, et
//   `ChatThread.tooLongForADayFixture(tripId)`, un vocal trop long pour une
//   journée ; `ChatThread.exhaustedNoticeFixtureId`, la bulle « reviens demain » ;
// - [ChatCreditFixture] : des crédits du jour frais, presque épuisé, épuisé,
//   illimité ;
// - [ChatFixtureCopy] : les textes des bulles d'exemple qui portent un bouton.
//
// L'écran est entièrement piloté par ces données : pas un titre, pas une date,
// pas une bulle n'est écrite dans une vue. Le jour où `GET /v1/trips/:id/chat`
// existe, ce fichier disparaît et rien d'autre ne bouge.
//
// Le voyage est **repris de l'accueil**, par `TripDetail.fixture(id)` : ouvrir
// une étape doit mener à ce qu'elle montrait, et le chat doit s'ouvrir sur la
// même relance que l'écran du voyage. C'est la même règle qui a fait que
// l'accueil d'un voyage ne réinvente pas son voyage.

/**
 * **Une** conversation par voyage.
 *
 * Et non une par étape : un carnet se relit d'un bout à l'autre, et couper le
 * récit en autant de fils que d'étapes obligerait à changer de fil pour relire
 * la veille. Ce sont les messages qui portent leur étape — voir
 * [ChatMessage.stepId] —, ce qui permet quand même d'ouvrir le fil **sur** une
 * journée.
 *
 * Le fil arrive avec ce qui a déjà été raconté : une journée par étape
 * terminée. Sans cet historique, ouvrir une étape depuis sa carte tombait sur
 * une conversation vide, et « montre-moi où j'en étais » n'avait rien à
 * montrer.
 */
internal fun ChatThread.Companion.fixture(tripId: String): ChatThread {
    val detail = TripDetail.fixture(id = tripId)
    val current = detail.steps.lastOrNull()
    val traveller = HomeFeed.fixture.traveller

    val messages = history(detail)
    return ChatThread(
        id = tripId,
        title = detail.trip.title,
        avatarUrl = detail.trip.coverPhotoUrl,
        destination = detail.trip.destination,
        greeting = greeting(detail.trip.destination),
        preview = preview(detail.trip),
        context = ChatContext(
            tripId = tripId,
            tripTitle = detail.trip.title,
            travellerFirstName = traveller.firstName,
            // Le portrait du voyageur du jeu d'essai, pour ses vocaux.
            travellerInitials = traveller.firstName.firstOrNull()?.toString()?.uppercase(),
            placeName = current?.placeName,
            stepNumber = current?.number,
            stepId = current?.id,
            prompt = detail.prompt,
        ),
        messages = messages,
        suggestions = if (messages.isEmpty()) emptyList() else afterAcceptTrio,
        // Trois minutes de crédit devant soi : assez pour raconter, et la barre
        // ne prévient de rien tant qu'on ne parle pas longtemps.
        dailyCredit = ChatCreditFixture.fresh,
    )
}

/** La même conversation. Le nom reste, employé par les aperçus. */
internal fun ChatThread.Companion.conversationFixture(tripId: String): ChatThread = fixture(tripId = tripId)

/**
 * L'identifiant de la bulle « reviens demain » du jeu d'essai — pour qu'un
 * aperçu montre son bouton déjà touché.
 */
internal val ChatThread.Companion.exhaustedNoticeFixtureId: String get() = "memo-daily-credit-exhausted"

/**
 * **Le crédit du jour épuisé** (03/10/2026) : la conversation, puis un vocal
 * qui a fait tomber le crédit à zéro, la bulle « reviens demain » de MEMO avec
 * son bouton « Raconter sans limite », et un message écrit ensuite hors ligne
 * que le serveur a refusé — il attend demain, en gris. Le micro et le clavier
 * sont pâlis.
 */
internal fun ChatThread.Companion.creditExhaustedFixture(tripId: String): ChatThread {
    val thread = fixture(tripId = tripId)
    val now = fixtureDate(27, 8, 2026)
    val stepId = thread.context.stepId

    return thread.copy(
        messages = thread.messages + listOf(
            ChatMessage(
                id = "voice-daily-credit-last",
                author = ChatAuthor.Traveller,
                body = ChatMessageBody.Voice(
                    VoiceNote(id = "voice-daily-credit-last", duration = 64.0, levels = BrandWaveform.sampleLevels),
                ),
                sentAt = now,
                stepId = stepId,
            ),
            ChatMessage(
                id = exhaustedNoticeFixtureId,
                author = ChatAuthor.Memo,
                body = ChatMessageBody.Text(DailyCreditCopy.exhaustedMessage),
                sentAt = now,
                stepId = stepId,
                callToAction = ChatCallToAction.dailyCreditSubscribe,
            ),
            ChatMessage(
                id = "text-daily-credit-tomorrow",
                author = ChatAuthor.Traveller,
                body = ChatMessageBody.Text("Et le soir, un dernier verre sur la terrasse de l’hôtel."),
                sentAt = now,
                stepId = stepId,
                delivery = ChatDelivery.WaitingForCredit(until = fixtureDate(28, 8, 2026)),
            ),
        ),
        suggestions = emptyList(),
        dailyCredit = ChatCreditFixture.exhausted,
    )
}

/**
 * **Un vocal plus long qu'une journée de crédit** (03/10/2026) : sept minutes
 * dites hors ligne, que le serveur refusera même pot plein. La bulle attend
 * l'illimité — « Trop long pour une journée · Passer en illimité » — et le
 * crédit du jour, lui, reste entier.
 */
internal fun ChatThread.Companion.tooLongForADayFixture(tripId: String): ChatThread {
    val thread = fixture(tripId = tripId)
    return thread.copy(
        messages = thread.messages + ChatMessage(
            id = "voice-too-long-for-a-day",
            author = ChatAuthor.Traveller,
            body = ChatMessageBody.Voice(
                VoiceNote(id = "voice-too-long-for-a-day", duration = 420.0, levels = BrandWaveform.sampleLevels),
            ),
            sentAt = fixtureDate(27, 8, 2026),
            stepId = thread.context.stepId,
            delivery = ChatDelivery.WaitingForUnlimited,
        ),
        suggestions = emptyList(),
        dailyCredit = ChatCreditFixture.fresh,
    )
}

// region Ce qui a déjà été raconté

/**
 * Une journée par étape : un vocal, la fiche que MEMO en a tirée, sa relance,
 * et la validation du voyageur.
 *
 * Les dates sont **figées** ([fixtureDate]) : un écran qui change de texte
 * selon le jour n'est plus comparable à la maquette.
 */
private fun history(detail: TripDetail): List<ChatMessage> {
    if (detail.steps.isEmpty()) return emptyList()
    val fallbackDay = fixtureDate(26, 8, 2026)

    val messages = mutableListOf(
        ChatMessage(
            id = "memo-opening",
            author = ChatAuthor.Memo,
            body = ChatMessageBody.Text(ChatCopy.opening),
            sentAt = detail.steps[0].startDate ?: fallbackDay,
        ),
    )

    // La dernière étape est celle qu'on est en train de vivre : elle n'a pas
    // encore été racontée, et c'est justement sur elle que le fil s'ouvre.
    detail.steps.dropLast(1).forEachIndexed { index, step ->
        val day = step.startDate ?: fallbackDay
        val note = VoiceNote(
            id = "voice-${step.id}",
            duration = 37 + index * 11.0,
            levels = BrandWaveform.sampleLevels,
        )

        messages += ChatMessage(
            id = "voice-${step.id}",
            author = ChatAuthor.Traveller,
            body = ChatMessageBody.Voice(note),
            sentAt = day,
            stepId = step.id,
        )
        messages += ChatMessage(
            id = "memo-${step.id}-transcript",
            author = ChatAuthor.Memo,
            body = ChatMessageBody.Transcript(
                TranscriptCard(
                    title = ChatCopy.transcriptTitle,
                    capturedAt = day,
                    placeLabel = step.placeName,
                    duration = note.duration,
                    text = transcripts[index % transcripts.size],
                    isSimulated = true,
                    footnote = ChatCopy.transcriptFootnote,
                ),
            ),
            sentAt = day,
            stepId = step.id,
        )
        messages += ChatMessage(
            id = "memo-${step.id}-after",
            author = ChatAuthor.Memo,
            body = ChatMessageBody.Text(ChatCopy.afterTranscript),
            sentAt = day,
            stepId = step.id,
        )
        messages += ChatMessage(
            id = "traveller-${step.id}-accept",
            author = ChatAuthor.Traveller,
            body = ChatMessageBody.Text(ChatCopy.Suggest.accept),
            sentAt = day,
            stepId = step.id,
        )
        messages += ChatMessage(
            id = "memo-${step.id}-acknowledged",
            author = ChatAuthor.Memo,
            body = ChatMessageBody.Text(ChatCopy.acknowledged),
            sentAt = day,
            stepId = step.id,
        )
    }

    // **Pas** la relance du jour en dernière bulle : « Comment ça se passe à
    // Testaccio ? » vit sur l'accueil du voyage, et sera une notification —
    // jamais une bulle que MEMO pose de lui-même dans le fil (Hugo, 17/09/2026).
    return messages
}

/**
 * Ce que MEMO propose après « C'est enregistré » — le dernier mot du jeu
 * d'essai : raconter la suite, ou plus tard. Le même jeu que le répondeur local
 * donne après une validation. **Pas** le trio de validation : celui-là ne suit
 * qu'une fiche qui porte du vrai texte.
 */
private val afterAcceptTrio = listOf(
    ChatSuggestion(
        id = "dictate",
        label = ChatCopy.Suggest.dictate,
        symbol = ChatCopy.Suggest.dictateSymbol,
        intent = ChatSuggestion.Intent.SendThenSpeak,
    ),
    ChatSuggestion(
        id = "photos",
        label = ChatCopy.Suggest.importPhotos,
        symbol = ChatCopy.Suggest.importPhotosSymbol,
        intent = ChatSuggestion.Intent.ImportPhotos,
    ),
    ChatSuggestion(
        id = "later",
        label = ChatCopy.Suggest.later,
        symbol = ChatCopy.Suggest.laterSymbol,
        intent = ChatSuggestion.Intent.Send,
    ),
)

/**
 * L'accueil nomme **la ville du voyage**.
 *
 * C'est ce que la maquette écrit — « Nouveau voyage à Rome ! » —, et c'est
 * désormais une donnée : [Destination.city], ajoutée au modèle et à la base
 * pour ça (D10). Le pays donnerait « à Italie », qui n'est pas du français.
 * Sans ville — un tour du monde —, la phrase se replie.
 */
private fun greeting(destination: Destination?): ChatGreeting =
    ChatGreeting(
        title = destination?.city?.let { ChatCopy.greetingTitle(place = it, flag = destination.flag) }
            ?: ChatCopy.greetingTitleWithoutPlace,
        message = ChatCopy.greetingMessage,
    )

/**
 * Les compteurs de la bannière, tirés de l'avancement du carnet que l'accueil
 * affiche déjà. Un voyage à venir n'a rien à montrer : la bannière disparaît
 * plutôt que d'annoncer zéro.
 */
private fun preview(trip: Trip): ChatBookPreview? {
    val progress = trip.progress ?: return null
    return ChatBookPreview(
        memoryCount = progress.memoryCount,
        pageCount = progress.pageCount,
        isOpenable = trip.isPrintable || progress.pageCount > 0,
    )
}

/**
 * Les récits déjà retranscrits, dans le registre oral d'une transcription
 * brute. Le premier est celui de la maquette, au caractère près.
 */
private val transcripts = listOf(
    "Ce voyage commence bien avant le décollage. Depuis plusieurs semaines, " +
        "l’idée de partir à Lisbonne tourne en boucle dans ma tête.\n" +
        "Une envie simple : changer d’air, couper avec le rythme habituel, et me " +
        "retrouver ailleurs, dans une ville que je ne connais pas encore vraiment.",
    "alors ce matin on est partis tôt pour éviter la chaleur, euh on a marché " +
        "jusqu’au marché et là on a pris un café debout au comptoir comme tout le " +
        "monde, c’était le meilleur moment de la journée franchement",
    "bon là on vient de rentrer, on a fait le tour du quartier à pied, il y " +
        "avait une fête dans la rue avec de la musique jusqu’à tard, du coup on a " +
        "mangé sur le pouce et on a regardé les gens danser",
)

// endregion

/**
 * Des crédits du jour pour les aperçus et le bac à sable : frais, presque
 * épuisé, épuisé, illimité (03/10/2026). Un espace de noms et non des
 * constantes sur [DailyCredit] : d'autres écrans tiennent les leurs.
 */
internal object ChatCreditFixture {
    /** Trois minutes de crédit devant soi. */
    val fresh: DailyCredit = credit(usedMs = 120_000)

    /** Vingt-quatre secondes : le bandeau paraît dès qu'on parle. */
    val lastSeconds: DailyCredit = credit(usedMs = 276_000)

    /** Plus rien : micro et clavier pâlis. */
    val exhausted: DailyCredit = credit(usedMs = DailyCredit.Catalog.limitMs)

    /** Un abonné : rien ne compte. */
    val unlimited = DailyCredit(isUnlimited = true, usedMs = 276_000, day = "2026-08-27")

    private fun credit(usedMs: Int): DailyCredit =
        DailyCredit(
            usedMs = usedMs,
            day = "2026-08-27",
            resetsAt = fixtureDate(28, 8, 2026),
        )
}

/** Les textes des bulles d'exemple qui portent un bouton. */
internal object ChatFixtureCopy {
    /**
     * La bulle de la maquette `3653:17090`, sous laquelle MEMO propose
     * « Modifier l’autorisation ».
     */
    const val limitedPhotosMessage =
        "MemoBook ne voit qu’une partie de tes photos. Autorise l’accès complet pour retrouver automatiquement les photos de chaque étape."

    /**
     * Le bouton du catalogue du serveur (`open_photo_settings`,
     * `services/callsToAction.ts`), recopié pour l'aperçu.
     */
    val limitedPhotosCallToAction = ChatCallToAction(
        id = "open_photo_settings",
        kind = ChatCallToAction.Kind.OpenPhotoSettings,
        label = "Modifier l’autorisation",
        eyebrow = "Accès aux photos limité",
    )
}
