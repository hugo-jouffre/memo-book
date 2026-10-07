import XCTest

@testable import MemoBookCore

/// Ce que `GET /v1/memos/:id/preview` dit d'une composition (contrat du
/// 06/10/2026) : la dernière composition, le rendu prêt qu'on commande, et ce
/// que l'écran de composition en raconte.
final class BookPreviewTests: XCTestCase {
    private func decode(_ json: String) throws -> BookPreview {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BookPreview.self, from: Data(json.utf8))
    }

    /// Une remise à jour qui tourne derrière un carnet déjà composé : le
    /// statut dit « ça compose », mais il y a un rendu prêt — on le feuillette
    /// et on le commande.
    func testARecompositionKeepsTheReadyRender() throws {
        let preview = try decode("""
            {"memoId":"m","title":"Rome","status":{"status":"composing"},
             "pdfUrl":"https://pdf.test/rome.pdf","pageCount":12,"shareUrl":null,
             "coverPhotoUrl":null,"tripDate":null,"excerpt":null,"hasConfiguredCovers":false,
             "render":{"id":"r2","status":"processing","phase":"writing",
                       "startedAt":"2026-10-06T10:00:00Z","updatedAt":"2026-10-06T10:01:00Z","error":null},
             "readyRenderId":"r1","isUpToDate":false,"pendingMemoryCount":2}
            """)

        XCTAssertEqual(preview.status, .composing)
        XCTAssertTrue(preview.hasReadyRender)
        XCTAssertEqual(preview.readyRenderId, "r1")
        XCTAssertEqual(preview.render?.phase, .writing)
        XCTAssertEqual(preview.pendingMemoryCount, 2)
        XCTAssertEqual(preview.isUpToDate, false)
    }

    /// Jamais composé : `render` est nul, et rien n'est commandable. C'est ce
    /// qui distingue « rien n'a été lancé » d'une composition qui tourne —
    /// le statut dit `composing` dans les deux cas.
    func testANeverComposedBookHasNoRender() throws {
        let preview = try decode("""
            {"memoId":"m","title":"Rome","status":{"status":"composing"},"pdfUrl":null,
             "pageCount":0,"hasConfiguredCovers":false,"render":null,"readyRenderId":null,
             "isUpToDate":false,"pendingMemoryCount":0}
            """)

        XCTAssertNil(preview.render)
        XCTAssertFalse(preview.hasReadyRender)
    }

    /// Un serveur d'avant le contrat ne sert aucun des quatre champs : l'aperçu
    /// se lit quand même.
    func testAnOlderServerStillDecodes() throws {
        let preview = try decode("""
            {"memoId":"m","title":"Rome","status":{"status":"ready"},"pdfUrl":null,
             "pageCount":10,"hasConfiguredCovers":true}
            """)

        XCTAssertNil(preview.render)
        XCTAssertNil(preview.isUpToDate)
        XCTAssertTrue(preview.hasReadyRender)
    }

    /// Une phase ajoutée côté serveur après cette version est une attente,
    /// pas une erreur de décodage.
    func testAnUnknownPhaseIsAWait() throws {
        let render = try JSONDecoder().decode(
            BookRenderProgress.self,
            from: Data(#"{"id":"r","phase":"proofreading"}"#.utf8)
        )
        XCTAssertEqual(render.phase, .unknown("proofreading"))
    }

    /// La ligne sous la page : la file, la rédaction attendue (accordée), la
    /// mise en page, la fabrication du PDF.
    func testThePhaseLineFollowsTheComposition() {
        typealias Copy = BookCopy.Composition
        XCTAssertEqual(Copy.phase(.queued, pendingMemories: 0), "Ton carnet attend son tour…")
        XCTAssertEqual(
            Copy.phase(.writing, pendingMemories: 1),
            "On attend la fin de la rédaction d’un souvenir…"
        )
        XCTAssertEqual(
            Copy.phase(.writing, pendingMemories: 3),
            "On attend la fin de la rédaction de 3 souvenirs…"
        )
        XCTAssertEqual(Copy.phase(.writing, pendingMemories: 0), "On met tes souvenirs en pages…")
        XCTAssertEqual(Copy.phase(.composing, pendingMemories: 0), "On fabrique le PDF de ton carnet…")
        XCTAssertEqual(Copy.phase(nil, pendingMemories: 0), "La composition de ton carnet est lancée…")
    }
}

/// Le message de partage compte des pages, et le dit — il annonçait des
/// « étapes » en comptant les pages du carnet.
final class ShareInvitationTests: XCTestCase {
    private let link = URL(string: "https://api.example.test/c/abc")!

    func testTheMessageCountsPages() {
        let message = BookCopy.Share.invitation(title: "Rome", pages: 12, link: link)
        XCTAssertTrue(message.contains("Il compte déjà 12 pages !"))
        XCTAssertFalse(message.contains("étape"))
        XCTAssertFalse(message.contains("financer"))
        XCTAssertTrue(message.hasSuffix(link.absoluteString))
    }

    func testOnePageIsSingular() {
        XCTAssertTrue(BookCopy.Share.invitation(title: "Rome", pages: 1, link: link).contains("1 page !"))
    }

    func testANotYetComposedBookSaysNoCount() {
        let message = BookCopy.Share.invitation(title: "Rome", pages: 0, link: link)
        XCTAssertFalse(message.contains("page"))
        XCTAssertTrue(message.contains("« Rome »"))
    }
}
