import XCTest

@testable import MemoBookCore

/// Le back-end sérialise ses dates avec `toISOString()`, qui inclut les
/// millisecondes. La stratégie `.iso8601` de Foundation les refuse : ces tests
/// verrouillent le décodage, sans quoi tout l'écran se vide silencieusement.
final class DecodingTests: XCTestCase {
    private let decoder = JSONDecoder.memoBook

    func testDecodesDateWithFractionalSeconds() throws {
        let json = Data(
            """
            {
              "id": "r1",
              "memoId": "m1",
              "status": "ready",
              "pdfUrl": "https://example.test/a.pdf",
              "error": null,
              "createdAt": "2026-08-08T12:48:25.295Z",
              "updatedAt": "2026-08-08T12:48:28.990Z"
            }
            """.utf8
        )

        let render = try decoder.decode(Render.self, from: json)

        XCTAssertEqual(render.status, .ready)
        XCTAssertEqual(
            render.createdAt.timeIntervalSince1970,
            ISO8601DateFormatter.memoBookDate(from: "2026-08-08T12:48:25.295Z")!
                .timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testDecodesDateWithoutFractionalSeconds() throws {
        let json = Data(
            """
            {
              "id": "r1", "memoId": "m1", "status": "pending", "pdfUrl": null,
              "error": null,
              "createdAt": "2026-08-08T12:48:25Z", "updatedAt": "2026-08-08T12:48:25Z"
            }
            """.utf8
        )

        XCTAssertNoThrow(try decoder.decode(Render.self, from: json))
    }

    func testRejectsUnparseableDate() {
        let json = Data(
            """
            {
              "id": "r1", "memoId": "m1", "status": "pending", "pdfUrl": null,
              "error": null, "createdAt": "hier", "updatedAt": "2026-08-08T12:48:25Z"
            }
            """.utf8
        )

        XCTAssertThrowsError(try decoder.decode(Render.self, from: json))
    }

    /// Un statut ajouté côté serveur ne doit pas casser une app déjà installée.
    func testUnknownStatusDecodesInsteadOfThrowing() throws {
        let json = Data(#"{"status":"queued_for_print"}"#.utf8)

        struct Wrapper: Decodable { let status: Status }
        let wrapper = try JSONDecoder().decode(Wrapper.self, from: json)

        XCTAssertEqual(wrapper.status, .unknown("queued_for_print"))
        XCTAssertTrue(wrapper.status.isInProgress)
    }

    func testStatusRoundTrips() throws {
        for status: Status in [.pending, .processing, .ready, .failed, .unknown("autre")] {
            let encoded = try JSONEncoder().encode([status])
            let decoded = try JSONDecoder().decode([Status].self, from: encoded)
            XCTAssertEqual(decoded.first, status)
        }
    }

    func testTerminalStates() {
        XCTAssertTrue(Status.ready.isTerminal)
        XCTAssertTrue(Status.failed.isTerminal)
        XCTAssertFalse(Status.pending.isTerminal)
        XCTAssertFalse(Status.processing.isTerminal)
    }

    func testMemoDetailExposesMostRecentRender() {
        let now = Date.now
        let recent = Render(id: "r2", memoId: "m1", status: .ready, createdAt: now, updatedAt: now)
        let older = Render(
            id: "r1",
            memoId: "m1",
            status: .failed,
            createdAt: now.addingTimeInterval(-100),
            updatedAt: now.addingTimeInterval(-100)
        )

        let memo = MemoDetail(
            id: "m1",
            title: "Carnet",
            createdAt: now,
            updatedAt: now,
            renders: [recent, older]
        )

        XCTAssertEqual(memo.latestRender?.id, "r2")
    }
}
