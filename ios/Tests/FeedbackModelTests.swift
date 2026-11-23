@testable import MemoBookFeature
import MemoBookCore
import MemoBookNetworking
import XCTest

/// **La demande d'avis** — T273.
///
/// Ce qui se teste ici est la règle, pas le dessin : qui voit la modale,
/// combien de fois on la demande, ce qu'on peut envoyer, et ce que le serveur
/// apprend quand on la referme sans répondre.
@MainActor
final class FeedbackModelTests: XCTestCase {
    private actor Script {
        var campaign: FeedbackCampaign?
        private(set) var loads = 0
        private(set) var sent: [(campaignId: String, response: FeedbackResponse)] = []
        var fails = false

        init(campaign: FeedbackCampaign?) { self.campaign = campaign }

        func load() throws -> FeedbackCampaign? {
            loads += 1
            if fails { throw APIError.server(statusCode: 500, code: nil, message: "Rien à dire.") }
            return campaign
        }

        func submit(_ campaignId: String, _ response: FeedbackResponse) {
            sent.append((campaignId, response))
        }

        func failLoading() { fails = true }
    }

    private func model(_ script: Script, appVersion: String? = "1.4.2") -> FeedbackModel {
        FeedbackModel(
            load: { try await script.load() },
            submit: { id, response in await script.submit(id, response) },
            appVersion: appVersion
        )
    }

    private let choix = FeedbackQuestion(
        id: "q-usage",
        kind: .choice,
        prompt: "Tu racontes…",
        isRequired: true,
        options: [
            FeedbackQuestion.Option(key: "souvent", label: "Souvent"),
            FeedbackQuestion.Option(key: "parfois", label: "Parfois"),
        ]
    )

    private let libre = FeedbackQuestion(id: "q-manque", kind: .text, prompt: "Qu'est-ce qui te manque ?")

    private func campaign(_ questions: [FeedbackQuestion]) -> FeedbackCampaign {
        FeedbackCampaign(id: "camp-1", key: "avis-v1", title: "Comment ça se passe ?", questions: questions)
    }

    // MARK: - Ce qui se montre

    func testLaCampagneArriveEtSeMontre() async {
        let script = Script(campaign: campaign([choix, libre]))
        let model = model(script)

        await model.askOnce()

        XCTAssertEqual(model.campaign?.key, "avis-v1")
    }

    /// ⚠️ La demander **compte comme un affichage** côté serveur : une
    /// seconde demande dans le même lancement brûlerait un affichage pour
    /// rien.
    func testOnNeLaDemandeQuUneFoisParLancement() async throws {
        let script = Script(campaign: campaign([libre]))
        let model = model(script)

        await model.askOnce()
        await model.askOnce()

        let loads = await script.loads
        XCTAssertEqual(loads, 1)
    }

    /// Une forme que cette version ne dessine pas : la campagne entière est
    /// écartée. Une modale à trous rendrait un avis qui ne répond pas à ce
    /// qu'on a demandé.
    func testUneCampagneQuOnNeSaitPasDessinerNeSeMontrePas() async {
        let etoiles = FeedbackQuestion(id: "q-note", kind: .rating, prompt: "Ta note ?")
        let script = Script(campaign: campaign([libre, etoiles]))
        let model = model(script)

        await model.askOnce()

        XCTAssertNil(model.campaign)
    }

    func testUneCampagneSansQuestionNeSeMontrePas() async {
        let script = Script(campaign: campaign([]))
        let model = model(script)

        await model.askOnce()

        XCTAssertNil(model.campaign)
    }

    /// Personne n'a demandé à voir cette modale : un échec ne se dit pas, il
    /// se tait.
    func testUnEchecNeDitRien() async {
        let script = Script(campaign: campaign([libre]))
        await script.failLoading()
        let model = model(script)

        await model.askOnce()

        XCTAssertNil(model.campaign)
    }

    // MARK: - Ce qu'on peut envoyer

    func testLeBoutonAttendLesQuestionsObligatoires() async {
        let script = Script(campaign: campaign([choix, libre]))
        let model = model(script)
        await model.askOnce()

        XCTAssertFalse(model.canSubmit, "Le choix est obligatoire.")
        model.answer(choix, choice: "souvent")
        XCTAssertTrue(model.canSubmit, "Le champ libre, lui, peut rester vide.")
    }

    func testUnChampLibreVideNeFaitPasUneReponse() async throws {
        let script = Script(campaign: campaign([libre]))
        let model = model(script)
        await model.askOnce()

        model.answer(libre, text: "   ")
        model.send()

        try await until("l'avis est parti") { await script.sent.count == 1 }
        let sent = await script.sent[0]
        XCTAssertTrue(sent.response.answers.isEmpty)
    }

    func testEnvoyerPorteLesReponsesEtLaVersion() async throws {
        let script = Script(campaign: campaign([choix, libre]))
        let model = model(script)
        await model.askOnce()

        model.answer(choix, choice: "parfois")
        model.answer(libre, text: "Un mode hors ligne complet.")
        model.send()

        XCTAssertNil(model.campaign, "La modale se referme tout de suite.")
        try await until("l'avis est parti") { await script.sent.count == 1 }
        let sent = await script.sent[0]
        XCTAssertEqual(sent.campaignId, "camp-1")
        XCTAssertFalse(sent.response.dismissed)
        XCTAssertEqual(sent.response.appVersion, "1.4.2")
        XCTAssertEqual(sent.response.answers.map(\.questionId), ["q-usage", "q-manque"])
        XCTAssertEqual(sent.response.answers.first?.choiceKey, "parfois")
        XCTAssertEqual(sent.response.answers.last?.text, "Un mode hors ligne complet.")
    }

