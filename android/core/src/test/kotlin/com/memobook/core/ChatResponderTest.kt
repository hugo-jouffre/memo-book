package com.memobook.core

import java.time.Instant
import kotlin.coroutines.Continuation
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.startCoroutine
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * Ce qui fait qu'on croit — ou pas — à MEMO. Le jumeau de `ChatResponderTests.swift`.
 *
 * Le moteur local est **déterministe et sans état** : c'est ce qui permet de
 * le vérifier ici, sans émulateur ni réseau. Chaque test verrouille une des
 * règles qui font qu'une réponse a l'air lue plutôt que tirée au sort.
 */
class ChatResponderTest {
    private val responder = LocalMemoResponder(voice = LocalMemoResponder.VoiceMode.Unavailable)
    private val context = ChatContext(
        tripId = "trip-rome",
        tripTitle = "Rome entre frère et sœur",
        travellerFirstName = "Camille",
        placeName = "Trastevere",
        stepNumber = 1,
        prompt = "Comment ça se passe à Trastevere ?",
    )

    // MARK: - L'analyse

    @Test
    fun readsTimeMarkers() {
        assertTrue(ChatSignals.read("Hier on a marché longtemps.").hasWhen)
        assertTrue(ChatSignals.read("On est partis à 18 h du refuge.").hasWhen)
        assertTrue(ChatSignals.read("C'était le 26 août, il faisait chaud.").hasWhen)
        assertFalse(ChatSignals.read("On a marché longtemps et c'était beau.").hasWhen)
    }

    @Test
    fun readsPlacesFromStrongPrepositions() {
        assertEquals("Trastevere", ChatSignals.read("On est allés à Trastevere en fin de journée.").places.firstOrNull())
        assertEquals("Monti", ChatSignals.read("On a marché jusqu'à Monti.").places.firstOrNull())
    }

    /**
     * « de » ne désigne un lieu que derrière un nom de lieu générique. Sans
     * cette règle, MEMO demanderait ce qui nous a marqué « là-bas » à propos
     * d'une personne.
     */
    @Test
    fun weakPrepositionNeedsAGenericPlace() {
        assertTrue("Testaccio" in ChatSignals.read("On a fait le marché de Testaccio.").places)
        assertFalse("Camille" in ChatSignals.read("On a dormi dans l'appartement de Camille.").places)
    }

    /**
     * Un même mot ne peut pas être à la fois quelqu'un et un endroit : c'est la
     * préposition qui tranche, et « avec » gagne.
     */
    @Test
    fun peopleAndPlacesNeverOverlap() {
        val signals = ChatSignals.read("On a marché jusqu'au marché de Testaccio avec Mila.")

        assertTrue("Mila" in signals.people)
        assertFalse("Mila" in signals.places)
        assertTrue("Testaccio" in signals.places)
    }

    /**
     * Une majuscule qui ouvre une phrase est grammaticale : elle ne désigne
     * personne.
     */
    @Test
    fun sentenceOpenerIsNotAPerson() {
        assertTrue(ChatSignals.read("Hier était une belle journée.").people.isEmpty())
    }

    @Test
    fun copiesFiguresVerbatim() {
        assertEquals(listOf("12 km"), ChatSignals.read("On a fait 12 km à pied.").figures)
        assertEquals(listOf("35 €"), ChatSignals.read("Le repas nous a coûté 35 euros.").figures)
        assertEquals(listOf("12 km"), ChatSignals.read("On a marché 12km ce matin.").figures)
    }

    @Test
    fun readsMoodAndRefusal() {
        assertEquals(ChatSignals.Mood.Positive, ChatSignals.read("C'était vraiment magnifique, un coup de cœur.").mood)
        assertEquals(ChatSignals.Mood.Negative, ChatSignals.read("Journée épuisée et compliquée, tout était raté.").mood)
        assertEquals(ChatSignals.Mood.Neutral, ChatSignals.read("On a marché puis on a mangé.").mood)
        assertTrue(ChatSignals.read("Pas envie ce soir.").isRefusal)
    }

    /**
     * « demain » est trop courant pour peser seul : sans cette nuance, un
     * projet de voyage serait lu comme une fin de non-recevoir.
     */
    @Test
    fun softRefusalOnlyCountsInAShortMessage() {
        assertTrue(ChatSignals.read("Demain").isRefusal)
        assertFalse(
            ChatSignals.read(
                "Demain on part pour Lisbonne et j'ai vraiment hâte de voir la ville.",
            ).isRefusal,
        )
    }

