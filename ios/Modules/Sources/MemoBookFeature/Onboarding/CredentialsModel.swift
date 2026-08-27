import Foundation
import MemoBookCore
import MemoBookNetworking
import Observation

/// Le formulaire de *Sign Up* et de *Login* — un seul modèle, parce que c'est
/// un seul écran à deux onglets.
///
/// Toute erreur de validation s'affiche **en inline sous le champ concerné**,
/// jamais en pop-up. Seul l'échec d'authentification de *Login* ouvre une
/// modale, parce que c'est ce que la maquette dessine.
@MainActor
@Observable
public final class CredentialsModel {
    public var tab: AuthTab

    public var firstName = ""
    public var lastName = ""
    public var email = ""
    public var password = ""
    public var passwordConfirmation = ""

    public private(set) var fieldErrors: [Field: String] = [:]
    /// Erreur serveur affichée en tête de formulaire — un email déjà pris, un
    /// réseau coupé. Les champs déjà saisis ne sont jamais vidés.
    public private(set) var formError: String?
    public private(set) var isSubmitting = false

    public enum Field: Hashable, Sendable {
        case firstName
        case lastName
        case email
        case password
        case passwordConfirmation
    }

    private let api: any MemoBookAPI
    private let onboarding: OnboardingModel
    private let social: any SocialSignInBroker

    public init(
        api: any MemoBookAPI,
        onboarding: OnboardingModel,
        tab: AuthTab,
        social: any SocialSignInBroker = UnwiredSocialSignInBroker()
    ) {
        self.api = api
        self.onboarding = onboarding
        self.social = social
        self.tab = tab
        self.email = onboarding.carriedEmail
    }

    /// Le CTA reste inactif tant que les champs requis sont vides — c'est
    /// l'état nominal des deux maquettes, dont le bouton est gris.
    public var canSubmit: Bool {
        guard !isSubmitting else { return false }

        let filled = [email, password].allSatisfy { !$0.trimmed.isEmpty }
        guard tab == .signUp else { return filled }

        return filled
            && ![firstName, lastName, passwordConfirmation].contains { $0.trimmed.isEmpty }
    }

    public func select(tab newTab: AuthTab) {
        tab = newTab
        fieldErrors = [:]
        formError = nil
        onboarding.select(tab: newTab)
    }

    public func forgotPassword() {
        onboarding.forgotPassword(email: email.trimmed)
    }

    // MARK: - Envoi

    public func submit() async {
        guard validate() else { return }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let session =
                tab == .signUp
                ? try await api.signUp(
                    NewAccount(
                        firstName: firstName.trimmed,
                        lastName: lastName.trimmed,
                        email: EmailValidation.normalize(email),
                        password: password
                    )
                )
                : try await api.signIn(
                    email: EmailValidation.normalize(email),
                    password: password
                )

            onboarding.finish(session)
        } catch {
            handle(error)
        }
    }

    public func signIn(with provider: SocialProvider) async {
        isSubmitting = true
        defer { isSubmitting = false }
        formError = nil

        do {
            let credential = try await social.credential(for: provider)

            switch try await api.signIn(with: provider, credential: credential) {
            case .signedIn(let session):
                onboarding.finish(session)
            case .profileRequired(let draft):
                onboarding.requireProfile(draft)
            }
        } catch SocialSignInError.cancelled {
            // Fermer la fenêtre du fournisseur ou refuser l'autorisation ramène
            // ici sans un mot : ce n'est pas une erreur, c'est un choix.
            return
        } catch {
            formError = error.localizedDescription
        }
    }

    // MARK: - Validation

    private func validate() -> Bool {
        var errors: [Field: String] = [:]
        formError = nil

        if !EmailValidation.isValid(email) {
            errors[.email] = "Vérifie ton adresse email."
        }

        if tab == .signUp {
            if firstName.trimmed.isEmpty { errors[.firstName] = "Ton prénom est requis." }
            if lastName.trimmed.isEmpty { errors[.lastName] = "Ton nom est requis." }

            if let problem = PasswordPolicy.check(password) {
                errors[.password] = problem.message
            }
            if passwordConfirmation != password {
                errors[.passwordConfirmation] = "Les deux mots de passe ne sont pas identiques."
            }
        } else if password.isEmpty {
            errors[.password] = "Saisis ton mot de passe."
        }

        fieldErrors = errors
        return errors.isEmpty
    }

    private func handle(_ error: any Error) {
        guard let apiError = error as? APIError else {
            formError = error.localizedDescription
            return
        }

        switch apiError {
        case .server(401, _, _) where tab == .signIn:
            // La maquette dessine une modale pour ce cas précis, et elle seule.
            onboarding.signInDidFail()

        case .server(409, _, _):
            fieldErrors[.email] = "Un compte existe déjà avec cette adresse."

        case .server(400, let code, let message):
            if let field = passwordField(for: code) {
                fieldErrors[field] = message
            } else {
                formError = message
            }

        default:
            formError = apiError.localizedDescription
        }
    }

    /// Les codes de la politique de mot de passe côté serveur, renvoyés tels
    /// quels par `backend/src/lib/password.ts`.
    private func passwordField(for code: String?) -> Field? {
        switch code {
        case "too_short", "too_long", "needs_letter_and_digit": .password
        default: nil
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
