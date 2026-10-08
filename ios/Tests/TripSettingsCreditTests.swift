import MemoBookCore
@testable import MemoBookFeature
import XCTest

/// Le crédit du jour des réglages du voyage : **seul l'envoyé compte** (Hugo,
/// 06/10/2026). Le crédit servi, moins ce qui a été envoyé et attend la file —
/// comme la conversation et l'accueil —, et rien d'autre.
@MainActor
final class TripSettingsCreditTests: XCTestCase {
    private func settings(usedMs: Int, isUnlimited: Bool = false) -> TripSettings {
        var settings = TripSettings.fixture
        settings.dailyCredit = DailyCredit(isUnlimited: isUnlimited, usedMs: usedMs)
        return settings
    }

    private func voice(seconds: TimeInterval, id: String = UUID().uuidString) -> OutgoingTurn {
        OutgoingTurn(
            id: id,
            body: .voice(
                RecordedTurnAudio(
                    data: Data(),
                    filename: "vocal.m4a",
                    mimeType: "audio/mp4",
                    capturedAt: .now,
                    durationSeconds: seconds,
                    levels: []
                )
            )
        )
    }

    /// Rien en file : le crédit servi, tel quel — un vocal en cours ou en
    /// pause n'est envoyé nulle part, il n'existe pas ici.
    func testNothingSentNothingCounted() async {
        let model = TripSettingsModel(
            tripId: "rome",
            source: { _ in self.settings(usedMs: 60_000) },
            waitingTurns: { [] }
        )
        await model.load()
        XCTAssertEqual(model.dailyCredit?.remainingMs, 240_000)
    }

    /// Un vocal envoyé hors ligne compte, comme dans la conversation.
    func testASentTurnWaitingForTheNetworkCounts() async {
        let turn = voice(seconds: 90)
        let model = TripSettingsModel(
            tripId: "rome",
            source: { _ in self.settings(usedMs: 60_000) },
            waitingTurns: { [turn] }
        )
        await model.load()
        XCTAssertEqual(model.dailyCredit?.remainingMs, 150_000)
    }

    /// Un tour retenu pour demain prendra le crédit de demain.
    func testATurnHeldForTomorrowDoesNotCountToday() async {
        let held = OutgoingTurn(body: .text("Hier soir"), waitingForCreditUntil: .now.addingTimeInterval(3_600))
        let model = TripSettingsModel(
            tripId: "rome",
            source: { _ in self.settings(usedMs: 60_000) },
            waitingTurns: { [held] }
        )
        await model.load()
        XCTAssertEqual(model.dailyCredit?.remainingMs, 240_000)
    }
}
