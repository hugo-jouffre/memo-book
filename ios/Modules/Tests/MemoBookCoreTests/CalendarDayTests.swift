import XCTest

@testable import MemoBookCore

/// Un jour sans heure ni fuseau : la date de naissance des « Dernières
/// questions ». Ce qui compte ici, c'est qu'un jour qui n'existe pas ne se
/// crée pas, et qu'il traverse le serveur sans reculer d'un jour.
final class CalendarDayTests: XCTestCase {
    func testReadsWhatIsTypedAndWhatTheServerSends() throws {
        let typed = try XCTUnwrap(CalendarDay(slashed: "12/05/1994"))
        XCTAssertEqual(typed.iso, "1994-05-12")
        XCTAssertEqual(CalendarDay(iso: "1994-05-12"), typed)
        XCTAssertEqual(typed.slashed, "12/05/1994")
    }

    func testRefusesADayThatDoesNotExist() {
        XCTAssertNil(CalendarDay(slashed: "30/02/1994"))
        XCTAssertNil(CalendarDay(slashed: "12/13/1994"))
        XCTAssertNil(CalendarDay(slashed: "1/5/1994"))
        XCTAssertNil(CalendarDay(iso: "1994-5-12"))
        XCTAssertNotNil(CalendarDay(slashed: "29/02/2000"))
    }

    func testABirthDateIsNeitherInTheFutureNorBefore1900() throws {
        let today = try XCTUnwrap(CalendarDay(year: 2026, month: 9, day: 26))
        XCTAssertTrue(try XCTUnwrap(CalendarDay(year: 1994, month: 5, day: 12)).isPlausibleBirthDate(today: today))
        XCTAssertTrue(today.isPlausibleBirthDate(today: today))
        XCTAssertFalse(try XCTUnwrap(CalendarDay(year: 2026, month: 9, day: 27)).isPlausibleBirthDate(today: today))
        XCTAssertFalse(try XCTUnwrap(CalendarDay(year: 1899, month: 12, day: 31)).isPlausibleBirthDate(today: today))
    }

    /// Le jour part et revient en `AAAA-MM-JJ` : c'est ce qui l'empêche de
    /// reculer d'un jour dans un fuseau à l'ouest de Greenwich.
    func testCodesAsTheServerDay() throws {
        let day = try XCTUnwrap(CalendarDay(year: 1994, month: 5, day: 12))
        let data = try JSONEncoder.memoBook.encode([day])
        XCTAssertEqual(String(data: data, encoding: .utf8), #"["1994-05-12"]"#)
        XCTAssertEqual(try JSONDecoder.memoBook.decode([CalendarDay].self, from: data), [day])
    }

    /// La date du profil se lit comme un jour ; une forme illisible ne fait
    /// pas tomber le profil — la date manque, c'est tout.
    func testTheProfileReadsItsBirthDateAndSurvivesAnUnreadableOne() throws {
        func profile(birthDate: String) throws -> TravellerProfile {
            let json = """
                {
                  "fullName": "Camille Dupont",
                  "birthDate": "\(birthDate)",
                  "address": { "street": "7 Rue", "postalCode": "69007", "city": "Lyon", "country": "France" },
                  "wantsNewsletter": false,
                  "walletBalance": 0,
                  "cards": [],
                  "connectors": [],
                  "subscription": { "weeklyPrice": 1.99, "isActive": false, "cancelledAt": null, "paidThrough": null, "hasEndedBefore": false },
                  "orders": []
                }
                """
            return try JSONDecoder.memoBook.decode(TravellerProfile.self, from: Data(json.utf8))
        }

        XCTAssertEqual(try profile(birthDate: "1994-05-12").birthDate, CalendarDay(year: 1994, month: 5, day: 12))
        let unreadable = try profile(birthDate: "le 12 mai")
        XCTAssertNil(unreadable.birthDate)
        XCTAssertEqual(unreadable.fullName, "Camille Dupont")
    }
}
