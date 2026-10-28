@testable import MemoBookFeature
import MemoBookCore
import MemoBookRecording
import XCTest

/// **Ce qu'une mise à jour de l'app ne doit pas emporter** (Hugo, 28/10/2026 —
/// « s'assurer que le passage d'une version à une autre, notamment d'une
/// version TestFlight à une version publique, ne fasse pas perdre la donnée
/// des utilisateurs et ce qu'ils ont commencé à raconter »).
///
/// Presque tout le récit vit sur le serveur, et une mise à jour n'y touche
/// pas. Deux choses n'existent **que** sur le téléphone : les tours de
/// conversation qui n'ont pas pu partir (``PendingRecordingStore``) et les
/// voyages créés hors ligne (``PendingTripStore``). Les deux sont relus d'un
/// format écrit par la version d'avant.
///
/// Ces tests tiennent la seule propriété qui compte : **une version qui ne
/// sait pas relire ne détruit pas**. Elle met de côté.
@MainActor
final class VersionUpgradeDataTests: XCTestCase {
    private func scratch() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "Upgrade-\(UUID().uuidString)")
    }

    // MARK: - Les vocaux en attente

    /// Une fiche écrite par une version suivante — un champ obligatoire de
    /// plus, un nom qui a changé — n'est pas comprise par celle-ci. Elle ne
    /// doit pas disparaître avec son audio : un vocal qui n'est pas parti
    /// n'existe nulle part ailleurs.
    func testAnUnreadableTurnIsSetAsideInsteadOfDeleted() async throws {
        let directory = scratch()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Une fiche d'un format qu'on ne sait pas lire, et son audio à côté.
        let id = "F0000000-0000-0000-0000-00000000000A"
        let metadata = directory.appending(path: "\(id).json")
        let audio = directory.appending(path: "\(id).audio")
        try Data(#"{"id":"\#(id)","format":"venu du futur"}"#.utf8).write(to: metadata)
        try Data("des octets de vocal".utf8).write(to: audio)

        let store = PendingRecordingStore(directory: directory)
        let visible = await store.all()
        XCTAssertEqual(visible.count, 0, "Elle n'est pas lisible : elle ne se montre pas.")

        // Mais elle est toujours là, avec son audio.
        let quarantine = directory.appending(path: "illisibles")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: quarantine.appending(path: "\(id).json").path(percentEncoded: false)),
            "La fiche illisible est mise de côté, pas supprimée."
        )
        let keptAudio = quarantine.appending(path: "\(id).audio")
        XCTAssertEqual(
            try? Data(contentsOf: keptAudio),
            Data("des octets de vocal".utf8),
            "L'audio part avec elle, intact."
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: metadata.path(percentEncoded: false)),
            "Et il ne reste pas une copie dans la file, qu'on relirait à chaque lancement."
        )
    }

    /// Une fiche illisible ne doit pas emporter les lisibles : c'est la règle
    /// qui existait déjà, et elle tient toujours.
    func testAnUnreadableTurnDoesNotBlockTheOthers() async throws {
        let directory = scratch()
        let store = PendingRecordingStore(directory: directory)
        _ = try await store.enqueue(
            PendingTurn(
                id: "A0000000-0000-0000-0000-00000000000C",
                tripId: "trip-1",
                kind: .voice,
                filenames: ["souvenir.m4a"],
                mimeTypes: ["audio/m4a"],
                recordedAt: .now
            ),
            files: [Data("un vocal".utf8)]
        )

        try Data(#"{"rien":"de lisible"}"#.utf8).write(
            to: directory.appending(path: "F0000000-0000-0000-0000-00000000000B.json")
        )

        let reread = PendingRecordingStore(directory: directory)
        let loaded = await reread.all()
        XCTAssertEqual(loaded.count, 1, "Le tour lisible arrive quand même.")
    }

    // MARK: - Les voyages créés hors ligne

    /// Toute la file tient dans un seul fichier. Une entrée qu'on ne comprend
    /// pas ne doit ni cacher les autres, ni être effacée par le prochain
    /// enregistrement.
    func testAnUnreadableTripSurvivesTheNextSave() async throws {
        let directory = scratch()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "pending-trips.json")

        // Un voyage d'un format inconnu, posé par une version suivante.
        try Data(#"[{"id":"venu-du-futur","nouveauChamp":42}]"#.utf8).write(to: file)

        let store = PendingTripStore(directory: directory)
        let trips = await store.all()
        XCTAssertTrue(trips.isEmpty, "On ne sait pas le lire : il ne se montre pas.")

        // Un voyage créé par cette version-ci, qui réécrit le fichier.
        var draft = TripDraft()
        draft.title = "Rome"
        try await store.save(PendingTrip(id: "trip-1", draft: draft, accountId: "compte-1"))

        // Les deux sont dans le fichier : le nôtre, et celui qu'on n'a pas su lire.
        let written = try XCTUnwrap(try? Data(contentsOf: file))
        let text = String(decoding: written, as: UTF8.self)
        XCTAssertTrue(text.contains("trip-1"), "Le voyage de cette version est enregistré.")
        XCTAssertTrue(
            text.contains("venu-du-futur"),
            "Et celui qu'on n'a pas su lire n'a pas été écrasé : il repartira le jour où une version le comprendra."
        )
    }

    /// Un fichier entièrement illisible — abîmé — est copié de côté avant
    /// qu'on écrive par-dessus.
    func testACorruptedQueueFileIsCopiedAsideBeforeBeingOverwritten() async throws {
        let directory = scratch()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "pending-trips.json")
        try Data("ceci n'est pas du JSON".utf8).write(to: file)

        let store = PendingTripStore(directory: directory)
        _ = await store.all()

        let kept = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
            .filter { $0.contains("illisible") }
        XCTAssertEqual(kept.count, 1, "Le fichier abîmé est gardé à côté, daté.")
    }

    /// Un fichier vide — la file a été vidée normalement — n'est pas un
    /// fichier abîmé, et n'a rien à mettre de côté.
    func testAnEmptyQueueIsNotTreatedAsCorrupted() async throws {
        let directory = scratch()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: directory.appending(path: "pending-trips.json"))

        let store = PendingTripStore(directory: directory)
        _ = await store.all()

        let kept = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
            .filter { $0.contains("illisible") }
        XCTAssertTrue(kept.isEmpty, "Rien à sauver : la file était simplement vide.")
    }
}
