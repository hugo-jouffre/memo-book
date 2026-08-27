import MemoBookCore
import MemoBookNetworking
import XCTest

@testable import MemoBookFeature

/// Le routage du flow d'entrée, tel que le détail fonctionnel le décrit.
@MainActor
final class OnboardingFlowTests: XCTestCase {
    private func makeModel(
        api: PreviewAPI = PreviewAPI(seeded: false),
        hasSeenOnboarding: Bool = false
    ) -> (OnboardingModel, PreviewAPI) {
        let sessions = InMemorySessionStore(hasSeenOnboarding: hasSeenOnboarding)
        // Plancher et plafond ramenés à presque rien : ce sont les décisions de
        // routage qu'on teste, pas la durée d'affichage du logo.
        let model = OnboardingModel(
            api: api,
            sessions: sessions,
            minimumSplashDuration: .milliseconds(1),
            maximumSplashDuration: .seconds(2)
        )
        return (model, api)
    }

    func testLePremierLancementMontreLeWelcome() async {
        let (model, _) = makeModel()

        await model.start()

        XCTAssertEqual(model.step, .welcome)
    }

    func testUnRetourApresOnboardingVaSurLaConnexion() async {
        let (model, _) = makeModel(hasSeenOnboarding: true)

        await model.start()

        XCTAssertEqual(model.step, .credentials(.signIn))
    }

    func testLeCtaDecouvreMemoBookOuvreLInscriptionEtMarqueLeFlag() {
        let sessions = InMemorySessionStore()
        let model = OnboardingModel(api: PreviewAPI(seeded: false), sessions: sessions)

        model.discoverMemoBook()

        XCTAssertEqual(model.step, .credentials(.signUp))
        XCTAssertTrue(
            sessions.hasSeenOnboarding,
            "Le flag passe à true dès le passage sur le Welcome, pas à l'inscription."
        )
    }

    func testLEmailSuitDeLaConnexionVersMotDePasseOublie() {
        let (model, _) = makeModel()

        model.forgotPassword(email: "cla.thioll@gmail.com")

        XCTAssertEqual(model.step, .forgotPassword)
        XCTAssertEqual(model.carriedEmail, "cla.thioll@gmail.com")
    }

    func testLeLienDeReinitialisationPorteSonJeton() {
        let (model, _) = makeModel()

        XCTAssertTrue(
            model.open(deepLink: URL(string: "memobook://reset-password?token=abc123")!)
        )
        XCTAssertEqual(model.step, .resetPassword(token: "abc123"))
    }

    func testUnLienIncompletEstIgnore() {
        let (model, _) = makeModel()

        XCTAssertFalse(model.open(deepLink: URL(string: "memobook://reset-password")!))
        XCTAssertFalse(model.open(deepLink: URL(string: "memobook://reset-password?token=")!))
        XCTAssertFalse(model.open(deepLink: URL(string: "https://memobook.app/reset")!))
        XCTAssertEqual(model.step, .splash)
    }
}

/// Le formulaire de *Sign Up* et de *Login*.
@MainActor
final class CredentialsModelTests: XCTestCase {
    private func makeModel(tab: AuthTab) -> (CredentialsModel, OnboardingModel, PreviewAPI) {
        let api = PreviewAPI(seeded: false)
        let onboarding = OnboardingModel(api: api, sessions: InMemorySessionStore())
        let model = CredentialsModel(
            api: api,
            onboarding: onboarding,
            tab: tab,
            social: PreviewSocialSignInBroker()
        )
        return (model, onboarding, api)
    }

    func testLeCtaResteInactifTantQueLesChampsSontVides() {
        let (model, _, _) = makeModel(tab: .signUp)

        XCTAssertFalse(model.canSubmit)

        model.firstName = "Cla"
        model.lastName = "Thioll"
        model.email = "cla.thioll@gmail.com"
        model.password = "carnet2026"
        XCTAssertFalse(model.canSubmit, "La confirmation manque encore.")

        model.passwordConfirmation = "carnet2026"
        XCTAssertTrue(model.canSubmit)
    }

