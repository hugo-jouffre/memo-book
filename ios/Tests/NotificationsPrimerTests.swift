import MemoBookCore
@testable import MemoBookFeature
import UserNotifications
import XCTest

/// L'écran « Améliorons MemoBook ensemble » (03/11/2026) : à qui il se montre,
/// et ce qu'il retient.
@MainActor
final class NotificationsPrimerTests: XCTestCase {
    /// Des réglages à part, vidés à chaque test : la mémoire de l'écran vit
    /// sur l'appareil, pas dans le fil.
    private func freshDefaults() throws -> UserDefaults {
        let suite = "NotificationsPrimerTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testShownOnlyAtTheFirstOpeningAndBeforeAnyAnswer() {
        // Une conversation ouverte pour la première fois, question jamais
        // posée : l'écran.
        XCTAssertTrue(NotificationsPrimer.isShown(isFirstOpeningOfANewTrip: true, authorization: .notDetermined))
        // Déjà répondu — autorisé, refusé : l'alerte ne reviendrait pas, donc
        // l'écran non plus.
        XCTAssertFalse(NotificationsPrimer.isShown(isFirstOpeningOfANewTrip: true, authorization: .authorized))
        XCTAssertFalse(NotificationsPrimer.isShown(isFirstOpeningOfANewTrip: true, authorization: .denied))
        XCTAssertFalse(NotificationsPrimer.isShown(isFirstOpeningOfANewTrip: true, authorization: .provisional))
        // Une conversation qu'on rouvre, ou un voyage rejoint par un code.
        XCTAssertFalse(NotificationsPrimer.isShown(isFirstOpeningOfANewTrip: false, authorization: .notDetermined))
    }

    func testOnlyTheFirstOpeningOfATripCreatedHereCounts() throws {
        let defaults = try freshDefaults()
        NotificationsPrimer.markTripCreated("rome", defaults: defaults)

        XCTAssertTrue(NotificationsPrimer.consumeFirstOpening(of: "rome", defaults: defaults))
        // La deuxième ouverture n'en est plus une.
        XCTAssertFalse(NotificationsPrimer.consumeFirstOpening(of: "rome", defaults: defaults))
        // Un voyage qu'on n'a pas créé ici n'a jamais été attendu.
        XCTAssertFalse(NotificationsPrimer.consumeFirstOpening(of: "lisbonne", defaults: defaults))
    }

    func testCorrectingADraftDoesNotQueueTheTripTwice() throws {
        let defaults = try freshDefaults()
        // Revenir en arrière et revalider renvoie la création sur le même
        // identifiant : la liste ne doit pas le retenir deux fois, sinon la
        // seconde ouverture rouvrirait l'écran.
        NotificationsPrimer.markTripCreated("rome", defaults: defaults)
        NotificationsPrimer.markTripCreated("rome", defaults: defaults)

        XCTAssertTrue(NotificationsPrimer.consumeFirstOpening(of: "rome", defaults: defaults))
        XCTAssertFalse(NotificationsPrimer.consumeFirstOpening(of: "rome", defaults: defaults))
    }

    func testSeveralTripsWaitSideBySide() throws {
        let defaults = try freshDefaults()
        NotificationsPrimer.markTripCreated("rome", defaults: defaults)
        NotificationsPrimer.markTripCreated("lisbonne", defaults: defaults)

        XCTAssertTrue(NotificationsPrimer.consumeFirstOpening(of: "lisbonne", defaults: defaults))
        // Ouvrir l'un n'oublie pas l'autre.
        XCTAssertTrue(NotificationsPrimer.consumeFirstOpening(of: "rome", defaults: defaults))
    }

    func testTheWordsOfTheScreen() {
        XCTAssertEqual(NotificationsPrimer.title, "Améliorons MemoBook ensemble")
        XCTAssertEqual(NotificationsPrimer.paragraphs.count, 2)
        // La phrase de la maquette, mot pour mot.
        XCTAssertEqual(
            NotificationsPrimer.paragraphs.last,
            "Le contenu de ton carnet de voyage reste privé et nous n’allons jamais revendre tes données."
        )
    }
}
