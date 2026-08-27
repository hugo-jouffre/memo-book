import XCTest

@testable import MemoBookCore

/// La politique de mot de passe et la validation d'email vivent en double :
/// ici pour le retour immédiat sous le champ, et dans
/// `backend/src/lib/password.ts` pour la garantie. Les deux doivent dire la
/// même chose, sinon l'app promet ce que le serveur refuse.
final class PasswordPolicyTests: XCTestCase {
    func testAccepteUnMotDePasseConforme() {
        XCTAssertNil(PasswordPolicy.check("carnet2026"))
    }

    func testRefuseUnMotDePasseTropCourt() {
        XCTAssertEqual(PasswordPolicy.check("cara26"), .tooShort)
    }

    func testRefuseUnMotDePasseSansChiffre() {
        XCTAssertEqual(PasswordPolicy.check("moncarnetdevoyage"), .needsLetterAndDigit)
    }

    func testRefuseUnMotDePasseSansLettre() {
        XCTAssertEqual(PasswordPolicy.check("20262026"), .needsLetterAndDigit)
    }

    func testRefuseUnMotDePasseDemesure() {
        let long = String(repeating: "a1", count: 200)
        XCTAssertEqual(PasswordPolicy.check(long), .tooLong)
    }

    func testLesMessagesTutoient() {
        for problem in [
            PasswordPolicy.Problem.tooShort,
            .tooLong,
            .needsLetterAndDigit,
        ] {
            XCTAssertTrue(
                problem.message.contains("Ton mot de passe"),
                "R9 : l'app tutoie, y compris dans ses messages d'erreur."
            )
        }
    }
}

final class EmailValidationTests: XCTestCase {
    func testAccepteUneAdresseCourante() {
        XCTAssertTrue(EmailValidation.isValid("cla.thioll@gmail.com"))
    }

    func testAccepteLeRelaisApple() {
        XCTAssertTrue(EmailValidation.isValid("xk29fj@privaterelay.appleid.com"))
    }

    func testRefuseLesFautesDeFrappeCourantes() {
        XCTAssertFalse(EmailValidation.isValid("cla.thioll@gmail"))
        XCTAssertFalse(EmailValidation.isValid("cla.thioll gmail.com"))
        XCTAssertFalse(EmailValidation.isValid("@gmail.com"))
        XCTAssertFalse(EmailValidation.isValid("cla@@gmail.com"))
        XCTAssertFalse(EmailValidation.isValid(""))
    }

    func testRangeLAdresseEnMinuscules() {
        XCTAssertEqual(
            EmailValidation.normalize("  Cla.Thioll@GMAIL.com "),
            "cla.thioll@gmail.com"
        )
    }
}

final class SocialProfileDraftTests: XCTestCase {
    func testReconnaitUneAdresseRelaisApple() {
        let draft = SocialProfileDraft(
            socialToken: "apple:001",
            provider: .apple,
            firstName: nil,
            lastName: nil,
            email: "XK29FJ@PrivateRelay.AppleID.com"
        )

        XCTAssertTrue(draft.usesAppleRelayEmail)
    }

    func testUneAdressePersonnelleNEstPasUnRelais() {
        let draft = SocialProfileDraft(
            socialToken: "google:g-42",
            provider: .google,
            firstName: "Cla",
            lastName: "Thioll",
            email: "cla.thioll@gmail.com"
        )

        XCTAssertFalse(draft.usesAppleRelayEmail)
    }
}
