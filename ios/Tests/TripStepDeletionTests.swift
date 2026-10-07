import MemoBookCore
@testable import MemoBookFeature
import MemoBookNetworking
import XCTest

/// T235 : la croix du tiroir d'une étape efface **tous** ses souvenirs, et
/// l'étape quitte l'écran. Sans simulateur — le modèle reçoit ses fonctions
/// comme l'app les lui branche.
@MainActor
final class TripStepDeletionTests: XCTestCase {
    private func step(_ id: String, entries: [String]?) -> TripStep {
        TripStep(id: id, number: 1, entryIds: entries)
    }

    private func detail(_ steps: [TripStep]) -> TripDetail {
        TripDetail(trip: Trip(id: "rome", title: "Rome", stage: .ongoing), steps: steps)
    }

    func testEveryMemoryOfTheStepIsDeletedThenTheStepLeaves() async {
        var deleted: [String] = []
        var served = detail([step("a", entries: ["e1", "e2"]), step("b", entries: ["e3"])])
        let model = TripHomeModel(
            tripId: "rome",
            source: { _ in served },
            deleteEntry: { id in
                deleted.append(id)
                served = self.detail([self.step("b", entries: ["e3"])])
            }
        )
        await model.load()

        let target = served.steps[0]
        XCTAssertTrue(model.canDeleteMemories(of: target))
        let done = await model.deleteMemories(of: target)

        XCTAssertTrue(done)
        XCTAssertEqual(deleted, ["e1", "e2"])
        XCTAssertEqual(model.detail?.steps.map(\.id), ["b"])
        XCTAssertNotNil(model.confirmation)
    }

    func testARefusalKeepsTheSheetOpenWithTheServerSentence() async {
        let model = TripHomeModel(
            tripId: "rome",
            source: { _ in self.detail([self.step("a", entries: ["e1"])]) },
            deleteEntry: { _ in throw APIError.server(statusCode: 500, code: nil, message: "Réessaie.") }
        )
        await model.load()

        let done = await model.deleteMemories(of: step("a", entries: ["e1"]))
        XCTAssertFalse(done)
        XCTAssertEqual(model.stepDeletionError, "Réessaie.")
        XCTAssertEqual(model.detail?.steps.count, 1)
    }

    /// Un serveur qui ne dit pas quels souvenirs porte l'étape : pas de croix.
    func testNoCrossWithoutTheMemoriesOfTheStep() {
        let model = TripHomeModel(tripId: "rome", deleteEntry: { _ in })
        XCTAssertFalse(model.canDeleteMemories(of: step("a", entries: nil)))
        XCTAssertFalse(model.canDeleteMemories(of: step("a", entries: [])))
        XCTAssertFalse(TripHomeModel(tripId: "rome").canDeleteMemories(of: step("a", entries: ["e1"])))
    }
}
