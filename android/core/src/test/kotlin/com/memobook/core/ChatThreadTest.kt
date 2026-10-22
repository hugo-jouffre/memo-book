package com.memobook.core

import java.io.File
import java.net.URI
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * Ce que le fil sait de lui-même : à quelle étape appartient un message, et ce
 * qu'il faut retrouver quand on l'ouvre depuis une carte d'étape. Le jumeau de
 * `ChatThreadTests.swift`.
 */
class ChatThreadTest {
    private val context = ChatContext(tripId = "trip-rome", stepId = "step-3")
    private val distantPast: Instant = Instant.parse("0001-01-01T00:00:00Z")

    // MARK: - Retrouver une étape

    /** Ouvrir une étape ne rouvre pas son début : on veut **où on en était**. */
    @Test
    fun findsTheLastMessageOfAStep() {
        val thread = makeThread(
            "a" to "step-1",
            "b" to "step-1",
            "c" to "step-2",
            "d" to "step-1",
            "e" to "step-2",
        )

        assertEquals("d", thread.lastMessage(about = "step-1")?.id)
        assertEquals("e", thread.lastMessage(about = "step-2")?.id)
    }

    /**
     * Une étape dont rien n'a été dit n'a rien à montrer : l'écran s'ouvre
     * alors sur la fin du fil, comme d'habitude.
     */
    @Test
    fun anUntouchedStepHasNothingToShow() {
        val thread = makeThread("a" to "step-1")
        assertNull(thread.lastMessage(about = "step-9"))
    }

    /**
     * Les bulles qui ne parlent d'aucune étape — l'ouverture de MEMO, une
     * question sur l'abonnement — ne se font pas rattacher par erreur.
     */
    @Test
    fun messagesWithoutAStepAreNeverMatched() {
        val thread = makeThread("opening" to null, "a" to "step-1")
        assertEquals("a", thread.lastMessage(about = "step-1")?.id)
    }

    /**
     * La carte d'une étape ouvre **son récit** — la bulle du voyageur qui
     * l'a racontée, pas MEMO, pas les photos, pas une précision (Hugo,
     * 12/10/2026).
     */
    @Test
    fun findsTheStoryOfAStep() {
        val date = Instant.ofEpochSecond(0)
        val messages = listOf(
            ChatMessage(id = "photos", author = ChatAuthor.Traveller, body = ChatMessageBody.Photos(emptyList()), sentAt = date, stepId = "step-2"),
            ChatMessage(id = "memo", author = ChatAuthor.Memo, body = ChatMessageBody.Text("Il te convient ?"), sentAt = date, stepId = "step-2"),
            ChatMessage(
                id = "precision", author = ChatAuthor.Traveller, body = ChatMessageBody.Text("Avec Clara."), sentAt = date, stepId = "step-2",
                disposition = ChatDisposition.Context,
            ),
            ChatMessage(
                id = "story", author = ChatAuthor.Traveller,
                body = ChatMessageBody.Voice(VoiceNote(id = "story", duration = 30.0, levels = emptyList())),
                sentAt = date, stepId = "step-2", disposition = ChatDisposition.Memory,
            ),
        )
        val thread = ChatThread(id = "t", title = "Rome", context = context, messages = messages)

        assertEquals("story", thread.storyMessage(about = "step-2")?.id)
        assertNull(thread.storyMessage(about = "step-9"))
    }

    // MARK: - La ville du voyage

    /**
     * La ville est une donnée à part entière, distincte du pays : c'est elle
     * qui permet d'écrire « Nouveau voyage à Rome ! ».
     */
    @Test
    fun greetingNamesTheCityNotTheCountry() {
        val rome = Destination(name = "Italie", countryCode = "IT", city = "Rome")

        assertEquals(
            "Nouveau voyage à Rome ! 🇮🇹",
            ChatCopy.greetingTitle(place = assertNotNull(rome.city), flag = rome.flag),
        )
    }

    /**
     * Un voyage sans ville — un tour du monde — n'a pas de phrase bancale à
     * afficher : elle se replie.
     */
    @Test
    fun aTripWithoutACityFallsBack() {
        assertNull(Destination(name = "Italie", countryCode = "IT").city)
        assertEquals("Nouveau carnet de voyage !", ChatCopy.greetingTitleWithoutPlace)
    }

