import Foundation
import MemoBookCore
import MemoBookNetworking
import XCTest

@testable import MemoBookFeature

/// **Un serveur qui travaille n'est pas une panne de réseau** (T318, Hugo,
/// 08/11/2026 — « “Hors ligne” s'affiche après un vocal alors que le réseau va
/// bien ; le serveur est simplement en train de travailler »).
///
/// Les deux situations se ressemblent de l'intérieur : l'appel n'aboutit pas,
/// le tour retombe dans la file. Elles ne se disent pourtant pas pareil —
/// l'une se répare en cherchant du réseau, l'autre en attendant.
@MainActor
final class ServerIsWorkingTests: XCTestCase {
    // MARK: Ce que l'erreur dit d'elle-même

    func testATimeoutIsNotALostNetwork() {
        let url = URL(string: "https://api.memo-book.com/v1/trips/1/chat")!

        XCTAssertTrue(APIError.transport(URLError(.timedOut), url: url).isTimeout)
        XCTAssertFalse(
            APIError.transport(URLError(.notConnectedToInternet), url: url).isTimeout,
            "Là, c'est vraiment le wifi."
        )
        XCTAssertFalse(APIError.server(statusCode: 500, code: nil, message: "Oups").isTimeout)
        // Les deux restent des pannes de transport : la file les garde pareil,
        // c'est la **phrase** qui change.
        XCTAssertTrue(APIError.transport(URLError(.timedOut), url: url).isTransport)
    }

    // MARK: Ce que l'écran en dit

    private func thread() -> ChatThread {
        ChatThread(
            id: "trip",
            title: "Rome",
            context: ChatContext(tripId: "trip", stepId: nil),
            messages: [],
            suggestions: [],
            now: .now
        )
    }

    /// Un transport dont le tour part toujours dans la file, et dont on pilote
    /// le moniteur réseau.
    private func model(isOnline: @escaping @Sendable () async -> Bool) -> ChatModel {
        let thread = thread()
        var transport = ChatTransport(
            load: { thread },
            poll: { _ in ChatThreadUpdate(messages: [], suggestions: [], turn: .idle, now: .now) },
            send: { _ in .queued },
            editTranscript: { _, _ in throw CancellationError() },
            media: { _ in Data() }
        )
        transport.isOnline = isOnline
        return ChatModel(transport: transport)
    }

    private func until(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("La condition n'est jamais arrivée.")
    }

    /// Le cas de Hugo : le vocal retombe dans la file parce que le serveur n'a
    /// pas répondu à temps, et le réseau va très bien.
    func testAQueuedTurnWithNetworkBlamesTheServer() async throws {
        let model = model(isOnline: { true })
        await model.load()

        model.draft = "On a marché jusqu'au Trastevere"
        model.sendDraft()

        try await until { model.showsQueuedNotice }
        XCTAssertTrue(model.networkIsUp)
        XCTAssertEqual(model.queuedNotice, ChatCopy.queuedWhileServerWorks)
    }

    /// Et sans réseau, la phrase d'avant : celle-là était juste.
    func testAQueuedTurnWithoutNetworkStillSaysOffline() async throws {
        let model = model(isOnline: { false })
        await model.load()

        model.draft = "On a marché jusqu'au Trastevere"
        model.sendDraft()

        try await until { model.showsQueuedNotice }
        XCTAssertFalse(model.networkIsUp)
        XCTAssertEqual(model.queuedNotice, ChatCopy.queuedOffline)
    }

    /// **C'est l'état présent qui parle**, et non la raison du départ en
    /// file : le réseau revenu pendant que le tour attend change la phrase.
    func testThePhraseFollowsTheNetworkComingBack() async throws {
        let up = Online()
        let model = model(isOnline: { await up.value })
        await model.load()
        model.draft = "On a marché jusqu'au Trastevere"
        model.sendDraft()
        try await until { model.showsQueuedNotice }
        XCTAssertEqual(model.queuedNotice, ChatCopy.queuedOffline)

        await up.turnOn()
        await model.refreshNetworkState()

        XCTAssertEqual(model.queuedNotice, ChatCopy.queuedWhileServerWorks)
    }

    private actor Online {
        private(set) var value = false
        func turnOn() { value = true }
    }

    /// Le fil ouvert sans le serveur dit la même chose, en tête : ce n'est pas
    /// le réseau quand le réseau est là.
    func testTheLocalThreadDoesNotClaimToBeOffline() async {
        let thread = thread()
        var transport = ChatTransport(
            load: { throw APIError.transport(URLError(.timedOut), url: nil) },
            poll: { _ in ChatThreadUpdate(messages: [], suggestions: [], turn: .idle, now: .now) },
            send: { _ in .queued },
            editTranscript: { _, _ in throw CancellationError() },
            media: { _ in Data() },
            offlineThread: { _ in thread }
        )
        transport.isOnline = { true }
        let model = ChatModel(transport: transport)

        await model.load()

        XCTAssertTrue(model.isOffline, "Le fil montré est bien le fil local.")
        XCTAssertEqual(model.threadNotice, ChatCopy.threadWhileServerWorks)
    }

    /// Sans réseau, le fil local garde la phrase d'origine.
    func testTheLocalThreadStillSaysOfflineWithoutNetwork() async {
        let thread = thread()
        var transport = ChatTransport(
            load: { throw APIError.transport(URLError(.notConnectedToInternet), url: nil) },
            poll: { _ in ChatThreadUpdate(messages: [], suggestions: [], turn: .idle, now: .now) },
            send: { _ in .queued },
            editTranscript: { _, _ in throw CancellationError() },
            media: { _ in Data() },
            offlineThread: { _ in thread }
        )
        transport.isOnline = { false }
        let model = ChatModel(transport: transport)

        await model.load()

        XCTAssertTrue(model.isOffline)
        XCTAssertEqual(model.threadNotice, ChatCopy.offline)
    }
}
