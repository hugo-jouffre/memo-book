import Foundation

/// Statut d'une étape du pipeline, tel que le back-end le renvoie.
///
/// Le cas `unknown` existe pour qu'un statut ajouté côté serveur ne fasse pas
/// planter une version de l'app déjà installée : elle l'affichera comme « en
/// cours » plutôt que d'échouer au décodage.
public enum Status: Sendable, Hashable {
    case pending
    case processing
    case ready
    case failed
    case unknown(String)

    public var isTerminal: Bool {
        switch self {
        case .ready, .failed: true
        case .pending, .processing, .unknown: false
        }
    }

    public var isInProgress: Bool { !isTerminal }
}

extension Status: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self =
            switch raw {
            case "pending": .pending
            case "processing": .processing
            case "ready": .ready
            case "failed": .failed
            default: .unknown(raw)
            }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .pending: "pending"
        case .processing: "processing"
        case .ready: "ready"
        case .failed: "failed"
        case .unknown(let raw): raw
        }
    }
}

/// Nature d'un souvenir déposé dans un carnet.
public enum EntryKind: String, Codable, Sendable, Hashable {
    case audio
    case text
    case photo
}