    /**
     * Le champ est optionnel côté serveur : une réponse qui ne le porte pas ne
     * doit pas faire échouer le décodage de tout l'écran.
     */
    @Test
    fun decodesADestinationWithoutACity() {
        val destination = MemoBookJson.decodeFromString<Destination>("""{"name":"Italie","countryCode":"IT"}""")

        assertEquals("Italie", destination.name)
        assertNull(destination.city)
    }

    // MARK: - Les photos

    /**
     * MEMO recompte ce qu'il a reçu et demande ce qu'on y voit. Il ne décrit
     * **pas** les images : il ne les a pas regardées.
     */
    @Test
    fun photosAreCountedNeverDescribed() {
        val responder = LocalMemoResponder(voice = LocalMemoResponder.VoiceMode.Unavailable)
        val attachments = (0 until 3).map { PhotoAttachment(id = "p$it") }
        val turn = ChatTurn(
            message = ChatMessage(
                id = "t1",
                author = ChatAuthor.Traveller,
                body = ChatMessageBody.Photos(attachments),
                sentAt = distantPast,
            ),
            history = emptyList(),
            context = context,
        )

        val reply = awaitWithoutDispatcher { responder.reply(turn) }
        val text = assertNotNull(reply.beats.firstNotNullOfOrNull(::textOf))

        assertTrue(text.startsWith("3 photos"), text)
        assertTrue(text.endsWith("?"), "MEMO doit demander ce qu'on y voit")
        assertTrue(reply.beats[0].pauseMilliseconds > 0)
    }

    @Test
    fun aSinglePhotoIsCountedInTheSingular() {
        assertTrue(ChatCopy.photosReceived(count = 1).startsWith("Une photo"))
    }

    /**
     * Le corps d'un message de photos n'a pas de texte : rien à copier, rien à
     * faire lire à voix haute.
     */
    @Test
    fun aPhotoMessageHasNothingToSpeak() {
        val message = ChatMessage(
            id = "p",
            author = ChatAuthor.Traveller,
            body = ChatMessageBody.Photos(listOf(PhotoAttachment(id = "p0"))),
            sentAt = distantPast,
        )
        assertNull(message.spokenText)
    }

    /**
     * Un chemin local ne part **jamais** vers le serveur : il n'a aucun sens
     * là-bas.
     */
    @Test
    fun aPhotoNeverEncodesItsLocalPath() {
        val attachment = PhotoAttachment(
            id = "p0",
            localUrl = File("/tmp/p0.jpg").toURI(),
        )
        val text = MemoBookJson.encodeToString(PhotoAttachment.serializer(), attachment)

        assertFalse(text.contains("localUrl"), text)
        assertFalse(text.contains("/tmp/"), text)
    }

    /**
     * Le reçu du serveur rend les photos sous l'identifiant de leur souvenir,
     * pas sous celui de la bulle posée avant l'envoi : elles gardent quand
     * même leur fichier local, retrouvé par son rang (30/09/2026).
     */
    @Test
    fun photosKeepTheirLocalFilesWhenTheServerRenamesThem() {
        val sent = ChatMessage(
            id = "tour",
            author = ChatAuthor.Traveller,
            body = ChatMessageBody.Photos(
                listOf(
                    PhotoAttachment(id = "tour-0", localUrl = File("/tmp/tour-0.jpg").toURI()),
                    PhotoAttachment(id = "tour-1", localUrl = File("/tmp/tour-1.jpg").toURI()),
                ),
            ),
            sentAt = distantPast,
            delivery = ChatDelivery.Sending,
        )
        val received = ChatMessage(
            id = "tour",
            author = ChatAuthor.Traveller,
            body = ChatMessageBody.Photos(
                listOf(
                    PhotoAttachment(id = "souvenir-a", remoteUrl = URI("https://api.test/v1/entries/souvenir-a/media")),
                    PhotoAttachment(id = "souvenir-b", remoteUrl = URI("https://api.test/v1/entries/souvenir-b/media")),
                ),
            ),
            sentAt = distantPast,
        )

        val merged = (received.keepingLocalFiles(sent).body as? ChatMessageBody.Photos)?.attachments
            ?: fail("des photos")
        assertEquals(listOf("tour-0.jpg", "tour-1.jpg"), merged.map { it.localUrl?.lastPathComponent() })
        assertEquals(listOf("souvenir-a", "souvenir-b"), merged.map { it.id }, "L'identifiant du serveur fait foi.")
    }

