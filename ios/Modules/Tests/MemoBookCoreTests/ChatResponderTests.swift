import XCTest

@testable import MemoBookCore

/// Ce qui fait qu'on croit — ou pas — à MEMO.
///
/// Le moteur local est **déterministe et sans état** : c'est ce qui permet de
/// le vérifier ici, sans simulateur ni réseau. Chaque test verrouille une des
/// règles qui font qu'une réponse a l'air lue plutôt que tirée au sort.
final class ChatResponderTests: XCTestCase {
    private let responder = LocalMemoResponder(voice: .unavailable)
    private let context = ChatContext(
        tripId: "trip-rome",
        tripTitle: "Rome entre frère et sœur",
        travellerFirstName: "Camille",
        placeName: "Trastevere",
        stepNumber: 1,
        prompt: "Comment ça se passe à Trastevere ?"
    )

    // MARK: - L'analyse

    func testReadsTimeMarkers() {
        XCTAssertTrue(ChatSignals.read("Hier on a marché longtemps.").hasWhen)
        XCTAssertTrue(ChatSignals.read("On est partis à 18 h du refuge.").hasWhen)
        XCTAssertTrue(ChatSignals.read("C'était le 26 août, il faisait chaud.").hasWhen)
        XCTAssertFalse(ChatSignals.read("On a marché longtemps et c'était beau.").hasWhen)
    }

    func testReadsPlacesFromStrongPrepositions() {
        XCTAssertEqual(ChatSignals.read("On est allés à Trastevere en fin de journée.").places.first, "Trastevere")
        XCTAssertEqual(ChatSignals.read("On a marché jusqu'à Monti.").places.first, "Monti")
    }

    /// « de » ne désigne un lieu que derrière un nom de lieu générique. Sans
    /// cette règle, MEMO demanderait ce qui nous a marqué « là-bas » à propos
    /// d'une personne.
    func testWeakPrepositionNeedsAGenericPlace() {
        XCTAssertTrue(ChatSignals.read("On a fait le marché de Testaccio.").places.contains("Testaccio"))
        XCTAssertFalse(ChatSignals.read("On a dormi dans l'appartement de Camille.").places.contains("Camille"))
    }

    /// Un même mot ne peut pas être à la fois quelqu'un et un endroit : c'est la
    /// préposition qui tranche, et « avec » gagne.
    func testPeopleAndPlacesNeverOverlap() {
        let signals = ChatSignals.read("On a marché jusqu'au marché de Testaccio avec Mila.")

        XCTAssertTrue(signals.people.contains("Mila"))
        XCTAssertFalse(signals.places.contains("Mila"))
        XCTAssertTrue(signals.places.contains("Testaccio"))
    }

    /// Une majuscule qui ouvre une phrase est grammaticale : elle ne désigne
    /// personne.
    func testSentenceOpenerIsNotAPerson() {
        XCTAssertTrue(ChatSignals.read("Hier était une belle journée.").people.isEmpty)
    }

    func testCopiesFiguresVerbatim() {
        XCTAssertEqual(ChatSignals.read("On a fait 12 km à pied.").figures, ["12 km"])
        XCTAssertEqual(ChatSignals.read("Le repas nous a coûté 35 euros.").figures, ["35 €"])
        XCTAssertEqual(ChatSignals.read("On a marché 12km ce matin.").figures, ["12 km"])
    }

    func testReadsMoodAndRefusal() {
        XCTAssertEqual(ChatSignals.read("C'était vraiment magnifique, un coup de cœur.").mood, .positive)
        XCTAssertEqual(ChatSignals.read("Journée épuisée et compliquée, tout était raté.").mood, .negative)
        XCTAssertEqual(ChatSignals.read("On a marché puis on a mangé.").mood, .neutral)
        XCTAssertTrue(ChatSignals.read("Pas envie ce soir.").isRefusal)
    }

    /// « demain » est trop courant pour peser seul : sans cette nuance, un
    /// projet de voyage serait lu comme une fin de non-recevoir.
    func testSoftRefusalOnlyCountsInAShortMessage() {
        XCTAssertTrue(ChatSignals.read("Demain").isRefusal)
        XCTAssertFalse(
            ChatSignals.read(
                "Demain on part pour Lisbonne et j'ai vraiment hâte de voir la ville."
            ).isRefusal
        )
    }

    // MARK: - La priorité

    func testARefusalNeverGetsAQuestion() async throws {
        let reply = try await responder.reply(to: turn("Laisse tomber pour ce soir."))

        XCTAssertEqual(text(of: reply), ChatCopy.refusal)
        XCTAssertFalse(try XCTUnwrap(text(of: reply)).hasSuffix("?"))
    }

