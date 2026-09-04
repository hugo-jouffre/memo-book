import Foundation
import MemoBookCore
import MemoBookNetworking
import Observation

/// L'état du formulaire d'entrée, et les règles qui décident si « Continuer »
/// est actif.
///
/// La validation vit ici plutôt que dans la vue pour être testable sans
/// simulateur — c'est la seule partie de cet écran qui porte des règles.
///
/// L'appel réseau vit ici aussi : c'est ce qui permet à la vue de ne connaître
/// que trois choses — un état en cours, un message d'erreur, et une réussite.
@MainActor
@Observable
final class AuthModel {
    private let api: any MemoBookAPI

    init(api: any MemoBookAPI) {
        self.api = api
    }

    var mode: AuthMode = .signUp

    var firstName = ""
    var lastName = ""
    var email = ""
    var password = ""
    var passwordConfirmation = ""

    /// Règle affichée sous le champ, et vérifiée ici : au moins 8 caractères,
    /// une lettre et un chiffre.
    static let passwordRule = "8 caractères, 1 lettre, 1 chiffre"

    var isPasswordValid: Bool {
        password.count >= 8
            && password.contains(where: \.isLetter)
            && password.contains(where: \.isNumber)
    }

    var isEmailValid: Bool {
        // Volontairement permissif : un email n'est vraiment validé que par
        // l'envoi. On écarte les fautes de frappe grossières, rien de plus.
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let host = parts[1]
        return host.contains(".") && !host.hasPrefix(".") && !host.hasSuffix(".")
    }

    var passwordsMatch: Bool {
        password == passwordConfirmation
    }

    /// Ce que « Continuer » attend pour s'allumer.
    var canSubmit: Bool {
        switch mode {
        case .signUp:
            !firstName.trimmed.isEmpty
                && !lastName.trimmed.isEmpty
                && isEmailValid
                && isPasswordValid
                && passwordsMatch
        case .signIn:
            isEmailValid && !password.isEmpty
        }
    }

    /// Vrai dès que l'utilisateur a posé le premier caractère dans le
    /// formulaire. L'écran s'en sert pour estomper les entrées par fournisseur
    /// tiers : le choix est fait, autant ne plus le mettre en concurrence avec
    /// « Continuer ».
    var hasStartedFilling: Bool {
        switch mode {
        case .signUp:
            ![firstName, lastName, email, password, passwordConfirmation].allSatisfy(\.isEmpty)
        case .signIn:
            !email.isEmpty || !password.isEmpty
        }
    }

    /// Message affiché sous la confirmation, une fois qu'il y a de quoi juger.
    var passwordConfirmationError: String? {
        guard !passwordConfirmation.isEmpty, !passwordsMatch else { return nil }
        return "Les deux mots de passe ne correspondent pas."
    }

    // MARK: - Fournisseurs tiers

    /// Message d'échec affiché sous les boutons. Nul quand tout va bien.
    var errorMessage: String?

    /// Un appel est en cours : les boutons se figent, « Continuer » tourne.
    private(set) var isWorking = false

    /// Envoie le formulaire — inscription ou connexion selon le mode.
    ///
    /// - Returns: le compte, quand la session est ouverte. `nil` si l'appel a
    ///   échoué : le message est alors dans ``errorMessage``.
    func submit() async -> Account? {
        await run {
            switch self.mode {
            case .signUp:
                try await self.api.signUp(
                    email: self.email.trimmed,
                    password: self.password,
                    firstName: self.firstName.trimmed,
                    lastName: self.lastName.trimmed
                )
            case .signIn:
                try await self.api.signIn(email: self.email.trimmed, password: self.password)
            }
        }
    }

    /// Un fournisseur a donné son accord ; reste à le faire vérifier.
    ///
    /// > Important : à ce stade l'utilisateur n'est **pas** authentifié. Le
    /// > jeton n'est qu'une affirmation tant que le serveur ne l'a pas vérifié
    /// > contre les clés publiques du fournisseur.
    func accept(_ credential: SocialCredential) async -> Account? {
        // Avant toute chose, avant même le réseau : le nom et l'adresse d'Apple
        // ne repasseront jamais. Si l'appel échoue, ils sont quand même gardés
        // pour la tentative suivante.
        SocialIdentityStore.remember(credential)
        let known = SocialIdentityStore.identity(for: credential)

        if let value = credential.firstName ?? known?.firstName { firstName = value }
        if let value = credential.lastName ?? known?.lastName { lastName = value }
        if let value = credential.email ?? known?.email { email = value }

        return await run {
            try await self.api.signIn(
                with: SocialSignIn(
                    provider: credential.provider.apiProvider,
                    identityToken: credential.identityToken,
                    nonce: credential.nonce,
                    firstName: credential.firstName ?? known?.firstName,
                    lastName: credential.lastName ?? known?.lastName
                )
            )
        }
    }

    func report(_ error: any Error) {
        errorMessage = authErrorMessage(for: error)
    }

    /// Le même enrobage pour les trois chemins d'entrée : un seul appel à la
    /// fois, l'erreur précédente effacée, et le message traduit en cas d'échec.
    private func run(_ work: @escaping () async throws -> AuthSession) async -> Account? {
        guard !isWorking else { return nil }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            return try await work().account
        } catch {
            report(error)
            return nil
        }
    }

    // MARK: - Clavier

    /// Champ suivant dans l'enchaînement du clavier, ou `nil` s'il faut valider.
    func fieldAfter(_ field: AuthField) -> AuthField? {
        switch (mode, field) {
        case (.signUp, .firstName): .lastName
        case (.signUp, .lastName): .email
        case (.signUp, .email): .password
        case (.signUp, .password): .passwordConfirmation
        case (.signIn, .email): .password
        default: nil
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension SocialCredential.Provider {
    var apiProvider: AuthProvider {
        switch self {
        case .apple: .apple
        case .google: .google
        }
    }
}
