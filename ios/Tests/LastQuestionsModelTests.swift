import MemoBookCore
@testable import MemoBookFeature
import MemoBookNetworking
import XCTest

/// Les « Dernières questions » : qui les voit, ce que « Valider » attend, ce
/// qui part au profil, et l'accueil qui suit. Sans simulateur — le modèle
/// reçoit sa fonction d'écriture comme l'app la lui branche.
@MainActor
final class LastQuestionsModelTests: XCTestCase {
    private func account(createdAt: Date = .now) -> Account {
        Account(id: UUID().uuidString, email: "camille@memobook.app", firstName: "camille", createdAt: createdAt)
    }

    func testOnlyAFreshAccountIsAskedAndOnlyOnce() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "LastQuestionsModelTests"))
        defaults.removePersistentDomain(forName: "LastQuestionsModelTests")

        let fresh = account()
        XCTAssertTrue(LastQuestionsModel.shouldAsk(fresh, defaults: defaults))
        XCTAssertFalse(LastQuestionsModel.shouldAsk(account(createdAt: .now.addingTimeInterval(-3600)), defaults: defaults))

        LastQuestionsModel.markAnswered(fresh, defaults: defaults)
        XCTAssertFalse(LastQuestionsModel.shouldAsk(fresh, defaults: defaults))
    }

    func testTheBirthDateTakesItsSlashesAsItIsTyped() {
        XCTAssertEqual(LastQuestionsModel.maskedBirthDate("12"), "12")
        XCTAssertEqual(LastQuestionsModel.maskedBirthDate("1205"), "12/05")
        XCTAssertEqual(LastQuestionsModel.maskedBirthDate("12051994"), "12/05/1994")
        XCTAssertEqual(LastQuestionsModel.maskedBirthDate("12/05/19945"), "12/05/1994")
        XCTAssertEqual(LastQuestionsModel.maskedBirthDate("ab12"), "12")
    }

    func testEachQuestionSavesWhatItAskedThenMovesOn() async throws {
        var sent: [ProfileEdit] = []
        let model = LastQuestionsModel(account: account()) { sent.append($0) }

        // Le prénom du fournisseur est là ; il manque le nom.
        XCTAssertFalse(model.canValidate)
        model.lastName = "Dupont"
        model.firstName = "Camille"
        let afterName = await model.validate()
        XCTAssertNil(afterName)
        XCTAssertEqual(model.step, .birthDate)

        model.birthDateText = "31/06/1994"
        XCTAssertFalse(model.canValidate)
        XCTAssertNotNil(model.birthDateProblem)
        model.birthDateText = "12051994"
        XCTAssertEqual(model.birthDateText, "12/05/1994")
        XCTAssertTrue(model.canValidate)
        _ = await model.validate()
        XCTAssertEqual(model.step, .phone)

        model.phoneNumber = "+33 6 12 34 56 78"
        let result = await model.validate()
        let finished = try XCTUnwrap(result)
        XCTAssertEqual(finished.firstName, "Camille")
        XCTAssertEqual(finished.lastName, "Dupont")

        XCTAssertEqual(sent.count, 3)
        XCTAssertEqual(sent[0], ProfileEdit(firstName: .some("Camille"), lastName: .some("Dupont")))
        XCTAssertEqual(sent[1], ProfileEdit(birthDate: .some(CalendarDay(year: 1994, month: 5, day: 12))))
        XCTAssertEqual(sent[2], ProfileEdit(phoneNumber: .some("+33 6 12 34 56 78")))
    }

    func testSkippingSavesNothingAndStillEnters() {
        var sent: [ProfileEdit] = []
        let model = LastQuestionsModel(account: account()) { sent.append($0) }

        XCTAssertNil(model.skip())
        XCTAssertNil(model.skip())
        XCTAssertNotNil(model.skip())
        XCTAssertTrue(sent.isEmpty)
    }

    func testAFailedSaveKeepsTheQuestionOpen() async {
        let model = LastQuestionsModel(account: account()) { _ in
            throw APIError.server(statusCode: 400, code: nil, message: "Refusé.")
        }
        model.lastName = "Dupont"

        let result = await model.validate()
        XCTAssertNil(result)
        XCTAssertEqual(model.step, .name)
        XCTAssertEqual(model.errorMessage, "Refusé.")
    }

    func testTheArrowGoesBackThenHandsOverAtTheFirstQuestion() {
        let model = LastQuestionsModel(account: account())
        _ = model.skip()
        XCTAssertTrue(model.goBack())
        XCTAssertEqual(model.step, .name)
        XCTAssertFalse(model.goBack())
    }
}

/// « Rejoins une aventure » : ce que l'accueil fait d'un code.
@MainActor
final class HomeJoinTests: XCTestCase {
    func testAKnownCodeOpensTheTrip() async {
        let trip = HomeFeed.fixture.trips[0]
        let model = HomeModel(join: { _ in CreatedTrip(trip: trip, accessCode: "JHKFDA") })
        let outcome = await model.join(code: "JHKFDA")
        XCTAssertEqual(outcome, .joined(tripId: trip.id))
    }

    func testAnUnknownCodeAsksForTheAlert() async {
        let model = HomeModel(join: { _ in
            throw APIError.server(statusCode: 404, code: "trip_not_found", message: "Aucun voyage.")
        })
        let outcome = await model.join(code: "ZZZZZZ")
        XCTAssertEqual(outcome, .notFound)
    }

    func testAnyOtherRefusalKeepsTheServerSentence() async {
        let model = HomeModel(join: { _ in
            throw APIError.server(statusCode: 403, code: "member_removed", message: "Tu ne fais plus partie de ce voyage.")
        })
        let outcome = await model.join(code: "JHKFDA")
        XCTAssertEqual(outcome, .failed("Tu ne fais plus partie de ce voyage."))
    }
}
