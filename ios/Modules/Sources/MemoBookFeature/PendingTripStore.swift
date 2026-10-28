import Foundation
import MemoBookCore

/// Un voyage créé sur le téléphone, que le serveur n'a pas encore vu.
///
/// Il porte **son brouillon entier**, et non une liste de corrections : la
/// création se rejoue (`POST /v1/trips` reconnaît son identifiant), donc
/// revenir sur les dates hors ligne ne fait que remplacer le brouillon qui
/// attend.
public struct PendingTrip: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public var draft: TripDraft

    /// Le compte qui l'a créé. Un autre compte ouvert sur le même téléphone ne
    /// le voit pas et ne l'envoie pas : c'est le voyage de quelqu'un, et le
    /// créer sous un autre nom le lui prendrait. `nil` dans le bac à sable,
    /// qui n'a pas de compte.
    public let accountId: String?

    public let queuedAt: Date

    public init(id: String, draft: TripDraft, accountId: String?, queuedAt: Date = .now) {
        self.id = id
        self.draft = draft
        self.accountId = accountId
        self.queuedAt = queuedAt
    }

    /// Le voyage tel qu'il se montre en attendant le serveur.
    public var trip: Trip { .local(draft, id: id) }
}

/// Une entrée de la file relue **sans jamais échouer** : le voyage quand on
/// sait le lire, et de toute façon ce que le disque portait.
///
/// C'est ce qui permet de relire la file voyage par voyage : une entrée qu'on
/// ne comprend pas rend `trip` nul au lieu de faire échouer le tableau entier
/// — voir ``PendingTripStore/all()``.
private struct UnreadablePendingTrip: Decodable {
    let trip: PendingTrip?
    let payload: JSONValue

    init(from decoder: any Decoder) throws {
        // Le brut d'abord : il ne peut pas échouer, et c'est lui qu'on garde.
        payload = try JSONValue(from: decoder)
        trip = try? PendingTrip(from: decoder)
    }
}

/// N'importe quelle valeur JSON, relue et réécrite **à l'identique**.
///
/// Elle ne sert qu'à ne rien perdre : ce qu'une version de l'app n'a pas su
/// relire, elle le réécrit tel quel. Aucun écran ne la lit.
enum JSONValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// Les voyages qui attendent le réseau, **sur le disque**.
///
/// À côté des vocaux en attente (``PendingRecordingStore``), et pour la même
/// raison dans `Application Support` et non dans `Caches` : un voyage créé
/// dans l'avion n'existe nulle part ailleurs, et iOS vide les caches sans
/// prévenir. Un seul fichier : ils se comptent sur les doigts d'une main.
public actor PendingTripStore {
    private let file: URL
    private var trips: [PendingTrip]?

    public init(directory: URL) {
        file = directory.appending(path: "pending-trips.json")
    }

    public static func inLibrary() -> PendingTripStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard let base = base.first else { return .temporary() }
        return PendingTripStore(directory: base.appending(path: "PendingTrips"))
    }

    public static func temporary() -> PendingTripStore {
        PendingTripStore(
            directory: FileManager.default.temporaryDirectory.appending(path: "PendingTrips-\(UUID().uuidString)")
        )
    }

    /// Les voyages en attente, le plus ancien d'abord — l'ordre où ils partent.
    ///
    /// **Voyage par voyage, et sans jamais jeter le fichier** (Hugo,
    /// 28/10/2026 — « s'assurer que le passage d'une version à une autre ne
    /// fasse pas perdre les données »). Toute la file tient dans **un seul**
    /// fichier : une version qui n'aurait pas su le relire lisait une liste
    /// vide, et le premier enregistrement qui suivait l'écrasait avec le seul
    /// voyage du moment. Un champ obligatoire ajouté à ``TripDraft`` suffisait
    /// à détruire en silence les voyages créés dans l'avion.
    ///
    /// Chaque entrée est donc relue séparément : celles qu'on comprend
    /// arrivent, les autres sont **gardées telles quelles** (``unreadable``)
    /// et réécrites avec le reste — elles repartiront le jour où une version
    /// saura les lire. Un fichier entièrement illisible est mis de côté avant
    /// toute réécriture (``setAsideCorruptedFile()``).
    public func all() -> [PendingTrip] {
        if let trips { return trips }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = try? Data(contentsOf: file) else {
            trips = []
            return []
        }

        // Chaque élément est relu seul : un voyage qu'on ne comprend pas ne
        // doit pas emporter ceux qu'on comprend.
        let raw = (try? decoder.decode([UnreadablePendingTrip].self, from: data)) ?? []
        if raw.isEmpty, !isEmptyArray(data) {
            // Rien n'a été relu alors que le fichier portait quelque chose :
            // on ne l'écrasera pas sans en garder une copie.
            setAsideCorruptedFile()
        }

        unreadable = raw.filter { $0.trip == nil }.map(\.payload)
        let sorted = raw.compactMap(\.trip).sorted { $0.queuedAt < $1.queuedAt }
        trips = sorted
        return sorted
    }

    /// Les entrées qu'on n'a pas su relire, gardées telles que le disque les
    /// portait. Elles ne se montrent pas et ne partent pas — elles survivent.
    private var unreadable: [JSONValue] = []

    /// Le fichier porte-t-il un tableau vide ? Un `[]` écrit par l'app n'est
    /// pas un fichier illisible, et n'a rien à mettre de côté.
    private func isEmptyArray(_ data: Data) -> Bool {
        (try? JSONDecoder().decode([JSONValue].self, from: data))?.isEmpty ?? false
    }

    /// Range le fichier qu'on n'a pas su relire à côté du vrai, avec l'heure
    /// où on l'a trouvé. Il n'est jamais relu par l'app : il existe pour que
    /// rien ne soit détruit.
    private func setAsideCorruptedFile() {
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let destination = file.deletingLastPathComponent()
            .appending(path: "\(file.deletingPathExtension().lastPathComponent)-illisible-\(stamp).json")
        try? FileManager.default.copyItem(at: file, to: destination)
    }

    /// Pose le voyage, ou remplace son brouillon s'il attendait déjà — sans
    /// changer sa place dans la file.
    public func save(_ trip: PendingTrip) throws {
        var known = all()
        if let index = known.firstIndex(where: { $0.id == trip.id }) {
            known[index].draft = trip.draft
        } else {
            known.append(trip)
        }
        try write(known)
        trips = known
    }

    public func remove(id: String) {
        let remaining = all().filter { $0.id != id }
        try? write(remaining)
        trips = remaining
    }

    /// Retire le voyage, **à condition** qu'il attende encore ce brouillon-là.
    /// Une correction posée pendant l'envoi reste, et partira à son tour.
    public func remove(id: String, ifDraftIs draft: TripDraft) {
        guard all().first(where: { $0.id == id })?.draft == draft else { return }
        remove(id: id)
    }

    public func removeAll() {
        try? FileManager.default.removeItem(at: file)
        trips = []
    }

    private func write(_ trips: [PendingTrip]) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Ce qu'on n'a pas su relire est réécrit **tel quel**, à la suite : il
        // ne se montre pas, il ne part pas, et il n'est pas perdu.
        let payloads = trips.compactMap { trip -> JSONValue? in
            (try? encoder.encode(trip)).flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
        }
        try encoder.encode(payloads + unreadable).write(
            to: file,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }
}
