import MemoBookCore
@testable import MemoBookFeature
import MemoBookNetworking
import XCTest

/// **« Séparer ces récits »** (Hugo, 28/10/2026 — « 1 message n'est pas
/// toujours égal à 1 étape »).
///
/// La rédaction réunit en une étape les récits qui se prolongent. Elle se
/// trompe parfois, et c'est le voyageur qui tranche en dernier : le geste du
/// tiroir rend à chaque récit son étape.
///
/// Sans simulateur — le modèle reçoit ses fonctions comme l'app les lui
/// branche.
@MainActor
final class TripStepSeparationTests: XCTestCase {
    private func step(_ id: String, number: Int, stories: Int?) -> TripStep {
        TripStep(id: id, number: number, entryIds: ["e-\(id)"], storyCount: stories)
    }

    private func detail(_ steps: [TripStep]) -> TripDetail {
        TripDetail(trip: Trip(id: "rome", title: "Rome", stage: .ongoing), steps: steps)
    }

    /// Le geste ne s'offre que sur une étape qui réunit plusieurs récits.
    func testTheGestureIsOfferedOnlyOnAGroupedStep() async {
        let grouped = step("a", number: 1, stories: 2)
        let alone = step("b", number: 2, stories: 1)
        let model = TripHomeModel(
            tripId: "rome",
            source: { _ in self.detail([grouped, alone]) },
            separateStep: { _, _ in self.detail([grouped, alone]) }
        )
        await model.load()

        XCTAssertTrue(model.canSeparateStories(of: grouped))
        XCTAssertFalse(model.canSeparateStories(of: alone), "Un seul récit : rien à séparer.")
    }

    /// Sans serveur qui sache le faire — un aperçu —, le geste ne paraît pas.
    func testWithoutTheRouteTheGestureIsNotOffered() async {
        let grouped = step("a", number: 1, stories: 2)
        let model = TripHomeModel(tripId: "rome", source: { _ in self.detail([grouped]) })
        await model.load()

        XCTAssertFalse(model.canSeparateStories(of: grouped))
    }

    /// **L'écran prend ce que le serveur rend**, et ne devine pas : séparer
    /// renumérote les étapes suivantes, et refaire ce découpage côté app
    /// reviendrait à réécrire sa règle.
    func testTheScreenTakesTheTripTheServerReturns() async {
        var asked: [String] = []
        let grouped = step("a", number: 1, stories: 2)
        let separated = [step("a", number: 1, stories: 1), step("a2", number: 2, stories: 1)]
        let model = TripHomeModel(
            tripId: "rome",
            source: { _ in self.detail([grouped]) },
            separateStep: { _, stepId in
                asked.append(stepId)
                return self.detail(separated)
            }
        )
        await model.load()

        model.separateStories(of: grouped)

        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(asked, ["a"])
        XCTAssertEqual(model.detail?.steps.map(\.id), ["a", "a2"])
        XCTAssertNotNil(model.confirmation, "Le geste se confirme, comme la validation.")
        XCTAssertNil(model.separatingStepId, "L'attente est finie.")
    }

    /// Un refus ne laisse pas l'écran sur un découpage inventé : il relit le
    /// voyage et **dit** ce qui s'est passé.
    ///
    /// L'ordre compte, et c'est ce que ce test tient : `load()` efface
    /// `errorMessage` quand il réussit, donc le bandeau se pose **après** la
    /// relecture. Posé avant, il disparaissait aussitôt et le refus ne se
    /// voyait nulle part.
    func testAFailureRereadsTheTrip() async {
        struct Refused: Error {}
        let grouped = step("a", number: 1, stories: 2)
        var reads = 0
        let model = TripHomeModel(
            tripId: "rome",
            source: { _ in
                reads += 1
                return self.detail([grouped])
            },
            separateStep: { _, _ in throw Refused() }
        )
        await model.load()

        model.separateStories(of: grouped)

        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(reads, 2, "Le voyage est relu après l'échec.")
        XCTAssertEqual(model.detail?.steps.map(\.id), ["a"])
    }
}
