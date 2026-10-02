import XCTest

@testable import MemoBookCore

/// « Valider cette étape » : une nouvelle clé côté serveur ne doit jamais
/// faire échouer le décodage d'un voyage déjà installé — même parti pris que
/// `TripTests`' étape de voyage inconnue.
final class TripDetailTests: XCTestCase {
    private func decode(_ json: String) throws -> TripStep {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TripStep.self, from: Data(json.utf8))
    }

    func testValidatedAtDecodesWhenPresent() throws {
        let step = try decode(
            #"{"id":"s1","number":1,"companions":[],"validatedAt":"2026-08-28T18:00:00Z"}"#
        )
        XCTAssertNotNil(step.validatedAt)
    }

    func testValidatedAtDecodesAsNilWhenAbsent() throws {
        let step = try decode(#"{"id":"s1","number":1,"companions":[]}"#)
        XCTAssertNil(step.validatedAt)
    }

    func testValidatedKeepsEveryOtherFieldAndSetsTheDate() {
        let step = TripStep(id: "s1", number: 1, placeName: "Trastevere")
        let validated = step.validated(at: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(validated.validatedAt, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(validated.id, step.id)
        XCTAssertEqual(validated.placeName, step.placeName)
        XCTAssertNil(step.validatedAt, "l'étape d'origine ne doit pas bouger : `validated()` en rend une copie")
    }
}