    // MARK: - La priorité

    @Test
    fun aRefusalNeverGetsAQuestion() {
        val reply = reply(turn("Laisse tomber pour ce soir."))

        assertEquals(ChatCopy.refusal, text(reply))
        assertFalse(assertNotNull(text(reply)).endsWith("?"))
    }

    /**
     * Répondre à une question par une question est le pire des aveux : il
     * prouve que rien n'a été lu.
     */
    @Test
    fun aQuestionNeverGetsAPrompt() {
        val reply = reply(turn("Comment je corrige un texte que tu as écrit ?"))

        assertEquals(ChatCopy.Answer.corrections, text(reply))
    }

    /**
     * Le prix, l'abonnement, la limite du jour : la même réponse que le
     * serveur, avec le bouton « Découvrir l’abonnement » sous la bulle.
     */
    @Test
    fun aSubscriptionQuestionGetsTheAnswerAndItsButton() {
        for (question in listOf(
            "Combien coûte l'abonnement ?",
            "Il me reste combien de temps aujourd'hui ?",
            "C'est quoi la limite du crédit ?",
        )) {
            val reply = reply(turn(question))
            assertEquals(ChatCopy.Answer.subscription, text(reply), question)
            assertEquals(ChatCallToAction.Kind.Subscribe, reply.beats.lastOrNull()?.message?.callToAction?.kind, question)
        }
    }

    /**
     * « coute » est dans « tu m'écoutes ? » : le lexique se lit en début de
     * mot, comme sur le serveur.
     */
    @Test
    fun listeningIsNotAPriceQuestion() {
        val reply = reply(turn("Est-ce que tu m'écoutes ?"))
        assertNotEquals(ChatCopy.Answer.subscription, text(reply))
        assertNull(reply.beats.lastOrNull()?.message?.callToAction)
    }

    /**
     * « euro » attrapait « Europe », « limit » la limite de vitesse, « prix »
     * le prix du carnet — et MEMO posait l'offre dessous (03/10/2026). Les
     * mêmes phrases que `conversation.test.ts`.
     */
    @Test
    fun aTravelQuestionIsNotASubscriptionQuestion() {
        for (question in listOf(
            "Tu connais des bons restos en Europe ?",
            "On a pris l’Eurostar ce matin, tu savais ?",
            "Le musée est gratuit le dimanche ?",
            "Quelle est la limite de vitesse en Italie ?",
            "Il fallait payer l’entrée du Colisée ?",
            "Combien coûte le carnet MemoBook ?",
            "Le billet de train coûte combien ?",
            "Quel est le prix du billet pour le Vatican ?",
            "J’ai payé par carte de crédit, c’est grave ?",
            "Le musée, c’est payant ?",
            "Il me reste combien de jours de voyage ?",
            // S02 (03/10/2026) : le temps d'un trajet, le crédit du téléphone,
            // le wifi illimité, une autre app.
            "C’est à combien de minutes à pied, le Colisée ?",
            "Il y a une limite de temps pour visiter le Louvre ?",
            "Il me reste combien de temps avant l’embarquement ?",
            "Il reste combien de minutes avant le départ du train ?",
            "Combien de temps pour aller au Colisée ?",
            "Je n’ai plus de crédit sur mon téléphone, tu sais où recharger ?",
            "Il me reste du crédit sur ma carte SIM ?",
            "On a eu le wifi illimité ?",
            "La voiture de location a le kilométrage illimité ?",
            "L’abonnement de métro vaut le coup ?",
            "Je dois résilier mon forfait téléphone ?",
            "Il y a une app gratuite pour le métro de Rome ?",
            "Tu connais une appli gratuite pour traduire ?",
            "Je suis bloqué à l’aéroport, tu sais quoi faire ?",
            "Il me reste combien jusqu’à Florence ?",
        )) {
            assertNotEquals(ChatSignals.Subject.Subscription, ChatSignals.read(question).subject, question)
            val reply = reply(turn(question))
            assertNull(reply.beats.lastOrNull()?.message?.callToAction, question)
        }
        assertEquals(ChatSignals.Subject.Book, ChatSignals.read("Combien coûte le carnet imprimé ?").subject)
    }