    /**
     * Des listes de longueurs différentes ne se rapprochent pas au rang : ce
     * ne sont plus les mêmes photos.
     */
    @Test
    fun photosAreNotMatchedByRankWhenTheCountsDiffer() {
        val sent = ChatMessage(
            id = "tour",
            author = ChatAuthor.Traveller,
            body = ChatMessageBody.Photos(listOf(PhotoAttachment(id = "tour-0", localUrl = File("/tmp/tour-0.jpg").toURI()))),
            sentAt = distantPast,
        )
        val received = ChatMessage(
            id = "tour",
            author = ChatAuthor.Traveller,
            body = ChatMessageBody.Photos(listOf(PhotoAttachment(id = "a"), PhotoAttachment(id = "b"))),
            sentAt = distantPast,
        )

        val merged = (received.keepingLocalFiles(sent).body as? ChatMessageBody.Photos)?.attachments
            ?: fail("des photos")
        assertTrue(merged.all { it.localUrl == null })
    }

    // MARK: - Outils

    private fun makeThread(vararg entries: Pair<String, String?>): ChatThread =
        ChatThread(
            id = "trip-rome",
            title = "Rome entre frère et sœur",
            context = context,
            messages = entries.map { (id, stepId) ->
                ChatMessage(
                    id = id,
                    author = ChatAuthor.Traveller,
                    body = ChatMessageBody.Text(id),
                    sentAt = distantPast,
                    stepId = stepId,
                )
            },
        )

    private fun textOf(beat: MemoBeat): String? = (beat.message.body as? ChatMessageBody.Text)?.value
}

/** `URL.lastPathComponent` de Swift. */
private fun URI.lastPathComponent(): String = path.trimEnd('/').substringAfterLast('/')

// MARK: - Ce que le serveur rend

/**
 * Le fil tel que `GET /v1/trips/:id/chat` le sert — `backend/src/routes/chatSerializers.ts`
 * —, et le même sans les champs que le jeu d'essai ne porte pas.
 */
class ChatThreadDecodingTest {
    private val served =
        """
        {
          "id": "trip-rome", "title": "Rome 2026", "avatarUrl": null,
          "destination": { "name": "Italie", "countryCode": "IT", "city": "Rome" },
          "greeting": { "title": "Nouveau voyage à Rome ! 🇮🇹", "message": "Je suis là." },
          "preview": { "memoryCount": 4, "pageCount": 8, "isOpenable": false },
          "context": { "tripId": "trip-rome", "tripTitle": "Rome 2026", "travellerFirstName": "Hugo",
                       "placeName": "Trastevere", "stepNumber": 3, "stepId": "step-3",
                       "prompt": "Comment ça se passe à Trastevere ?", "memberCount": 2 },
          "messages": [
            { "id": "m1", "seq": 1, "author": "memo", "authorName": null,
              "body": { "kind": "text", "text": "Bonjour" },
              "sentAt": "2026-09-21T08:00:00.000Z", "stepId": null, "disposition": null, "pauseMilliseconds": 700 },
            { "id": "m2", "seq": 2, "author": "traveller", "authorName": "Clara",
              "body": { "kind": "voice", "voice": { "id": "m2", "duration": 37, "levels": [0.2, 0.8], "remoteUrl": "http://localhost:3000/v1/entries/e1/media" } },
              "sentAt": "2026-09-21T18:02:11.000Z", "stepId": "step-3", "disposition": "memory", "pauseMilliseconds": null },
            { "id": "m3", "seq": 3, "author": "memo", "authorName": null,
              "body": { "kind": "transcript", "transcript": { "title": "Retranscription du contexte",
                        "capturedAt": "2026-09-21T18:02:11.000Z", "placeLabel": "Trastevere, Rome", "duration": 37,
                        "text": "Ce matin…", "isSimulated": false, "entryId": "e1", "footnote": null,
                        "phase": "writing", "isValidated": false } },
              "sentAt": "2026-09-21T18:02:12.000Z", "stepId": "step-3", "disposition": null, "pauseMilliseconds": 2800 }
          ],
          "suggestions": [ { "id": "accept", "label": "Ça me convient", "symbol": "👌", "intent": "send" } ],
          "turn": { "status": "replying", "messageId": "m2" },
          "canClear": false,
          "now": "2026-09-21T18:03:00.412Z"
        }
        """

