import MemoBookCore
import XCTest

@testable import MemoBookFeature

/// **On ne partage pas un carnet qui n'existe pas encore** (T302, Hugo,
/// 08/11/2026 — « un carnet non composé se présente comme prêt : page blanche,
/// aucun chargement visible, et “Partager” envoie un PDF qui dit lui-même qu'il
/// n'est pas composé »).
///
/// L'état en cause est précis, et le serveur le produit : `status` vient du
/// **dernier** rendu, `pdfUrl` du dernier rendu **prêt**
/// (`appSerializers.ts`). Un rendu marqué prêt dont le fichier n'a jamais été
/// écrit annonce donc « ready » sans PDF — et c'est exactement le carnet que
/// ces tests posent.
@MainActor
final class BookShareClosedTests: XCTestCase {
    /// Le carnet du ticket : le serveur le dit prêt, et il n'y a rien derrière.
    private func annonceePrete() -> BookPreview {
        BookPreview(memoId: "memo-1", title: "Rome", status: .ready, pageCount: 10)
    }

    /// Le même, composé pour de bon. **Sans `pdfUrl`** : un rendu prêt suffit à
    /// dire qu'il y a un carnet, et ces tests n'ouvrent ainsi aucune connexion.
    private func composee() -> BookPreview {
        BookPreview(
            memoId: "memo-1",
            title: "Rome",
            status: .ready,
            pageCount: 10,
            readyRenderId: "render-1"
        )
    }

    private func model(_ reponses: [BookPreview]) -> BookPreviewModel {
        var restantes = reponses
        return BookPreviewModel(
            memoId: "memo-1",
            source: { _ in
                guard !restantes.isEmpty else { throw Vide() }
                return restantes.removeFirst()
            }
        )
    }

    private struct Vide: Error {}

    /// Le cas de Hugo : « Partager » est fermé, et l'écran ne se présente plus
    /// comme prêt.
    func testABookAnnouncedReadyWithoutItsPdfDoesNotOpenSharing() async {
        let model = model([annonceePrete()])

        await model.run()

        XCTAssertEqual(model.stage, .preview)
        XCTAssertFalse(
            model.canShare,
            "Un carnet annoncé prêt sans PDF n'a ni fichier ni lien à envoyer."
        )
        XCTAssertEqual(model.notice?.message, BookCopy.Preview.notComposed)
        XCTAssertEqual(
            model.notice?.answersAGesture,
            false,
            "Personne n'a rien demandé : c'est l'état des choses, au beige de la marque."
        )
    }

    /// Ce qu'un `disabled` ne faisait pas : répondre.
    func testTheClosedShareButtonExplainsItself() async {
        let model = model([annonceePrete()])
        await model.run()

        model.explainShareIsClosed()

        XCTAssertEqual(model.notice?.message, BookCopy.Share.notComposedYet)
        XCTAssertEqual(
            model.notice?.answersAGesture,
            true,
            "La phrase répond à un geste : c'est le ton d'information, pas le beige."
        )
    }

    /// Un carnet composé ne dit rien de lui-même — il se feuillette.
    func testAComposedBookSharesWithoutAWord() async {
        let model = model([composee()])

        await model.run()

        XCTAssertTrue(model.canShare)
        XCTAssertNil(model.notice)
    }

    /// L'explication ne survit pas à la raison qui l'a posée.
    func testTheExplanationGoesAwayWhenTheBookArrives() async {
        let model = model([annonceePrete(), composee()])
        await model.run()
        model.explainShareIsClosed()
        XCTAssertNotNil(model.notice)

        await model.refreshIfNeeded()

        XCTAssertTrue(model.canShare)
        XCTAssertNil(model.notice, "Le carnet est là : le bouton s'est ouvert, le mot n'a plus d'objet.")
    }

    /// **L'écran de composition ne se répète pas.** Il dit déjà sous sa page où
    /// en est la composition, et bien mieux que ce bandeau — qui n'y paraît
    /// donc qu'en réponse à un appui sur « Partager ».
    func testTheComposingScreenOnlySpeaksWhenAsked() {
        let model = model([])

        XCTAssertEqual(model.stage, .composing)
        XCTAssertFalse(model.canShare)
        XCTAssertNil(model.notice)

        model.explainShareIsClosed()

        XCTAssertEqual(model.notice?.message, BookCopy.Share.notComposedYet)
    }

    /// **L'en-tête ne compte pas des pages qui n'existent pas.** Le compte
    /// vient du serveur et survit à un rendu qui n'a pas abouti : « 10 pages
    /// composées » au-dessus d'une page vide est la première chose qui fait
    /// prendre ce carnet pour un carnet prêt.
    func testTheHeaderDoesNotCountPagesThatAreNotComposed() async {
        let ouvert = model([annonceePrete()])
        await ouvert.run()

        XCTAssertEqual(ouvert.headerSubtitle, "Rome")

        let compose = model([composee()])
        await compose.run()

        XCTAssertEqual(compose.headerSubtitle, BookCopy.Preview.subtitle(title: "Rome", pages: 10))
    }

    /// Le jeu d'essai est un carnet **composé** : sans ça, le bac à sable
    /// n'aurait plus montré ni la feuille de partage ni le choix des étapes
    /// (T285).
    func testTheSandboxBookIsStillShareable() {
        XCTAssertTrue(BookPreview.fixture.hasComposedDocument)
        XCTAssertFalse(
            BookPreview.composingFixture.hasComposedDocument,
            "Celui qui se compose, lui, n'a encore rien à partager."
        )
    }
}