    @Test
    fun theSubscriptionTheCreditAndTheTimeLeftAreSubscriptionQuestions() {
        for (question in listOf(
            "Comment je résilie ?",
            "C’est illimité ?",
            "Mon crédit du jour est fini ?",
            "Combien de minutes je peux raconter ?",
            "Ça coûte combien ?",
            "Est-ce que c’est payant ?",
            "Ça coûte combien, MEMO ?",
            "MemoBook, c'est gratuit ?",
            "Il y a une limite ?",
            // S09 (03/10/2026) : ce qui reste, et pourquoi on est limité.
            "Il me reste combien aujourd’hui ?",
            "Il me reste combien ?",
            "Il me reste combien de temps ?",
            "Combien de temps il me reste ?",
            "Il me reste combien, MEMO ?",
            "Il reste combien de crédit ?",
            "Combien de crédit il reste ?",
            "Pourquoi je suis limité ?",
            "Il y a une limite de temps ?",
            "Combien de minutes par jour ?",
            "Combien de temps je peux raconter par jour ?",
            "Il me reste combien de temps pour raconter le Colisée ?",
            "Le crédit se recharge quand ?",
            "Je n’ai plus de crédit pour raconter ?",
            "L’appli est payante ?",
        )) {
            assertEquals(ChatSignals.Subject.Subscription, ChatSignals.read(question).subject, question)
        }
    }

    /**
     * La question d'exemple du prompt reçoit la réponse et son bouton ; une
     * question de trajet, ni l'une ni l'autre (S02, S09 — 03/10/2026).
     */
    @Test
    fun whatRemainsGetsTheOfferAndATripDoesNot() {
        val remains = reply(turn("Il me reste combien aujourd’hui ?"))
        assertEquals(ChatCopy.Answer.subscription, text(remains))
        assertEquals(ChatCallToAction.Kind.Subscribe, remains.beats.lastOrNull()?.message?.callToAction?.kind)

        for (question in listOf(
            "C’est à combien de minutes à pied, le Colisée ?",
            "Il me reste combien de temps avant l’embarquement ?",
            "Je n’ai plus de crédit sur mon téléphone, tu sais où recharger ?",
        )) {
            val reply = reply(turn(question))
            assertNotEquals(ChatCopy.Answer.subscription, text(reply), question)
            assertNull(reply.beats.lastOrNull()?.message?.callToAction, question)
        }
    }

    @Test
    fun anUnknownQuestionGetsTheHonestFallback() {
        val reply = reply(turn("Est-ce que tu sais faire la cuisine ?"))

        assertEquals(ChatCopy.Answer.unknown, text(reply))
    }

    /** Une émotion difficile s'accuse **avant** toute demande. */
    @Test
    fun aNegativeMoodIsAcknowledgedFirst() {
        val reply = reply(turn("Journée vraiment compliquée, le train était annulé et on a tout raté."))

        assertTrue(assertNotNull(text(reply)) in ChatCopy.negativeMood)
    }

    @Test
    fun aPlaceIsEchoedVerbatim() {
        val reply = reply(turn("On est retournés à Monti hier, c'était calme et on a bien marché."))

        assertEquals(ChatCopy.foundPlace("Monti"), text(reply))
    }

    // MARK: - Le rythme

    /** Une latence nulle est le premier signe qu'il n'y a personne en face. */
    @Test
    fun noBeatIsInstant() {
        for (message in sampleMessages) {
            val reply = reply(turn(message))
            for (beat in reply.beats) {
                assertTrue(beat.pauseMilliseconds > 0, "« $message » répond sans délai")
            }
        }
    }

    /**
     * Une latence **constante** se lit comme une minuterie. Elle doit dépendre
     * de ce que MEMO vient de lire.
     */
    @Test
    fun paceDependsOnWhatWasSaid() {
        val short = reply(turn("Oui."))
        val long = reply(turn("On a marché longtemps dans la vieille ville. ".repeat(5)))

        assertTrue(short.beats[0].pauseMilliseconds < long.beats[0].pauseMilliseconds)
    }

    // MARK: - L'anti-répétition

    /**
     * Le même message rend toujours la même réponse : c'est ce qui rend le
     * moteur testable, et ce qui interdit l'aléatoire.
     */
    @Test
    fun theSameTurnAlwaysGivesTheSameReply() {
        val first = reply(turn("On a marché toute la journée."))
        val second = reply(turn("On a marché toute la journée."))

        assertEquals(text(first), text(second))
    }

