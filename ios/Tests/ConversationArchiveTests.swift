@testable import MemoBookFeature
import MemoBookCore
import XCTest

/// « Supprimer la conversation » : ce que le fil montre après, et ce qu'il
/// garde.
///
/// La promesse est dans la feuille de confirmation — les messages partent, le
/// mot d'accueil de MEMO revient — et elle se vérifie sans simulateur : le
/// modèle du chat reçoit l'archive et le jeu d'essai, comme dans l'app.
@MainActor
final class ConversationArchiveTests: XCTestCase {
    private let tripId = "trip-rome"

    func testAClearedConversationReopensOnMemosOpening() async {
        let archive = ConversationArchive()
        archive.clear(tripId: tripId)

        let model = ChatModel(tripId: tripId, archive: archive, responder: LocalMemoResponder(voice: .unavailable))
        await model.load()

        // **La bulle d'ouverture, seule** (§ 26, Hugo, 17/09/2026) : la relance
        // du voyage n'est plus une bulle. Les deux PR se sont croisées, et ce
        // test attendait encore la seconde.
        XCTAssertEqual(model.messages.map(\.author), [.memo], "La bulle d’ouverture de MEMO, rien d’autre.")
        XCTAssertEqual(model.messages.first?.spokenText, ChatCopy.opening)
        XCTAssertFalse(model.suggestions.isEmpty, "Les puces d’ouverture reviennent avec la bulle.")
    }

    func testAnUntouchedConversationKeepsItsThread() async {
        let model = ChatModel(tripId: tripId, archive: ConversationArchive(), responder: LocalMemoResponder(voice: .unavailable))
        await model.load()

        XCTAssertTrue(model.messages.contains { $0.author == .traveller }, "Le jeu d’essai a des bulles du voyageur.")
    }

    /// Le fil recharge sur ``ConversationArchive/version`` : supprimer deux
    /// fois le même voyage ne doit pas le faire recharger deux fois.
    func testClearingIsIdempotent() {
        let archive = ConversationArchive()

        archive.clear(tripId: tripId)
        archive.clear(tripId: tripId)

        XCTAssertEqual(archive.version, 1)
        XCTAssertTrue(archive.isCleared(tripId: tripId))
    }

    func testTheArchiveSurvivesARelaunch() {
        let suite = "ConversationArchiveTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        ConversationArchive(defaults: defaults).clear(tripId: tripId)

        XCTAssertTrue(ConversationArchive(defaults: defaults).isCleared(tripId: tripId))
    }
}
