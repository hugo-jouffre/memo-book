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