    /**
     * La rotation neutre est **parcourue en entier** avant qu'une relance
     * revienne : la mémoire du moteur, c'est l'historique, et il descend d'un
     * cran plutôt que de se répéter.
     */
    @Test
    fun theNeutralRotationIsExhaustedBeforeRepeating() {
        val answers = neutralConversation(turns = ChatCopy.rotation.size)

        assertEquals(
            ChatCopy.rotation.size,
            answers.toSet().size,
            "la rotation devrait être parcourue en entier avant de se répéter",
        )
    }

    /**
     * Une fois la rotation épuisée, MEMO finit forcément par se répéter — mais
     * **jamais deux fois de suite**. C'est la répétition immédiate qui se voit,
     * pas celle d'il y a vingt messages.
     */
    @Test
    fun noPromptRepeatsBackToBack() {
        val answers = neutralConversation(turns = 20)

        for ((previous, next) in answers.zipWithNext()) {
            assertNotEquals(previous, next, "deux relances identiques d'affilée")
        }
    }

    /**
     * Une suite de tours sans le moindre signal : c'est là que la rotation
     * travaille seule.
     */
    private fun neutralConversation(turns: Int): List<String> {
        val history = mutableListOf<ChatMessage>()
        val answers = mutableListOf<String>()

        for (index in 0 until turns) {
            val message = travellerMessage("On a un peu tourné en rond, et puis voilà. ($index)")
            val reply = reply(ChatTurn(message = message, history = history.toList(), context = context))
            answers.add(assertNotNull(text(reply)))

            history.add(message)
            history.addAll(reply.beats.map { it.message })
        }

        return answers
    }

    // MARK: - Le vocal

    /**
     * Une fiche « Retranscription du contexte » remplie d'un texte que personne
     * n'a écouté est un fait inventé — et il finirait imprimé.
     */
    @Test
    fun anUnavailableTranscriptStaysEmpty() {
        val note = VoiceNote(id = "v1", duration = 37.0)
        val reply = reply(turn(ChatMessageBody.Voice(note)))

        val card = assertNotNull(firstCard(reply))
        assertNull(card.text)
        assertFalse(card.isSimulated)
        assertNull(card.footnote)
    }

    /**
     * Un vocal vaut **deux** temps : la fiche, puis la relance. Un bloc unique
     * qui tombe d'un coup ne ressemble à rien de vivant.
     */
    @Test
    fun aVoiceNoteAnswersInTwoBeats() {
        val reply = reply(turn(ChatMessageBody.Voice(VoiceNote(id = "v1", duration = 37.0))))

        assertEquals(2, reply.beats.size)
        if (reply.beats[0].message.body !is ChatMessageBody.Transcript) {
            fail("la première bulle d'un vocal doit être la fiche")
        }
    }

    /**
     * Le moteur simulé reste déterministe, et **se dénonce** : sans
     * `isSimulated`, un texte fabriqué pourrait partir vers le carnet.
     */
    @Test
    fun aSimulatedTranscriptIsMarkedAndStable() {
        val simulator = LocalMemoResponder(voice = LocalMemoResponder.VoiceMode.Simulated)
        val note = VoiceNote(id = "v1", duration = 37.0)

        val first = reply(turn(ChatMessageBody.Voice(note)), simulator)
        val second = reply(turn(ChatMessageBody.Voice(note)), simulator)

        val card = assertNotNull(firstCard(first))
        assertNotNull(card.text)
        assertTrue(card.isSimulated)
        assertEquals(ChatCopy.transcriptFootnote, card.footnote)
        assertEquals(firstCard(second)?.text, card.text)
    }

    // MARK: - Les suggestions

    /**
     * Le trio de validation ne suit qu'une fiche qui porte du vrai texte :
     * trois puces « Ça me convient » sous une question ouverte ne répondent à
     * rien.
     */
    @Test
    fun theValidationTrioOnlyFollowsARealTranscript() {
        val empty = reply(turn(ChatMessageBody.Voice(VoiceNote(id = "v1", duration = 12.0))))
        assertFalse(empty.suggestions.any { it.label == ChatCopy.Suggest.accept })

        val filled = reply(
            turn(ChatMessageBody.Voice(VoiceNote(id = "v1", duration = 12.0))),
            LocalMemoResponder(voice = LocalMemoResponder.VoiceMode.Simulated),
        )
        assertTrue(filled.suggestions.any { it.label == ChatCopy.Suggest.accept })
    }

