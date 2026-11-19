import XCTest

@testable import MemoBookCore

/// **T268** — revenir deux fois sur un voyage en 24 h ouvre l'app dessus.
final class TripVisitsTests: XCTestCase {
    private let maintenant = Date(timeIntervalSince1970: 1_700_000_000)

    private func ilYA(_ heures: Double) -> Date {
        maintenant.addingTimeInterval(-heures * 3600)
    }

    func testUneSeuleVisiteNeSuffitPas() {
        // On ouvre un voyage pour le regarder. Une visite ne dit rien.
        let visites = ["rome": [ilYA(2)]]
        XCTAssertNil(TripVisits.voyageAReprendre(visites, maintenant: maintenant))
    }

    func testDeuxVisitesDansLaJournee() {
        let visites = ["rome": [ilYA(6), ilYA(1)]]
        XCTAssertEqual(TripVisits.voyageAReprendre(visites, maintenant: maintenant), "rome")
    }

    func testLesVisitesDeLaVeilleNeComptentPlus() {
        // Deux visites, mais il y a plus de 24 h : qui cesse de revenir
        // retrouve son accueil le lendemain, sans rien désactiver.
        let visites = ["rome": [ilYA(30), ilYA(26)]]
        XCTAssertNil(TripVisits.voyageAReprendre(visites, maintenant: maintenant))
        XCTAssertTrue(TripVisits.recentes(visites, maintenant: maintenant).isEmpty)
    }

    func testUneVisiteDHierEtUneDAujourdHuiNeSuffisentPas() {
        // La vieille est jetée : il n'en reste qu'une, donc pas de reprise.
        let visites = ["rome": [ilYA(30), ilYA(1)]]
        XCTAssertNil(TripVisits.voyageAReprendre(visites, maintenant: maintenant))
    }

    func testLePlusRecemmentVisiteLEmporte() {
        let visites = [
            "rome": [ilYA(10), ilYA(9)],
            "paros": [ilYA(5), ilYA(2)],
        ]
        XCTAssertEqual(TripVisits.voyageAReprendre(visites, maintenant: maintenant), "paros")
    }

    /// **Le test qui porte le piège.** Si l'ouverture automatique comptait
    /// comme une visite, la condition resterait vraie pour toujours et
    /// l'accueil deviendrait inatteignable au lancement. `enNotant` n'est
    /// appelé que depuis un geste délibéré ; ce test fige le fait qu'une
    /// reprise ne modifie rien.
    func testUneRepriseNeSeNotePas() {
        let visites = ["rome": [ilYA(6), ilYA(1)]]
        let apresReprise = TripVisits.recentes(visites, maintenant: maintenant)
        XCTAssertEqual(apresReprise["rome"]?.count, 2, "la reprise ne doit rien ajouter")
    }

    func testUneHorlogeQuiReculeNOublieRien() {
        // Une visite datée dans le futur — l'horloge du téléphone a reculé.
        // La jeter ferait oublier la journée en cours au pire moment.
        let visites = ["rome": [maintenant.addingTimeInterval(3600), ilYA(1)]]
        XCTAssertEqual(TripVisits.voyageAReprendre(visites, maintenant: maintenant), "rome")
    }

    func testNoterAjouteEtNettoieEnMemeTemps() {
        let avant = ["rome": [ilYA(40)], "paros": [ilYA(3)]]
        let apres = TripVisits.enNotant("paros", dans: avant, maintenant: maintenant)

        XCTAssertNil(apres["rome"], "la visite de l'avant-veille est jetée")
        XCTAssertEqual(apres["paros"]?.count, 2)
        XCTAssertEqual(TripVisits.voyageAReprendre(apres, maintenant: maintenant), "paros")
    }

    func testSansAucuneVisite() {
        XCTAssertNil(TripVisits.voyageAReprendre([:], maintenant: maintenant))
    }
}