    @Test
    fun decodesEverythingTheServerAdds() {
        val thread = MemoBookJson.decodeFromString<ChatThread>(served)

        assertEquals(2, thread.context.memberCount)
        assertEquals(ChatTurnStatus.Replying(messageId = "m2"), thread.turn)
        assertFalse(thread.canClear)
        assertNotNull(thread.now)
        assertEquals(listOf(1, 2, 3), thread.messages.map { it.seq })
        assertEquals("Clara", thread.messages[1].authorName)
        assertEquals(ChatDisposition.Memory, thread.messages[1].disposition)
        assertEquals(2800, thread.messages[2].pauseMilliseconds)

        val card = (thread.messages[2].body as? ChatMessageBody.Transcript)?.card ?: fail("une fiche")
        assertEquals(TranscriptCard.Phase.Writing, card.phase)
        assertEquals("e1", card.entryId)
        assertTrue(card.isSettling)
        assertFalse(card.isValidated)

        val note = (thread.messages[1].body as? ChatMessageBody.Voice)?.note ?: fail("un vocal")
        assertEquals("media", note.remoteUrl?.lastPathComponent())
        assertNull(note.localUrl, "Un chemin d'appareil ne vient jamais du serveur.")
    }

    /**
     * Le jeu d'essai des aperçus ne porte aucun des champs ajoutés : il décode
     * encore, avec les valeurs qui ne changent rien.
     */
    @Test
    fun decodesAThreadWithoutTheServerFields() {
        val bare =
            """
            {
              "id": "t", "title": "T",
              "context": { "tripId": "t" },
              "messages": [
                { "id": "m", "author": "memo", "body": { "kind": "transcript", "transcript": {
                    "title": "Retranscription du contexte", "capturedAt": "2026-09-21T08:00:00.000Z",
                    "text": "…", "isSimulated": true } }, "sentAt": "2026-09-21T08:00:00.000Z" }
              ],
              "suggestions": []
            }
            """
        val thread = MemoBookJson.decodeFromString<ChatThread>(bare)

        assertEquals(1, thread.context.memberCount)
        assertEquals(ChatTurnStatus.Idle, thread.turn)
        assertTrue(thread.canClear)
        assertNull(thread.now)
        assertNull(thread.messages[0].seq)
        val card = (thread.messages[0].body as? ChatMessageBody.Transcript)?.card ?: fail("une fiche")
        assertEquals(TranscriptCard.Phase.Ready, card.phase)
        assertFalse(card.isSettling)
    }

    /**
     * La fiche porte le titre du récit, et « Voir ma page » ouvre l'aperçu
     * sans rien envoyer (Hugo, 01/10/2026).
     */
    @Test
    fun decodesTheStoryHeadingAndThePreviewIntent() {
        val json =
            """
            { "title": "Retranscription étape 2", "heading": "Dernier brunch à Paros",
              "capturedAt": "2026-09-21T08:00:00.000Z", "text": "…", "phase": "ready" }
            """
        val card = MemoBookJson.decodeFromString<TranscriptCard>(json)
        assertEquals("Retranscription étape 2", card.title)
        assertEquals("Dernier brunch à Paros", card.heading)
        assertEquals("Dernier brunch à Paros", card.filled(text = "…", isSimulated = false).heading)

        val intent = MemoBookJson.decodeFromString<ChatSuggestion.Intent>("\"open_preview\"")
        assertEquals(ChatSuggestion.Intent.OpenPreview, intent)
    }

    /**
     * Un temps ou un classement que cette version ne connaît pas ne casse pas
     * le fil — même parti que `Status.Unknown`.
     */
    @Test
    fun unknownPhaseAndDispositionSurvive() {
        val json =
            """
            { "id": "m", "author": "traveller", "body": { "kind": "text", "text": "x" },
              "sentAt": "2026-09-21T08:00:00.000Z", "disposition": "dream" }
            """
        val message = MemoBookJson.decodeFromString<ChatMessage>(json)
        assertEquals(ChatDisposition.Unknown("dream"), message.disposition)

        val phase = MemoBookJson.decodeFromString<TranscriptCard.Phase>("\"dreaming\"")
        assertEquals(TranscriptCard.Phase.Unknown("dreaming"), phase)
    }