    func testLesErreursDeValidationSAffichentSousLeChampConcerne() async {
        let (model, _, _) = makeModel(tab: .signUp)
        model.firstName = "Cla"
        model.lastName = "Thioll"
        model.email = "cla.thioll@gmail"
        model.password = "court"
        model.passwordConfirmation = "autre"

        await model.submit()

        XCTAssertNotNil(model.fieldErrors[.email])
        XCTAssertNotNil(model.fieldErrors[.password])
        XCTAssertNotNil(model.fieldErrors[.passwordConfirmation])
        XCTAssertNil(model.formError, "Rien ne s'affiche en pop-up ni en bandeau ici.")
    }

    func testUneInscriptionReussieTermineLeFlow() async {
        let (model, onboarding, _) = makeModel(tab: .signUp)
        model.firstName = "Cla"
        model.lastName = "Thioll"
        model.email = "cla.thioll@gmail.com"
        model.password = "carnet2026"
        model.passwordConfirmation = "carnet2026"

        await model.submit()

        XCTAssertEqual(onboarding.step, .home)
    }

    func testUnEmailDejaPrisSAfficheSousLeChampSansViderLeFormulaire() async {
        let (model, _, api) = makeModel(tab: .signUp)
        _ = try? await api.signUp(
            NewAccount(
                firstName: "Cla",
                lastName: "Thioll",
                email: "cla.thioll@gmail.com",
                password: "carnet2026"
            )
        )

        model.firstName = "Claire"
        model.lastName = "Thiollier"
        model.email = "cla.thioll@gmail.com"
        model.password = "carnet2026"
        model.passwordConfirmation = "carnet2026"
        await model.submit()

        XCTAssertNotNil(model.fieldErrors[.email])
        XCTAssertEqual(model.firstName, "Claire", "La saisie ne doit jamais être perdue.")
    }

    func testUnEchecDeConnexionOuvreLaModaleEtGardeLEmail() async {
        let (model, onboarding, _) = makeModel(tab: .signIn)
        model.email = "personne@exemple.fr"
        model.password = "carnet2026"

        await model.submit()

        XCTAssertNotNil(onboarding.signInFailure)
        XCTAssertEqual(model.email, "personne@exemple.fr")
    }

    func testUneConnexionTierceInconnueDemandeDeCompleterLeProfil() async {
        let (model, onboarding, _) = makeModel(tab: .signUp)

        await model.signIn(with: .apple)

        guard case .completeProfile(let draft) = onboarding.step else {
            return XCTFail("Un compte tiers inconnu passe par *Complète tes informations*.")
        }
        XCTAssertEqual(draft.provider, .apple)
    }

    func testUneConnexionTierceAnnuleeNeDitRien() async {
        let api = PreviewAPI(seeded: false)
        let onboarding = OnboardingModel(api: api, sessions: InMemorySessionStore())
        let model = CredentialsModel(
            api: api,
            onboarding: onboarding,
            tab: .signUp,
            social: PreviewSocialSignInBroker(cancels: true)
        )

        await model.signIn(with: .apple)

        XCTAssertNil(model.formError, "Refuser l'autorisation est un choix, pas une erreur.")
        XCTAssertEqual(onboarding.step, .splash)
    }

    func testUnBoutonTiersNonIntegreLeDitPlutotQueDEchouerEnSilence() async {
        let api = PreviewAPI(seeded: false)
        let onboarding = OnboardingModel(api: api, sessions: InMemorySessionStore())
        let model = CredentialsModel(api: api, onboarding: onboarding, tab: .signUp)

        await model.signIn(with: .google)

        XCTAssertNotNil(model.formError)
    }
}

