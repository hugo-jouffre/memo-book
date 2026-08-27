import Foundation
import MemoBookCore
import MemoBookNetworking

/// Double de l'API pour les aperçus SwiftUI et les tests d'interface.
///
/// Il garde son état en mémoire : ajouter un souvenir dans un aperçu met
/// vraiment la liste à jour, ce qui rend les aperçus utilisables pour
/// travailler les écrans sans back-end lancé.
public actor PreviewAPI: MemoBookAPI {
    private var memosById: [String: MemoDetail] = [:]
    private var rendersById: [String: Render] = [:]
    private var ordersByMemoId: [String: [PrintOrder]] = [:]

    public init(seeded: Bool = true) {
        // Le jeu d'essai est construit hors de l'acteur puis affecté : un `init`
        // synchrone d'acteur ne peut pas appeler ses propres méthodes isolées.
        if seeded {
            let seed = Self.seedMemo()
            memosById[seed.id] = seed
        }
    }

    private static func seedMemo() -> MemoDetail {
        let memoId = "preview-memo"
        let now = Date.now

        let entries = [
            Entry(
                id: "entry-1",
                memoId: memoId,
                kind: .audio,
                status: .ready,
                transcript:
                    "euh du coup on arrive à Bogotá après un vol de nuit, et enfin la première claque c'est l'altitude quoi",
                redactionStatus: .ready,
                redactedText:
                    "On arrive à Bogotá après un vol de nuit. La première claque, c'est l'altitude.",
                suggestedTitle: "Premier souffle à 2 600 mètres",
                funFact: "Bogotá culmine à 2 640 m : la troisième capitale la plus haute d'Amérique du Sud.",
                funFactTitle: "Fun fact",
                weatherKey: "cloud",
                capturedAt: now.addingTimeInterval(-86_400 * 2),
                placeLabel: "Bogotá, Colombie",
                error: nil,
                media: nil,
                createdAt: now.addingTimeInterval(-86_400 * 2)
            ),
            Entry(
                id: "entry-2",
                memoId: memoId,
                kind: .audio,
                status: .ready,
                transcript: "on est montés à Monserrate en funiculaire, la vue est dingue",
                redactionStatus: .processing,
                capturedAt: now.addingTimeInterval(-86_400),
                placeLabel: "Monserrate",
                error: nil,
                media: nil,
                createdAt: now.addingTimeInterval(-86_400)
            ),
        ]

        return MemoDetail(
            id: memoId,
            title: "Claire et Gus en Colombie",
            subtitle: "Un carnet de voyage raconté à l'oral",
            authors: "Claire et Augustin",
            theme: "voyage",
            startDate: nil,
            endDate: nil,
            coverPhotoUrl: nil,
            createdAt: now,
            updatedAt: now,
            entries: entries,
            renders: []
        )
    }

    public func ensureDeviceRegistered() async throws {}

    // MARK: - Compte

    /// Le compte simulé. Les écrans d'onboarding s'y branchent sans back-end :
    /// l'inscription crée vraiment un compte, la connexion le retrouve, et le
    /// lien de réinitialisation est lisible dans `lastResetToken`.
    private var accountsByEmail: [String: (account: Account, password: String?)] = [:]
    private var currentUserId: String?
    private var socialIdentities: [String: String] = [:]
    public private(set) var lastResetToken: String?

    public func currentAccount() async throws -> Account {
        guard let currentUserId,
            let match = accountsByEmail.values.first(where: { $0.account.id == currentUserId })
        else {
            throw APIError.notAuthenticated
        }
        return match.account
    }

    public func signUp(_ account: NewAccount) async throws -> AuthenticatedSession {
        let email = EmailValidation.normalize(account.email)
        guard accountsByEmail[email] == nil else {
            throw APIError.server(
                statusCode: 409,
                code: "conflict",
                message: "Un compte existe déjà avec cette adresse."
            )
        }

        let created = Account(
            id: UUID().uuidString,
            email: email,
            firstName: account.firstName,
            lastName: account.lastName,
            hasSeenOnboarding: true
        )
        accountsByEmail[email] = (created, account.password)
        return open(created)
    }

    public func signIn(email: String, password: String) async throws -> AuthenticatedSession {
        let match = accountsByEmail[EmailValidation.normalize(email)]
        guard let match, match.password == password else {
            throw APIError.server(
                statusCode: 401,
                code: "invalid_credentials",
                message: "Email ou mot de passe incorrect."
            )
        }
        return open(match.account)
    }

    public func signOut() async {
        currentUserId = nil
    }

    public func signIn(
        with provider: SocialProvider,
        credential: String
    ) async throws -> SocialSignInOutcome {
        if let email = socialIdentities[credential], let match = accountsByEmail[email] {
            return .signedIn(open(match.account))
        }

        return .profileRequired(
            SocialProfileDraft(
                socialToken: credential,
                provider: provider,
                firstName: "Cla",
                lastName: "Thioll",
                email: provider == .apple ? "xk29fj@privaterelay.appleid.com" : nil
            )
        )
    }

    public func completeSocialProfile(
        _ profile: CompletedSocialProfile
    ) async throws -> AuthenticatedSession {
        let email = EmailValidation.normalize(profile.email)
        guard accountsByEmail[email] == nil else {
            throw APIError.server(
                statusCode: 409,
                code: "conflict",
                message: "Un compte existe déjà avec cette adresse."
            )
        }

        let created = Account(
            id: UUID().uuidString,
            email: email,
            firstName: profile.firstName,
            lastName: profile.lastName,
            hasSeenOnboarding: true
        )
        accountsByEmail[email] = (created, nil)
        socialIdentities[profile.socialToken] = email
        return open(created)
    }

    public func requestPasswordReset(email: String) async throws {
        guard accountsByEmail[EmailValidation.normalize(email)] != nil else {
            throw APIError.server(
                statusCode: 404,
                code: "not_found",
                message: "Aucun compte n'est associé à cette adresse."
            )
        }
        lastResetToken = UUID().uuidString
    }

    public func resetPassword(token: String, newPassword: String) async throws {
        guard token == lastResetToken else {
            throw APIError.server(
                statusCode: 400,
                code: "invalid_or_expired_token",
                message: "Ce lien n'est plus valable."
            )
        }
        lastResetToken = nil
    }

    private func open(_ account: Account) -> AuthenticatedSession {
        currentUserId = account.id
        return AuthenticatedSession(
            userId: account.id,
            sessionToken: "preview-session",
            hasSeenOnboarding: account.hasSeenOnboarding
        )
    }

    public func memos() async throws -> [MemoSummary] {
        memosById.values
            .sorted { $0.createdAt > $1.createdAt }
            .map { memo in
                MemoSummary(
                    id: memo.id,
                    title: memo.title,
                    subtitle: memo.subtitle,
                    theme: memo.theme,
                    coverPhotoUrl: memo.coverPhotoUrl,
                    createdAt: memo.createdAt,
                    entryCount: memo.entries.count,
                    latestRender: memo.renders.first
                )
            }
    }

    public func createMemo(_ memo: NewMemo) async throws -> Memo {
        let id = UUID().uuidString
        let now = Date.now

        memosById[id] = MemoDetail(
            id: id,
            title: memo.title,
            subtitle: memo.subtitle,
            authors: memo.authors,
            theme: memo.theme,
            startDate: memo.startDate,
            endDate: memo.endDate,
            coverPhotoUrl: nil,
            createdAt: now,
            updatedAt: now,
            entries: [],
            renders: []
        )

        return Memo(
            id: id,
            title: memo.title,
            subtitle: memo.subtitle,
            authors: memo.authors,
            theme: memo.theme,
            startDate: memo.startDate,
            endDate: memo.endDate,
            createdAt: now,
            updatedAt: now
        )
    }

    public func memo(id: String) async throws -> MemoDetail {
        guard let memo = memosById[id] else {
            throw APIError.server(statusCode: 404, code: "not_found", message: "Carnet introuvable.")
        }
        return memo
    }

    public func deleteMemo(id: String) async throws {
        memosById[id] = nil
    }

    public func addTextEntry(memoId: String, entry: NewTextEntry) async throws -> Entry {
        try append(
            to: memoId,
            kind: .text,
            status: .ready,
            redactionStatus: .pending,
            transcript: entry.transcript,
            capturedAt: entry.capturedAt,
            placeLabel: entry.placeLabel
        )
    }

    public func uploadAudio(
        memoId: String,
        data: Data,
        filename: String,
        mimeType: String,
        capturedAt: Date,
        placeLabel: String?
    ) async throws -> Entry {
        try append(
            to: memoId,
            kind: .audio,
            status: .pending,
            redactionStatus: .pending,
            transcript: nil,
            capturedAt: capturedAt,
            placeLabel: placeLabel
        )
    }

    public func uploadPhoto(
        memoId: String,
        data: Data,
        filename: String,
        mimeType: String,
        capturedAt: Date,
        placeLabel: String?
    ) async throws -> Entry {
        try append(
            to: memoId,
            kind: .photo,
            status: .ready,
            redactionStatus: .ready,
            transcript: nil,
            capturedAt: capturedAt,
            placeLabel: placeLabel
        )
    }

    private func append(
        to memoId: String,
        kind: EntryKind,
        status: Status,
        redactionStatus: Status,
        transcript: String?,
        capturedAt: Date,
        placeLabel: String?
    ) throws -> Entry {
        let memo = try existingMemo(memoId)

        let entry = Entry(
            id: UUID().uuidString,
            memoId: memoId,
            kind: kind,
            status: status,
            transcript: transcript,
            redactionStatus: redactionStatus,
            capturedAt: capturedAt,
            placeLabel: placeLabel,
            error: nil,
            media: nil,
            createdAt: .now
        )

        memosById[memoId] = memo.appending(entry: entry)
        return entry
    }

    public func entry(id: String) async throws -> Entry {
        for memo in memosById.values {
            if let entry = memo.entries.first(where: { $0.id == id }) { return entry }
        }
        throw APIError.server(statusCode: 404, code: "not_found", message: "Entrée introuvable.")
    }

    public func updateEntry(id: String, edit: EntryEdit) async throws -> Entry {
        let current = try await entry(id: id)

        // `String??` : `.some(nil)` revient au texte proposé, `nil` ne touche
        // à rien. Le double niveau est ce qui distingue les deux.
        let editedText: String? = edit.editedText ?? current.editedText
        let updated = current.applying(editedText: editedText)

        replace(entry: updated)
        return updated
    }

    public func retryRedaction(entryId: String) async throws -> Entry {
        let current = try await entry(id: entryId)

        guard current.editedText == nil else {
            throw APIError.server(
                statusCode: 400,
                code: "manually_edited",
                message: "Ce souvenir a été corrigé à la main."
            )
        }

        let queued = current.applying(redactionStatus: .pending)
        replace(entry: queued)
        return queued
    }

    private func replace(entry: Entry) {
        guard let memo = memosById[entry.memoId] else { return }
        memosById[entry.memoId] = memo.replacing(entry: entry)
    }

    public func startRender(memoId: String) async throws -> Render {
        let memo = try existingMemo(memoId)

        let render = Render(
            id: UUID().uuidString,
            memoId: memoId,
            status: .ready,
            pdfUrl: "https://pdf.example.test/preview.pdf",
            error: nil,
            createdAt: .now,
            updatedAt: .now
        )

        rendersById[render.id] = render
        memosById[memoId] = memo.prepending(render: render)
        return render
    }

    public func render(id: String) async throws -> Render {
        guard let render = rendersById[id] else {
            throw APIError.server(
                statusCode: 404,
                code: "not_found",
                message: "Génération introuvable."
            )
        }
        return render
    }

    public func createPrintOrder(memoId: String, order: NewPrintOrder) async throws -> PrintOrder {
        _ = try existingMemo(memoId)

        let created = PrintOrder(
            id: UUID().uuidString,
            memoId: memoId,
            renderId: order.renderId,
            status: .draft,
            copies: order.copies,
            shipping: order.shipping,
            trackingUrl: nil,
            error: nil,
            createdAt: .now,
            updatedAt: .now
        )

        ordersByMemoId[memoId, default: []].insert(created, at: 0)
        return created
    }

    public func printOrders(memoId: String) async throws -> [PrintOrder] {
        ordersByMemoId[memoId] ?? []
    }

    private func existingMemo(_ id: String) throws -> MemoDetail {
        guard let memo = memosById[id] else {
            throw APIError.server(statusCode: 404, code: "not_found", message: "Carnet introuvable.")
        }
        return memo
    }
}