    /// Répondre à une question par une question est le pire des aveux : il
    /// prouve que rien n'a été lu.
    func testAQuestionNeverGetsAPrompt() async throws {
        let reply = try await responder.reply(to: turn("Comment je corrige un texte que tu as écrit ?"))

        XCTAssertEqual(text(of: reply), ChatCopy.Answer.corrections)
    }

    /// Le prix, l'abonnement, la limite du jour : la même réponse que le
    /// serveur, avec le bouton « Découvrir l’abonnement » sous la bulle.
    func testASubscriptionQuestionGetsTheAnswerAndItsButton() async throws {
        for question in [
            "Combien coûte l'abonnement ?",
            "Il me reste combien de temps aujourd'hui ?",
            "C'est quoi la limite du crédit ?",
        ] {
            let reply = try await responder.reply(to: turn(question))
            XCTAssertEqual(text(of: reply), ChatCopy.Answer.subscription, question)
            XCTAssertEqual(reply.beats.last?.message.callToAction?.kind, .subscribe, question)
        }
    }

    /// « coute » est dans « tu m'écoutes ? » : le lexique se lit en début de
    /// mot, comme sur le serveur.
    func testListeningIsNotAPriceQuestion() async throws {
        let reply = try await responder.reply(to: turn("Est-ce que tu m'écoutes ?"))
        XCTAssertNotEqual(text(of: reply), ChatCopy.Answer.subscription)
        XCTAssertNil(reply.beats.last?.message.callToAction)
    }

    /// « euro » attrapait « Europe », « limit » la limite de vitesse, « prix »
    /// le prix du carnet — et MEMO posait l'offre dessous (03/10/2026). Les
    /// mêmes phrases que `conversation.test.ts`.
    func testATravelQuestionIsNotASubscriptionQuestion() async throws {
        for question in [
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
        ] {
            XCTAssertNotEqual(ChatSignals.read(question).subject, .subscription, question)
            let reply = try await responder.reply(to: turn(question))
            XCTAssertNil(reply.beats.last?.message.callToAction, question)
        }
        XCTAssertEqual(ChatSignals.read("Combien coûte le carnet imprimé ?").subject, .book)
    }

    func testTheSubscriptionTheCreditAndTheTimeLeftAreSubscriptionQuestions() {
        for question in [
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
        ] {
            XCTAssertEqual(ChatSignals.read(question).subject, .subscription, question)
        }
    }

    /// La question d'exemple du prompt reçoit la réponse et son bouton ; une
    /// question de trajet, ni l'une ni l'autre (S02, S09 — 03/10/2026).
    func testWhatRemainsGetsTheOfferAndATripDoesNot() async throws {
        let remains = try await responder.reply(to: turn("Il me reste combien aujourd’hui ?"))
        XCTAssertEqual(text(of: remains), ChatCopy.Answer.subscription)
        XCTAssertEqual(remains.beats.last?.message.callToAction?.kind, .subscribe)

        for question in [
            "C’est à combien de minutes à pied, le Colisée ?",
            "Il me reste combien de temps avant l’embarquement ?",
            "Je n’ai plus de crédit sur mon téléphone, tu sais où recharger ?",
        ] {
            let reply = try await responder.reply(to: turn(question))
            XCTAssertNotEqual(text(of: reply), ChatCopy.Answer.subscription, question)
            XCTAssertNil(reply.beats.last?.message.callToAction, question)
        }
    }

    func testAnUnknownQuestionGetsTheHonestFallback() async throws {
        let reply = try await responder.reply(to: turn("Est-ce que tu sais faire la cuisine ?"))

        XCTAssertEqual(text(of: reply), ChatCopy.Answer.unknown)
    }

    /// Une émotion difficile s'accuse **avant** toute demande.
    func testANegativeMoodIsAcknowledgedFirst() async throws {
        let reply = try await responder.reply(
            to: turn("Journée vraiment compliquée, le train était annulé et on a tout raté.")
        )

        XCTAssertTrue(ChatCopy.negativeMood.contains(try XCTUnwrap(text(of: reply))))
    }

    func testAPlaceIsEchoedVerbatim() async throws {
        let reply = try await responder.reply(
            to: turn("On est retournés à Monti hier, c'était calme et on a bien marché.")
        )

        XCTAssertEqual(text(of: reply), ChatCopy.foundPlace("Monti"))
    }

    // MARK: - Le rythme

    /// Une latence nulle est le premier signe qu'il n'y a personne en face.
    func testNoBeatIsInstant() async throws {
        for message in Self.sampleMessages {
            let reply = try await responder.reply(to: turn(message))
            for beat in reply.beats {
                XCTAssertGreaterThan(beat.pauseMilliseconds, 0, "« \(message) » répond sans délai")
            }
        }
    }

