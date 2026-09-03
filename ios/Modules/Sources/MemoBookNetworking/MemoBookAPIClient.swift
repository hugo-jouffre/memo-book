import Foundation
import MemoBookCore

/// Implémentation HTTP du contrat `MemoBookAPI`.
public actor MemoBookAPIClient: MemoBookAPI {
    private let configuration: APIConfiguration
    private let session: URLSession
    private let tokenStore: any TokenStore
    private let sessionStore: any TokenStore
    private let decoder = JSONDecoder.memoBook
    private let encoder = JSONEncoder.memoBook

    /// Qui parle. Les deux identifications cohabitent : les carnets appartiennent
    /// encore à l'appareil, le compte n'a pour l'instant que ses propres routes.
    private enum Credential {
        case none
        case device
        case session
    }

    /// Enregistrement en cours, partagé : deux écrans qui démarrent en même
    /// temps ne doivent pas créer deux appareils.
    private var registrationTask: Task<Void, any Error>?

    public init(
        configuration: APIConfiguration = .localDevelopment,
        session: URLSession = .shared,
        tokenStore: any TokenStore = KeychainTokenStore(),
        sessionStore: any TokenStore = KeychainTokenStore(account: "session-token")
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
                credential: .none
            )
            tokenStore.write(registration.token)
        }

        registrationTask = task
        defer { registrationTask = nil }
        try await task.value
    }

    // MARK: - Compte

    public func hasStoredSession() -> Bool {
        sessionStore.read() != nil
    }

    public func signUp(
        email: String,
        password: String,
        firstName: String?,
        lastName: String?
    ) async throws -> AuthSession {
        var body = ["email": email, "password": password]
        // Champs facultatifs : les envoyer vides ferait échouer la validation
        // du serveur, qui exige au moins un caractère quand ils sont présents.
        if let firstName, !firstName.isEmpty { body["firstName"] = firstName }
        if let lastName, !lastName.isEmpty { body["lastName"] = lastName }
        return try await openSession(path: "/v1/auth/signup", body: body)
    }

    public func signIn(email: String, password: String) async throws -> AuthSession {
        try await openSession(
            path: "/v1/auth/signin",
            body: ["email": email, "password": password]
        )
    }

    public func signIn(with credential: SocialSignIn) async throws -> AuthSession {
        var body = ["identityToken": credential.identityToken]
        if let nonce = credential.nonce { body["nonce"] = nonce }
        if let firstName = credential.firstName, !firstName.isEmpty {
            body["firstName"] = firstName
        }
        if let lastName = credential.lastName, !lastName.isEmpty {
            body["lastName"] = lastName
        }
        return try await openSession(
            path: "/v1/auth/\(credential.provider.rawValue)",
            body: body
        )
    }

    public func currentAccount() async throws -> Account {
        struct Response: Decodable { let account: Account }
        let response: Response = try await send(
            method: "GET",
            path: "/v1/auth/me",
            credential: .session
        )
        return response.account
    }

    public func signOut() async {
        // Le trousseau est vidé quoi qu'il arrive : quelqu'un qui se déconnecte
        // dans un train sans réseau ne doit pas rester connecté sur son écran.
        // La session côté serveur expirera d'elle-même.
        defer { sessionStore.clear() }
        try? await sendIgnoringResponse(
            method: "POST",
            path: "/v1/auth/signout",
            credential: .session
        )
    }

    private func openSession(path: String, body: [String: String]) async throws -> AuthSession {
        let session: AuthSession = try await send(
            method: "POST",
            path: path,
            body: body,
            credential: .none
        )
        sessionStore.write(session.token)
        return session
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

        return try await perform(request, credential: .device)
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

    /// Le magasin qui porte un type de jeton donné, ou `nil` pour un appel qui
    /// n'en présente aucun.
    private func store(for credential: Credential) -> (any TokenStore)? {
        switch credential {
        case .none: nil
        case .device: tokenStore
        case .session: sessionStore
        }
    }

    private func makeRequest(
        method: String,
        path: String,
        credential: Credential = .device
    ) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: configuration.baseURL) else {
            throw APIError.server(statusCode: 0, code: nil, message: "Chemin d'API invalide : \(path)")
        }

        var request = URLRequest(url: url, timeoutInterval: configuration.timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let store = store(for: credential) {
            guard let token = store.read() else { throw APIError.notAuthenticated }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func send<Response: Decodable>(
        method: String,
        path: String,
        body: [String: String]? = nil,
        credential: Credential = .device
    ) async throws -> Response {
        var request = try makeRequest(method: method, path: path, credential: credential)

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        return try await perform(request, credential: credential)
    }

    private func send<Body: Encodable, Response: Decodable>(
        method: String,
        path: String,
        encodableBody: Body
    ) async throws -> Response {
        var request = try makeRequest(method: method, path: path)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(encodableBody)
        return try await perform(request, credential: .device)
    }

    private func sendIgnoringResponse(
        method: String,
        path: String,
        credential: Credential = .device
    ) async throws {
        let request = try makeRequest(method: method, path: path, credential: credential)
        _ = try await performRaw(request, credential: credential)
    }

    private func perform<Response: Decodable>(
        _ request: URLRequest,
        credential: Credential
    ) async throws -> Response {
        let data = try await performRaw(request, credential: credential)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// Exécute la requête et traduit tout ce qui n'est pas un 2xx en `APIError`.
    private func performRaw(
        _ request: URLRequest,
        credential: Credential
    ) async throws -> Data {
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

            // Un jeton refusé ne vaudra pas mieux au prochain essai : on efface
            // **celui qui a été présenté**, et lui seul. Effacer le jeton
            // d'appareil parce qu'une session a expiré ferait perdre les
            // carnets, qui lui appartiennent encore.
            if http.statusCode == 401 {
                store(for: credential)?.clear()
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
