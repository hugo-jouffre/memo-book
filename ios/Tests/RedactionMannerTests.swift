import MemoBookCore
@testable import MemoBookFeature
import MemoBookNetworking
import XCTest

/// **La manière d'être rédigé** (T292) : ce que le modèle décode, ce qu'il
/// envoie, et ce qu'il refuse d'envoyer.
///
/// Le garde-fou lui-même — qui a le droit de changer de manière — est tranché
/// par le serveur (`services/redactionMannerAccess.ts`) et testé là-bas. Ici on
/// vérifie que l'app **lit** sa décision au lieu de la refaire, et qu'elle ne
/// reprend pas le carnet pour rien.
@MainActor
final class RedactionMannerTests: XCTestCase {
    // MARK: Le décodage

    func testAnUnknownMannerFallsBackToTheDefaultRatherThanFailing() throws {
        // Une version plus récente du serveur peut servir une manière que ce
        // build ne connaît pas : la ligne retombe sur le défaut, et **tout
        // l'écran** continue de décoder.
        let json = """
        {"manner":"en-alexandrins","notes":"Tutoie-moi.","isAvailable":true,"reason":"unlimited"}
        """
        let decoded = try JSONDecoder().decode(RedactionSettings.self, from: Data(json.utf8))

        XCTAssertNil(decoded.chosenManner, "Une clé inconnue n'est pas un choix.")
        XCTAssertEqual(decoded.manner, .spoken)
        XCTAssertEqual(decoded.notes, "Tutoie-moi.")
        XCTAssertTrue(decoded.isAvailable)
    }

    func testAnUnknownReasonClosesTheSettingRatherThanOpeningIt() throws {
        let json = #"{"manner":null,"notes":null,"isAvailable":false,"reason":"parce-que"}"#
        let decoded = try JSONDecoder().decode(RedactionSettings.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.reason, .needsUnlimited, "Le refus sûr.")
        XCTAssertFalse(decoded.isAvailable)
    }

    func testAServerThatSaysNothingServesAClosedSetting() {
        // Un serveur plus ancien ne sert pas le bloc : mieux vaut une ligne qui
        // mène au paywall qu'un réglage que le serveur refusera.
        var settings = TripSettings.fixture
        settings.redaction = nil

        XCTAssertFalse(settings.redactionSettings.isAvailable)
        XCTAssertEqual(settings.redactionSettings.manner, .spoken)
    }

    func testNobodyChoseAndSpokenChosenAreTheSameMannerButNotTheSameState() {
        // La distinction ne sert qu'à la pastille « Par défaut ».
        let untouched = RedactionSettings(chosenManner: nil, isAvailable: true, reason: .unlimited)
        let chosen = RedactionSettings(chosenManner: .spoken, isAvailable: true, reason: .unlimited)

        XCTAssertEqual(untouched.manner, chosen.manner)
        XCTAssertNil(untouched.chosenManner)
        XCTAssertEqual(chosen.chosenManner, .spoken)
    }

    // MARK: Ce que le modèle envoie

    func testChoosingAMannerPostsItAndShowsItBeforeTheServerAnswers() async throws {
        let (model, server) = await open(manner: nil, isAvailable: true)

        model.setRedactionManner(.literary)

        // Posé à l'écran tout de suite : un réglage qui attend le réseau se lit
        // comme cassé.
        XCTAssertEqual(model.settings?.redactionSettings.manner, .literary)
        try await settled(model)
        XCTAssertEqual(server.received, [.redactionManner(.literary)])
    }

    func testChoosingTheMannerAlreadyInPlaceSendsNothing() async throws {
        // Le serveur ne reprendrait rien, mais le voyage pour rien se voit : un
        // 202 ferait clignoter l'écran.
        let (model, server) = await open(manner: .factual, isAvailable: true)

        model.setRedactionManner(.factual)

        try await settled(model)
        XCTAssertTrue(server.received.isEmpty)
    }

    func testTheDefaultMannerCountsAsChosenWhenNobodyChose() async throws {
        // Personne n'a choisi : toucher « Comme je parle » ne reprend rien.
        let (model, server) = await open(manner: nil, isAvailable: true)

        model.setRedactionManner(.spoken)

        try await settled(model)
        XCTAssertTrue(server.received.isEmpty)
    }

    func testNotesAreTrimmedAndAnEmptyFieldErasesThem() async throws {
        let (model, server) = await open(manner: nil, notes: "Appelle-moi Max.", isAvailable: true)

        model.setRedactionNotes("   ")

        XCTAssertNil(model.settings?.redactionSettings.notes)
        try await settled(model)
        XCTAssertEqual(server.received, [.redactionNotes(nil)])
    }

    func testWritingTheSameNotesAgainSendsNothing() async throws {
        let (model, server) = await open(manner: nil, notes: "Garde mes mots.", isAvailable: true)

        model.setRedactionNotes("  Garde mes mots.  ")

        try await settled(model)
        XCTAssertTrue(server.received.isEmpty, "Chaque envoi reprend le carnet.")
    }

    // MARK: Tout faire reprendre

    func testRewritingAsksTheServerAndIsReplayable() async throws {
        let (model, server) = await open(manner: .literary, isAvailable: true)

        model.rewriteRedaction()
        try await settled(model)
        model.rewriteRedaction()
        try await settled(model)

        // Rejouable, contrairement à la reprise d'un changement de cible : ici
        // le geste *est* la demande.
        XCTAssertEqual(server.rewrites, 2)
    }

    // MARK: - Le double de serveur

    private func open(
        manner: RedactionManner?,
        notes: String? = nil,
        isAvailable: Bool
    ) async -> (TripSettingsModel, MannerServer) {
        let server = MannerServer(manner: manner, notes: notes, isAvailable: isAvailable)
        let model = TripSettingsModel(
            tripId: "preview",
            source: { _ in server.settings },
            persist: { _, edit in server.patch(edit) },
            rewriteRedaction: { _ in server.rewrite() }
        )
        await model.load()
        return (model, server)
    }

    /// Laisse partir l'envoi en vol. Le modèle n'expose pas sa tâche : deux
    /// tours de boucle suffisent, comme dans les autres suites de réglages.
    private func settled(_ model: TripSettingsModel) async throws {
        for _ in 0..<4 { await Task.yield() }
    }

    @MainActor
    private final class MannerServer {
        var settings: TripSettings
        var received: [TripSettingsEdit] = []
        var rewrites = 0

        init(manner: RedactionManner?, notes: String?, isAvailable: Bool) {
            settings = .fixture
            settings.redaction = RedactionSettings(
                chosenManner: manner,
                notes: notes,
                isAvailable: isAvailable,
                reason: isAvailable ? .unlimited : .needsUnlimited
            )
        }

        func patch(_ edit: TripSettingsEdit) -> TripSettings {
            received.append(edit)
            var redaction = settings.redactionSettings
            switch edit {
            case .redactionManner(let manner): redaction.chosenManner = manner
            case .redactionNotes(let notes): redaction.notes = notes
            default: break
            }
            settings.redaction = redaction
            return settings
        }

        func rewrite() -> TripSettings {
            rewrites += 1
            return settings
        }
    }
}
