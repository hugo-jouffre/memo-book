import Foundation
import MemoBookCore

/// Implémentation HTTP du contrat `MemoBookAPI`.
public actor MemoBookAPIClient: MemoBookAPI {
    private let configuration: APIConfiguration
    private let session: URLSession
    private let tokenStore: any TokenStore
    private let sessionStore: any SessionStore
    private let decoder = JSONDecoder.memoBook
    private let encoder = JSONEncoder.memoBook

    /// Enregistrement en cours, partagé : deux écrans qui démarrent en même
    /// temps ne doivent pas créer deux appareils.
    private var registrationTask: Task<Void, any Error>?

    public init(
        configuration: APIConfiguration = .localDevelopment,
        session: URLSession = .shared,
        tokenStore: any TokenStore = KeychainTokenStore(),
        sessionStore: any SessionStore = KeychainSessionStore()
    ) {
        self.configuration = configuration
        self.session = session
        self.tokenStore = tokenStore
        self.sessionStore = sessionStore
    }

    // MARK: - Identité

    public func ensureDeviceRegistered() async throws {
        if tokenStore.read() != nil { return }

        if let registrationTask {
            return try await registrationTask.value
        }

        let task = Task<Void, any Error> { [tokenStore] in
            let registration: DeviceRegistration = try await self.send(
                method: "POST",
                path: "/v1/devices",
                body: ["platform": "ios"],
                authenticated: false
            )
            tokenStore.write(registration.token)
        }

        registrationTask = task
        defer { registrationTask = nil }
        try await task.value
    }

    // MARK: - Compte

    public func currentAccount() async throws -> Account {
        struct Response: Decodable { let user: Account }
        let response: Response = try await send(method: "GET", path: "/v1/auth/me")
        return response.user
    }

    public func signUp(_ account: NewAccount) async throws -> AuthenticatedSession {
        try await openSession(
            path: "/v1/auth/signup",
            body: SignUpBody(
                firstName: account.firstName,
                lastName: account.lastName,
                email: account.email,
                password: account.password,
                deviceToken: tokenStore.read(),
                hasSeenOnboarding: sessionStore.hasSeenOnboarding
            )
        )
    }

    public func signIn(email: String, password: String) async throws -> AuthenticatedSession {
        try await openSession(
            path: "/v1/auth/login",
            body: SignInBody(
                email: email,
                password: password,
                deviceToken: tokenStore.read(),
                hasSeenOnboarding: sessionStore.hasSeenOnboarding
            )
        )
    }

    public func signOut() async {
        // Le serveur d'abord, le trousseau ensuite : si l'appel échoue, la
        // session locale part quand même. Rester connecté malgré une demande
        // explicite de déconnexion serait le pire des deux comportements.
        if let request = try? makeRequest(method: "POST", path: "/v1/auth/logout") {
            _ = try? await performRaw(request)
        }
        sessionStore.clearSession()
    }

    public func signIn(
        with provider: SocialProvider,
        credential: String
    ) async throws -> SocialSignInOutcome {
        let response: SocialSignInResponse = try await send(
            method: "POST",
            path: "/v1/auth/social/\(provider.rawValue)",
            encodableBody: SocialSignInBody(
                credential: credential,
                deviceToken: tokenStore.read(),
                hasSeenOnboarding: sessionStore.hasSeenOnboarding
            ),
            authenticated: false
        )

        switch response.status {
        case .signedIn:
            guard let userId = response.userId, let token = response.sessionToken else {
                throw APIError.server(
                    statusCode: 200,
                    code: "malformed_session",
                    message: "Réponse de connexion incomplète."
                )
            }
            let session = AuthenticatedSession(
                userId: userId,
                sessionToken: token,
                hasSeenOnboarding: response.hasSeenOnboarding ?? false
            )
            adopt(session)
            return .signedIn(session)

        case .profileRequired:
            guard let socialToken = response.socialToken else {
                throw APIError.server(
                    statusCode: 200,
                    code: "malformed_session",
                    message: "Réponse de connexion incomplète."
                )
            }
            return .profileRequired(
                SocialProfileDraft(
                    socialToken: socialToken,
                    provider: response.provider ?? provider,
                    firstName: response.firstName,
                    lastName: response.lastName,
                    email: response.email
                )
            )
        }
    }

    public func completeSocialProfile(
        _ profile: CompletedSocialProfile
    ) async throws -> AuthenticatedSession {
        try await openSession(
            path: "/v1/auth/social/complete",
            body: SocialCompleteBody(
                socialToken: profile.socialToken,
                firstName: profile.firstName,
                lastName: profile.lastName,
                email: profile.email,
                deviceToken: tokenStore.read(),
                hasSeenOnboarding: sessionStore.hasSeenOnboarding
            )
        )
    }

    public func requestPasswordReset(email: String) async throws {
        struct Response: Decodable { let message: String }
        let _: Response = try await send(
            method: "POST",
            path: "/v1/auth/forgot-password",
            encodableBody: ForgotPasswordBody(email: email),
            authenticated: false
        )
    }

    public func resetPassword(token: String, newPassword: String) async throws {
        struct Response: Decodable { let message: String }
        let _: Response = try await send(
            method: "POST",
            path: "/v1/auth/reset-password",
            encodableBody: ResetPasswordBody(token: token, newPassword: newPassword),
            authenticated: false
        )
    }

    /// Ouvre une session et la mémorise. Les quatre routes qui en ouvrent une
    /// renvoient exactement le même corps.
    private func openSession<Body: Encodable>(
        path: String,
        body: Body
    ) async throws -> AuthenticatedSession {
        let session: AuthenticatedSession = try await send(
            method: "POST",
            path: path,
            encodableBody: body,
            authenticated: false
        )
        adopt(session)
        return session
    }

    /// À partir d'ici, toutes les requêtes `/v1` parlent au nom du compte.
    private func adopt(_ session: AuthenticatedSession) {
        sessionStore.saveSession(token: session.sessionToken)
        if session.hasSeenOnboarding { sessionStore.markOnboardingSeen() }
    }

    // MARK: - Carnets

    public func memos() async throws -> [MemoSummary] {
        struct Response: Decodable { let memos: [MemoSummary] }
        let response: Response = try await send(method: "GET", path: "/v1/memos")
        return response.memos
    }

    public func createMemo(_ memo: NewMemo) async throws -> Memo {
        try await send(method: "POST", path: "/v1/memos", encodableBody: memo)
    }

    public func memo(id: String) async throws -> MemoDetail {
        try await send(method: "GET", path: "/v1/memos/\(id)")
    }

    public func deleteMemo(id: String) async throws {
        try await sendIgnoringResponse(method: "DELETE", path: "/v1/memos/\(id)")
    }

    // MARK: - Souvenirs

    public func addTextEntry(memoId: String, entry: NewTextEntry) async throws -> Entry {
        try await send(
            method: "POST",
            path: "/v1/memos/\(memoId)/entries",
            encodableBody: entry
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
        try await uploadMedia(
            memoId: memoId,
            data: data,
            filename: filename,
            mimeType: mimeType,
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
        try await uploadMedia(
            memoId: memoId,
            data: data,
            filename: filename,
            mimeType: mimeType,
            capturedAt: capturedAt,
            placeLabel: placeLabel
        )
    }

    private func uploadMedia(
        memoId: String,
        data: Data,
        filename: String,
        mimeType: String,
        capturedAt: Date,
        placeLabel: String?
    ) async throws -> Entry {
        var form = MultipartFormData()
        form.addField(name: "capturedAt", value: ISO8601DateFormatter.memoBookString(from: capturedAt))
        if let placeLabel {
            form.addField(name: "placeLabel", value: placeLabel)
        }
        form.addFile(name: "file", filename: filename, mimeType: mimeType, data: data)

        let contentType = form.contentType
        var request = try makeRequest(method: "POST", path: "/v1/memos/\(memoId)/entries")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finalized()

        return try await perform(request)
    }

    public func entry(id: String) async throws -> Entry {
        try await send(method: "GET", path: "/v1/entries/\(id)")
    }

    public func updateEntry(id: String, edit: EntryEdit) async throws -> Entry {
        try await send(method: "PATCH", path: "/v1/entries/\(id)", encodableBody: edit)
    }

    public func retryRedaction(entryId: String) async throws -> Entry {
        try await send(method: "POST", path: "/v1/entries/\(entryId)/redaction")
    }

    // MARK: - Génération

    public func startRender(memoId: String) async throws -> Render {
        try await send(method: "POST", path: "/v1/memos/\(memoId)/renders")
    }

    public func render(id: String) async throws -> Render {
        try await send(method: "GET", path: "/v1/renders/\(id)")
    }

    // MARK: - Impression

    public func createPrintOrder(memoId: String, order: NewPrintOrder) async throws -> PrintOrder {
        try await send(
            method: "POST",
            path: "/v1/memos/\(memoId)/orders",
            encodableBody: order
        )
    }

    public func printOrders(memoId: String) async throws -> [PrintOrder] {
        struct Response: Decodable { let orders: [PrintOrder] }
        let response: Response = try await send(method: "GET", path: "/v1/memos/\(memoId)/orders")
        return response.orders
    }

    // MARK: - Transport

    private func makeRequest(
        method: String,
        path: String,
        authenticated: Bool = true
    ) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: configuration.baseURL) else {
            throw APIError.server(statusCode: 0, code: nil, message: "Chemin d'API invalide : \(path)")
        }

        var request = URLRequest(url: url, timeoutInterval: configuration.timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Le jeton de session prime : dès qu'un compte est connecté, c'est lui
        // qui parle. Sans session, l'appareil anonyme prend le relais — c'est ce
        // qui laisse raconter une étape avant de s'être inscrit.
        if authenticated {
            guard let token = sessionStore.sessionToken ?? tokenStore.read() else {
                throw APIError.notAuthenticated
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func send<Response: Decodable>(
        method: String,
        path: String,
        body: [String: String]? = nil,
        authenticated: Bool = true
    ) async throws -> Response {
        var request = try makeRequest(method: method, path: path, authenticated: authenticated)

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        return try await perform(request)
    }

    private func send<Body: Encodable, Response: Decodable>(
        method: String,
        path: String,
        encodableBody: Body,
        authenticated: Bool = true
    ) async throws -> Response {
        var request = try makeRequest(
            method: method,
            path: path,
            authenticated: authenticated
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(encodableBody)
        return try await perform(request)
    }

    private func sendIgnoringResponse(method: String, path: String) async throws {
        let request = try makeRequest(method: method, path: path)
        _ = try await performRaw(request)
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data = try await performRaw(request)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// Exécute la requête et traduit tout ce qui n'est pas un 2xx en `APIError`.
    private func performRaw(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(statusCode: 0, code: nil, message: "Réponse non HTTP.")
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = try? JSONDecoder().decode(APIErrorBody.self, from: data)

            // Un jeton refusé ne vaut plus rien : session expirée côté serveur,
            // ou appareil supprimé. On repart d'une identité propre au prochain
            // lancement plutôt que de rejouer un 401 à chaque écran.
            if http.statusCode == 401 {
                if sessionStore.sessionToken != nil {
                    sessionStore.clearSession()
                } else {
                    tokenStore.clear()
                }
            }

            throw APIError.server(
                statusCode: http.statusCode,
                code: body?.error,
                message: body?.message ?? "Le serveur a répondu \(http.statusCode)."
            )
        }

        return data
    }
}


// MARK: - Corps de requête

/// Le jeton de l'appareil anonyme accompagne chaque ouverture de session : c'est
/// lui qui fait suivre les carnets déjà racontés dans le compte.
private struct SignUpBody: Encodable {
    let firstName: String
    let lastName: String
    let email: String
    let password: String
    let deviceToken: String?
    let hasSeenOnboarding: Bool
}

private struct SignInBody: Encodable {
    let email: String
    let password: String
    let deviceToken: String?
    let hasSeenOnboarding: Bool
}

private struct SocialSignInBody: Encodable {
    let credential: String
    let deviceToken: String?
    let hasSeenOnboarding: Bool
}

private struct SocialCompleteBody: Encodable {
    let socialToken: String
    let firstName: String
    let lastName: String
    let email: String
    let deviceToken: String?
    let hasSeenOnboarding: Bool
}

private struct ForgotPasswordBody: Encodable {
    let email: String
}

private struct ResetPasswordBody: Encodable {
    let token: String
    let newPassword: String
}

/// `POST /v1/auth/social/:provider` renvoie l'un ou l'autre : une session
/// ouverte, ou le profil à compléter. Un seul corps, discriminé par `status`.
private struct SocialSignInResponse: Decodable {
    enum Status: String, Decodable {
        case signedIn = "signed_in"
        case profileRequired = "profile_required"
    }

    let status: Status
    let userId: String?
    let sessionToken: String?
    let hasSeenOnboarding: Bool?
    let socialToken: String?
    let provider: SocialProvider?
    let firstName: String?
    let lastName: String?
    let email: String?
}
