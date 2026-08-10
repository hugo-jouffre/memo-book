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
            client?.didFailWithError(URLError(.badServerResponse))
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

    private func makeClient(token: String? = "jeton") -> MemoBookAPIClient {
        MemoBookAPIClient(
            configuration: APIConfiguration(baseURL: baseURL),
            session: session,
            tokenStore: InMemoryTokenStore(token: token)
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

    func testRegisterDeviceStoresToken() async throws {
        let store = InMemoryTokenStore()
        let client = MemoBookAPIClient(
            configuration: APIConfiguration(baseURL: baseURL),
            session: session,
            tokenStore: store
        )

        respond(status: 201, json: #"{"deviceId":"d1","token":"secret"}"#)
        try await client.ensureDeviceRegistered()

        XCTAssertEqual(store.read(), "secret")
    }

    func testRegisteredDeviceIsNotRegisteredTwice() async throws {
        let client = makeClient(token: "déjà-là")
        StubURLProtocol.handler = { _ in
            XCTFail("Aucune requête ne devait partir : l'appareil a déjà un token.")
            throw URLError(.badServerResponse)
        }

        try await client.ensureDeviceRegistered()
    }

    func testAuthorizationHeaderIsSent() async throws {
        let client = makeClient(token: "mon-jeton")
        respond(status: 200, json: #"{"memos":[]}"#)

        _ = try await client.memos()

        XCTAssertEqual(
            StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer mon-jeton"
        )
    }

    func testMissingTokenFailsBeforeAnyRequest() async {
        let client = makeClient(token: nil)

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
        let store = InMemoryTokenStore(token: "périmé")
        let client = MemoBookAPIClient(
            configuration: APIConfiguration(baseURL: baseURL),
            session: session,
            tokenStore: store
        )
        respond(status: 401, json: #"{"error":"unauthorized","message":"Token invalide."}"#)

        _ = try? await client.memos()

        XCTAssertNil(store.read(), "Un token refusé doit être oublié.")
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
            placeLabel: "Kyoto"
        )

        XCTAssertEqual(entry.status, .pending)
        XCTAssertEqual(entry.kind, .audio)

        let contentType = StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type")
        XCTAssertEqual(contentType?.hasPrefix("multipart/form-data; boundary="), true)

        let body = String(decoding: StubURLProtocol.lastBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains(#"name="file"; filename="memo.m4a""#))
        XCTAssertTrue(body.contains("2026-08-08T09:00:00.000Z"), "La date de capture doit être transmise")
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