    /// Fermer est un résultat : le serveur l'apprend, et ne repropose pas.
    func testFermerSeDitAuServeur() async throws {
        let script = Script(campaign: campaign([libre]))
        let model = model(script)
        await model.askOnce()

        model.dismiss()

        XCTAssertNil(model.campaign)
        try await until("le geste est parti") { await script.sent.count == 1 }
        let sent = await script.sent[0]
        XCTAssertTrue(sent.response.dismissed)
        XCTAssertTrue(sent.response.answers.isEmpty)
    }

    private func until(
        _ what: String,
        timeout: Duration = .seconds(5),
        _ condition: @MainActor () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Jamais atteint : \(what)", file: file, line: line)
    }
}

/// **Le curseur et les étoiles** (T273, reste du 23/11/2026).
///
/// Les deux formes manquaient, et une campagne qui les employait ne se
/// montrait pas du tout. Ce qui se teste ici est ce que l'app comprend de ce
/// que la base écrit — et ce qu'elle refuse de dessiner.
@MainActor
final class FeedbackScaleTests: XCTestCase {
    private func question(_ json: String) throws -> FeedbackQuestion {
        try JSONDecoder().decode(FeedbackQuestion.self, from: Data(json.utf8))
    }

    func testUneNoteNeLitQueSonMaximum() throws {
        let note = try question(#"{"id":"q","kind":"rating","config":{"max":5}}"#)
        XCTAssertEqual(note.scale?.min, 1, "Une note part de 1 : zéro étoile serait une absence de réponse.")
        XCTAssertEqual(note.scale?.max, 5)
        XCTAssertEqual(note.scale?.steps, [1, 2, 3, 4, 5])
        XCTAssertTrue(note.isDrawable)
    }

    func testUnCurseurLitSesBornesEtSesCrans() throws {
        let curseur = try question(
            #"{"id":"q","kind":"slider","config":{"min":0,"max":4,"step":1,"ticks":["Jamais","Peu","Bien","Assez","Trop"],"minLabel":"Pas assez"}}"#
        )
        XCTAssertEqual(curseur.scale?.steps, [0, 1, 2, 3, 4])
        XCTAssertEqual(curseur.scale?.ticks.count, 5)
        XCTAssertEqual(curseur.scale?.minLabel, "Pas assez")
        XCTAssertTrue(curseur.isDrawable)
    }

    /// Une échelle impossible ne se dessine pas de travers : elle ferme la
    /// campagne entière, le temps d'un `UPDATE`.
    func testUneEchelleImpossibleNeSeDessinePas() throws {
        let bornesInversees = try question(#"{"id":"q","kind":"slider","config":{"min":5,"max":1}}"#)
        XCTAssertFalse(bornesInversees.isDrawable)

        let pasQuiNeTombePasJuste = try question(#"{"id":"q","kind":"slider","config":{"min":0,"max":5,"step":2}}"#)
        XCTAssertFalse(pasQuiNeTombePasJuste.isDrawable, "Le dernier cran tomberait entre deux étiquettes.")

        let tropDeCrans = try question(#"{"id":"q","kind":"slider","config":{"min":0,"max":50,"step":1}}"#)
        XCTAssertFalse(tropDeCrans.isDrawable, "Cinquante et un crans ne se touchent pas du pouce.")

        let etiquettesEnMoins = try question(
            #"{"id":"q","kind":"slider","config":{"min":0,"max":2,"step":1,"ticks":["Peu","Trop"]}}"#
        )
        XCTAssertFalse(etiquettesEnMoins.isDrawable, "Trois crans, deux étiquettes : on ne sait pas laquelle manque.")

        let sansBornes = try question(#"{"id":"q","kind":"slider"}"#)
        XCTAssertFalse(sansBornes.isDrawable)
    }

    /// Le trou que le ticket laissait : une liste **sans option** se dessinait
    /// comme un cadre vide, parce que seule la forme était regardée.
    func testUneListeSansOptionNeSeDessinePas() throws {
        let vide = try question(#"{"id":"q","kind":"choice","config":{"options":[]}}"#)
        XCTAssertFalse(vide.isDrawable)

        let campagne = FeedbackCampaign(id: "c", key: "k", title: "T", questions: [vide])
        XCTAssertFalse(campagne.isDrawable, "Une seule question indessinable ferme la campagne.")
    }

    /// Ce que le modèle retient d'un curseur — et ce qu'il ne retient pas.
    func testUnCurseurNonTouchéNeRépondPas() async throws {
        let curseur = try question(#"{"id":"rythme","kind":"slider","isRequired":true,"config":{"min":0,"max":4}}"#)
        let campagne = FeedbackCampaign(id: "c", key: "k", title: "T", questions: [curseur])
        let model = FeedbackModel(load: { campagne }, submit: { _, _ in })
        await model.askOnce()

        XCTAssertNil(model.number(for: curseur), "Rien tant que le doigt n'a rien bougé.")
        XCTAssertFalse(model.canSubmit, "Une question obligatoire sans réponse ferme l'envoi.")

        model.answer(curseur, number: 3)
        XCTAssertEqual(model.number(for: curseur), 3)
        XCTAssertTrue(model.canSubmit)
    }

    func testCeQueVoiceOverDitDUneNote() {
        XCTAssertEqual(FeedbackCopy.ratingValue(nil, max: 5), "Pas encore noté")
        XCTAssertEqual(FeedbackCopy.ratingValue(1, max: 5), "1 étoile sur 5")
        XCTAssertEqual(FeedbackCopy.ratingValue(4, max: 5), "4 étoiles sur 5")
    }
}