    /**
     * « À la main » ne se contente pas d'ouvrir le clavier : la puce porte
     * l'intention qui pose la retranscription dans le champ. Un serveur qui
     * enverra la sienne dira la même chose, sous le même nom.
     */
    @Test
    fun editingByHandCarriesTheTranscriptIntoTheComposer() {
        val filled = reply(
            turn(ChatMessageBody.Voice(VoiceNote(id = "v1", duration = 12.0))),
            LocalMemoResponder(voice = LocalMemoResponder.VoiceMode.Simulated),
        )
        val byHand = filled.suggestions.firstOrNull { it.label == ChatCopy.Suggest.editByHand }

        assertEquals(ChatSuggestion.Intent.SendThenEditTranscript, byHand?.intent)
        assertEquals("send_then_edit_transcript", ChatSuggestion.Intent.SendThenEditTranscript.rawValue)
    }

    @Test
    fun everyTurnOffersAtMostThreeSuggestions() {
        for (message in sampleMessages) {
            val reply = reply(turn(message))
            assertTrue(reply.suggestions.size <= 3, "trop de puces pour « $message »")
        }
    }

    /**
     * Une puce renvoie son propre libellé comme message : MEMO doit savoir y
     * répondre autrement que par une relance au hasard.
     */
    @Test
    fun suggestionsAreAnswered() {
        val reply = reply(turn(ChatCopy.Suggest.accept))

        assertEquals(ChatCopy.acknowledged, text(reply))
    }

    // MARK: - L'ouverture

    /**
     * La bulle d'ouverture se termine sur une question — le contexte du
     * voyage — et **rien ne vient après**, même quand le voyage porte une
     * relance : « Comment ça se passe à Testaccio ? » n'est pas une bulle
     * (Hugo, 17/09/2026).
     */
    @Test
    fun theOpeningIsTheSingleOpeningBubble() {
        val opening = responder.opening(context)

        assertNotNull(context.prompt, "Le contexte de test porte une relance, et elle ne doit pas s'entendre.")
        assertEquals(1, opening.beats.size)
        assertEquals(ChatCopy.opening, bodyText(opening.beats[0].message))
    }

    @Test
    fun theOpeningWithoutAPromptIsTheSameSingleBeat() {
        val bare = ChatContext(tripId = "trip-rome")
        assertEquals(1, responder.opening(bare).beats.size)
    }

    // MARK: - Outils

    private val sampleMessages = listOf(
        "Oui.",
        "Pas envie ce soir.",
        "Comment marche l'impression du carnet ?",
        "On est allés à Monti hier, c'était magnifique.",
        "Journée compliquée, le train était annulé.",
        "On a fait 12 km avec Mila.",
        "On a marché longtemps dans la vieille ville. ".repeat(12),
    )

    private fun reply(turn: ChatTurn, engine: MemoResponder = responder): MemoReply =
        awaitWithoutDispatcher { engine.reply(turn) }

    private fun turn(text: String): ChatTurn = turn(ChatMessageBody.Text(text))

    private fun turn(body: ChatMessageBody): ChatTurn =
        ChatTurn(
            message = ChatMessage(id = "t1", author = ChatAuthor.Traveller, body = body, sentAt = distantPast),
            history = emptyList(),
            context = context,
        )

    private fun travellerMessage(text: String): ChatMessage =
        ChatMessage(
            id = "t-${text.length}-${text.hashCode()}",
            author = ChatAuthor.Traveller,
            body = ChatMessageBody.Text(text),
            sentAt = distantPast,
        )

    private fun text(reply: MemoReply): String? = reply.beats.firstNotNullOfOrNull { bodyText(it.message) }

    private fun bodyText(message: ChatMessage): String? = (message.body as? ChatMessageBody.Text)?.value

    private fun firstCard(reply: MemoReply): TranscriptCard? =
        reply.beats.firstNotNullOfOrNull { (it.message.body as? ChatMessageBody.Transcript)?.card }

    private val distantPast: Instant = Instant.parse("0001-01-01T00:00:00Z")
}

/**
 * Le `async` des tests XCTest : le moteur local ne suspend jamais, la
 * coroutine se termine donc dans l'appel — sans dépendre de
 * kotlinx-coroutines, que `:core` n'embarque pas.
 */
internal fun <T> awaitWithoutDispatcher(block: suspend () -> T): T {
    var outcome: Result<T>? = null
    block.startCoroutine(Continuation(EmptyCoroutineContext) { outcome = it })
    return checkNotNull(outcome) { "La coroutine a suspendu : ce test ne sait pas l'attendre." }.getOrThrow()
}
