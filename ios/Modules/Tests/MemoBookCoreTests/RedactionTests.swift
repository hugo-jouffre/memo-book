import XCTest

@testable import MemoBookCore

/// Le texte d'un souvenir existe en trois versions — brute, rédigée, corrigée.
/// Ces tests verrouillent la seule règle qui compte pour l'utilisateur : sa
/// correction gagne toujours, et elle ne se perd jamais en route.
final class RedactionTests: XCTestCase {
    private let decoder = JSONDecoder.memoBook

    private func entryJSON(_ extraFields: String) -> Data {
        Data(
            """
            {
              "id": "e1", "memoId": "m1", "kind": "audio", "status": "ready",
              "transcript": "euh du coup on est arrivés",
              "capturedAt": "2026-08-08T09:00:00.000Z",
              "createdAt": "2026-08-08T09:00:01.000Z"
              \(extraFields)
            }
            """.utf8
        )
    }

    func testDecodesRedactionFields() throws {
        let entry = try decoder.decode(
            Entry.self,
            from: entryJSON(
                """
                , "redactionStatus": "ready",
                  "redactedText": "On est arrivés.",
                  "displayText": "On est arrivés.",
                  "suggestedTitle": "Premier jour",
                  "funFact": "Un fait vérifiable.",
                  "funFactTitle": "Fun fact",
                  "weatherKey": "rain"
                """
            )
        )

        XCTAssertEqual(entry.redactionStatus, .ready)
        XCTAssertEqual(entry.displayText, "On est arrivés.")
        XCTAssertEqual(entry.suggestedTitle, "Premier jour")
        XCTAssertEqual(entry.weatherKey, "rain")
        XCTAssertFalse(entry.isEdited)
        XCTAssertTrue(entry.isReadyForBook)
    }

    /// Le serveur peut être plus ancien que l'app, ou un endpoint peut ne pas
    /// renvoyer ces champs : le souvenir doit rester décodable.
    func testDecodesWithoutRedactionFields() throws {
        let entry = try decoder.decode(Entry.self, from: entryJSON(""))

        XCTAssertEqual(entry.redactionStatus, .pending)
        XCTAssertEqual(entry.displayText, "euh du coup on est arrivés")
        XCTAssertTrue(entry.isProcessing, "Sans rédaction, le souvenir n'est pas prêt")
        XCTAssertFalse(entry.isReadyForBook)
    }

    func testEditedTextWinsOverRedactedText() throws {
        let entry = try decoder.decode(
            Entry.self,
            from: entryJSON(
                """
                , "redactionStatus": "ready",
                  "redactedText": "La version du modèle.",
                  "editedText": "Ma version.",
                  "editedAt": "2026-08-08T10:00:00.000Z",
                  "displayText": "Ma version."
                """
            )
        )

        XCTAssertEqual(entry.displayText, "Ma version.")
        XCTAssertTrue(entry.isEdited)
        XCTAssertNotNil(entry.redactedText, "La version proposée reste consultable")
    }

    /// Une photo n'a rien à rédiger : elle ne doit pas retenir la génération
    /// du carnet en restant éternellement « en attente ».
    func testPhotoIsNeverBlockedByRedaction() throws {
        let json = Data(
            """
            {
              "id": "e2", "memoId": "m1", "kind": "photo", "status": "ready",
              "redactionStatus": "pending",
              "capturedAt": "2026-08-08T09:00:00.000Z",
              "createdAt": "2026-08-08T09:00:01.000Z"
            }
            """.utf8
        )

        let entry = try decoder.decode(Entry.self, from: json)

        XCTAssertFalse(entry.isProcessing)
        XCTAssertTrue(entry.isReadyForBook)
    }

    func testFailedRedactionIsReadyForBook() throws {
        let entry = try decoder.decode(
            Entry.self,
            from: entryJSON(
                """
                , "redactionStatus": "failed",
                  "redactionError": "Le modèle a refusé de rédiger ce souvenir."
                """
            )
        )

        XCTAssertFalse(entry.isProcessing, "Un échec n'est pas une attente")
        XCTAssertTrue(entry.isReadyForBook, "Le carnet part avec la transcription brute")
        XCTAssertEqual(entry.displayText, "euh du coup on est arrivés")
    }
}

/// `EntryEdit` doit distinguer trois intentions. Une seule les confond, et
/// « revenir au texte proposé » devient « ne rien faire ».
final class EntryEditEncodingTests: XCTestCase {
    private let encoder = JSONEncoder.memoBook

    private func encoded(_ edit: EntryEdit) throws -> String {
        String(decoding: try encoder.encode(edit), as: UTF8.self)
    }

    func testNewTextIsSent() throws {
        let json = try encoded(.text("Ma version."))

        XCTAssertTrue(json.contains("\"editedText\""))
        XCTAssertTrue(json.contains("Ma version."))
    }

    func testRevertSendsExplicitNull() throws {
        let json = try encoded(.revertToRedaction)

        XCTAssertTrue(
            json.contains("\"editedText\":null"),
            "Un null explicite est ce qui distingue « revenir en arrière » de « ne pas toucher »"
        )
    }

    func testUntouchedFieldIsOmitted() throws {
        let json = try encoded(EntryEdit(weatherKey: .some("rain")))

        XCTAssertFalse(json.contains("editedText"), "Un champ absent ne doit pas écraser le texte")
        XCTAssertTrue(json.contains("rain"))
    }
}
