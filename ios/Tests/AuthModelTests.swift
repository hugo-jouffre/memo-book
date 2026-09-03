@testable import MemoBookFeature
import MemoBookNetworking
import XCTest

/// Les règles qui décident si « Continuer » s'allume. Elles vivent dans le
/// modèle précisément pour être vérifiables ici, sans simulateur.
@MainActor
final class AuthModelTests: XCTestCase {
    /// Ces règles sont purement locales : elles décident si « Continuer »
    /// s'allume, avant tout appel. L'API n'est là que parce que le modèle en
    /// exige une.
    private func model(_ configure: (AuthModel) -> Void) -> AuthModel {
        let model = AuthModel(api: PreviewAPI(seeded: false))
        configure(model)
        return model
    }

    // MARK: - Email

    func testEmailNeedsAnAtSignAndADottedHost() {
        let cases: [(String, Bool)] = [
            ("hugo@memobook.app", true),
            ("hugo+voyage@memo.book.app", true),
            ("hugo@memobook", false),
            ("hugo.memobook.app", false),
            ("@memobook.app", false),
            ("hugo@.app", false),
            ("hugo@memobook.", false),
            ("", false),
        ]

        for (email, expected) in cases {
            let model = model { $0.email = email }
            XCTAssertEqual(model.isEmailValid, expected, "« \(email) »")
        }
    }

    // MARK: - Mot de passe

    func testPasswordNeedsEightCharactersALetterAndADigit() {
        let cases: [(String, Bool)] = [
            ("carnet2026", true),
            ("a1bcdefg", true),
            ("carnet26", true),
            ("carnets", false),  // trop court et sans chiffre
            ("carnetsdevoyage", false),  // pas de chiffre
            ("20260903", false),  // pas de lettre
            ("a1bcdef", false),  // sept caractères
        ]

        for (password, expected) in cases {
            let model = model { $0.password = password }
            XCTAssertEqual(model.isPasswordValid, expected, "« \(password) »")
        }
    }

    func testConfirmationErrorOnlyShowsOnceSomethingIsTyped() {
        let model = model {
            $0.password = "carnet2026"
        }
        XCTAssertNil(model.passwordConfirmationError, "Rien à signaler tant que le champ est vide.")

        model.passwordConfirmation = "carnet20"
        XCTAssertNotNil(model.passwordConfirmationError)

        model.passwordConfirmation = "carnet2026"
        XCTAssertNil(model.passwordConfirmationError)
    }

    // MARK: - Ce que « Continuer » attend

    func testSignUpNeedsEveryField() {
        let model = model {
            $0.mode = .signUp
            $0.firstName = "Hugo"
            $0.lastName = "Jouffre"
            $0.email = "hugo@memobook.app"
            $0.password = "carnet2026"
            $0.passwordConfirmation = "carnet2026"
        }
        XCTAssertTrue(model.canSubmit)

        model.passwordConfirmation = "carnet2027"
        XCTAssertFalse(model.canSubmit, "Deux mots de passe différents bloquent l'envoi.")

        model.passwordConfirmation = "carnet2026"
        model.firstName = "   "
        XCTAssertFalse(model.canSubmit, "Un prénom fait d'espaces ne compte pas.")
    }

    func testSignInOnlyNeedsAnEmailAndAPassword() {
        let model = model {
            $0.mode = .signIn
            $0.email = "hugo@memobook.app"
            $0.password = "x"
        }
        // À la connexion on ne rejoue pas la règle de complexité : le mot de
        // passe a pu être créé sous d'autres règles, c'est au serveur de dire
        // s'il est bon.
        XCTAssertTrue(model.canSubmit)

        model.email = "hugo@memobook"
        XCTAssertFalse(model.canSubmit)
    }

    func testSwitchingModeReusesWhatWasAlreadyTyped() {
        let model = model {
            $0.mode = .signUp
            $0.email = "hugo@memobook.app"
            $0.password = "carnet2026"
        }
        XCTAssertFalse(model.canSubmit, "Il manque le nom et la confirmation.")

        model.mode = .signIn
        XCTAssertTrue(model.canSubmit, "L'email et le mot de passe suffisent en connexion.")
    }

    // MARK: - Estompage des fournisseurs tiers

    func testTheSocialSectionOnlyFadesOnceSomethingIsTyped() {
        let fresh = model { $0.mode = .signUp }
        XCTAssertFalse(fresh.hasStartedFilling, "Formulaire vierge : les trois chemins se valent.")

        for keystroke in [\AuthModel.firstName, \.lastName, \.email, \.password, \.passwordConfirmation] {
            let model = model { $0[keyPath: keystroke] = "x" }
            XCTAssertTrue(model.hasStartedFilling, "N'importe quel champ suffit à faire un choix.")
        }
    }

    func testTheNamesTypedInSignUpDoNotFadeTheSignInScreen() {
        // Le prénom et le nom n'ont pas de champ en connexion : ce qui y a été
        // tapé ne doit pas estomper un écran où il ne se voit plus.
        let model = model {
            $0.firstName = "Hugo"
            $0.mode = .signIn
        }
        XCTAssertFalse(model.hasStartedFilling)
    }

    // MARK: - Enchaînement du clavier

    func testKeyboardChainsThroughTheVisibleFieldsOnly() {
        let signUp = model { $0.mode = .signUp }
        XCTAssertEqual(signUp.fieldAfter(.firstName), .lastName)
        XCTAssertEqual(signUp.fieldAfter(.lastName), .email)
        XCTAssertEqual(signUp.fieldAfter(.email), .password)
        XCTAssertEqual(signUp.fieldAfter(.password), .passwordConfirmation)
        XCTAssertNil(signUp.fieldAfter(.passwordConfirmation), "Dernier champ : on valide.")

        let signIn = model { $0.mode = .signIn }
        XCTAssertEqual(signIn.fieldAfter(.email), .password)
        XCTAssertNil(signIn.fieldAfter(.password))
        XCTAssertNil(signIn.fieldAfter(.firstName), "Le prénom n'existe pas en connexion.")
    }
}
