import AppTrackingTransparency
@testable import MemoBookFeature
import XCTest

/// Le panneau « Autoriser à suivre votre activité ? » — App Tracking
/// Transparency, exigé par la guideline 5.1.2(i) dès que la fiche App Store
/// Connect déclare un suivi.
///
/// Ce qui se vérifie ici est ce qui **échoue en silence** : une clé absente de
/// l'Info.plist et un cas d'énumération mal replié ne cassent aucun build, ne
/// lèvent aucune erreur, et ne se voient qu'au moment où le panneau ne s'ouvre
/// pas — ou pire, à la revue App Store. Le reste (le moment de la demande, le
/// fait qu'on ne demande qu'une fois) se regarde en simulateur : c'est de la
/// vue, et ça se voit.
@MainActor
final class TrackingAuthorizationTests: XCTestCase {
    /// **Sans cette clé, `requestTrackingAuthorization` ne montre rien.** Pas
    /// d'erreur, pas de log : la demande rend la main et l'app croit avoir
    /// demandé. C'est exactement le genre de panne qu'on ne découvre qu'au
    /// rejet suivant, d'où ce test dans la cible d'assemblage.
    func testTheUsageDescriptionTravelsInTheBundle() {
        let description = Bundle.main.object(
            forInfoDictionaryKey: "NSUserTrackingUsageDescription"
        ) as? String

        XCTAssertNotNil(
            description,
            "NSUserTrackingUsageDescription absente de l'Info.plist : le panneau ne s'ouvrira jamais. Voir ios/project.yml."
        )
        XCTAssertFalse(
            description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
            "Une phrase vide vaut une clé absente pour la revue App Store."
        )
    }

    /// Les trois réponses possibles, et le repli.
    ///
    /// `restricted` — contrôle parental, ou « Autoriser les apps à demander »
    /// éteint — vaut un refus : dans les deux cas on ne suit pas.
    func testEveryAnswerFoldsOntoADecision() {
        let cases: [(ATTrackingManager.AuthorizationStatus, TrackingAuthorization.Decision)] = [
            (.notDetermined, .notDetermined),
            (.authorized, .granted),
            (.denied, .denied),
            (.restricted, .denied),
        ]

        for (status, expected) in cases {
            XCTAssertEqual(TrackingAuthorization.Decision(status), expected, "\(status)")
        }
    }

    /// Le défaut est **fermé** : un cas qu'une version future d'iOS ajouterait
    /// ne doit pas ouvrir le suivi par accident.
    ///
    /// Swift refuse aujourd'hui de fabriquer un cas absent de l'énumération
    /// ObjC — `init?(rawValue:)` rend `nil`. Le test se saute alors au lieu de
    /// mentir, et se remettra à mordre le jour où iOS en ajoutera un.
    func testAnUnknownStatusDoesNotOpenTracking() throws {
        guard let unknown = ATTrackingManager.AuthorizationStatus(rawValue: 99) else {
            throw XCTSkip("Aucun cas inconnu n'est constructible depuis Swift.")
        }

        XCTAssertEqual(TrackingAuthorization.Decision(unknown), .denied)
    }

    /// Ce que voient les aperçus Xcode. `current` doit rendre autre chose que
    /// `notDetermined`, sinon l'accueil tenterait de demander dans le canevas.
    func testTheSilentOneNeverAsks() async {
        XCTAssertEqual(TrackingAuthorization.never.current(), .denied)

        let answer = await TrackingAuthorization.never.request()
        XCTAssertEqual(answer, .denied)
    }

    /// Les dépendances portent bien celui qu'on leur donne — c'est ce qui
    /// permet à un test de piloter la réponse sans panneau à l'écran, et à
    /// l'app de descendre le vrai dans l'environnement (voir `RootView`).
    ///
    /// Le **défaut**, lui, ne se teste pas ici : `.system` lit l'état réel du
    /// simulateur, et sur une machine où le suivi a déjà été refusé il rend
    /// `.denied` — exactement comme `.never`. Un test qui les comparerait
    /// passerait ou échouerait selon l'ordre des lancements. C'est le
    /// simulateur qui vérifie ça, et la revue de code qui le tient.
    func testTheDependenciesCarryThePromptTheyWereGiven() async {
        let dependencies = AppDependencies(
            api: PreviewAPI(seeded: false),
            trackingAuthorization: TrackingAuthorization(
                current: { .granted },
                request: { .granted }
            )
        )

        XCTAssertEqual(dependencies.trackingAuthorization.current(), .granted)
        let answer = await dependencies.trackingAuthorization.request()
        XCTAssertEqual(answer, .granted)
    }
}
