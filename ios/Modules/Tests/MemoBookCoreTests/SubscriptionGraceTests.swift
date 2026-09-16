import Foundation
import XCTest

@testable import MemoBookCore

/// **Le sursis de la semaine payée.** Une semaine commencée est une semaine
/// réglée : résilier le lundi ne rend pas les six jours suivants, donc ça ne
/// ferme pas le micro non plus (Hugo, 16/09/2026).
///
/// Les règles vivent sur ``Subscription`` et non dans une vue, précisément pour
/// qu'elles se testent sans simulateur — c'est de la date, pas du dessin.
final class SubscriptionGraceTests: XCTestCase {
    private let today = Date(timeIntervalSince1970: 1_789_000_000)

    private func days(_ count: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: count, to: today) ?? today
    }

    func testAnActiveSubscriptionGrantsAccess() {
        let subscription = Subscription(weeklyPrice: 1.99, isActive: true)
        XCTAssertTrue(subscription.grantsAccess(on: today))
        // Actif, il n'y a pas de sursis à annoncer : la phrase des feuilles de
        // résiliation n'a pas lieu d'être tant qu'on n'a pas résilié.
        XCTAssertNil(subscription.graceEnd(on: today))
    }

    func testACancelledSubscriptionKeepsItsPaidWeek() {
        let subscription = Subscription(
            weeklyPrice: 1.99,
            isActive: false,
            cancelledAt: today,
            paidThrough: days(5)
        )

        XCTAssertTrue(subscription.grantsAccess(on: today))
        XCTAssertEqual(subscription.graceEnd(on: today), days(5))
    }

    func testTheLastDayKeepsTheOldBehaviour() {
        // **Le cas que Hugo a nommément épargné** : « si le dernier jour est
        // aujourd'hui, le processus reste celui d'avant ». Il n'y a pas de
        // sursis à annoncer pour un jour qui est déjà là, et la dernière
        // feuille garde « l'abonnement s'arrête aujourd'hui ».
        let subscription = Subscription(
            weeklyPrice: 1.99,
            isActive: false,
            cancelledAt: today,
            // La **même journée**, à quelques heures près : c'est le jour qui
            // compte, pas l'heure.
            paidThrough: today.addingTimeInterval(6 * 3_600)
        )

        XCTAssertFalse(subscription.isWithinPaidWeek(on: today))
        XCTAssertFalse(subscription.grantsAccess(on: today))
        XCTAssertNil(subscription.graceEnd(on: today))
    }

    func testAPastWeekGrantsNothing() {
        let subscription = Subscription(
            weeklyPrice: 1.99,
            isActive: false,
            cancelledAt: days(-9),
            paidThrough: days(-2)
        )

        XCTAssertFalse(subscription.grantsAccess(on: today))
        XCTAssertNil(subscription.graceEnd(on: today))
    }

    func testNothingPaidGrantsNothing() {
        // Un compte qui n'a jamais souscrit : `paidThrough` est nul, et on
        // retombe sur le comportement d'avant.
        let subscription = Subscription(weeklyPrice: 1.99)
        XCTAssertFalse(subscription.grantsAccess(on: today))
    }

    /// Un profil d'ancien abonné : plus d'abonnement actif, et aucun quota
    /// d'étapes — c'est exactement l'état de quelqu'un qui vient de résilier.
    private func cancelledProfile(paidThrough: Date?) -> TravellerProfile {
        TravellerProfile(
            fullName: "Margaux Prn",
            subscription: Subscription(
                weeklyPrice: 1.99,
                isActive: false,
                cancelledAt: .now,
                paidThrough: paidThrough
            )
        )
    }

    func testTheProfileTierFollowsTheAccessAndNotTheFlag() {
        // Le point qui compte : le palier se lit sur l'**accès**, pas sur
        // `isActive`. Fermer le jour du geste rendrait fausse la phrase que la
        // feuille de résiliation vient d'écrire.
        let profile = cancelledProfile(
            paidThrough: Calendar.current.date(byAdding: .day, value: 4, to: .now)
        )

        XCTAssertEqual(profile.freemiumStatus(override: nil), FreemiumStatus.subscriber)
        XCTAssertTrue(profile.isSubscriber)
    }

    func testTheProfileTierClosesOnceTheWeekIsOver() {
        let profile = cancelledProfile(
            paidThrough: Calendar.current.date(byAdding: .day, value: -1, to: .now)
        )

        XCTAssertEqual(profile.freemiumStatus(override: nil), FreemiumStatus.limitReached)
        XCTAssertFalse(profile.isSubscriber)
    }

    func testDisplayedPriceIsNeverZero() {
        // Un abonnement à zéro euro n'existe pas : c'est la marque d'un serveur
        // qui n'a pas de ligne à lire. L'app écrivait « 0,00 €/semaine ».
        let empty = Subscription(weeklyPrice: 0)
        XCTAssertEqual(empty.displayedWeeklyPrice, Subscription.offer.weeklyPrice)

        let nothing: Subscription? = nil
        XCTAssertEqual(nothing.displayedWeeklyPrice, Subscription.offer.weeklyPrice)

        // Un vrai prix, lui, passe tel quel.
        XCTAssertEqual(Subscription(weeklyPrice: 2.99).displayedWeeklyPrice, 2.99)
    }
}
