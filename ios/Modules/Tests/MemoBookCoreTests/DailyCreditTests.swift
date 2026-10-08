import Foundation
import XCTest

@testable import MemoBookCore

/// Le **crédit du jour**, côté app : ce qui reste, les phases de la barre
/// d'enregistrement, le coût d'un texte, et les phrases qui le disent.
///
/// Le serveur tranche (`services/dailyCredit.ts`) ; ici on ne teste que ce que
/// l'app en déduit pour prévenir — à 4:30, à 4:55, à 5:00 — et ce qu'elle
/// affiche dans les réglages du voyage.
final class DailyCreditTests: XCTestCase {
    /// Un crédit du catalogue (5 min, 75 ms par caractère) dont il reste
    /// `remaining` millisecondes.
    private func credit(remaining: Int, isUnlimited: Bool = false) -> DailyCredit {
        DailyCredit(isUnlimited: isUnlimited, usedMs: DailyCredit.Catalog.limitMs - remaining)
    }

    // MARK: - Ce qui reste

    func testRemainingNeverGoesNegative() {
        // Un vocal accepté dans la tolérance (3 s) peut faire dépasser : la
        // ligne doit lire « Plus rien », pas « -2 s ».
        let credit = DailyCredit(usedMs: 303_000)
        XCTAssertEqual(credit.remainingMs, 0)
        XCTAssertEqual(credit.fraction, 1)
        XCTAssertTrue(credit.isExhausted)
    }

