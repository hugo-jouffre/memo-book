import MemoBookCore
import XCTest

@testable import MemoBookNetworking

/// Intercepte les requêtes pour tester le client sans serveur.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        // `httpBody` est vidé quand URLSession passe par un flux : on le relit.
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map(Self.readAll)

        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

final class APIClientTests: XCTestCase {
    private var session: URLSession!
    private let baseURL = URL(string: "https://api.test")!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
        StubURLProtocol.handler = nil
        StubURLProtocol.lastRequest = nil
        StubURLProtocol.lastBody = nil
    }

    /// Un client identifié par une **session de compte** : c'est ce que
    /// présentent toutes les routes qui touchent à quelque chose de quelqu'un.
    /// Le jeton d'appareil ne sert plus qu'à l'enregistrement.
    private func makeClient(
        sessionToken: String? = "jeton-de-session",
        deviceToken: String? = "jeton-d-appareil"
    ) -> MemoBookAPIClient {
        MemoBookAPIClient(
            configuration: APIConfiguration(baseURL: baseURL),
            session: session,
            tokenStore: InMemoryTokenStore(token: deviceToken),
            sessionStore: InMemoryTokenStore(token: sessionToken)
        )
    }

    private func respond(status: Int, json: String) {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }
    }

    // MARK: - L'adresse de secours

    /// Compte les requêtes par hôte, depuis la fermeture `@Sendable` du stub.
    private final class HostTally: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [String: Int] = [:]

        func record(_ host: String?) {
            lock.withLock { counts[host ?? "?", default: 0] += 1 }
        }

        func count(_ host: String) -> Int {
            lock.withLock { counts[host] ?? 0 }
        }
    }

    private func makeClientWithFallback() -> MemoBookAPIClient {
        MemoBookAPIClient(
            configuration: APIConfiguration(
                baseURL: URL(string: "http://localhost:3000")!,
                fallbackBaseURL: URL(string: "https://api.production.test")!
            ),
            session: session,
            tokenStore: InMemoryTokenStore(token: "jeton-d-appareil"),
            sessionStore: InMemoryTokenStore(token: "jeton-de-session")
        )
    }

    private static let accountJSON =
        #"{"account":{"id":"a1","email":"demo@memo-book.com","firstName":"Camille","lastName":null,"createdAt":"2026-09-01T10:00:00.000Z"}}"#

    /// Rien n'écoute sur `localhost` : le client bascule sur le secours, rejoue
    /// la requête, et **y reste** pour la suite de la session.
    func testFallsBackWhenLocalhostRefusesAndStaysThere() async throws {
        let client = makeClientWithFallback()
        let tally = HostTally()

        StubURLProtocol.handler = { request in
            let host = request.url?.host()
            tally.record(host)
            guard host != "localhost" else { throw URLError(.cannotConnectToHost) }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(Self.accountJSON.utf8))
        }

        let account = try await client.currentAccount()
        XCTAssertEqual(account.id, "a1")
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.host(), "api.production.test")
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.path(), "/v1/auth/me")
        // Le jeton de session voyage avec la requête rejouée.
        XCTAssertEqual(
            StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer jeton-de-session"
        )

        _ = try await client.currentAccount()
        XCTAssertEqual(tally.count("localhost"), 1, "une seule tentative sur localhost par session")
        XCTAssertEqual(tally.count("api.production.test"), 2)
    }

    /// Un délai dépassé n'est pas une porte close : on ne bascule pas.
    func testTimeoutDoesNotFallBack() async {
        let client = makeClientWithFallback()
        let tally = HostTally()

        StubURLProtocol.handler = { request in
            tally.record(request.url?.host())
            throw URLError(.timedOut)
        }

        do {
            _ = try await client.currentAccount()
            XCTFail("L'appel devait échouer.")
        } catch let error as APIError {
            XCTAssertTrue(error.isTransport)
        } catch {
            XCTFail("Erreur inattendue : \(error)")
        }
        XCTAssertEqual(tally.count("localhost"), 1)
        XCTAssertEqual(tally.count("api.production.test"), 0)
    }

    /// Sans secours configuré — un appareil, la production —, une porte close
    /// reste une erreur de transport, comme avant.
    func testNoFallbackWithoutFallbackAddress() async {
        let client = makeClient()
        StubURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }

        do {
            _ = try await client.currentAccount()
            XCTFail("L'appel devait échouer.")
        } catch let error as APIError {
            XCTAssertTrue(error.isTransport)
        } catch {
            XCTFail("Erreur inattendue : \(error)")
        }
    }

    func testRegisterDeviceStoresToken() async throws {
        let store = InMemoryTokenStore()
        let client = MemoBookAPIClient(
            configuration: APIConfiguration(baseURL: baseURL),
            session: session,
            tokenStore: store,
            sessionStore: InMemoryTokenStore()
        )

        respond(status: 201, json: #"{"deviceId":"d1","token":"secret"}"#)
        try await client.ensureDeviceRegistered()

        XCTAssertEqual(store.read(), "secret")
    }

    func testRegisteredDeviceIsNotRegisteredTwice() async throws {
        let client = makeClient(deviceToken: "déjà-là")
        StubURLProtocol.handler = { _ in
            XCTFail("Aucune requête ne devait partir : l'appareil a déjà un token.")
            throw URLError(.badServerResponse)
        }

        try await client.ensureDeviceRegistered()
    }

    /// Les carnets appartiennent à un compte : c'est le jeton de session qui
    /// part, jamais celui de l'appareil.
    func testAuthorizationHeaderCarriesTheSessionToken() async throws {
        let client = makeClient(sessionToken: "ma-session", deviceToken: "mon-appareil")
        respond(status: 200, json: #"{"memos":[]}"#)

        _ = try await client.memos()

        XCTAssertEqual(
            StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer ma-session"
        )
    }

    func testMissingTokenFailsBeforeAnyRequest() async {
        let client = makeClient(sessionToken: nil)

        do {
            _ = try await client.memos()
            XCTFail("Une requête sans token doit échouer.")
        } catch let error as APIError {
            guard case .notAuthenticated = error else {
                return XCTFail("Erreur inattendue : \(error)")
            }
        } catch {
            XCTFail("Erreur inattendue : \(error)")
        }
    }

    /// Le back-end renvoie déjà un message en français : il doit arriver
    /// intact jusqu'à l'écran, sans être remplacé par un code HTTP.
    func testServerMessageIsSurfacedToTheUser() async {
        let client = makeClient()
        respond(
            status: 400,
            json: #"{"error":"empty_memo","message":"Ce carnet ne contient encore aucun souvenir."}"#
        )

        do {
            _ = try await client.startRender(memoId: "m1")
            XCTFail("Un 400 doit produire une erreur.")
        } catch let error as APIError {
            XCTAssertEqual(
                error.errorDescription,
                "Ce carnet ne contient encore aucun souvenir."
            )
            XCTAssertFalse(error.isRetryable)
        } catch {
            XCTFail("Erreur inattendue : \(error)")
        }
    }

    func testUnauthorizedClearsStoredToken() async {
        let sessionStore = InMemoryTokenStore(token: "périmé")
        let deviceStore = InMemoryTokenStore(token: "appareil")
        let client = MemoBookAPIClient(
            configuration: APIConfiguration(baseURL: baseURL),
            session: session,
            tokenStore: deviceStore,
            sessionStore: sessionStore
        )
        respond(status: 401, json: #"{"error":"unauthorized","message":"Token invalide."}"#)

        _ = try? await client.memos()

        XCTAssertNil(sessionStore.read(), "Un token refusé doit être oublié.")
        XCTAssertNotNil(
            deviceStore.read(),
            "Seul le jeton présenté est effacé : celui de l'appareil n'a rien à voir avec un 401 de session."
        )
    }

    /// Supprimer son compte vide **les deux** trousseaux : le compte n'existe
    /// plus, et son appareil a disparu avec lui côté serveur.
    func testDeleteAccountClearsBothTokens() async throws {
        let sessionStore = InMemoryTokenStore(token: "ma-session")
        let deviceStore = InMemoryTokenStore(token: "mon-appareil")
        let client = MemoBookAPIClient(
            configuration: APIConfiguration(baseURL: baseURL),
            session: session,
            tokenStore: deviceStore,
            sessionStore: sessionStore
        )
        respond(status: 204, json: "")

        try await client.deleteAccount()

        XCTAssertEqual(StubURLProtocol.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.path, "/v1/accounts/me")
        XCTAssertNil(sessionStore.read())
        XCTAssertNil(deviceStore.read())
    }

    /// « Mot de passe oublié » part **sans** jeton : c'est parce qu'on ne peut
    /// pas entrer qu'on l'appelle. Un client sans aucune session doit donc
    /// pouvoir l'envoyer, et l'adresse voyage dans le corps.
    func testPasswordResetRequestNeedsNoSession() async throws {
        let client = makeClient(sessionToken: nil, deviceToken: nil)
        respond(status: 202, json: "")

        try await client.requestPasswordReset(email: "hugo@memobook.app")

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/auth/password/forgot")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(StubURLProtocol.lastBody))
        XCTAssertEqual(body as? [String: String], ["email": "hugo@memobook.app"])
    }

    /// Le nouveau mot de passe répond comme une connexion : la session rendue
    /// est **gardée**, pour que l'app entre sans rien retaper.
    func testResetPasswordStoresTheNewSession() async throws {
        let sessionStore = InMemoryTokenStore(token: nil)
        let client = MemoBookAPIClient(
            configuration: APIConfiguration(baseURL: baseURL),
            session: session,
            tokenStore: InMemoryTokenStore(token: nil),
            sessionStore: sessionStore
        )
        respond(
            status: 200,
            json: #"{"token":"session-neuve","expiresAt":"2027-01-01T00:00:00.000Z","account":{"id":"a1","email":"hugo@memobook.app","createdAt":"2026-01-01T00:00:00.000Z"}}"#
        )

        let opened = try await client.resetPassword(token: "secret", password: "nouveau2027")

        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.path, "/v1/auth/password/reset")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(StubURLProtocol.lastBody))
        XCTAssertEqual(body as? [String: String], ["token": "secret", "password": "nouveau2027"])
        XCTAssertEqual(opened.account.email, "hugo@memobook.app")
        XCTAssertEqual(sessionStore.read(), "session-neuve")
    }

    func testServerErrorIsRetryable() async {
        let client = makeClient()
        respond(status: 503, json: #"{"error":"unavailable","message":"Service indisponible."}"#)

        do {
            _ = try await client.memos()
            XCTFail("Un 503 doit produire une erreur.")
        } catch let error as APIError {
            XCTAssertTrue(error.isRetryable)
        } catch {
            XCTFail("Erreur inattendue : \(error)")
        }
    }

    func testAudioUploadSendsMultipartWithFileAndCaptureDate() async throws {
        let client = makeClient()
        respond(
            status: 201,
            json: """
                {
                  "id":"e1","memoId":"m1","kind":"audio","status":"pending",
                  "transcript":null,"capturedAt":"2026-08-08T09:00:00.000Z",
                  "placeLabel":"Kyoto","error":null,"media":null,
                  "createdAt":"2026-08-08T09:00:01.000Z"
                }
                """
        )

        let capturedAt = ISO8601DateFormatter.memoBookDate(from: "2026-08-08T09:00:00.000Z")!
        let entry = try await client.uploadAudio(
            memoId: "m1",
            data: Data("son".utf8),
            filename: "memo.m4a",
            mimeType: "audio/mp4",
            capturedAt: capturedAt,
            durationSeconds: 95,
            placeLabel: "Kyoto"
        )

        XCTAssertEqual(entry.status, .pending)
        XCTAssertEqual(entry.kind, .audio)

        let contentType = StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type")
        XCTAssertEqual(contentType?.hasPrefix("multipart/form-data; boundary="), true)

        let body = String(decoding: StubURLProtocol.lastBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains(#"name="file"; filename="memo.m4a""#))
        XCTAssertTrue(body.contains("2026-08-08T09:00:00.000Z"), "La date de capture doit être transmise")
        // La durée part avec le fichier : c'est elle qui décompte les limites
        // de souvenirs, et le serveur ne peut pas la déduire du poids, qui
        // dépend du codec. Arrondie à la seconde.
        XCTAssertTrue(body.contains(#"name="durationSeconds""#), "La durée doit être transmise")
        XCTAssertTrue(body.contains("95"), "La durée doit être transmise arrondie à la seconde")
        XCTAssertTrue(body.contains("Kyoto"))
    }

    func testTextEntryIsSentAsJSON() async throws {
        let client = makeClient()
        respond(
            status: 201,
            json: """
                {
                  "id":"e2","memoId":"m1","kind":"text","status":"ready",
                  "transcript":"Une note","capturedAt":"2026-08-08T09:00:00.000Z",
                  "placeLabel":null,"error":null,"media":null,
                  "createdAt":"2026-08-08T09:00:00.000Z"
                }
                """
        )

        let entry = try await client.addTextEntry(
            memoId: "m1",
            entry: NewTextEntry(transcript: "Une note")
        )

        XCTAssertEqual(entry.transcript, "Une note")
        XCTAssertEqual(
            StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )

        let body = String(decoding: StubURLProtocol.lastBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains(#""kind":"text""#))
    }
}
