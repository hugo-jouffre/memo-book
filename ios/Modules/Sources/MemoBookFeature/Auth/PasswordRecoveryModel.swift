import Foundation
import MemoBookCore
import MemoBookNetworking
import Observation

/// L'état de la feuille « Mot de passe oublié », et l'appel qui envoie
/// l'e-mail.
///
/// Un seul modèle pour toutes les étapes du parcours : la feuille change de
/// contenu, elle ne s'empile pas (voir `BrandSheet`). Chaque étape est un cas
/// de ``Step``, et c'est lui que la vue dessine.
@MainActor
@Observable
final class PasswordRecoveryModel: Identifiable {
    private let api: any MemoBookAPI

    /// Une identité par ouverture de la feuille : c'est ce qui la présente
    /// (`brandSheet(item:)`), et ce qui garantit qu'une seconde ouverture
    /// repart d'un modèle neuf.
    let id = UUID()

    /// - Parameter email: ce que le formulaire de connexion contenait déjà.
    ///   La feuille s'ouvre dessus, prérempli : on ne fait pas retaper une
    ///   adresse qu'on vient d'écrire.
    init(api: any MemoBookAPI, email: String) {
        self.api = api
        self.email = email
        self.step = .request
    }

    /// La feuille ouverte **par le lien de l'e-mail**, directement sur le
    /// nouveau mot de passe. L'adresse n'est pas connue ici — le lien ne la
    /// porte pas, et n'a pas à la porter : le secret suffit.
    init(api: any MemoBookAPI, resetToken: String) {
        self.api = api
        self.email = ""
        self.step = .reset(token: resetToken)
    }

    /// Où en est le parcours.
    enum Step: Equatable {
        /// L'adresse, à confirmer ou corriger, et « Continuer ».
        case request
        /// L'e-mail est parti pour `email` : il n'y a plus qu'à l'ouvrir.
        case sent
        /// Le lien de l'e-mail a été ouvert : le nouveau mot de passe, deux
        /// fois, et le secret qui l'accompagnera.
        case reset(token: String)
    }

    private(set) var step: Step

    // MARK: - Nouveau mot de passe

    var password = "" {
        didSet { if password != oldValue { errorMessage = nil } }
    }
    var passwordConfirmation = "" {
        didSet { if passwordConfirmation != oldValue { errorMessage = nil } }
    }

    /// La règle vit dans ``PasswordRule`` : l'inscription pose la même.
    var isPasswordValid: Bool { PasswordRule.isValid(password) }

    var passwordsMatch: Bool { password == passwordConfirmation }

    /// Même phrase que l'inscription, une fois qu'il y a de quoi juger.
    var passwordConfirmationError: String? {
        guard !passwordConfirmation.isEmpty, !passwordsMatch else { return nil }
        return AuthModel.passwordMismatchMessage
    }

    var canSave: Bool { isPasswordValid && passwordsMatch && !isWorking }

    /// Enregistre le nouveau mot de passe. Réussite : la session est ouverte,
    /// le compte est rendu et l'app entre. Échec : le message est posé — dont
    /// « ce lien n'est plus valable », qui renvoie à l'étape de l'adresse.
    func resetPassword() async -> Account? {
        guard case .reset(let token) = step, canSave else { return nil }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            return try await api.resetPassword(token: token, password: password).account
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    /// « Ce lien n'est plus valable » : la seule issue est d'en redemander un.
    /// On repart de l'adresse, champs et message effacés — l'étape est neuve.
    func startOver() {
        password = ""
        passwordConfirmation = ""
        step = .request
    }

    var email: String {
        // Corriger l'adresse efface ce qu'on lui reprochait — même règle que
        // le formulaire d'entrée. Le refus « aucun compte » aussi : la feuille
        // redevient alors celle du départ, avec « Continuer ».
        didSet {
            if email != oldValue {
                errorMessage = nil
                unknownEmail = nil
            }
        }
    }

    /// La règle vit dans ``EmailAddress`` : une seule copie pour toute l'app.
    var canSubmit: Bool { EmailAddress.isValid(email) && !isWorking && !isUnknownAccount }

    /// Message d'échec, sous le bouton. Nul quand tout va bien.
    var errorMessage: String?

    /// L'adresse que le serveur a refusée parce qu'aucun compte n'y répond,
    /// telle qu'il l'a cherchée (normalisée). C'est elle que la feuille écrit
    /// en rouge, avec la porte vers l'inscription. Nul le reste du temps.
    private(set) var unknownEmail: String?

    var isUnknownAccount: Bool { unknownEmail != nil }

    /// Le code du serveur pour « aucun compte à cette adresse » — voir
    /// `backend/src/services/passwordReset.ts`.
    static let unknownAccountCode = "unknown_account"

    /// L'appel est parti : le bouton tourne, et la feuille ne se referme plus
    /// au glissé — une demande envoyée à moitié n'a pas de sens.
    private(set) var isWorking = false

    /// Demande l'e-mail. Réussite : la feuille passe à ``Step/sent``. Échec :
    /// le message est posé, l'étape ne bouge pas.
    func submit() async {
        guard canSubmit else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            try await api.requestPasswordReset(email: email.trimmed)
            step = .sent
        } catch let APIError.server(404, code?, _) where code == Self.unknownAccountCode {
            // Le serveur a normalisé l'adresse ; on garde la nôtre, telle
            // qu'elle est écrite dans le champ, pour que la phrase rouge et
            // le champ disent la même chose.
            unknownEmail = email.trimmed
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Un serveur muet ou en panne se dit avec les mots de la maquette ; tout
    /// le reste garde le libellé qu'il porte, déjà en français.
    private static func message(for error: any Error) -> String {
        if let apiError = error as? APIError {
            if case .server(let statusCode, _, _) = apiError, statusCode >= 500 {
                return AuthModel.unavailableMessage
            }
            #if !DEBUG
                if apiError.isTransport { return AuthModel.unavailableMessage }
            #endif
        }
        return authErrorMessage(for: error)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
