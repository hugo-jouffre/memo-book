import Foundation

/// La politique de mot de passe, **la même que celle du back-end**
/// (`backend/src/lib/password.ts`). Le client valide pour donner un retour
/// immédiat sous le champ ; le serveur revalide, parce qu'un client n'est
/// jamais une garantie.
///
/// ⚠️ Ces critères sont une proposition : le détail fonctionnel dit « mot de
/// passe respectant les critères de sécurité définis » sans les définir.
/// À confirmer avec Clara.
public enum PasswordPolicy: Sendable {
    public static let minimumLength = 8
    public static let maximumLength = 200

    public enum Problem: Sendable, Hashable {
        case tooShort
        case tooLong
        case needsLetterAndDigit

        /// Le message affiché sous le champ. Il tutoie (R9) et dit quoi faire.
        public var message: String {
            switch self {
            case .tooShort:
                "Ton mot de passe doit faire au moins \(minimumLength) caractères."
            case .tooLong:
                "Ton mot de passe ne peut pas dépasser \(maximumLength) caractères."
            case .needsLetterAndDigit:
                "Ton mot de passe doit contenir au moins une lettre et un chiffre."
            }
        }
    }

    /// `nil` quand le mot de passe convient.
    public static func check(_ password: String) -> Problem? {
        if password.count < minimumLength { return .tooShort }
        if password.count > maximumLength { return .tooLong }

        let hasLetter = password.contains { $0.isLetter }
        let hasDigit = password.contains { $0.isNumber }
        if !hasLetter || !hasDigit { return .needsLetterAndDigit }

        return nil
    }
}

/// Validation d'adresse email.
///
/// Volontairement permissive : elle attrape la faute de frappe (« @gmail »
/// sans point, un espace au milieu) sans prétendre décider ce qui est une
/// adresse valide — seul l'envoi d'un email le prouve.
public enum EmailValidation: Sendable {
    public static func isValid(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(" "), trimmed.count <= 254 else { return false }

        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, let local = parts.first, let domain = parts.last else {
            return false
        }

        guard !local.isEmpty, domain.contains("."), !domain.hasPrefix("."),
            !domain.hasSuffix("."), domain.count >= 3
        else { return false }

        return true
    }

    /// Forme canonique : minuscules, sans espaces autour. La même que celle du
    /// serveur, sans quoi deux casses feraient deux comptes.
    public static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
