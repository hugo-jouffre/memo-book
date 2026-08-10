import Foundation

/// Identité de l'appareil, provisoire tant qu'il n'y a pas de comptes.
public struct DeviceRegistration: Codable, Sendable, Hashable {
    public let deviceId: String
    public let token: String

    public init(deviceId: String, token: String) {
        self.deviceId = deviceId
        self.token = token
    }
}

/// Un projet de carnet.
public struct Memo: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let authors: String?
    public let theme: String?
    public let startDate: Date?
    public let endDate: Date?
    public let coverPhotoUrl: String?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        authors: String? = nil,
        theme: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        coverPhotoUrl: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.authors = authors
        self.theme = theme
        self.startDate = startDate
        self.endDate = endDate
        self.coverPhotoUrl = coverPhotoUrl
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Un carnet tel qu'il apparaît dans la liste d'accueil.
public struct MemoSummary: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let theme: String?
    public let coverPhotoUrl: String?
    public let createdAt: Date
    public let entryCount: Int
    public let latestRender: Render?

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        theme: String? = nil,
        coverPhotoUrl: String? = nil,
        createdAt: Date,
        entryCount: Int,
        latestRender: Render? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.theme = theme
        self.coverPhotoUrl = coverPhotoUrl
        self.createdAt = createdAt
        self.entryCount = entryCount
        self.latestRender = latestRender
    }
}

public struct MediaSummary: Codable, Sendable, Hashable {
    public let id: String
    public let mimeType: String
    public let bytes: Int
    public let durationSeconds: Double?
    public let cdnUrl: String?

    public init(
        id: String,
        mimeType: String,
        bytes: Int,
        durationSeconds: Double? = nil,
        cdnUrl: String? = nil
    ) {
        self.id = id
        self.mimeType = mimeType
        self.bytes = bytes
        self.durationSeconds = durationSeconds
        self.cdnUrl = cdnUrl
    }
}

/// Un souvenir : un vocal, une note ou une photo.
public struct Entry: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let memoId: String
    public let kind: EntryKind
    public let status: Status
    public let transcript: String?
    public let capturedAt: Date
    public let placeLabel: String?
    public let error: String?
    public let media: MediaSummary?
    public let createdAt: Date

    public init(
        id: String,
        memoId: String,
        kind: EntryKind,
        status: Status,
        transcript: String? = nil,
        capturedAt: Date,
        placeLabel: String? = nil,
        error: String? = nil,
        media: MediaSummary? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.memoId = memoId
        self.kind = kind
        self.status = status
        self.transcript = transcript
        self.capturedAt = capturedAt
        self.placeLabel = placeLabel
        self.error = error
        self.media = media
        self.createdAt = createdAt
    }
}

/// Une génération de carnet.
public struct Render: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let memoId: String
    public let status: Status
    public let pdfUrl: String?
    public let error: String?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String,
        memoId: String,
        status: Status,
        pdfUrl: String? = nil,
        error: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.memoId = memoId
        self.status = status
        self.pdfUrl = pdfUrl
        self.error = error
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Un carnet avec tout son contenu — la réponse de `GET /v1/memos/:id`.
public struct MemoDetail: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let authors: String?
    public let theme: String?
    public let startDate: Date?
    public let endDate: Date?
    public let coverPhotoUrl: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let entries: [Entry]
    public let renders: [Render]

    /// La génération la plus récente, celle que l'écran de statut suit.
    public var latestRender: Render? { renders.first }

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        authors: String? = nil,
        theme: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        coverPhotoUrl: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        entries: [Entry] = [],
        renders: [Render] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.authors = authors
        self.theme = theme
        self.startDate = startDate
        self.endDate = endDate
        self.coverPhotoUrl = coverPhotoUrl
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.entries = entries
        self.renders = renders
    }
}

/// Paramètres de création d'un carnet.
public struct NewMemo: Codable, Sendable, Hashable {
    public var title: String
    public var subtitle: String?
    public var authors: String?
    public var theme: String?
    public var startDate: Date?
    public var endDate: Date?

    public init(
        title: String,
        subtitle: String? = nil,
        authors: String? = nil,
        theme: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.authors = authors
        self.theme = theme
        self.startDate = startDate
        self.endDate = endDate
    }
}

/// Une note écrite, envoyée telle quelle sans transcription.
///
/// Uniquement `Encodable` : ce type ne sert qu'à l'envoi, et un `let` avec
/// valeur par défaut ne peut de toute façon pas être décodé.
public struct NewTextEntry: Encodable, Sendable, Hashable {
    public let kind = EntryKind.text
    public var transcript: String
    public var capturedAt: Date
    public var placeLabel: String?

    public init(transcript: String, capturedAt: Date = .now, placeLabel: String? = nil) {
        self.transcript = transcript
        self.capturedAt = capturedAt
        self.placeLabel = placeLabel
    }

    private enum CodingKeys: String, CodingKey {
        case kind, transcript, capturedAt, placeLabel
    }
}
