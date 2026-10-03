import Foundation
import XCTest

@testable import MemoBookCore

/// **Le sursis de la période payée.** Un mois commencé est un mois réglé :
/// résilier le 3 ne rend pas les semaines suivantes, donc ça ne referme pas
/// l'illimité non plus (Hugo, 16/09/2026 pour la semaine, règle tenue au
/// passage au mois le 03/10/2026).
///
/// Les règles vivent sur ``Subscription`` et non dans une vue, précisément pour
/// qu'elles se testent sans simulateur — c'est de la date, pas du dessin.
final class SubscriptionGraceTests: XCTestCase {
    private let today = Date(timeIntervalSince1970: 1_789_000_000)

    private func days(_ count: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: count, to: today) ?? today
    }

    func testAnActiveSubscriptionGrantsAccess() {
        let subscription = Subscription(price: 4.99, isActive: true)
        XCTAssertTrue(subscription.grantsAccess(on: today))
        // Actif, il n'y a pas de sursis à annoncer : la phrase des feuilles de
        // résiliation n'a pas lieu d'être tant qu'on n'a pas résilié.
        XCTAssertNil(subscription.graceEnd(on: today))
    }

    func testACancelledSubscriptionKeepsItsPaidMonth() {
        let subscription = Subscription(
            price: 4.99,
            isActive: false,
            cancelledAt: today,
            paidThrough: days(20)
        )

        XCTAssertTrue(subscription.grantsAccess(on: today))
        XCTAssertEqual(subscription.graceEnd(on: today), days(20))
    }

    func testTheLastDayKeepsTheOldBehaviour() {
        // **Le cas que Hugo a nommément épargné** : « si le dernier jour est
        // aujourd'hui, le processus reste celui d'avant ». Il n'y a pas de
        // sursis à annoncer pour un jour qui est déjà là, et la dernière
        // feuille garde « l'abonnement s'arrête aujourd'hui ».
        let subscription = Subscription(
            price: 4.99,
            isActive: false,
            cancelledAt: today,
            // La **même journée**, à quelques heures près : c'est le jour qui
            // compte, pas l'heure.
            paidThrough: today.addingTimeInterval(6 * 3_600)
        )

        XCTAssertFalse(subscription.isWithinPaidPeriod(on: today))
        XCTAssertFalse(subscription.grantsAccess(on: today))
        XCTAssertNil(subscription.graceEnd(on: today))
    }

    func testAPastPeriodGrantsNothing() {
        let subscription = Subscription(
            price: 4.99,
            isActive: false,
            cancelledAt: days(-40),
            paidThrough: days(-2)
        )

        XCTAssertFalse(subscription.grantsAccess(on: today))
        XCTAssertNil(subscription.graceEnd(on: today))
    }

    func testNothingPaidGrantsNothing() {
        // Un compte qui n'a jamais souscrit : `paidThrough` est nul, et on
        // retombe sur le comportement d'avant.
        let subscription = Subscription(price: 4.99)
        XCTAssertFalse(subscription.grantsAccess(on: today))
    }

    /// Un profil d'ancien abonné : plus d'abonnement actif — exactement l'état
    /// de quelqu'un qui vient de résilier.
    private func cancelledProfile(paidThrough: Date?) -> TravellerProfile {
        TravellerProfile(
            fullName: "Margaux Prn",
            subscription: Subscription(
                price: 4.99,
                isActive: false,
                cancelledAt: .now,
                paidThrough: paidThrough
            )
        )
    }

    func testTheProfileFollowsTheAccessAndNotTheFlag() {
        // Le point qui compte : l'illimité se lit sur l'**accès**, pas sur
        // `isActive`. Le refermer le jour du geste rendrait fausse la phrase
        // que la feuille de résiliation vient d'écrire.
        let profile = cancelledProfile(
            paidThrough: Calendar.current.date(byAdding: .day, value: 4, to: .now)
        )

        XCTAssertTrue(profile.isSubscriber)
        XCTAssertTrue(profile.subscription.isUnlimited)
    }

    func testTheProfileClosesOnceThePeriodIsOver() {
        let profile = cancelledProfile(
            paidThrough: Calendar.current.date(byAdding: .day, value: -1, to: .now)
        )

        XCTAssertFalse(profile.isSubscriber)
        XCTAssertFalse(profile.subscription.isUnlimited)
    }

    // MARK: Le prix à écrire

    func testTheOfferIsFourNinetyNineAMonth() {
        XCTAssertEqual(Subscription.offer.price, 4.99)
        XCTAssertEqual(Subscription.offer.interval, .month)
        XCTAssertEqual(Subscription.offer.periodLabel, "mois")
    }

    func testDisplayedPriceIsNeverZero() {
        // Un abonnement à zéro euro n'existe pas : c'est la marque d'un serveur
        // qui n'a pas de ligne à lire. L'app écrivait « 0,00 € ».
        let empty = Subscription(price: 0)
        XCTAssertEqual(empty.displayedPrice, Subscription.offer.price)
        XCTAssertEqual(empty.periodLabel, "mois")

        // Un vrai prix, lui, passe tel quel — avec sa période.
        XCTAssertEqual(Subscription(price: 5.99).displayedPrice, 5.99)
        XCTAssertEqual(Subscription(price: 1.99, interval: .week).periodLabel, "semaine")
    }

    func testThePaywallOnlySellsTheMonth() {
        // Un ancien abonné à la semaine garde son tarif dans « Mon
        // abonnement », mais l'offre qu'on lui présente est la mensuelle.
        XCTAssertEqual(Subscription(price: 1.99, interval: .week).offeredPrice, 4.99)
        XCTAssertEqual(Subscription(price: 5.49, interval: .month).offeredPrice, 5.49)
        XCTAssertEqual(Subscription(price: 0).offeredPrice, 4.99)

        let nothing: Subscription? = nil
        XCTAssertEqual(nothing.offeredPrice, 4.99)
    }

    // MARK: Le décodage

    func testTheMonthlyPriceIsRead() throws {
        let json = #"{ "price": 4.99, "interval": "month", "weeklyPrice": 4.99, "isActive": true }"#
        let subscription = try JSONDecoder.memoBook.decode(Subscription.self, from: Data(json.utf8))
        XCTAssertEqual(subscription.price, Decimal(string: "4.99"))
        XCTAssertEqual(subscription.interval, .month)
        XCTAssertTrue(subscription.isUnlimited)
    }

    func testAnOlderServerStillDecodes() throws {
        // Un serveur d'avant le mois ne sert que `weeklyPrice` : le profil ne
        // doit pas tomber, et sa période est la semaine.
        let json = #"{ "weeklyPrice": 1.99, "isActive": false }"#
        let subscription = try JSONDecoder.memoBook.decode(Subscription.self, from: Data(json.utf8))
        XCTAssertEqual(subscription.price, Decimal(string: "1.99"))
        XCTAssertEqual(subscription.interval, .week)
        XCTAssertEqual(subscription.offeredPrice, Subscription.offer.price)
    }

    func testAnUnknownIntervalFallsBackToTheMonth() throws {
        let json = #"{ "price": 49.99, "interval": "year", "isActive": true }"#
        let subscription = try JSONDecoder.memoBook.decode(Subscription.self, from: Data(json.utf8))
        XCTAssertEqual(subscription.interval, .month)
    }

    func testTheSubscriptionRoundTripsThroughTheCache() throws {
        // Le cache disque réencode le profil : il doit se relire tel quel.
        let original = Subscription(
            price: 4.99,
            interval: .month,
            isActive: true,
            tripTitle: "Rome entre amis",
            managedByAppStore: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Subscription.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: Apple tient l'abonnement (01/10/2026)

    func testAnAppStoreSubscriptionSaysSo() throws {
        let json = #"{ "price": 4.99, "interval": "month", "isActive": true, "managedByAppStore": true }"#
        let subscription = try JSONDecoder.memoBook.decode(Subscription.self, from: Data(json.utf8))
        XCTAssertTrue(subscription.managedByAppStore)
    }

    func testAnOlderServerIsNotTakenForApple() throws {
        // Sans le champ, la résiliation reste celle d'avant : une route d'ici,
        // pas la feuille d'iOS.
        let json = #"{ "weeklyPrice": 1.99, "isActive": true }"#
        let subscription = try JSONDecoder.memoBook.decode(Subscription.self, from: Data(json.utf8))
        XCTAssertFalse(subscription.managedByAppStore)
    }

    // MARK: Le verdict du serveur (03/10/2026)

    /// Le dernier jour payé, le serveur accorde encore l'illimité jusqu'à
    /// l'heure de `renewsAt` ; le recalcul au jour près dirait non. Le profil
    /// suit le serveur, et ne contredit plus la conversation.
    func testTheServedVerdictWinsOnTheLastPaidDay() throws {
        // Une minute de mois payé devant soi — aujourd'hui, donc : le recalcul
        // au jour près le refuse, le serveur l'accorde.
        let paidThrough = ISO8601DateFormatter.memoBookString(from: .now.addingTimeInterval(60))
        let json = """
            { "price": 4.99, "interval": "month", "isActive": false, \
            "cancelledAt": "2026-10-01T09:00:00.000Z", "paidThrough": "\(paidThrough)", \
            "isUnlimited": true }
            """
        let subscription = try JSONDecoder.memoBook.decode(Subscription.self, from: Data(json.utf8))
        XCTAssertEqual(subscription.servedIsUnlimited, true)
        XCTAssertTrue(subscription.isUnlimited)
        XCTAssertTrue(TravellerProfile(fullName: "Camille", subscription: subscription).isSubscriber)
    }

    /// Délai de grâce de facturation d'Apple (`past_due`) : `isActive` est faux
    /// et rien n'est résilié, mais le serveur accorde l'illimité.
    func testABillingGracePeriodStaysUnlimited() throws {
        let json = #"{ "price": 4.99, "interval": "month", "isActive": false, "isUnlimited": true }"#
        let subscription = try JSONDecoder.memoBook.decode(Subscription.self, from: Data(json.utf8))
        XCTAssertTrue(subscription.isUnlimited)
        XCTAssertNil(subscription.cancelledAt)
    }

    /// Un geste fait dans l'app retouche l'abonnement sur place : le verdict
    /// servi avant lui ne vaut plus, et le recalcul reprend la main.
    func testALocalGestureDropsTheServedVerdict() {
        var subscription = Subscription(price: 4.99, isActive: true, servedIsUnlimited: true)

        subscription.isActive = true
        XCTAssertEqual(subscription.servedIsUnlimited, true, "Rien n'a changé : le verdict tient.")

        subscription.isActive = false
        XCTAssertNil(subscription.servedIsUnlimited)
        XCTAssertFalse(subscription.isUnlimited, "Ni actif ni mois payé : plus d'illimité.")

        var paid = Subscription(price: 4.99, servedIsUnlimited: false)
        paid.paidThrough = .now.addingTimeInterval(10 * 86_400)
        XCTAssertNil(paid.servedIsUnlimited)
        XCTAssertTrue(paid.isUnlimited, "Dix jours payés devant soi : l'illimité.")
    }

    func testAnOlderServerFallsBackOnTheDay() throws {
        let json = #"{ "price": 4.99, "interval": "month", "isActive": true }"#
        let subscription = try JSONDecoder.memoBook.decode(Subscription.self, from: Data(json.utf8))
        XCTAssertNil(subscription.servedIsUnlimited)
        XCTAssertTrue(subscription.isUnlimited)
    }

    func testTheServedVerdictRoundTripsThroughTheCache() throws {
        let original = Subscription(price: 4.99, isActive: false, servedIsUnlimited: true)
        let decoded = try JSONDecoder().decode(Subscription.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.servedIsUnlimited, true)
        XCTAssertEqual(decoded, original)
    }

    /// Mis en cache pendant le mois payé, relu hors ligne une fois ce mois
    /// passé : le « oui » du serveur ne vaut plus, l'illimité se referme comme
    /// le serveur l'aurait refermé.
    func testAServedVerdictExpiresWithItsPaidPeriod() throws {
        let paidThrough = ISO8601DateFormatter.memoBookString(from: .now.addingTimeInterval(-2 * 86_400))
        let json = """
            { "price": 4.99, "interval": "month", "isActive": false, \
            "cancelledAt": "2026-10-01T09:00:00.000Z", "paidThrough": "\(paidThrough)", \
            "isUnlimited": true }
            """
        let served = try JSONDecoder.memoBook.decode(Subscription.self, from: Data(json.utf8))
        let cached = try JSONDecoder.memoBook.decode(Subscription.self, from: JSONEncoder.memoBook.encode(served))
        XCTAssertEqual(cached.servedIsUnlimited, true, "Le verdict voyage avec le cache…")
        XCTAssertFalse(cached.isUnlimited, "… mais ne survit pas à sa période.")
        XCTAssertFalse(TravellerProfile(fullName: "Camille", subscription: cached).isSubscriber)

        // La veille de la fin, il tenait.
        XCTAssertTrue(cached.isUnlimited(at: .now.addingTimeInterval(-3 * 86_400)))
    }

    /// Les phrases de la résiliation disent la période **payée** : la semaine
    /// d'un ancien abonné hebdomadaire, le mois sinon.
    func testThePaidIntervalFollowsThePrice() {
        XCTAssertEqual(Subscription(price: 1.99, interval: .week).paidInterval, .week)
        XCTAssertEqual(Subscription(price: 4.99).paidInterval, .month)
        XCTAssertEqual(Subscription(price: 0, interval: .week).paidInterval, .month)
        XCTAssertEqual(Subscription(price: 1.99, interval: .week).periodLabel, "semaine")
    }

    // MARK: L'accueil

    func testTheTripEndReminderIsReadFromTheHome() throws {
        let json = #"{ "id": "t", "firstName": "Camille", "subscriptionOutlivesTrip": true }"#
        let traveller = try JSONDecoder.memoBook.decode(Traveller.self, from: Data(json.utf8))
        XCTAssertTrue(traveller.subscriptionOutlivesTrip)

        // Et un serveur qui ne le sert pas ne rappelle rien à personne.
        let older = #"{ "id": "t", "firstName": "Camille" }"#
        XCTAssertFalse(
            try JSONDecoder.memoBook.decode(Traveller.self, from: Data(older.utf8)).subscriptionOutlivesTrip
        )
    }

    func testTheHomeSaysWhoIsUnlimited() throws {
        let json = #"{ "id": "t", "firstName": "Camille", "isUnlimited": true, "hasSubscribedBefore": true }"#
        let traveller = try JSONDecoder.memoBook.decode(Traveller.self, from: Data(json.utf8))
        XCTAssertTrue(traveller.isUnlimited)
        XCTAssertTrue(traveller.hasSubscribedBefore)

        // Un serveur plus ancien : personne n'est illimité, et le paywall
        // ouvre sur la découverte. Les anciens champs d'étapes s'ignorent.
        let older = #"{ "id": "t", "firstName": "Camille", "offeredSteps": 3, "remainingSteps": 0 }"#
        let decoded = try JSONDecoder.memoBook.decode(Traveller.self, from: Data(older.utf8))
        XCTAssertFalse(decoded.isUnlimited)
        XCTAssertFalse(decoded.hasSubscribedBefore)
    }
}
