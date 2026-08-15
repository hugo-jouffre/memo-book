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
///
/// Le texte traverse trois états, et les trois sont conservés :
/// `transcript` (ce qui a été dit), `redactedText` (ce que l'agent de
/// rédaction en a fait) et `editedText` (ce que l'utilisateur a corrigé au
/// clavier). `displayText` applique la hiérarchie — calculé par le serveur
/// pour que la règle ne diverge pas entre les clients.
public struct Entry: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let memoId: String
    public let kind: EntryKind
    /// Avancement de la transcription audio.
    public let status: Status
    public let transcript: String?

    /// Avancement de la rédaction, suivi séparément : une transcription
    /// réussie dont la rédaction échoue laisse un souvenir exploitable.
    public let redactionStatus: Status
    public let redactedText: String?
    public let redactionError: String?

    public let editedText: String?
    public let editedAt: Date?

    /// Le texte à afficher et à éditer. Jamais `nil` une fois la
    /// transcription passée.
    public let displayText: String?

    public let suggestedTitle: String?
    public let funFact: String?
    public let funFactTitle: String?
    public let weatherKey: String?

    public let capturedAt: Date
    public let placeLabel: String?
    public let error: String?
    public let media: MediaSummary?
    public let createdAt: Date

    /// `true` quand l'utilisateur a repris le texte à la main.
    public var isEdited: Bool { editedText != nil }

    /// `true` tant qu'il reste une étape de traitement en cours sur ce
    /// souvenir — c'est ce que la liste affiche comme « en cours ».
    public var isProcessing: Bool {
        status.isInProgress || (kind != .photo && redactionStatus.isInProgress)
    }

    /// Prêt à entrer dans le carnet : le texte ne bougera plus tout seul.
    public var isReadyForBook: Bool {
        kind == .photo || redactionStatus == .ready || redactionStatus == .failed
    }

    public init(
        id: String,
        memoId: String,
        kind: EntryKind,
        status: Status,
        transcript: String? = nil,
        redactionStatus: Status = .pending,
        redactedText: String? = nil,
        redactionError: String? = nil,
        editedText: String? = nil,
        editedAt: Date? = nil,
        displayText: String? = nil,
        suggestedTitle: String? = nil,
        funFact: String? = nil,
        funFactTitle: String? = nil,
        weatherKey: String? = nil,
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
        self.redactionStatus = redactionStatus
        self.redactedText = redactedText
        self.redactionError = redactionError
        self.editedText = editedText
        self.editedAt = editedAt
        self.displayText = displayText ?? editedText ?? redactedText ?? transcript
        self.suggestedTitle = suggestedTitle
        self.funFact = funFact
        self.funFactTitle = funFactTitle
        self.weatherKey = weatherKey
        self.capturedAt = capturedAt
        self.placeLabel = placeLabel
        self.error = error
        self.media = media
        self.createdAt = createdAt
    }

    /// Décodage tolérant sur les champs de rédaction.
    ///
    /// Même raison que `Status.unknown` : une app déjà installée ne doit pas
    /// planter parce que le serveur a changé. Ici c'est l'inverse dans le
    /// temps — un serveur plus ancien que l'app, ou une réponse d'un endpoint
    /// qui ne renvoie pas encore ces champs, donne un souvenir « en attente de
    /// rédaction » plutôt qu'une erreur de décodage.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        memoId = try container.decode(String.self, forKey: .memoId)
        kind = try container.decode(EntryKind.self, forKey: .kind)
        status = try container.decode(Status.self, forKey: .status)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript)

        redactionStatus =
            try container.decodeIfPresent(Status.self, forKey: .redactionStatus) ?? .pending
        redactedText = try container.decodeIfPresent(String.self, forKey: .redactedText)
        redactionError = try container.decodeIfPresent(String.self, forKey: .redactionError)
        editedText = try container.decodeIfPresent(String.self, forKey: .editedText)
        editedAt = try container.decodeIfPresent(Date.self, forKey: .editedAt)

        suggestedTitle = try container.decodeIfPresent(String.self, forKey: .suggestedTitle)
        funFact = try container.decodeIfPresent(String.self, forKey: .funFact)
        funFactTitle = try container.decodeIfPresent(String.self, forKey: .funFactTitle)
        weatherKey = try container.decodeIfPresent(String.self, forKey: .weatherKey)

        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        placeLabel = try container.decodeIfPresent(String.self, forKey: .placeLabel)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        media = try container.decodeIfPresent(MediaSummary.self, forKey: .media)
        createdAt = try container.decode(Date.self, forKey: .createdAt)

        // Le serveur calcule `displayText` ; le repli local applique la même
        // hiérarchie pour que les deux ne puissent pas diverger.
        displayText =
            try container.decodeIfPresent(String.self, forKey: .displayText)
            ?? editedText ?? redactedText ?? transcript
    }
}