    /**
     * Le contexte du voyage, tel que `serializeTripContext` le sert : la
     * pastille lit le compte, la fiche lit les lignes. Un statut inconnu ne
     * casse rien.
     */
    @Test
    fun decodesTheTripContext() {
        val json =
            """
            { "messages": [], "suggestions": [], "turn": { "status": "idle" },
              "now": "2026-09-28T10:00:00.000Z",
              "tripContext": {
                "status": "gathering", "filledCount": 2, "requiredCount": 5,
                "items": [
                  { "key": "departureCountry", "label": "Pays de départ", "value": "France",
                    "isRequired": true, "isFilled": true },
                  { "key": "companions", "label": "Compagnons de route", "value": null,
                    "isRequired": true, "isFilled": false }
                ] } }
            """
        val update = MemoBookJson.decodeFromString<ChatThreadUpdate>(json)
        val context = assertNotNull(update.tripContext)
        assertTrue(context.isGathering)
        assertEquals(0.4, context.progress, absoluteTolerance = 0.001)
        assertEquals(listOf(true, false), context.items.map { it.isFilled })
        assertNull(context.items[1].value)

        val status = MemoBookJson.decodeFromString<ChatTripContext.Status>("\"paused\"")
        assertEquals(ChatTripContext.Status.Unknown("paused"), status)
    }

    /** La suite du fil et le reçu d'un tour, tels que l'app les sonde et les reçoit. */
    @Test
    fun decodesAnUpdateAndAReceipt() {
        val update = MemoBookJson.decodeFromString<ChatThreadUpdate>(
            """
            { "messages": [], "suggestions": [], "preview": null,
              "turn": { "status": "idle" }, "now": "2026-09-21T18:03:02.418Z" }
            """,
        )
        assertEquals(ChatTurnStatus.Idle, update.turn)
        assertTrue(update.messages.isEmpty())

        val receipt = MemoBookJson.decodeFromString<ChatTurnReceipt>(
            """
            { "messages": [ { "id": "m9", "seq": 9, "author": "traveller", "body": { "kind": "text", "text": "…" },
                              "sentAt": "2026-09-21T18:03:00.000Z" } ],
              "turn": { "status": "replying", "messageId": "m9" }, "now": "2026-09-21T18:03:00.412Z" }
            """,
        )
        assertEquals(ChatTurnStatus.Replying(messageId = "m9"), receipt.turn)
        assertEquals(9, receipt.messages.firstOrNull()?.seq)
        assertNull(receipt.dailyCredit, "Un serveur d'avant le crédit du jour : rien à compter.")
        assertNull(update.dailyCredit)
    }

    // MARK: - Le crédit du jour et le bouton d'une bulle (03/10/2026)

    /**
     * Le crédit du jour voyage avec le fil, la suite du fil et le reçu — tel
     * que `services/dailyCredit.ts` le sert.
     */
    @Test
    fun decodesTheDailyCreditEverywhereItIsServed() {
        val credit =
            """
            "dailyCredit": { "isUnlimited": false, "limitMs": 300000, "usedMs": 120000,
              "remainingMs": 180000, "textMsPerCharacter": 75, "warningRemainingMs": 30000,
              "urgentRemainingMs": 5000, "day": "2026-10-03", "resetsAt": "2026-10-03T22:00:00.000Z" }
            """
        val thread = MemoBookJson.decodeFromString<ChatThread>(
            """{ "id": "t", "title": "T", "context": { "tripId": "t" }, """ + credit + "}",
        )
        assertEquals(180_000, thread.dailyCredit?.remainingMs)
        assertEquals("2026-10-03", thread.dailyCredit?.day)
        assertNotNull(thread.dailyCredit?.resetsAt)

        val update = MemoBookJson.decodeFromString<ChatThreadUpdate>(
            """{ "messages": [], "suggestions": [], "turn": { "status": "idle" }, "now": "2026-10-03T10:00:00.000Z", """ +
                credit + "}",
        )
        assertEquals(120_000, update.dailyCredit?.usedMs)

        val receipt = MemoBookJson.decodeFromString<ChatTurnReceipt>(
            """{ "messages": [], "turn": { "status": "idle" }, "now": "2026-10-03T10:00:00.000Z", """ + credit + "}",
        )
        assertEquals(75, receipt.dailyCredit?.textMsPerCharacter)
    }

