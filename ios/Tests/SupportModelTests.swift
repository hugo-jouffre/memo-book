import MemoBookCore
@testable import MemoBookFeature
import MemoBookNetworking
import XCTest

/// T226 (Hugo, 06/10/2026) : « Envoyer » attendait 600 ms puis disait
/// « envoyé », et rien ne partait. Le message part désormais au serveur, et
/// « envoyé » ne se dit qu'après sa réponse ; les votes aussi.
@MainActor
final class SupportModelTests: XCTestCase {
    /// Ce que le double du serveur a reçu.
    private actor Inbox {
        var messages: [SupportMessage] = []
        var votes: [(String, Bool)] = []
        func receive(_ message: SupportMessage) { messages.append(message) }
        func receive(vote questionId: String, _ isHelpful: Bool) { votes.append((questionId, isHelpful)) }
    }

    private func backend(
        inbox: Inbox,
        failure: (any Error & Sendable)? = nil,
        served: [FaqVote] = []
    ) -> SupportBackend {
        SupportBackend(
            send: { message in
                if let failure { throw failure }
                await inbox.receive(message)
            },
            vote: { questionId, isHelpful in
                if let failure { throw failure }
                await inbox.receive(vote: questionId, isHelpful)
            },
            loadVotes: { served }
        )
    }

    func testTheMessageReachesTheServerBeforeItIsSent() async {
        let inbox = Inbox()
        let model = SupportModel()
        await model.connect(backend(inbox: inbox))

        await model.send("  Bonjour  ", source: .foundersNote, topicId: "faq.aide.suggestion", tripId: "trip")

        XCTAssertEqual(model.sendState, .sent)
        let received = await inbox.messages
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.message, "Bonjour")
        XCTAssertEqual(received.first?.source, .foundersNote)
        XCTAssertEqual(received.first?.topicId, "faq.aide.suggestion")
        XCTAssertEqual(received.first?.tripId, "trip")
        XCTAssertNotNil(received.first?.diagnostics)
    }

    func testOfflineSaysSoAndKeepsTheForm() async {
        let model = SupportModel()
        await model.connect(
            backend(inbox: Inbox(), failure: APIError.transport(URLError(.notConnectedToInternet), url: nil))
        )

        await model.send("Bonjour")

        XCTAssertEqual(model.sendState, .failed(SupportCopy.Contact.sendOffline))
    }

    func testTooManyMessagesSaysSo() async {
        let model = SupportModel()
        await model.connect(
            backend(
                inbox: Inbox(),
                failure: APIError.server(statusCode: 429, code: "support_rate_limited", message: "Trop")
            )
        )

        await model.send("Bonjour")

        XCTAssertEqual(model.sendState, .failed(SupportCopy.Contact.sendRateLimited))
    }

    func testAVoteIsThankedOnceReceived() async throws {
        let inbox = Inbox()
        let model = SupportModel()
        await model.connect(backend(inbox: inbox))
        let entry = try XCTUnwrap(Faq.entry(id: "faq.carnet.pages"))

        await model.vote(true, on: entry)

        XCTAssertEqual(model.votes[entry.id], true)
        let votes = await inbox.votes
        XCTAssertEqual(votes.map(\.0), [entry.id])
    }

    func testAVoteThatDidNotLeaveKeepsTheThumbs() async throws {
        let model = SupportModel()
        await model.connect(
            backend(inbox: Inbox(), failure: APIError.transport(URLError(.notConnectedToInternet), url: nil))
        )
        let entry = try XCTUnwrap(Faq.entry(id: "faq.carnet.pages"))

        await model.vote(false, on: entry)

        XCTAssertNil(model.votes[entry.id])
        XCTAssertEqual(model.voteFailure?.questionId, entry.id)
        XCTAssertEqual(model.voteFailure?.message, SupportCopy.Answer.voteOffline)
    }

    /// Les votes déjà donnés reviennent du serveur ; ceux d'un autre compte
    /// s'effacent.
    func testTheVotesFollowTheAccount() async {
        let model = SupportModel()
        await model.connect(
            backend(inbox: Inbox(), served: [FaqVote(questionId: "faq.carnet.pages", isHelpful: true)])
        )
        XCTAssertEqual(model.votes["faq.carnet.pages"], true)

        await model.connect(backend(inbox: Inbox()))
        XCTAssertTrue(model.votes.isEmpty)
    }
}