/// Les trois écrans de mot de passe.
@MainActor
final class PasswordResetTests: XCTestCase {
    func testUneAdresseSansCompteBasculeSurLEcranQuiProposeDenCreerUn() async {
        let api = PreviewAPI(seeded: false)
        let onboarding = OnboardingModel(api: api, sessions: InMemorySessionStore())
        onboarding.forgotPassword(email: "personne@exemple.fr")

        let model = ForgotPasswordModel(api: api, onboarding: onboarding)
        await model.submit()

        XCTAssertEqual(
            onboarding.step,
            .forgotPasswordNoAccount(email: "personne@exemple.fr")
        )
    }

    func testUneAdresseConnueRepartSurLaConnexionSansAttendreLEnvoi() async {
        let api = PreviewAPI(seeded: false)
        _ = try? await api.signUp(
            NewAccount(
                firstName: "Cla",
                lastName: "Thioll",
                email: "cla.thioll@gmail.com",
                password: "carnet2026"
            )
        )

        let onboarding = OnboardingModel(api: api, sessions: InMemorySessionStore())
        onboarding.forgotPassword(email: "cla.thioll@gmail.com")

        let model = ForgotPasswordModel(api: api, onboarding: onboarding)
        await model.submit()

        XCTAssertEqual(onboarding.step, .credentials(.signIn))
    }

    func testUnLienMortLaisseUneSortieVersLaConnexion() async {
        let api = PreviewAPI(seeded: false)
        let onboarding = OnboardingModel(api: api, sessions: InMemorySessionStore())
        let model = ResetPasswordModel(token: "perime", api: api, onboarding: onboarding)

        model.password = "nouveaucarnet2026"
        model.confirmation = "nouveaucarnet2026"
        await model.submit()

        XCTAssertNotNil(model.linkError)

        model.backToSignIn()
        XCTAssertEqual(onboarding.step, .credentials(.signIn))
    }

    func testLesDeuxMotsDePasseDoiventEtreIdentiques() async {
        let api = PreviewAPI(seeded: false)
        let onboarding = OnboardingModel(api: api, sessions: InMemorySessionStore())
        let model = ResetPasswordModel(token: "jeton", api: api, onboarding: onboarding)

        model.password = "nouveaucarnet2026"
        model.confirmation = "autrecarnet2026"
        await model.submit()

        XCTAssertNotNil(model.confirmationError)
    }
}

/// *Complète tes informations*.
@MainActor
final class CompleteProfileTests: XCTestCase {
    private let draft = SocialProfileDraft(
        socialToken: "apple:001.abcdef",
        provider: .apple,
        firstName: "Cla",
        lastName: nil,
        email: "xk29fj@privaterelay.appleid.com"
    )

    func testLeProfilArrivePreRempliAvecCeQueLeFournisseurATransmis() {
        let api = PreviewAPI(seeded: false)
        let onboarding = OnboardingModel(api: api, sessions: InMemorySessionStore())
        let model = CompleteProfileModel(draft: draft, api: api, onboarding: onboarding)

        XCTAssertEqual(model.firstName, "Cla")
        XCTAssertEqual(model.lastName, "", "Un champ non transmis reste vide, pas absent.")
        XCTAssertTrue(model.draft.usesAppleRelayEmail)
    }

    func testLeRelaisAppleEstAccepteTelQuel() async {
        let api = PreviewAPI(seeded: false)
        let onboarding = OnboardingModel(api: api, sessions: InMemorySessionStore())
        let model = CompleteProfileModel(draft: draft, api: api, onboarding: onboarding)
        model.lastName = "Thioll"

        await model.submit()

        XCTAssertEqual(onboarding.step, .home)
    }

    func testUnChampVideSAfficheSousLeChamp() async {
        let api = PreviewAPI(seeded: false)
        let onboarding = OnboardingModel(api: api, sessions: InMemorySessionStore())
        let model = CompleteProfileModel(draft: draft, api: api, onboarding: onboarding)

        await model.submit()

        XCTAssertNotNil(model.fieldErrors[.lastName])
    }
}
