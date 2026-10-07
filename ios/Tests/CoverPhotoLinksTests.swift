import MemoBookCore
@testable import MemoBookFeature
import XCTest

/// **Les photos de couverture passent par un lien signé d'une heure** (T237) :
/// un écran resté ouvert montrait des images cassées. Le modèle renouvelle les
/// liens — à l'échec d'une image, ou en revenant sur le parcours passé le
/// délai — sans toucher au plat qu'on compose.
@MainActor
final class CoverPhotoLinksTests: XCTestCase {
    private final class Server {
        var generation = 1
        var reads = 0

        var covers: BookCovers {
            var covers = BookCovers.fixture
            covers.photos = covers.photos.map {
                CoverPhoto(id: $0.id, url: URL(string: "https://cdn.test/\($0.id)?sig=\(generation)"))
            }
            return covers
        }
    }

    private func model(_ server: Server, clock: @escaping () -> Date) -> CoversModel {
        let model = CoversModel(tripId: "trip", source: { _ in
            server.reads += 1
            return server.covers
        })
        model.now = clock
        return model
    }

    func testStaleLinksAreRenewedWithoutLosingTheCoverBeingComposed() async throws {
        let server = Server()
        var now = Date(timeIntervalSince1970: 0)
        let model = model(server, clock: { now })
        await model.load()

        let otherStyle = try XCTUnwrap(model.styles.first { $0.id != model.cover?.styleId })
        model.preview(style: otherStyle)

        server.generation = 2
        now += 50 * 60
        await model.load()

        XCTAssertEqual(server.reads, 2)
        XCTAssertTrue(model.covers?.photos.allSatisfy { $0.url?.query == "sig=2" } == true)
        XCTAssertEqual(model.cover?.styleId, otherStyle.id, "Le style choisi sans valider reste.")
    }

    func testAFreshParcoursDoesNotRereadTheServer() async {
        let server = Server()
        var now = Date(timeIntervalSince1970: 0)
        let model = model(server, clock: { now })
        await model.load()
        now += 10 * 60
        await model.load()

        XCTAssertEqual(server.reads, 1)
    }

    func testABrokenImageDoesNotHammerTheServer() async {
        let server = Server()
        let now = Date(timeIntervalSince1970: 0)
        let model = model(server, clock: { now })
        await model.load()

        server.generation = 2
        await model.refreshPhotoLinks()
        await model.refreshPhotoLinks()
        await model.refreshPhotoLinks()

        XCTAssertEqual(server.reads, 2, "Une seule relecture par délai de grâce.")
        XCTAssertTrue(model.covers?.photos.allSatisfy { $0.url?.query == "sig=2" } == true)
    }

    func testAPhotoImportedOnTheDeviceKeepsItsLocalAddress() async {
        let server = Server()
        let model = model(server, clock: { .now })
        await model.load()
        let local = CoverPhoto(id: "local-1", url: URL(fileURLWithPath: "/tmp/local-1.jpg"))
        model.add(local)

        await model.refreshPhotoLinks()

        XCTAssertEqual(model.covers?.photos.first { $0.id == "local-1" }, local)
    }
}
