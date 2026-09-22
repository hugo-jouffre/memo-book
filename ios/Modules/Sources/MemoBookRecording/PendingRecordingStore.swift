import Foundation

/// Un tour de conversation qui n'a pas pu partir — un vocal, un texte, des
/// photos —, gardé sur l'appareil jusqu'à ce qu'il parte.
///
/// Ce qui est stocké, c'est **ce que le voyageur a dit**, jamais ce que le
/// serveur en fera : la transcription appartient au serveur, et un tour en
/// attente n'a encore rien produit.
public struct PendingTurn: Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case voice
        case text
        case photos
    }

    /// L'identifiant **du message**, celui que le serveur reprendra : c'est ce
    /// qui fait qu'un tour parti deux fois — une panne de transport après un
    /// envoi qui avait abouti — ne se retrouve pas deux fois dans le fil.
    public let id: String

    /// Le carnet auquel il n'est **pas encore** arrivé. Un seul : un tour parle
    /// à une conversation.
    public var tripId: String

    public let kind: Kind

    /// Le texte d'un tour `text`, la puce qui l'a produit, le souvenir visé.
    public let text: String?
    public let suggestionId: String?
    public let entryId: String?

    public let stepId: String?

    /// Les fichiers, dans l'ordre : un pour un vocal, un à quatre pour des
    /// photos, aucun pour un texte. Écrits à côté de la fiche.
    public let filenames: [String]
    public let mimeTypes: [String]

    /// La durée réellement capturée d'un vocal — c'est elle qui décompte.
    public let duration: TimeInterval?

    /// La forme d'onde relevée pendant l'enregistrement, pour la bulle.
    public let levels: [Double]

    public let placeLabel: String?

    /// Le moment où **on a parlé**, pas celui où le tour partira. C'est cette
    /// date que le carnet range : un souvenir raconté hier au fond d'une vallée
    /// ne se pose pas au jour de la reconnexion.
    public let recordedAt: Date

    /// Depuis quand il attend. Sert à l'ordre d'envoi — le plus ancien
    /// d'abord — et à rien d'autre.
    public let queuedAt: Date

    public init(
        id: String,
        tripId: String,
        kind: Kind,
        text: String? = nil,
        suggestionId: String? = nil,
        entryId: String? = nil,
        stepId: String? = nil,
        filenames: [String] = [],
        mimeTypes: [String] = [],
        duration: TimeInterval? = nil,
        levels: [Double] = [],
        placeLabel: String? = nil,
        recordedAt: Date,
        queuedAt: Date = .now
    ) {
        self.id = id
        self.tripId = tripId
        self.kind = kind
        self.text = text
        self.suggestionId = suggestionId
        self.entryId = entryId
        self.stepId = stepId
        self.filenames = filenames
        self.mimeTypes = mimeTypes
        self.duration = duration
        self.levels = levels
        self.placeLabel = placeLabel
        self.recordedAt = recordedAt
        self.queuedAt = queuedAt
    }
}

extension PendingTurn: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, tripId, kind, text, suggestionId, entryId, stepId
        case filenames, mimeTypes, duration, levels, placeLabel, recordedAt, queuedAt
        // La fiche d'avant le 22/09/2026 : un vocal, plusieurs carnets.
        case tripIds, filename, mimeType
    }

    /// Décodage **tolérant** : une fiche écrite par une version d'avant — un
    /// vocal pour plusieurs carnets, sous `tripIds`, `filename`, `mimeType` —
    /// se relit comme un tour vocal pour le premier de ses carnets. Un
    /// souvenir qui a passé la nuit sur le disque ne se jette pas parce que
    /// l'app a été mise à jour entre-temps.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let legacyTripIds = try container.decodeIfPresent([String].self, forKey: .tripIds) ?? []
        guard let tripId = try container.decodeIfPresent(String.self, forKey: .tripId) ?? legacyTripIds.first
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .tripId,
                in: container,
                debugDescription: "Un tour en attente sans carnet."
            )
        }

        let legacyFilename = try container.decodeIfPresent(String.self, forKey: .filename)
        let legacyMimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)

        self.init(
            id: try container.decode(String.self, forKey: .id),
            tripId: tripId,
            kind: try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .voice,
            text: try container.decodeIfPresent(String.self, forKey: .text),
            suggestionId: try container.decodeIfPresent(String.self, forKey: .suggestionId),
            entryId: try container.decodeIfPresent(String.self, forKey: .entryId),
            stepId: try container.decodeIfPresent(String.self, forKey: .stepId),
            filenames: try container.decodeIfPresent([String].self, forKey: .filenames)
                ?? legacyFilename.map { [$0] } ?? [],
            mimeTypes: try container.decodeIfPresent([String].self, forKey: .mimeTypes)
                ?? legacyMimeType.map { [$0] } ?? [],
            duration: try container.decodeIfPresent(TimeInterval.self, forKey: .duration),
            levels: try container.decodeIfPresent([Double].self, forKey: .levels) ?? [],
            placeLabel: try container.decodeIfPresent(String.self, forKey: .placeLabel),
            recordedAt: try container.decode(Date.self, forKey: .recordedAt),
            queuedAt: try container.decode(Date.self, forKey: .queuedAt)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(tripId, forKey: .tripId)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(suggestionId, forKey: .suggestionId)
        try container.encodeIfPresent(entryId, forKey: .entryId)
        try container.encodeIfPresent(stepId, forKey: .stepId)
        try container.encode(filenames, forKey: .filenames)
        try container.encode(mimeTypes, forKey: .mimeTypes)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encode(levels, forKey: .levels)
        try container.encodeIfPresent(placeLabel, forKey: .placeLabel)
        try container.encode(recordedAt, forKey: .recordedAt)
        try container.encode(queuedAt, forKey: .queuedAt)
    }
}