    /**
     * Un crédit illisible ne coûte jamais le fil : la barre ne compte pas,
     * le serveur tranche.
     */
    @Test
    fun anUnreadableCreditDoesNotBreakTheThread() {
        val thread = MemoBookJson.decodeFromString<ChatThread>(
            """{ "id": "t", "title": "T", "context": { "tripId": "t" }, "dailyCredit": "beaucoup" }""",
        )
        assertNull(thread.dailyCredit)
    }

    /**
     * Le bouton d'une bulle de MEMO : une clé optionnelle du message, jamais
     * un `body.kind` — un genre inconnu survit en `Unknown`, un bouton
     * illisible laisse la bulle intacte, et le message aller-retour le garde.
     */
    @Test
    fun decodesTheCallToActionOfABubble() {
        val json =
            """
            [
              { "id": "a", "seq": 1, "author": "memo", "body": { "kind": "text", "text": "Quelle journée !" },
                "sentAt": "2026-10-03T20:00:00.000Z",
                "callToAction": { "id": "daily_credit_subscribe", "kind": "subscribe", "label": "Raconter sans limite",
                                  "eyebrow": "Crédit du jour épuisé", "dismissible": true } },
              { "id": "b", "seq": 2, "author": "memo", "body": { "kind": "text", "text": "Un jour." },
                "sentAt": "2026-10-03T20:00:01.000Z",
                "callToAction": { "id": "future", "kind": "open_map", "label": "Voir la carte" } },
              { "id": "c", "seq": 3, "author": "memo", "body": { "kind": "text", "text": "Toujours là." },
                "sentAt": "2026-10-03T20:00:02.000Z", "callToAction": { "kind": 42 } },
              { "id": "d", "seq": 4, "author": "memo", "body": { "kind": "text", "text": "Sans bouton." },
                "sentAt": "2026-10-03T20:00:03.000Z" }
            ]
            """
        val messages = MemoBookJson.decodeFromString<List<ChatMessage>>(json)

        assertEquals(ChatCallToAction.dailyCreditSubscribe, messages[0].callToAction)
        assertEquals(ChatCallToAction.Kind.Unknown("open_map"), messages[1].callToAction?.kind)
        assertEquals(false, messages[1].callToAction?.kind?.isSupported)
        assertTrue(messages[1].callToAction?.dismissible ?: false, "« Ignorer » par défaut.")
        assertNull(messages[2].callToAction, "Un bouton illisible : la bulle reste, sans bouton.")
        assertEquals("Toujours là.", messages[2].spokenText)
        assertNull(messages[3].callToAction)

        val roundTrip = MemoBookJson.decodeFromString<ChatMessage>(
            MemoBookJson.encodeToString(ChatMessage.serializer(), messages[0]),
        )
        assertEquals(ChatCallToAction.dailyCreditSubscribe, roundTrip.callToAction)
    }

    /**
     * « Ça me convient » ne rend plus que le souvenir : les étapes offertes
     * d'un ancien serveur sont ignorées.
     */
    @Test
    fun aValidationIgnoresTheOldOfferedSteps() {
        val json =
            """
            { "entry": { "id": "e1", "memoId": "m", "kind": "audio", "status": "ready", "redactionStatus": "ready",
                         "capturedAt": "2026-10-03T10:00:00.000Z", "createdAt": "2026-10-03T10:00:00.000Z" },
              "offeredSteps": 3, "remainingSteps": 1 }
            """
        val validation = MemoBookJson.decodeFromString<EntryValidation>(json)
        assertEquals("e1", validation.entry.id)
    }

    /** Un tour qui attend le crédit de demain n'est ni envoyé, ni en échec. */
    @Test
    fun waitingForCreditIsNeitherSentNorFailed() {
        val delivery = ChatDelivery.WaitingForCredit(until = null)
        assertTrue(delivery.isWaitingForCredit)
        assertFalse(delivery.hasFailed)
        assertFalse(ChatDelivery.Failed("non").isWaitingForCredit)
    }

    /** Un tour qui attend l'illimité n'attend pas demain, et n'a pas échoué. */
    @Test
    fun waitingForUnlimitedIsNeitherTomorrowNorFailed() {
        val delivery = ChatDelivery.WaitingForUnlimited
        assertTrue(delivery.isWaitingForUnlimited)
        assertFalse(delivery.isWaitingForCredit)
        assertFalse(delivery.hasFailed)
        assertFalse(ChatDelivery.WaitingForCredit(until = null).isWaitingForUnlimited)
    }
}