/// Correction manuelle d'un souvenir, envoyée en `PATCH`.
///
/// `editedText` distingue trois cas et le codage doit les préserver :
/// une valeur (nouveau texte), `.some(nil)` (revenir à la version proposée),
/// et l'absence de clé (ne pas toucher au texte). `encodeIfPresent` ne suffit
/// donc pas — il écraserait le deuxième cas.
public struct EntryEdit: Encodable, Sendable, Hashable {
    public var editedText: String??
    public var suggestedTitle: String??
    public var weatherKey: String??

    public init(
        editedText: String?? = nil,
        suggestedTitle: String?? = nil,
        weatherKey: String?? = nil
    ) {
        self.editedText = editedText
        self.suggestedTitle = suggestedTitle
        self.weatherKey = weatherKey
    }

    /// Reprend le texte à la main.
    public static func text(_ value: String) -> EntryEdit {
        EntryEdit(editedText: .some(value))
    }

    /// Revient au texte proposé par la rédaction.
    public static var revertToRedaction: EntryEdit {
        EntryEdit(editedText: .some(nil))
    }

    private enum CodingKeys: String, CodingKey {
        case editedText, suggestedTitle, weatherKey
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let editedText { try container.encode(editedText, forKey: .editedText) }
        if let suggestedTitle { try container.encode(suggestedTitle, forKey: .suggestedTitle) }
        if let weatherKey { try container.encode(weatherKey, forKey: .weatherKey) }
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

/// Adresse de livraison d'un carnet imprimé.
public struct ShippingAddress: Codable, Sendable, Hashable {
    public var name: String
    public var line1: String
    public var line2: String?
    public var postalCode: String
    public var city: String
    /// Code ISO 3166-1 alpha-2.
    public var country: String

    public init(
        name: String,
        line1: String,
        line2: String? = nil,
        postalCode: String,
        city: String,
        country: String
    ) {
        self.name = name
        self.line1 = line1
        self.line2 = line2
        self.postalCode = postalCode
        self.city = city
        self.country = country
    }
}

public enum PrintOrderStatus: String, Codable, Sendable, Hashable {
    case draft
    case submitted
    case inProduction = "in_production"
    case shipped
    case cancelled
}

/// Une commande de carnet imprimé, passée sur un rendu précis.
public struct PrintOrder: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let memoId: String
    /// Le rendu commandé est figé : c'est exactement le PDF prévisualisé.
    public let renderId: String
    public let status: PrintOrderStatus
    public let copies: Int
    public let shipping: ShippingAddress
    public let trackingUrl: String?
    public let error: String?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String,
        memoId: String,
        renderId: String,
        status: PrintOrderStatus,
        copies: Int,
        shipping: ShippingAddress,
        trackingUrl: String? = nil,
        error: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.memoId = memoId
        self.renderId = renderId
        self.status = status
        self.copies = copies
        self.shipping = shipping
        self.trackingUrl = trackingUrl
        self.error = error
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Paramètres d'une commande d'impression.
public struct NewPrintOrder: Encodable, Sendable, Hashable {
    public var renderId: String
    public var copies: Int
    public var shipping: ShippingAddress

    public init(renderId: String, copies: Int = 1, shipping: ShippingAddress) {
        self.renderId = renderId
        self.copies = copies
        self.shipping = shipping
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