    /// Une latence **constante** se lit comme un `Timer`. Elle doit dépendre de
    /// ce que MEMO vient de lire.
    func testPaceDependsOnWhatWasSaid() async throws {
        let short = try await responder.reply(to: turn("Oui."))
        let long = try await responder.reply(
            to: turn(String(repeating: "On a marché longtemps dans la vieille ville. ", count: 5))
        )

        XCTAssertLessThan(
            short.beats[0].pauseMilliseconds,
            long.beats[0].pauseMilliseconds
        )
    }

    // MARK: - L'anti-répétition

    /// Le même message rend toujours la même réponse : c'est ce qui rend le
    /// moteur testable, et ce qui interdit l'aléatoire.
    func testTheSameTurnAlwaysGivesTheSameReply() async throws {
        let first = try await responder.reply(to: turn("On a marché toute la journée."))
        let second = try await responder.reply(to: turn("On a marché toute la journée."))

        XCTAssertEqual(text(of: first), text(of: second))
    }

    /// La rotation neutre est **parcourue en entier** avant qu'une relance
    /// revienne : la mémoire du moteur, c'est l'historique, et il descend d'un
    /// cran plutôt que de se répéter.
    func testTheNeutralRotationIsExhaustedBeforeRepeating() async throws {
        let answers = try await neutralConversation(turns: ChatCopy.rotation.count)

        XCTAssertEqual(
            Set(answers).count,
            ChatCopy.rotation.count,
            "la rotation devrait être parcourue en entier avant de se répéter"
        )
    }

    /// Une fois la rotation épuisée, MEMO finit forcément par se répéter — mais
    /// **jamais deux fois de suite**. C'est la répétition immédiate qui se voit,
    /// pas celle d'il y a vingt messages.
    func testNoPromptRepeatsBackToBack() async throws {
        let answers = try await neutralConversation(turns: 20)

        for (previous, next) in zip(answers, answers.dropFirst()) {
            XCTAssertNotEqual(previous, next, "deux relances identiques d'affilée")
        }
    }

    /// Une suite de tours sans le moindre signal : c'est là que la rotation
    /// travaille seule.
    private func neutralConversation(turns: Int) async throws -> [String] {
        var history: [ChatMessage] = []
        var answers: [String] = []

        for index in 0..<turns {
            let message = travellerMessage("On a un peu tourné en rond, et puis voilà. (\(index))")
            let reply = try await responder.reply(
                to: ChatTurn(message: message, history: history, context: context)
            )
            answers.append(try XCTUnwrap(text(of: reply)))

            history.append(message)
            history.append(contentsOf: reply.beats.map(\.message))
        }

        return answers
    }

    // MARK: - Le vocal

    /// Une fiche « Retranscription du contexte » remplie d'un texte que personne
    /// n'a écouté est un fait inventé — et il finirait imprimé.
    func testAnUnavailableTranscriptStaysEmpty() async throws {
        let note = VoiceNote(id: "v1", duration: 37)
        let reply = try await responder.reply(to: turn(.voice(note)))

        let card = try XCTUnwrap(firstCard(of: reply))
        XCTAssertNil(card.text)
        XCTAssertFalse(card.isSimulated)
        XCTAssertNil(card.footnote)
    }

    /// Un vocal vaut **deux** temps : la fiche, puis la relance. Un bloc unique
    /// qui tombe d'un coup ne ressemble à rien de vivant.
    func testAVoiceNoteAnswersInTwoBeats() async throws {
        let reply = try await responder.reply(to: turn(.voice(VoiceNote(id: "v1", duration: 37))))

        XCTAssertEqual(reply.beats.count, 2)
        if case .transcript = reply.beats[0].message.body {} else {
            XCTFail("la première bulle d'un vocal doit être la fiche")
        }
    }

    /// Le moteur simulé reste déterministe, et **se dénonce** : sans
    /// `isSimulated`, un texte fabriqué pourrait partir vers le carnet.
    func testASimulatedTranscriptIsMarkedAndStable() async throws {
        let simulator = LocalMemoResponder(voice: .simulated)
        let note = VoiceNote(id: "v1", duration: 37)

        let first = try await simulator.reply(to: turn(.voice(note)))
        let second = try await simulator.reply(to: turn(.voice(note)))

        let card = try XCTUnwrap(firstCard(of: first))
        XCTAssertNotNil(card.text)
        XCTAssertTrue(card.isSimulated)
        XCTAssertEqual(card.footnote, ChatCopy.transcriptFootnote)
        XCTAssertEqual(card.text, firstCard(of: second)?.text)
    }

