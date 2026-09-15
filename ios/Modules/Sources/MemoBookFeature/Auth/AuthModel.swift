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
    var email = "" {
        // Corriger l'adresse efface ce qu'on lui reprochait : le message ne
        // parle plus de ce qui est écrit.
        didSet { if email != oldValue { emailError = nil } }
    }
    var password = ""
    var passwordConfirmation = ""

    /// La règle vit dans ``PasswordRule`` : le nouveau mot de passe après
    /// « Mot de passe oublié » la pose aussi.
    var isPasswordValid: Bool { PasswordRule.isValid(password) }

    /// La règle vit dans ``EmailAddress`` : le profil la pose aussi, et deux
    /// copies auraient fini par diverger.
    var isEmailValid: Bool { EmailAddress.isValid(email) }

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

    /// Message affiché sous la confirmation, une fois qu'il y a de quoi juger.
    ///
    /// La phrase de la maquette (`Sign Up Filled`, `3390:10812`), au
    /// tutoiement près : elle écrivait « Vérifiez votre saisie », et R9 ne
    /// souffre pas d'exception — voir T9.
    var passwordConfirmationError: String? {
        guard !passwordConfirmation.isEmpty, !passwordsMatch else { return nil }
        return Self.passwordMismatchMessage
    }

    /// Partagé avec le nouveau mot de passe de « Mot de passe oublié ».
    static let passwordMismatchMessage = "Les deux mots de passe sont différents. Vérifie ta saisie."

    /// Ce que le serveur reproche à **l'adresse**, affiché sous son champ et
    /// non sous le bouton : c'est la ligne qu'il faut changer. Aujourd'hui un
    /// seul cas, l'adresse déjà prise. Voir ``report(_:)``.
    var emailError: String?

    /// Un compte existe déjà avec cette adresse. La phrase de la maquette
    /// (`3394:10929`), au tutoiement près — elle écrivait « Connectez-vous ou
    /// utilisez » (T9).
    static let emailTakenMessage =
        "Cette adresse e-mail est déjà associée à un compte. Connecte-toi ou utilise une autre adresse."

    /// Le serveur ne répond pas, ou répond qu'il est en panne. La phrase de la
    /// maquette (`3405:10991`), au tutoiement près — « veuillez réessayer ».
    static let unavailableMessage = "MemoBook est actuellement indisponible, réessaie plus tard."

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

    /// Traduit un échec en phrase, **et la pose au bon endroit**.
    ///
    /// Trois cas, ceux que la maquette dessine (T9) : l'adresse déjà prise va
    /// sous le champ de l'adresse ; un serveur muet ou en panne dit qu'il est
    /// indisponible ; tout le reste garde le libellé qu'il porte — le
    /// back-end écrit déjà les siens en français.
    func report(_ error: any Error) {
        if let apiError = error as? APIError {
            if case .server(let statusCode, _, _) = apiError, statusCode == 409 {
                emailError = Self.emailTakenMessage
                return
            }
            if case .server(let statusCode, _, _) = apiError, statusCode >= 500 {
                errorMessage = Self.unavailableMessage
                return
            }
            #if !DEBUG
                // En développement, le transport garde son diagnostic — il nomme
                // le serveur qui ne tourne pas et donne la commande. Livré, la
                // panne se dit avec les mots de la maquette.
                if apiError.isTransport {
                    errorMessage = Self.unavailableMessage
                    return
                }
            #endif
        }
        errorMessage = authErrorMessage(for: error)
    }

    // MARK: - Compléter ce qu'un fournisseur a donné

    /// Le compte qui vient d'être ouvert par Apple ou Google, et dont il reste
    /// à **vérifier le prénom et le nom** avant d'entrer. `nil` le reste du
    /// temps. Voir ``SocialCompletionView``.
    var completing: Account?

    /// Faut-il passer par la page de compléments ?
    ///
    /// Oui pour un compte **neuf** — la maquette (`2707:9456`) demande de
    /// vérifier ce qu'on a récupéré, même quand tout y est —, et pour un compte
    /// auquel il manque encore un prénom ou un nom. Une reconnexion sur un
    /// compte complet passe tout droit. Un compte est neuf quand il vient
    /// d'être créé : le serveur ne le dit pas autrement que par sa date.
    func needsCompletion(_ account: Account) -> Bool {
        let isFresh = Date.now.timeIntervalSince(account.createdAt) < 120
        let isMissingName = [account.firstName, account.lastName]
            .contains { ($0 ?? "").trimmed.isEmpty }
        return isFresh || isMissingName
    }

    /// Ouvre la page de compléments, préremplie de ce que le fournisseur a
    /// donné : le compte d'abord, puis ce que l'app avait retenu d'une première
    /// autorisation (Apple ne redonne jamais le nom).
    func beginCompletion(_ account: Account) {
        if let value = account.firstName, !value.trimmed.isEmpty { firstName = value }
        if let value = account.lastName, !value.trimmed.isEmpty { lastName = value }
        if let value = account.email { email = value }
        errorMessage = nil
        completing = account
    }

    var canCompleteProfile: Bool {
        !firstName.trimmed.isEmpty && !lastName.trimmed.isEmpty
    }

    /// Enregistre le prénom et le nom vérifiés, et rend le compte à jour.
    ///
    /// `nil` si l'appel a échoué : le message est dans ``errorMessage`` et la
    /// page reste ouverte. Le compte, lui, existe déjà — c'est le profil qu'on
    /// corrige, par la route qu'emploie l'écran de profil.
    func completeProfile() async -> Account? {
        guard let account = completing, !isWorking else { return nil }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            // Le profil renvoyé ne porte que le nom composé (`fullName`) : ce
            // qu'on vient d'envoyer est la vérité la plus fraîche.
            _ = try await api.updateProfile(
                ProfileEdit(firstName: .some(firstName.trimmed), lastName: .some(lastName.trimmed))
            )
            completing = nil
            return Account(
                id: account.id,
                email: account.email,
                firstName: firstName.trimmed,
                lastName: lastName.trimmed,
                createdAt: account.createdAt
            )
        } catch {
            report(error)
            return nil
        }
    }

    #if DEBUG

        /// Le compte de test de l'app, celui que `backend/prisma/seed.ts` pose
        /// et tient à jour.
        ///
        /// **Le mot de passe n'est pas un secret** : il n'ouvre qu'un compte de
        /// démonstration, il est écrit dans le seed et dans `docs/supabase.md`,
        /// et ce bloc ne compile pas en release.
        static let testAccount = (email: "demo@memo-book.com", password: "memobook2026")

        /// Entre dans l'app par le compte de test — **une vraie connexion**, pas
        /// un compte inventé.
        ///
        /// Le bouton fabriquait jusqu'ici un `Account` de toutes pièces. Il
        /// ouvrait bien l'accueil, mais sans session : chaque écran derrière
        /// tombait alors sur un 401, et on croyait à un bug d'écran. Ici, la
        /// session est celle du serveur, avec les voyages et le profil du seed.
        func signInAsTestAccount() async -> Account? {
            await run {
                try await self.api.signIn(
                    email: Self.testAccount.email,
                    password: Self.testAccount.password
                )
            }
        }

    #endif

    /// Le même enrobage pour les trois chemins d'entrée : un seul appel à la
    /// fois, l'erreur précédente effacée, et le message traduit en cas d'échec.
    private func run(_ work: @escaping () async throws -> AuthSession) async -> Account? {
        guard !isWorking else { return nil }
        isWorking = true
        errorMessage = nil
        emailError = nil
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
