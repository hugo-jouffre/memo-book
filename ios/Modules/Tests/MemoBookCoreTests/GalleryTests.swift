import XCTest

@testable import MemoBookCore

/// Ce que la carte d'un carnet de la galerie décide toute seule : quel
/// pictogramme elle porte, et sous quelle catégorie elle se range.
///
/// Les deux règles se lisent en un coup d'œil sur l'écran et se cassent en
/// silence : un tour du monde qui prend le drapeau de son premier pays a l'air
/// juste tant qu'on ne connaît pas le voyage.
final class GalleryTripTests: XCTestCase {
    private func trip(
        _ destinations: [Destination],
        categoryIds: [String] = []
    ) -> GalleryTrip {
        GalleryTrip(
            id: "t1",
            title: "Un voyage",
            destinations: destinations,
            categoryIds: categoryIds
        )
    }

    func testSinglecountryCarriesItsFlag() {
        let subject = trip([Destination(name: "Islande", countryCode: "IS")])
        XCTAssertEqual(subject.flag, "🇮🇸")
    }

    func testSeveralCountriesCarryNoFlag() {
        // C'est ce `nil` qui fait poser le globe : choisir un drapeau parmi
        // quatre désignerait le premier pays comme *le* pays du voyage.
        let subject = trip([
            Destination(name: "Argentine", countryCode: "AR"),
            Destination(name: "Chili", countryCode: "CL"),
        ])
        XCTAssertNil(subject.flag)
    }

    func testCountryWithoutUsableCodeCarriesNoFlag() {
        // Mieux vaut un globe qu'un carré blanc.
        XCTAssertNil(trip([Destination(name: "Quelque part")]).flag)
        XCTAssertNil(trip([]).flag)
    }

    func testBelongsToEveryCategoryWhenNoneIsSelected() {
        // `nil`, c'est « Tout » : la barre ouverte, aucun filtre posé.
        XCTAssertTrue(trip([], categoryIds: []).belongs(to: nil))
    }

    func testBelongsToEachOfItsCategories() {
        let subject = trip([], categoryIds: ["rando", "montagne"])

        XCTAssertTrue(subject.belongs(to: "rando"))
        XCTAssertTrue(subject.belongs(to: "montagne"))
        XCTAssertFalse(subject.belongs(to: "velo"))
    }
}
