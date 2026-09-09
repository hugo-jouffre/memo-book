import Foundation

/// Un vocal enregistré alors que le réseau manquait, gardé sur l'appareil
/// jusqu'à ce qu'il parte.
///
/// Ce qui est stocké, c'est **le fichier audio**, jamais le texte : la
/// transcription appartient au serveur, et un vocal en attente n'a encore rien
/// produit.
public struct PendingRecording: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID

    /// Les carnets auxquels il n'est **pas encore** arrivé.
    ///
    /// La liste rétrécit à chaque envoi réussi : quelqu'un qui mène deux
    /// voyages de front et dont un seul des deux envois passe ne doit pas
    /// recevoir le vocal en double dans le premier.
    public var tripIds: [String]

    public let filename: String
    public let mimeType: String
    public let duration: TimeInterval

    /// Le moment où **on a parlé**, pas celui où le vocal partira. C'est cette
    /// date que le carnet range : un souvenir raconté hier au fond d'une vallée
    /// ne se pose pas au jour de la reconnexion.
    public let recordedAt: Date

    /// Depuis quand il attend. Sert à l'ordre d'envoi — le plus ancien
    /// d'abord — et à rien d'autre.
    public let queuedAt: Date
}

/// La file d'attente des vocaux, sur le disque de l'appareil.
///
/// **Sur le disque et non en mémoire, parce que c'est tout l'intérêt** : un
/// vocal enregistré dans un train doit survivre à la fermeture de l'app, à la
/// batterie vide et au redémarrage. Une file en mémoire ne promettrait la même
/// chose qu'à l'écran.
///
/// Elle vit dans `Application Support` et non dans `Caches` : iOS vide les
/// caches sous pression disque, et ce qui est ici est le récit de quelqu'un,
/// que rien ne peut régénérer. Le dossier est donc aussi sauvegardé — c'est
/// voulu.
///
/// Un acteur, pas une classe : les lectures et écritures de fichiers ne
/// bloquent jamais l'écran, et deux envois concurrents ne peuvent pas se
/// marcher dessus.
public actor PendingRecordingStore {
    private let directory: URL

    /// L'état de la file, lu une fois du disque puis tenu à jour ici. `nil`
    /// tant qu'on n'a pas encore regardé.
    private var records: [PendingRecording]?

    public init(directory: URL) {
        self.directory = directory
    }

    /// La file de l'app : celle qui survit à tout.
    public static func inLibrary() -> PendingRecordingStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        // Le repli sur `temporary` n'arrive pas sur un iPhone : `Application
        // Support` existe toujours. Mais il vaut mieux une file éphémère qu'un
        // `!` qui ferme l'app au premier enregistrement.
        guard let base = base.first else { return .temporary() }
        return PendingRecordingStore(directory: base.appending(path: "PendingRecordings"))
    }

    /// Une file jetable, dans le dossier temporaire : les aperçus SwiftUI et
    /// les tests. Le code exercé est **le même** — c'est le dossier qui change.
    public static func temporary() -> PendingRecordingStore {
        PendingRecordingStore(
            directory: FileManager.default.temporaryDirectory
                .appending(path: "PendingRecordings-\(UUID().uuidString)")
        )
    }

    /// Les vocaux en attente, le plus ancien d'abord — c'est l'ordre dans
    /// lequel ils repartiront.
    public func all() -> [PendingRecording] {
        if let records { return records }

        let loaded = readFromDisk().sorted { $0.queuedAt < $1.queuedAt }
        records = loaded
        return loaded
    }

    public func count() -> Int { all().count }

    /// Met un vocal de côté. Le fichier audio est écrit **avant** sa fiche :
    /// une écriture interrompue laisse alors un audio orphelin, que rien ne
    /// lira, plutôt qu'une fiche qui promet un fichier absent.
    @discardableResult
    public func enqueue(_ audio: RecordedAudio, for tripIds: [String]) throws -> PendingRecording {
        // La file est relue **avant** d'écrire quoi que ce soit. Après, une
        // première relecture verrait déjà la fiche qu'on vient de poser sur le
        // disque, et l'ajouter une seconde fois compterait deux vocaux en
        // attente pour un seul enregistrement.
        var known = all()

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let record = PendingRecording(
            id: UUID(),
            tripIds: tripIds,
            filename: audio.filename,
            mimeType: audio.mimeType,
            duration: audio.duration,
            recordedAt: audio.recordedAt,
            queuedAt: .now
        )

        try audio.data.write(
            to: audioURL(record.id),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        try write(record)

        known.append(record)
        records = known
        return record
    }

    /// Le vocal lui-même, relu du disque au moment de l'envoyer et pas avant :
    /// une file de dix souvenirs ne tient pas dix fichiers audio en mémoire.
    public func audio(for record: PendingRecording) throws -> RecordedAudio {
        RecordedAudio(
            data: try Data(contentsOf: audioURL(record.id)),
            filename: record.filename,
            mimeType: record.mimeType,
            duration: record.duration,
            recordedAt: record.recordedAt
        )
    }

    /// Réécrit une fiche — en pratique, sa liste de carnets, une fois qu'une
    /// partie des envois est passée.
    public func update(_ record: PendingRecording) throws {
        try write(record)
        records = all().map { $0.id == record.id ? record : $0 }
    }

    /// Le vocal est arrivé partout, ou plus rien ne peut le faire arriver : on
    /// le retire, fiche et audio.
    public func remove(_ record: PendingRecording) {
        try? FileManager.default.removeItem(at: metadataURL(record.id))
        try? FileManager.default.removeItem(at: audioURL(record.id))
        records = all().filter { $0.id != record.id }
    }

    public func removeAll() {
        for record in all() { remove(record) }
    }

    // MARK: - Le disque

    private func metadataURL(_ id: UUID) -> URL { directory.appending(path: "\(id.uuidString).json") }
    private func audioURL(_ id: UUID) -> URL { directory.appending(path: "\(id.uuidString).audio") }

    private func write(_ record: PendingRecording) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(
            to: metadataURL(record.id),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    /// Relit la file. Une fiche illisible — mise à jour de l'app, disque
    /// abîmé — est **jetée avec son audio** plutôt que de faire échouer la
    /// lecture entière : un souvenir perdu ne doit pas en bloquer neuf autres.
    private func readFromDisk() -> [PendingRecording] {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                let record = try? decoder.decode(PendingRecording.self, from: data),
                manager.fileExists(atPath: audioURL(record.id).path(percentEncoded: false))
            else {
                try? manager.removeItem(at: url)
                return nil
            }
            return record
        }
    }
}
