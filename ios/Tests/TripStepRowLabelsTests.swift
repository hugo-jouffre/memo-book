@testable import MemoBookFeature
import MemoBookCore
import XCTest

/// **Ce que dit une carte d'étape** (Hugo, 25/10/2026 — « titres d'étape
/// accrocheurs avec numéro en pastille et ville à la place du co-voyageur
/// répété »).
///
/// Une liste d'étapes doit se lire comme un itinéraire — Trastevere, Monti,
/// Testaccio —, pas comme une numérotation suivie du même nom à chaque ligne.
/// Le numéro part dans sa pastille, le lieu prend le titre, et les
/// co-voyageurs quittent l'écran.
///
/// ⚠️ **Quitter l'écran n'est pas quitter l'app.** Qui écoute la liste ne la
/// parcourt pas du regard : ``TripStep/spokenLabel`` lui rend ce que la carte
/// ne dessine plus. C'est la moitié de ce changement, et la plus facile à
/// perdre dans une relecture.
final class TripStepRowLabelsTests: XCTestCase {
    private func step(
        number: Int = 1,
        place: String? = "Trastevere",
        companions: [Companion] = [Companion(id: "c-1", name: "Léa Martin")],
        validated: Bool = false
    ) -> TripStep {
        TripStep(
            id: "step-\(number)",
            number: number,
            placeName: place,
            destination: nil,
            startDate: nil,
            endDate: nil,
            companions: companions,
            transport: nil,
            validatedAt: validated ? Date(timeIntervalSince1970: 0) : nil,
            entryIds: []
        )
    }

    func testThePlaceTakesTheTitle() {
        XCTAssertEqual(step().title, "Trastevere")
    }

    /// Sans lieu, le numéro revient dans le titre : la pastille ne doublerait
    /// rien d'autre que lui, et une carte sans titre ne dirait rien.
    func testWithoutAPlaceTheNumberComesBackIntoTheTitle() {
        XCTAssertEqual(step(number: 4, place: nil).title, "Etape n°4")
    }

    /// Le titre ne porte plus les co-voyageurs, sous aucune forme.
    func testTheTitleNeverNamesACompanion() {
        let titre = step(companions: [Companion(id: "c-1", name: "Fanny Delorme")]).title
        XCTAssertFalse(titre.contains("Fanny"))
        XCTAssertFalse(titre.contains("avec"))
    }

    /// Et VoiceOver, lui, les entend encore — avec le numéro, le lieu et
    /// l'état de validation.
    func testVoiceOverStillHearsTheCompanions() {
        let dit = step(number: 2, validated: true).spokenLabel
        XCTAssertTrue(dit.contains("Étape 2"), dit)
        XCTAssertTrue(dit.contains("Trastevere"), dit)
        XCTAssertTrue(dit.contains("avec Léa"), dit)
        XCTAssertTrue(dit.contains("validée"), dit)
    }

    /// Une étape sans personne ni lieu ne dit pas de vide : pas de virgule
    /// orpheline, pas de « , , ».
    func testAnEmptyStepStillReadsCleanly() {
        let dit = step(number: 7, place: nil, companions: []).spokenLabel
        XCTAssertEqual(dit, "Étape 7")
    }
}