extension MemoDetail {
    fileprivate func appending(entry: Entry) -> MemoDetail {
        MemoDetail(
            id: id,
            title: title,
            subtitle: subtitle,
            authors: authors,
            theme: theme,
            startDate: startDate,
            endDate: endDate,
            coverPhotoUrl: coverPhotoUrl,
            createdAt: createdAt,
            updatedAt: .now,
            entries: (entries + [entry]).sorted { $0.capturedAt < $1.capturedAt },
            renders: renders
        )
    }

    fileprivate func replacing(entry: Entry) -> MemoDetail {
        MemoDetail(
            id: id,
            title: title,
            subtitle: subtitle,
            authors: authors,
            theme: theme,
            startDate: startDate,
            endDate: endDate,
            coverPhotoUrl: coverPhotoUrl,
            createdAt: createdAt,
            updatedAt: .now,
            entries: entries.map { $0.id == entry.id ? entry : $0 },
            renders: renders
        )
    }

    fileprivate func prepending(render: Render) -> MemoDetail {
        MemoDetail(
            id: id,
            title: title,
            subtitle: subtitle,
            authors: authors,
            theme: theme,
            startDate: startDate,
            endDate: endDate,
            coverPhotoUrl: coverPhotoUrl,
            createdAt: createdAt,
            updatedAt: .now,
            entries: entries,
            renders: [render] + renders
        )
    }
}

extension Entry {
    /// Recopie l'entrée en changeant la correction manuelle. `displayText` est
    /// recalculé par l'initialiseur, comme le ferait le serveur.
    fileprivate func applying(editedText newValue: String?) -> Entry {
        copy(editedText: newValue, editedAt: newValue == nil ? nil : .now, redactionStatus: redactionStatus)
    }

    fileprivate func applying(redactionStatus newValue: Status) -> Entry {
        copy(editedText: editedText, editedAt: editedAt, redactionStatus: newValue)
    }

    private func copy(editedText: String?, editedAt: Date?, redactionStatus: Status) -> Entry {
        Entry(
            id: id,
            memoId: memoId,
            kind: kind,
            status: status,
            transcript: transcript,
            redactionStatus: redactionStatus,
            redactedText: redactedText,
            redactionError: redactionError,
            editedText: editedText,
            editedAt: editedAt,
            displayText: nil,
            suggestedTitle: suggestedTitle,
            funFact: funFact,
            funFactTitle: funFactTitle,
            weatherKey: weatherKey,
            capturedAt: capturedAt,
            placeLabel: placeLabel,
            error: error,
            media: media,
            createdAt: createdAt
        )
    }
}
