import Foundation
import MemoBookCore

/// Implémentation HTTP du contrat `MemoBookAPI`.
public actor MemoBookAPIClient: MemoBookAPI {
    private let configuration: APIConfiguration
    private let session: URLSession
    private let tokenStore: any TokenStore
    private let decoder = JSONDecoder.memoBook
    private let encoder = JSONEncoder.memoBook

    /// Enregistrement en cours, partagé : deux écrans qui démarrent en même
    /// temps ne doivent pas créer deux appareils.
    private var registrationTask: Task<Void, any Error>?

    public init(
        configuration: APIConfiguration = .localDevelopment,
        session: URLSession = .shared,
        tokenStore: any TokenStore = KeychainTokenStore()
    ) {
        self.configuration = configuration
        self.session = session
        self.tokenStore = tokenStore
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

        if authenticated {
            guard let token = tokenStore.read() else { throw APIError.notAuthenticated }
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
        encodableBody: Body
    ) async throws -> Response {
        var request = try makeRequest(method: method, path: path)
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

            // Un token refusé signifie que l'appareil a été supprimé côté
            // serveur : on repart d'une identité propre au prochain lancement.
            if http.statusCode == 401 {
                tokenStore.clear()
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