/// La file d'attente des tours, sur le disque de l'appareil.
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
    private var records: [PendingTurn]?

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

    /// Les tours en attente, le plus ancien d'abord — c'est l'ordre dans
    /// lequel ils repartiront.
    public func all() -> [PendingTurn] {
        if let records { return records }

        let loaded = readFromDisk().sorted { $0.queuedAt < $1.queuedAt }
        records = loaded
        return loaded
    }

    public func count() -> Int { all().count }

    /// Met un tour de côté. Les fichiers sont écrits **avant** la fiche : une
    /// écriture interrompue laisse alors des fichiers orphelins, que rien ne
    /// lira, plutôt qu'une fiche qui promet un fichier absent.
    ///
    /// Un tour déjà en file sous le même identifiant n'est pas repris : c'est
    /// le renvoi d'un même message, pas un second.
    @discardableResult
    public func enqueue(_ turn: PendingTurn, files: [Data]) throws -> PendingTurn {
        // La file est relue **avant** d'écrire quoi que ce soit. Après, une
        // première relecture verrait déjà la fiche qu'on vient de poser sur le
        // disque, et l'ajouter une seconde fois compterait deux tours en
        // attente pour un seul.
        var known = all()
        if let existing = known.first(where: { $0.id == turn.id }) { return existing }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for (index, data) in files.enumerated() {
            try data.write(
                to: fileURL(turn.id, index: index),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        }
        try write(turn)

        known.append(turn)
        records = known
        return turn
    }

    /// Les fichiers d'un tour, relus du disque au moment de l'envoyer et pas
    /// avant : une file de dix souvenirs ne tient pas dix vocaux en mémoire.
    public func files(for turn: PendingTurn) throws -> [Data] {
        try turn.filenames.indices.map { index in
            try Data(contentsOf: fileURL(turn.id, index: index))
        }
    }

    /// Réécrit une fiche.
    public func update(_ turn: PendingTurn) throws {
        try write(turn)
        records = all().map { $0.id == turn.id ? turn : $0 }
    }

    /// Le tour est arrivé, ou plus rien ne peut le faire arriver : on le
    /// retire, fiche et fichiers.
    public func remove(_ turn: PendingTurn) {
        try? FileManager.default.removeItem(at: metadataURL(turn.id))
        for index in 0..<max(turn.filenames.count, 1) {
            try? FileManager.default.removeItem(at: fileURL(turn.id, index: index))
        }
        records = all().filter { $0.id != turn.id }
    }

    public func removeAll() {
        for turn in all() { remove(turn) }
    }

    // MARK: - Le disque

    private func metadataURL(_ id: String) -> URL { directory.appending(path: "\(id).json") }

    /// Le premier fichier garde le nom d'avant (`<id>.audio`) : c'est celui
    /// qu'une fiche d'une version précédente désigne.
    private func fileURL(_ id: String, index: Int) -> URL {
        index == 0
            ? directory.appending(path: "\(id).audio")
            : directory.appending(path: "\(id)-\(index).file")
    }

    private func write(_ turn: PendingTurn) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(turn).write(
            to: metadataURL(turn.id),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    /// Relit la file. Une fiche illisible — disque abîmé — est **jetée avec ses
    /// fichiers** plutôt que de faire échouer la lecture entière : un souvenir
    /// perdu ne doit pas en bloquer neuf autres. Une fiche qui promet un
    /// fichier absent aussi.
    private func readFromDisk() -> [PendingTurn] {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                let turn = try? decoder.decode(PendingTurn.self, from: data)
            else {
                try? manager.removeItem(at: url)
                return nil
            }
            let filesArePresent = turn.filenames.indices.allSatisfy { index in
                manager.fileExists(atPath: fileURL(turn.id, index: index).path(percentEncoded: false))
            }
            guard filesArePresent else {
                try? manager.removeItem(at: url)
                return nil
            }
            return turn
        }
    }
}
