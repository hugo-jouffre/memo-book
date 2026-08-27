import Foundation
import MemoBookCore
import MemoBookNetworking
import Observation

/// *Mot de passe oublié* — vérifie qu'un compte existe, puis déclenche l'envoi.
///
/// Le détail fonctionnel est explicite : l'app **n'attend pas** la confirmation
/// d'envoi, elle repart sur *Connection* dès que le serveur a dit qu'un compte
/// existe. Attendre un SMTP pour afficher un écran, c'est faire porter à
/// l'utilisateur la latence d'un fournisseur.
@MainActor
@Observable
public final class ForgotPasswordModel {
    public var email: String
    /// Le champ est en lecture seule tant qu'on n'a pas touché au crayon :
    /// l'adresse arrive de *Connection*, la corriger est l'exception.
    public var isEditingEmail = false

    public private(set) var emailError: String?
    public private(set) var formError: String?
    public private(set) var isSubmitting = false

    private let api: any MemoBookAPI
    private let onboarding: OnboardingModel

    public init(api: any MemoBookAPI, onboarding: OnboardingModel) {
        self.api = api
        self.onboarding = onboarding
        self.email = onboarding.carriedEmail
        self.isEditingEmail = onboarding.carriedEmail.isEmpty
    }

    public var canSubmit: Bool { !isSubmitting && !email.trimmed.isEmpty }

    public func submit() async {
        guard EmailValidation.isValid(email) else {
            emailError = "Vérifie ton adresse email."
            return
        }

        emailError = nil
        formError = nil
        isSubmitting = true
        defer { isSubmitting = false }

        let address = EmailValidation.normalize(email)

        do {
            try await api.requestPasswordReset(email: address)
            onboarding.returnToSignIn()
        } catch let error as APIError {
            if case .server(404, _, _) = error {
                onboarding.noAccount(for: address)
            } else {
                formError = error.localizedDescription
            }
        } catch {
            formError = error.localizedDescription
        }
    }
}

/// *Mdp oublié - config* — la saisie du nouveau mot de passe, atteinte
/// uniquement par le deep link reçu par email.
@MainActor
@Observable
public final class ResetPasswordModel {
    public var password = ""
    public var confirmation = ""

    public private(set) var passwordError: String?
    public private(set) var confirmationError: String?
    /// Message affiché quand le lien est périmé, invalide ou déjà utilisé. Il
    /// invite à relancer la procédure : on ne laisse jamais quelqu'un devant un
    /// formulaire qui ne servira à rien.
    public private(set) var linkError: String?
    public private(set) var isSubmitting = false

    private let token: String
    private let api: any MemoBookAPI
    private let onboarding: OnboardingModel

    public init(token: String, api: any MemoBookAPI, onboarding: OnboardingModel) {
        self.token = token
        self.api = api
        self.onboarding = onboarding
    }

    public var canSubmit: Bool {
        !isSubmitting && !password.isEmpty && !confirmation.isEmpty
    }

    public func submit() async {
        passwordError = PasswordPolicy.check(password)?.message
        confirmationError =
            confirmation == password ? nil : "Les deux mots de passe ne sont pas identiques."

        guard passwordError == nil, confirmationError == nil else { return }

        linkError = nil
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await api.resetPassword(token: token, newPassword: password)
            onboarding.returnToSignIn()
        } catch let error as APIError {
            if case .server(400, "invalid_or_expired_token", _) = error {
                linkError =
                    "Ce lien n'est plus valable. Relance « Mot de passe oublié » depuis l'écran de connexion."
            } else {
                linkError = error.localizedDescription
            }
        } catch {
            linkError = error.localizedDescription
        }
    }

    public func backToSignIn() {
        onboarding.returnToSignIn()
    }
}

/// *Complète tes informations* — la finalisation d'un compte créé par un
/// fournisseur tiers qui n'a pas transmis de profil exploitable.
@MainActor
@Observable
public final class CompleteProfileModel {
    public var firstName: String
    public var lastName: String
    public var email: String

    public private(set) var fieldErrors: [Field: String] = [:]
    public private(set) var isSubmitting = false

    public enum Field: Hashable, Sendable {
        case firstName
        case lastName
        case email
    }

    public let draft: SocialProfileDraft

    private let api: any MemoBookAPI
    private let onboarding: OnboardingModel

    public init(draft: SocialProfileDraft, api: any MemoBookAPI, onboarding: OnboardingModel) {
        self.draft = draft
        self.api = api
        self.onboarding = onboarding
        self.firstName = draft.firstName ?? ""
        self.lastName = draft.lastName ?? ""
        self.email = draft.email ?? ""
    }

    public var canSubmit: Bool {
        !isSubmitting
            && ![firstName, lastName, email].contains { $0.trimmed.isEmpty }
    }

    public func submit() async {
        var errors: [Field: String] = [:]
        if firstName.trimmed.isEmpty { errors[.firstName] = "Ton prénom est requis." }
        if lastName.trimmed.isEmpty { errors[.lastName] = "Ton nom est requis." }
        if !EmailValidation.isValid(email) { errors[.email] = "Vérifie ton adresse email." }

        fieldErrors = errors
        guard errors.isEmpty else { return }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let session = try await api.completeSocialProfile(
                CompletedSocialProfile(
                    socialToken: draft.socialToken,
                    firstName: firstName.trimmed,
                    lastName: lastName.trimmed,
                    // L'adresse relais Apple part telle quelle : elle sert aux
                    // communications produit et aux alertes de facturation, et
                    // Apple fait suivre le courrier.
                    email: EmailValidation.normalize(email)
                )
            )
            onboarding.finish(session)
        } catch let error as APIError {
            if case .server(409, _, _) = error {
                fieldErrors[.email] = "Un compte existe déjà avec cette adresse."
            } else {
                fieldErrors[.email] = error.localizedDescription
            }
        } catch {
            fieldErrors[.email] = error.localizedDescription
        }
    }
}