    // MARK: - Les suggestions

    /// Le trio de validation ne suit qu'une fiche qui porte du vrai texte :
    /// trois puces « Ça me convient » sous une question ouverte ne répondent à
    /// rien.
    func testTheValidationTrioOnlyFollowsARealTranscript() async throws {
        let empty = try await responder.reply(to: turn(.voice(VoiceNote(id: "v1", duration: 12))))
        XCTAssertFalse(empty.suggestions.contains { $0.label == ChatCopy.Suggest.accept })

        let filled = try await LocalMemoResponder(voice: .simulated)
            .reply(to: turn(.voice(VoiceNote(id: "v1", duration: 12))))
        XCTAssertTrue(filled.suggestions.contains { $0.label == ChatCopy.Suggest.accept })
    }

    /// « À la main » ne se contente pas d'ouvrir le clavier : la puce porte
    /// l'intention qui pose la retranscription dans le champ. Un serveur qui
    /// enverra la sienne dira la même chose, sous le même nom.
    func testEditingByHandCarriesTheTranscriptIntoTheComposer() async throws {
        let filled = try await LocalMemoResponder(voice: .simulated)
            .reply(to: turn(.voice(VoiceNote(id: "v1", duration: 12))))
        let byHand = filled.suggestions.first { $0.label == ChatCopy.Suggest.editByHand }

        XCTAssertEqual(byHand?.intent, .sendThenEditTranscript)
        XCTAssertEqual(ChatSuggestion.Intent.sendThenEditTranscript.rawValue, "send_then_edit_transcript")
    }

    func testEveryTurnOffersAtMostThreeSuggestions() async throws {
        for message in Self.sampleMessages {
            let reply = try await responder.reply(to: turn(message))
            XCTAssertLessThanOrEqual(reply.suggestions.count, 3, "trop de puces pour « \(message) »")
        }
    }

    /// Une puce renvoie son propre libellé comme message : MEMO doit savoir y
    /// répondre autrement que par une relance au hasard.
    func testSuggestionsAreAnswered() async throws {
        let reply = try await responder.reply(to: turn(ChatCopy.Suggest.accept))

        XCTAssertEqual(text(of: reply), ChatCopy.acknowledged)
    }

    // MARK: - L'ouverture

    /// La bulle d'ouverture se termine sur une question — le contexte du
    /// voyage — et **rien ne vient après**, même quand le voyage porte une
    /// relance : « Comment ça se passe à Testaccio ? » n'est pas une bulle
    /// (Hugo, 17/09/2026).
    func testTheOpeningIsTheSingleOpeningBubble() {
        let opening = responder.opening(for: context)

        XCTAssertNotNil(context.prompt, "Le contexte de test porte une relance, et elle ne doit pas s'entendre.")
        XCTAssertEqual(opening.beats.count, 1)
        XCTAssertEqual(bodyText(opening.beats[0].message), ChatCopy.opening)
    }

    func testTheOpeningWithoutAPromptIsTheSameSingleBeat() {
        let bare = ChatContext(tripId: "trip-rome")
        XCTAssertEqual(responder.opening(for: bare).beats.count, 1)
    }

    // MARK: - Outils

    private static let sampleMessages = [
        "Oui.",
        "Pas envie ce soir.",
        "Comment marche l'impression du carnet ?",
        "On est allés à Monti hier, c'était magnifique.",
        "Journée compliquée, le train était annulé.",
        "On a fait 12 km avec Mila.",
        String(repeating: "On a marché longtemps dans la vieille ville. ", count: 12),
    ]

    private func turn(_ text: String) -> ChatTurn {
        turn(.text(text))
    }

    private func turn(_ body: ChatMessageBody) -> ChatTurn {
        ChatTurn(
            message: ChatMessage(id: "t1", author: .traveller, body: body, sentAt: .distantPast),
            history: [],
            context: context
        )
    }

    private func travellerMessage(_ text: String) -> ChatMessage {
        ChatMessage(
            id: "t-\(text.count)-\(text.hashValue)",
            author: .traveller,
            body: .text(text),
            sentAt: .distantPast
        )
    }

    private func text(of reply: MemoReply) -> String? {
        reply.beats.compactMap { bodyText($0.message) }.first
    }

    private func bodyText(_ message: ChatMessage) -> String? {
        if case .text(let value) = message.body { return value }
        return nil
    }

    private func firstCard(of reply: MemoReply) -> TranscriptCard? {
        for beat in reply.beats {
            if case .transcript(let card) = beat.message.body { return card }
        }
        return nil
    }
}
