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

    // MARK: - Le sens qui fait perdre des données

    /// ⚠️ **Les cas ci-dessus tiennent le mauvais sens.** Ils prouvent qu'une
    /// fiche illisible est mise de côté — ce qui protège *après* coup. Ce qui
    /// fait perdre un souvenir, c'est l'inverse : une fiche écrite par la
    /// version d'hier que celle d'aujourd'hui ne sait plus lire. Elle part en
    /// quarantaine **en silence**, l'écran n'en parle pas, et rien ici ne
    /// serait rouge.
    ///
    /// Les cas qui suivent figent donc le format **octet pour octet**, tel
    /// qu'une version livrée l'écrit sur le téléphone des gens. Renommer un
    /// champ, en rendre un obligatoire, changer le format d'une date : l'un de
    /// ces cas casse, et c'est le but.
    ///
    /// **Un format figé ici ne se corrige pas, il s'accompagne** : on garde le
    /// cas tel quel et on ajoute au décodeur de quoi relire l'ancien, comme
    /// ``PendingTurn/init(from:)`` le fait déjà pour les fiches d'avant le
    /// 22/09/2026.

    /// Pose une fiche et ses fichiers comme une version livrée les a écrits.
    private func plant(_ json: String, id: String, files: Int, in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: directory.appending(path: "\(id).json"))
        for index in 0..<files {
            let name = index == 0 ? "\(id).audio" : "\(id)-\(index).file"
            try Data("octets".utf8).write(to: directory.appending(path: name))
        }
    }

    /// Un vocal qui attendait le réseau quand la mise à jour est arrivée.
    func testAVoiceTurnWrittenByAShippedVersionStillLoads() async throws {
        let directory = scratch()
        let id = "11111111-1111-1111-1111-111111111111"
        try plant(
            """
            {"id":"\(id)","tripId":"voyage-kyoto","kind":"voice",\
            "filenames":["souvenir.m4a"],"mimeTypes":["audio/m4a"],\
            "duration":42.5,"levels":[0.1,0.9,0.4],"placeLabel":"Kyoto",\
            "recordedAt":"2026-11-12T08:30:00Z","queuedAt":"2026-11-12T08:31:00Z"}
            """,
            id: id, files: 1, in: directory
        )

        let enAttente = await PendingRecordingStore(directory: directory).all()
        let turn = try XCTUnwrap(enAttente.first)
        XCTAssertEqual(turn.id, id)
        XCTAssertEqual(turn.tripId, "voyage-kyoto")
        XCTAssertEqual(turn.kind, .voice)
        XCTAssertEqual(turn.filenames, ["souvenir.m4a"])
        XCTAssertEqual(turn.mimeTypes, ["audio/m4a"])
        XCTAssertEqual(turn.duration, 42.5)
        XCTAssertEqual(turn.levels, [0.1, 0.9, 0.4])
        XCTAssertEqual(turn.placeLabel, "Kyoto")
        XCTAssertFalse(turn.isOnHold(at: .now), "Rien ne le retient : il doit repartir au premier réseau.")
    }

    /// Un texte tapé dans le fil, qui n'a pas de fichier à côté.
    func testATextTurnWrittenByAShippedVersionStillLoads() async throws {
        let directory = scratch()
        let id = "22222222-2222-2222-2222-222222222222"
        try plant(
            """
            {"id":"\(id)","tripId":"voyage-kyoto","kind":"text",\
            "text":"On a mangé des nouilles sous la pluie.","suggestionId":"sugg-3",\
            "filenames":[],"mimeTypes":[],"levels":[],\
            "recordedAt":"2026-11-12T09:00:00Z","queuedAt":"2026-11-12T09:00:00Z"}
            """,
            id: id, files: 0, in: directory
        )

        let enAttente = await PendingRecordingStore(directory: directory).all()
        let turn = try XCTUnwrap(enAttente.first)
        XCTAssertEqual(turn.kind, .text)
        XCTAssertEqual(turn.text, "On a mangé des nouilles sous la pluie.")
        XCTAssertEqual(turn.suggestionId, "sugg-3")
    }

    /// Deux photos envoyées ensemble : le second fichier porte le nom indexé.
    func testAPhotosTurnWrittenByAShippedVersionStillLoads() async throws {
        let directory = scratch()
        let id = "33333333-3333-3333-3333-333333333333"
        try plant(
            """
            {"id":"\(id)","tripId":"voyage-kyoto","kind":"photos","entryId":"entry-7","stepId":"step-2",\
            "filenames":["photo-0.jpg","photo-1.jpg"],"mimeTypes":["image/jpeg","image/jpeg"],\
            "levels":[],"recordedAt":"2026-11-12T10:00:00Z","queuedAt":"2026-11-12T10:00:00Z"}
            """,
            id: id, files: 2, in: directory
        )

        let enAttente = await PendingRecordingStore(directory: directory).all()
        let turn = try XCTUnwrap(enAttente.first)
        XCTAssertEqual(turn.kind, .photos)
        XCTAssertEqual(turn.filenames.count, 2)
        XCTAssertEqual(turn.entryId, "entry-7")
        XCTAssertEqual(turn.stepId, "step-2")
    }

    /// Un tour retenu jusqu'au crédit de demain garde sa retenue : relu sans
    /// elle, il partirait tout de suite et se ferait refuser.
    func testATurnHeldUntilTomorrowKeepsItsHold() async throws {
        let directory = scratch()
        let id = "44444444-4444-4444-4444-444444444444"
        // Sans fraction de seconde : c'est ce que la file écrit
        // (`dateEncodingStrategy = .iso8601`), et ce qu'elle sait relire.
        let demain = ISO8601DateFormatter().string(from: .now.addingTimeInterval(3600))
        try plant(
            """
            {"id":"\(id)","tripId":"voyage-kyoto","kind":"voice",\
            "filenames":["souvenir.m4a"],"mimeTypes":["audio/m4a"],"levels":[],\
            "recordedAt":"2026-11-12T11:00:00Z","queuedAt":"2026-11-12T11:00:00Z",\
            "waitingForCreditUntil":"\(demain)"}
            """,
            id: id, files: 1, in: directory
        )

        let enAttente = await PendingRecordingStore(directory: directory).all()
        let turn = try XCTUnwrap(enAttente.first)
        XCTAssertTrue(turn.isWaitingForCredit(), "Il attend le crédit de demain, et doit continuer d'attendre.")
    }

    /// La fiche d'avant le 22/09/2026 — un vocal, plusieurs carnets, un seul
    /// `filename`. Le décodeur sait encore la lire, et doit continuer.
    func testTheFormatFromBeforeSeptemberStillLoads() async throws {
        let directory = scratch()
        let id = "55555555-5555-5555-5555-555555555555"
        try plant(
            """
            {"id":"\(id)","tripIds":["voyage-kyoto","voyage-osaka"],\
            "filename":"souvenir.m4a","mimeType":"audio/m4a","duration":12,\
            "recordedAt":"2026-09-20T07:00:00Z","queuedAt":"2026-09-20T07:00:00Z"}
            """,
            id: id, files: 1, in: directory
        )

        let enAttente = await PendingRecordingStore(directory: directory).all()
        let turn = try XCTUnwrap(enAttente.first)
        XCTAssertEqual(turn.tripId, "voyage-kyoto", "Le premier carnet de la liste d'alors.")
        XCTAssertEqual(turn.kind, .voice, "Avant les textes et les photos, tout était un vocal.")
        XCTAssertEqual(turn.filenames, ["souvenir.m4a"])
        XCTAssertEqual(turn.mimeTypes, ["audio/m4a"])
    }

    /// Un voyage créé hors ligne, écrit par une version livrée. Perdre
    /// celui-ci, c'est perdre un voyage que le serveur n'a jamais vu.
    func testAPendingTripWrittenByAShippedVersionStillLoads() async throws {
        let directory = scratch()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("""
            [{"id":"66666666-6666-6666-6666-666666666666","accountId":"compte-1",\
            "queuedAt":"2026-11-12T12:00:00Z",\
            "draft":{"id":"66666666-6666-6666-6666-666666666666","title":"Rome","theme":"Gastronomie",\
            "startDate":"2026-11-10T00:00:00Z","endDate":"2026-11-18T00:00:00Z",\
            "narrationPace":"Tous les jours","photoTextRatio":70}}]
            """.utf8).write(to: directory.appending(path: "pending-trips.json"))

        let enAttente = await PendingTripStore(directory: directory).all()
        let trip = try XCTUnwrap(enAttente.first)
        XCTAssertEqual(trip.id, "66666666-6666-6666-6666-666666666666")
        XCTAssertEqual(trip.accountId, "compte-1")
        XCTAssertEqual(trip.draft.title, "Rome")
        XCTAssertEqual(trip.draft.theme, "Gastronomie")
        XCTAssertEqual(trip.draft.narrationPace, "Tous les jours")
        XCTAssertEqual(trip.draft.photoTextRatio, 70)
        XCTAssertNotNil(trip.draft.startDate)
        XCTAssertNotNil(trip.draft.endDate)
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
