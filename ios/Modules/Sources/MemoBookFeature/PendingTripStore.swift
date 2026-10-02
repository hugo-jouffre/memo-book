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
    public func all() -> [PendingTrip] {
        if let trips { return trips }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = (try? Data(contentsOf: file))
            .flatMap { try? decoder.decode([PendingTrip].self, from: $0) } ?? []
        let sorted = loaded.sorted { $0.queuedAt < $1.queuedAt }
        trips = sorted
        return sorted
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
        try encoder.encode(trips).write(
            to: file,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }
}
