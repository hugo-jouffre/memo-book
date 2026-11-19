import MemoBookCore
@testable import MemoBookFeature
import XCTest

/// **Les titres posés sur les couvertures** — T276.
///
/// Hugo : « les titres posés sur la 1re et la 4e de couverture ne
/// fonctionnent pas ». Le chemin serveur est vérifié depuis T259 ; ce qui
/// suit tient le chemin de l'app, de « Valider » jusqu'à l'appel.
@MainActor
final class CoverTextsTests: XCTestCase {
    /// Un serveur qui note ce qu'on lui demande, et qui peut prendre son
    /// temps — c'est dans ce temps-là que les bugs d'enregistrement vivent.
    @MainActor
    private final class Server {
        private(set) var edits: [BookCoverEdit] = []
        var delay: Duration?
        var covers = BookCovers.fixture

        @MainActor
        func save(_ edit: BookCoverEdit) async throws -> BookCovers {
            if let delay { try await Task.sleep(for: delay) }
            edits.append(edit)
            switch edit {
            case .texts(let face, let title, let subtitle):
                covers[face].title = title
                covers[face].subtitle = subtitle
            case .style(let face, let styleId):
                covers[face].styleId = styleId
            case .photo(let face, let photoId):
                covers[face].photoId = photoId
            case .stats(let ids):
                covers.back.statIds = ids
            }
            return covers
        }
    }

    private func model(_ server: Server) -> CoversModel {
        CoversModel(
            tripId: "trip",
            source: { _ in server.covers },
            persist: { @MainActor _, edit in try await server.save(edit) }
        )
    }

    private func titles(of edits: [BookCoverEdit]) -> [String] {
        edits.compactMap { edit in
            if case .texts(_, let title, _) = edit { return title }
            return nil
        }
    }

    func testUnTitreValideArriveAuServeur() async throws {
        let server = Server()
        let model = model(server)
        await model.load()

        model.setTexts(title: "Rome, entre frère et sœur", subtitle: "Dix jours")

        try await until("le titre est parti") { server.edits.count == 1 }
        XCTAssertEqual(titles(of: server.edits), ["Rome, entre frère et sœur"])
        XCTAssertEqual(model.cover?.title, "Rome, entre frère et sœur")
    }

    /// Le titre se pose sur le plat qu'on regarde, pas sur l'autre.
    func testLeTitreVaSurLePlatChoisi() async throws {
        let server = Server()
        let model = model(server)
        await model.load()
        model.face = .back

        model.setTexts(title: "Ce qu'on en garde", subtitle: "")

        try await until("le titre est parti") { server.edits.count == 1 }
        guard case .texts(let face, _, _) = server.edits[0] else { return XCTFail("Pas un texte.") }
        XCTAssertEqual(face, .back)
        XCTAssertEqual(server.covers.back.title, "Ce qu'on en garde")
        XCTAssertEqual(server.covers.front.title, BookCovers.fixture.front.title, "Le devant n'a pas bougé.")
    }

    /// ⚠️ **Le cœur de T276.** Chaque enregistrement annulait le précédent
    /// (`pendingSave?.cancel()`), et l'annulé repartait sans rien dire : un
    /// titre validé puis suivi d'un autre geste — choisir un style, changer la
    /// photo — ne parvenait jamais au serveur.
    func testUnTitreNEstPasAnnuleParLeGesteSuivant() async throws {
        let server = Server()
        server.delay = .milliseconds(80)
        let model = model(server)
        await model.load()
        let autreStyle = try XCTUnwrap(model.styles.first { $0.id != model.cover?.styleId })

        model.setTexts(title: "Rome, entre frère et sœur", subtitle: "Dix jours")
        model.preview(style: autreStyle)
        model.commitStyle()

        try await until("les deux gestes sont partis") { server.edits.count == 2 }
        XCTAssertEqual(titles(of: server.edits), ["Rome, entre frère et sœur"])
        XCTAssertEqual(server.covers.front.title, "Rome, entre frère et sœur")
        XCTAssertEqual(server.covers.front.styleId, autreStyle.id)
    }

    /// Et l'ordre tient : deux titres de suite laissent le **dernier**.
    func testDeuxTitresDeSuiteLaissentLeDernier() async throws {
        let server = Server()
        server.delay = .milliseconds(40)
        let model = model(server)
        await model.load()

        model.setTexts(title: "Un premier", subtitle: "")
        model.setTexts(title: "Un second", subtitle: "")

        try await until("les deux sont partis") { server.edits.count == 2 }
        XCTAssertEqual(titles(of: server.edits), ["Un premier", "Un second"])
        XCTAssertEqual(server.covers.front.title, "Un second")
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
