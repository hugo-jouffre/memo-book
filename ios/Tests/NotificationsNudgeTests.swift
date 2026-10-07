import MemoBookCore
@testable import MemoBookFeature
import UserNotifications
import XCTest

/// T246 : la bulle « Suggestions » des notifications — à qui l'a montrée, et
/// ce qu'elle propose.
@MainActor
final class NotificationsNudgeTests: XCTestCase {
    func testShownOnlyAfterTheStepAndWithoutAuthorization() {
        // Jamais traversé l'étape — un co-voyageur venu par un code : rien.
        XCTAssertFalse(NotificationsNudge.isShown(hasPassedStep: false, authorization: .notDetermined, state: .pending))
        // Passée sans réponse, ou refusée : la bulle.
        XCTAssertTrue(NotificationsNudge.isShown(hasPassedStep: true, authorization: .notDetermined, state: .pending))
        XCTAssertTrue(NotificationsNudge.isShown(hasPassedStep: true, authorization: .denied, state: .pending))
        // Autorisé : elle s'en va.
        XCTAssertFalse(NotificationsNudge.isShown(hasPassedStep: true, authorization: .authorized, state: .pending))
        XCTAssertFalse(NotificationsNudge.isShown(hasPassedStep: true, authorization: .provisional, state: .pending))
        // Ignorée : elle se tait.
        XCTAssertFalse(NotificationsNudge.isShown(hasPassedStep: true, authorization: .denied, state: .dismissed))
    }

    func testRefusedItSendsToTheSettings() {
        XCTAssertEqual(NotificationsNudge.callToAction(isDenied: true).label, "Activer dans les Réglages")
        XCTAssertEqual(NotificationsNudge.callToAction(isDenied: false).label, "Activer les notifications")
        XCTAssertEqual(NotificationsNudge.callToAction(isDenied: false).kind, .enableNotifications)
    }

    func testTheStepIsRememberedWhetherChosenOrSkipped() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "NotificationsNudgeTests"))
        defaults.removePersistentDomain(forName: "NotificationsNudgeTests")
        XCTAssertFalse(NotificationsNudge.hasPassedStep(defaults: defaults))

        let model = TripCreationModel(notificationsStepPassed: { NotificationsNudge.markStepPassed(defaults: defaults) })
        model.draft.title = "Lisbonne"
        await model.validate()
        model.draft.startDate = .now
        await model.validate()
        XCTAssertFalse(NotificationsNudge.hasPassedStep(defaults: defaults))

        await model.skip()
        XCTAssertTrue(NotificationsNudge.hasPassedStep(defaults: defaults))
    }
}