    func testFractionIsWhatTheTripHasAlreadyTold() {
        let credit = DailyCredit(usedMs: 100_000)
        XCTAssertEqual(credit.remainingMs, 200_000)
        XCTAssertEqual(credit.fraction, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertFalse(credit.isExhausted)
    }

    func testZeroLimitDoesNotDivideByZero() {
        let credit = DailyCredit(limitMs: 0, usedMs: 10)
        XCTAssertEqual(credit.fraction, 1)
        XCTAssertEqual(credit.remainingMs, 0)
    }

    func testASubscriberIsNeverExhausted() {
        // Il ne consomme rien du pot commun, même quand ses co-voyageurs l'ont
        // vidé : le crédit lu par un abonné dit « illimité », pas « épuisé ».
        let credit = DailyCredit(isUnlimited: true, usedMs: DailyCredit.Catalog.limitMs)
        XCTAssertFalse(credit.isExhausted)
        XCTAssertEqual(credit.phase, .calm)
        XCTAssertTrue(credit.allows(text: String(repeating: "a", count: 10_000)))
    }

    // MARK: - Pendant l'enregistrement

    func testRemainingWhileRecordingCountsWhatIsBeingSaid() {
        let credit = credit(remaining: 180_000)
        XCTAssertEqual(credit.remainingMs(whileRecording: 60_000), 120_000)
        XCTAssertEqual(credit.remainingMs(whileRecording: 200_000), 0)
        // Une horloge qui recule (un `currentTime` relu trop tôt) ne rend
        // jamais du crédit.
        XCTAssertEqual(credit.remainingMs(whileRecording: -5_000), 180_000)
    }

    func testPhasesFollowTheServedThresholds() {
        let full = credit(remaining: 300_000)
        XCTAssertEqual(full.phase(remainingMs: 30_001), .calm)
        XCTAssertEqual(full.phase(remainingMs: 30_000), .warning)
        XCTAssertEqual(full.phase(remainingMs: 5_001), .warning)
        XCTAssertEqual(full.phase(remainingMs: 5_000), .urgent)
        XCTAssertEqual(full.phase(remainingMs: 1), .urgent)
        XCTAssertEqual(full.phase(remainingMs: 0), .exhausted)
    }

    func testThresholdsTravelWithTheBalance() {
        // Si le serveur avance l'avertissement à une minute, l'app suit : les
        // seuils ne sont pas écrits dans la barre d'enregistrement.
        let credit = DailyCredit(usedMs: 0, warningRemainingMs: 60_000, urgentRemainingMs: 10_000)
        XCTAssertEqual(credit.phase(remainingMs: 45_000), .warning)
        XCTAssertEqual(credit.phase(remainingMs: 8_000), .urgent)
    }

    func testPhaseBeforeSpeaking() {
        XCTAssertEqual(credit(remaining: 120_000).phase, .calm)
        XCTAssertEqual(credit(remaining: 20_000).phase, .warning)
        XCTAssertEqual(credit(remaining: 0).phase, .exhausted)
        XCTAssertEqual(credit(remaining: 0, isUnlimited: true).phase, .calm)
    }

    func testConsumingIsTheEstimateHeldBetweenTwoAnswers() {
        let credit = credit(remaining: 10_000)

        let spent = credit.consuming(4_000)
        XCTAssertEqual(spent.remainingMs, 6_000)

        // Jamais au-delà de la limite : un vocal toléré ne fait pas descendre
        // le reste sous zéro.
        let over = credit.consuming(20_000)
        XCTAssertEqual(over.usedMs, DailyCredit.Catalog.limitMs)
        XCTAssertTrue(over.isExhausted)

        XCTAssertEqual(credit.consuming(0), credit)
        XCTAssertEqual(credit.consuming(-3), credit)

        let subscriber = DailyCredit(isUnlimited: true, usedMs: 1_000)
        XCTAssertEqual(subscriber.consuming(60_000), subscriber)
    }

    // MARK: - Moins d'une seconde

    /// Moins d'une seconde, c'est plus rien — la règle du serveur
    /// (`EXHAUSTION_SLACK_MS`). Hors ligne, un vocal arrêté à 0:59,6 sur une
    /// minute laissait 400 ms : le micro se rouvrait pour un vocal aussitôt
    /// coupé, que le serveur refusait ensuite. L'estimation s'arrondit à
    /// zéro, et un reste de 400 ms servi se lit épuisé.
    func testLessThanASecondLeftIsAnEmptyPot() {
        let spent = credit(remaining: 60_000).consuming(59_600)
        XCTAssertEqual(spent.remainingMs, 0, "Arrondi à zéro, comme le serveur le fera.")
        XCTAssertTrue(spent.isExhausted)
        XCTAssertEqual(spent.phase, .exhausted, "Le micro ne s'ouvre pas.")

        let crumbs = credit(remaining: 400)
        XCTAssertTrue(crumbs.isExhausted)
        XCTAssertEqual(crumbs.phase, .exhausted)
        XCTAssertFalse(crumbs.allows(text: "abc"), "Cinq caractères tiendraient dans 400 ms : le pot est vide quand même.")
        XCTAssertEqual(crumbs.charactersLeft, 0)

        // Une seconde pile reste une seconde.
        let second = credit(remaining: 1_000)
        XCTAssertFalse(second.isExhausted)
        XCTAssertEqual(second.phase, .urgent)
        XCTAssertEqual(credit(remaining: 2_000).consuming(1_000).remainingMs, 1_000)

        // Un abonné n'est jamais à court, quelques millisecondes ou pas.
        XCTAssertFalse(credit(remaining: 400, isUnlimited: true).isExhausted)
    }

    /// La règle voyage avec le solde quand le serveur la sert ; sinon, celle
    /// du catalogue.
    func testTheSlackTravelsWithTheBalance() throws {
        let served = try JSONDecoder.memoBook.decode(
            DailyCredit.self,
            from: Data(#"{"usedMs":299400,"exhaustionSlackMs":500}"#.utf8)
        )
        XCTAssertEqual(served.exhaustionSlackMs, 500)
        XCTAssertFalse(served.isExhausted, "600 ms, au-dessus du seuil servi.")

        let older = try JSONDecoder.memoBook.decode(DailyCredit.self, from: Data(#"{"usedMs":299400}"#.utf8))
        XCTAssertEqual(older.exhaustionSlackMs, 1_000)
        XCTAssertTrue(older.isExhausted)
    }

    // MARK: - Deux crédits gardés

    /// Le calendrier de Paris, et un instant du 3 octobre 2026.
    private var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    private func midnight(after day: Int) -> Date {
        paris.date(from: DateComponents(year: 2026, month: 10, day: day + 1))!
    }

    /// Le jour le plus tardif l'emporte, dans un sens comme dans l'autre :
    /// le crédit épuisé d'hier ne passe pas devant celui de ce matin.
    func testTheLaterDayWins() {
        let yesterday = DailyCredit(usedMs: 300_000, day: "2026-10-02", resetsAt: midnight(after: 2))
        let today = DailyCredit(usedMs: 60_000, day: "2026-10-03", resetsAt: midnight(after: 3))
        XCTAssertEqual(yesterday.merged(with: today), today)
        XCTAssertEqual(today.merged(with: yesterday), today)
    }

    /// Le même jour, le plus consommé l'emporte : la consommation d'une
    /// journée ne fait que croître. Le cache du matin (5:00) ne passe pas
    /// devant celui de l'accueil relu après un vocal de 4 minutes.
    func testOnTheSameDayTheMostSpentWins() {
        let morning = DailyCredit(usedMs: 0, day: "2026-10-03", resetsAt: midnight(after: 3))
        let afternoon = DailyCredit(usedMs: 240_000, day: "2026-10-03", resetsAt: midnight(after: 3))
        XCTAssertEqual(morning.merged(with: afternoon).remainingMs, 60_000)
        XCTAssertEqual(afternoon.merged(with: morning).remainingMs, 60_000)
    }

    /// Illimité dès que l'un des deux le dit : un crédit servi avant l'achat
    /// ne le sait pas encore.
    func testUnlimitedAsSoonAsOneSaysSo() {
        let before = DailyCredit(usedMs: 240_000, day: "2026-10-03", resetsAt: midnight(after: 3))
        let after = DailyCredit(isUnlimited: true, usedMs: 0, day: "2026-10-03", resetsAt: midnight(after: 3))
        let merged = before.merged(with: after)
        XCTAssertTrue(merged.isUnlimited)
        XCTAssertEqual(merged.usedMs, 240_000, "Le compte du voyage reste le plus avancé.")
        XCTAssertTrue(after.merged(with: before).isUnlimited)
    }

    /// Un crédit rechargé n'a plus de `day` : il se range par son heure de
    /// recharge. Plus tardive, elle l'emporte sur hier ; égale, c'est de
    /// nouveau le plus consommé.
    func testARefreshedCreditIsRankedByItsRecharge() {
        let morning = paris.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 9))!
        let yesterday = DailyCredit(usedMs: 300_000, day: "2026-10-02", resetsAt: midnight(after: 2))
        let refreshed = yesterday.refreshed(now: morning, calendar: paris)
        XCTAssertNil(refreshed.day)
        XCTAssertEqual(yesterday.merged(with: refreshed).usedMs, 0)
        XCTAssertEqual(refreshed.merged(with: yesterday).usedMs, 0)

        let servedToday = DailyCredit(usedMs: 120_000, day: "2026-10-03", resetsAt: midnight(after: 3))
        XCTAssertEqual(refreshed.merged(with: servedToday), servedToday)
        XCTAssertEqual(servedToday.merged(with: refreshed), servedToday)
    }

    func testMergingWithNothingKeepsWhatWeHave() {
        let known = credit(remaining: 90_000)
        XCTAssertEqual(known.merged(with: nil), known)
        // Ni jour ni recharge : le plus consommé, faute de mieux.
        XCTAssertEqual(DailyCredit(usedMs: 10).merged(with: DailyCredit(usedMs: 20)).usedMs, 20)
    }

    // MARK: - Un crédit gardé

    /// Un crédit gardé de la veille repart plein : épuisé à 22 h 30, il ne
    /// bloque plus le micro le lendemain matin, même hors ligne. Le barème et
    /// l'abonnement restent ; la recharge suivante est le même minuit, un
    /// jour plus tard.
    func testAKeptCreditFromYesterdayIsRefreshed() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4))!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 9))!
        let yesterday = DailyCredit(
            limitMs: 300_000,
            usedMs: 300_000,
            textMsPerCharacter: 60,
            day: "2026-10-03",
            resetsAt: midnight
        )

        let refreshed = yesterday.refreshed(now: morning, calendar: calendar)
        XCTAssertEqual(refreshed.usedMs, 0)
        XCTAssertFalse(refreshed.isExhausted)
        XCTAssertEqual(refreshed.textMsPerCharacter, 60, "Le barème servi reste.")
        XCTAssertNil(refreshed.day, "Le jour du serveur ne s'invente pas.")
        XCTAssertEqual(refreshed.resetsAt, calendar.date(from: DateComponents(year: 2026, month: 10, day: 5)))

        // Ce qu'on consomme ensuite n'est pas effacé par une seconde lecture.
        let spent = refreshed.consuming(60_000)
        XCTAssertEqual(spent.refreshed(now: morning, calendar: calendar), spent)

        // Gardé plusieurs jours : la recharge suivante reste devant.
        let weekLater = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 23, minute: 59))!
        XCTAssertEqual(
            yesterday.refreshed(now: weekLater, calendar: calendar).resetsAt,
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 11))
        )
    }

    /// Un crédit d'aujourd'hui, ou sans heure de recharge, se lit tel quel.
    func testATodayCreditIsLeftAlone() {
        let resetsAt = Date.now.addingTimeInterval(3_600)
        let today = DailyCredit(usedMs: 120_000, resetsAt: resetsAt)
        XCTAssertEqual(today.refreshed(now: .now), today)
        let undated = DailyCredit(usedMs: 120_000)
        XCTAssertEqual(undated.refreshed(now: .now), undated)
        let subscriber = DailyCredit(isUnlimited: true, usedMs: 0, resetsAt: Date.now.addingTimeInterval(-60))
        XCTAssertTrue(subscriber.refreshed(now: .now).isUnlimited)
    }

    /// Le plus long tour qu'une journée laisse passer : la limite, et la
    /// tolérance du serveur pour un vocal.
    func testTheLongestTurnADayAllows() {
        let credit = DailyCredit()
        XCTAssertEqual(credit.limitWithTolerance(forVoice: true), 303_000)
        XCTAssertEqual(credit.limitWithTolerance(forVoice: false), 300_000)
    }

    // MARK: - L'écrit

    func testATextCostsSeventyFiveMillisecondsPerCharacter() {
        let credit = DailyCredit()
        XCTAssertEqual(credit.cost(ofText: "abc"), 225)
        // 800 caractères valent une minute ; 4 000, tout le crédit.
        XCTAssertEqual(credit.cost(ofText: String(repeating: "a", count: 800)), 60_000)
        XCTAssertEqual(credit.cost(ofText: String(repeating: "a", count: 4_000)), 300_000)
    }

    func testCharactersAreCountedInUnicodeScalarsLikeTheServer() {
        // Le serveur compte `[...text].length` : des scalaires Unicode, ni des
        // graphèmes (`count`), ni des unités UTF-16 (`utf16.count`).
        let credit = DailyCredit()

        let decomposed = "e\u{301}"  // « é » en deux scalaires
        XCTAssertEqual(decomposed.count, 1)
        XCTAssertEqual(credit.cost(ofText: decomposed), 150)

        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"  // une famille : trois personnes, deux liants
        XCTAssertEqual(family.count, 1)
        XCTAssertEqual(family.utf16.count, 8)
        XCTAssertEqual(credit.cost(ofText: family), 5 * 75)
    }

    func testATextLongerThanTheRestDoesNotLeave() {
        let credit = credit(remaining: 60_000)
        XCTAssertTrue(credit.allows(text: String(repeating: "a", count: 800)))
        XCTAssertFalse(credit.allows(text: String(repeating: "a", count: 801)))
    }

    func testCharactersLeft() {
        XCTAssertEqual(credit(remaining: 180_000).charactersLeft, 2_400)
        XCTAssertEqual(credit(remaining: 74).charactersLeft, 0)
        XCTAssertEqual(DailyCredit(textMsPerCharacter: 0).charactersLeft, 0)
    }

    // MARK: - Le décodage

    func testDecodesTheServedObject() throws {
        let json = Data(
            #"""
            {
              "isUnlimited": false,
              "limitMs": 300000,
              "usedMs": 120000,
              "remainingMs": 180000,
              "textMsPerCharacter": 75,
              "warningRemainingMs": 30000,
              "urgentRemainingMs": 5000,
              "day": "2026-10-03",
              "resetsAt": "2026-10-03T22:00:00.000Z"
            }
            """#.utf8
        )
        let credit = try JSONDecoder.memoBook.decode(DailyCredit.self, from: json)

        XCTAssertFalse(credit.isUnlimited)
        XCTAssertEqual(credit.usedMs, 120_000)
        XCTAssertEqual(credit.remainingMs, 180_000)
        XCTAssertEqual(credit.day, "2026-10-03")
        XCTAssertEqual(credit.resetsAt, ISO8601DateFormatter.memoBookDate(from: "2026-10-03T22:00:00.000Z"))
    }

    func testDecodesAServerThatDoesNotServeTheScaleYet() throws {
        // Un serveur plus ancien ne doit faire tomber ni le fil ni les
        // réglages : on retombe sur le barème du catalogue.
        let json = Data(#"{"usedMs":42000}"#.utf8)
        let credit = try JSONDecoder.memoBook.decode(DailyCredit.self, from: json)

        XCTAssertFalse(credit.isUnlimited)
        XCTAssertEqual(credit.usedMs, 42_000)
        XCTAssertEqual(credit.limitMs, 300_000)
        XCTAssertEqual(credit.textMsPerCharacter, 75)
        XCTAssertEqual(credit.warningRemainingMs, 30_000)
        XCTAssertEqual(credit.urgentRemainingMs, 5_000)
        XCTAssertNil(credit.resetsAt)
    }

    func testAnUnreadableResetDateDoesNotSinkTheCredit() throws {
        let json = Data(#"{"usedMs":1000,"resetsAt":"demain"}"#.utf8)
        let credit = try JSONDecoder.memoBook.decode(DailyCredit.self, from: json)
        XCTAssertEqual(credit.usedMs, 1_000)
        XCTAssertNil(credit.resetsAt)
    }

    func testTripSettingsReadTheNewKeyAndIgnoreTheOldOne() throws {
        // Le cache disque garde des réglages lus avant le crédit du jour, avec
        // leurs limites de souvenirs sous `memory`. Ils ne doivent pas se
        // relire comme un crédit plein inventé.
        let old = Data(
            #"""
            { "tripId": "t", "name": "Rome", "walletBalance": 0,
              "memory": { "plan": "included", "used": 312, "allowance": 2000 },
              "wantsNotifications": true, "notifications": {}, "companions": [],
              "isPublicGallery": false, "isPrintable": false }
            """#.utf8
        )
        XCTAssertNil(try JSONDecoder.memoBook.decode(TripSettings.self, from: old).dailyCredit)

        let new = Data(
            #"""
            { "tripId": "t", "name": "Rome", "walletBalance": 0,
              "dailyCredit": { "isUnlimited": true, "usedMs": 0 },
              "wantsNotifications": true, "notifications": {}, "companions": [],
              "isPublicGallery": false, "isPrintable": false }
            """#.utf8
        )
        let settings = try JSONDecoder.memoBook.decode(TripSettings.self, from: new)
        XCTAssertEqual(settings.dailyCredit?.isUnlimited, true)
    }

    // MARK: - Les textes

    func testDurations() {
        XCTAssertEqual(DailyCreditCopy.duration(300_000), "5 min")
        XCTAssertEqual(DailyCreditCopy.duration(200_000), "3 min 20")
        XCTAssertEqual(DailyCreditCopy.duration(185_000), "3 min 05")
        XCTAssertEqual(DailyCreditCopy.duration(45_000), "45 s")
        // Arrondi à la seconde inférieure : on n'annonce pas une demi-seconde
        // qui n'existe pas.
        XCTAssertEqual(DailyCreditCopy.duration(29_600), "29 s")
        XCTAssertEqual(DailyCreditCopy.duration(-1_000), "0 s")
    }

    func testCharactersUseTheFrenchThousandsSeparator() {
        XCTAssertEqual(DailyCreditCopy.characters(1), "1 caractère")
        XCTAssertEqual(DailyCreditCopy.characters(800), "800 caractères")
        let thousands = DailyCreditCopy.characters(2_650)
        XCTAssertTrue(thousands.hasPrefix("2"))
        XCTAssertTrue(thousands.hasSuffix("650 caractères"))
        XCTAssertFalse(thousands.contains(","))
    }

    func testRowSaysWhatIsLeftOrUnlimited() {
        XCTAssertEqual(DailyCreditCopy.rowValue(credit(remaining: 200_000)), "3 min 20 restantes")
        XCTAssertEqual(DailyCreditCopy.rowValue(credit(remaining: 60_000)), "1 min restante")
        XCTAssertEqual(DailyCreditCopy.rowValue(credit(remaining: 45_000)), "45 s restantes")
        XCTAssertEqual(DailyCreditCopy.rowValue(credit(remaining: 0)), "Épuisé")
        XCTAssertEqual(DailyCreditCopy.rowValue(credit(remaining: 0, isUnlimited: true)), "Illimité")
        XCTAssertEqual(
            DailyCreditCopy.rowCaption(limitMs: 300_000),
            "5 min par jour pour tout le voyage"
        )
    }

    func testSheetSaysWhatIsLeftToday() {
        XCTAssertEqual(
            DailyCreditCopy.Sheet.remaining(credit(remaining: 200_000)),
            "Il reste 3 min 20 aujourd’hui"
        )
        XCTAssertEqual(
            DailyCreditCopy.Sheet.remaining(credit(remaining: 0)),
            "Plus rien pour aujourd’hui : reviens demain"
        )
        XCTAssertNil(DailyCreditCopy.Sheet.charactersEquivalent(credit(remaining: 0)))
        XCTAssertEqual(
            DailyCreditCopy.Sheet.charactersEquivalent(credit(remaining: 60_000)),
            "soit environ 800 caractères à l’écrit"
        )
    }

    func testSheetReadsTheScaleFromTheBalance() {
        XCTAssertEqual(
            DailyCreditCopy.Sheet.sharing(limitMs: 300_000),
            "5 minutes par jour pour ce voyage, à partager entre les co-voyageurs qui ne sont pas abonnés."
        )
        XCTAssertTrue(
            DailyCreditCopy.Sheet.consumption(textMsPerCharacter: 75).contains("800 caractères valent une minute")
        )
        XCTAssertEqual(DailyCreditCopy.Sheet.spelledDuration(60_000), "1 minute")
        XCTAssertEqual(DailyCreditCopy.Sheet.spelledDuration(90_000), "1 min 30")
        XCTAssertTrue(DailyCreditCopy.Sheet.unlimitedExplanation(limitMs: 300_000).contains("les 5 minutes du jour"))
    }

    func testWarningCountsDown() {
        XCTAssertEqual(
            DailyCreditCopy.warning(remainingMs: 30_000),
            "Plus que 30 secondes avant la limite du jour"
        )
        XCTAssertEqual(
            DailyCreditCopy.warning(remainingMs: 1_400),
            "Plus qu’une seconde avant la limite du jour"
        )
    }

    func testVisibleTextsUseTheTypographicApostrophe() {
        let texts = [
            DailyCreditCopy.exhaustedMessage,
            DailyCreditCopy.exhaustedDetail,
            DailyCreditCopy.rowCaptionUnlimited,
            DailyCreditCopy.textTooLong(charactersLeft: 0),
            DailyCreditCopy.textTooLong(charactersLeft: 120),
            DailyCreditCopy.Sheet.recharge,
            DailyCreditCopy.Sheet.remaining(DailyCredit()),
            DailyCreditCopy.Sheet.consumption(textMsPerCharacter: 75),
            DailyCreditCopy.Sheet.unlimitedExplanation(limitMs: 300_000),
        ]
        for text in texts {
            XCTAssertFalse(text.contains("'"), "apostrophe droite dans « \(text) »")
            XCTAssertFalse(text.localizedCaseInsensitiveContains("jeton"), text)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("token"), text)
        }
    }
}
