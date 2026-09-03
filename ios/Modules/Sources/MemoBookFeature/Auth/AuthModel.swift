import Foundation
import Observation

/// L'état du formulaire d'entrée, et les règles qui décident si « Continuer »
/// est actif.
///
/// La validation vit ici plutôt que dans la vue pour être testable sans
/// simulateur — c'est la seule partie de cet écran qui porte des règles.
///
/// > Important : rien n'est encore branché à un back-end. `submit` remonte les
/// > valeurs saisies à l'appelant ; l'API d'authentification n'existe pas côté
/// > serveur (`MemoBookNetworking` ne connaît que l'enregistrement d'appareil).
@MainActor
@Observable
final class AuthModel {
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

    /// Message affiché sous la confirmation, une fois qu'il y a de quoi juger.
    var passwordConfirmationError: String? {
        guard !passwordConfirmation.isEmpty, !passwordsMatch else { return nil }
        return "Les deux mots de passe ne correspondent pas."
    }

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
