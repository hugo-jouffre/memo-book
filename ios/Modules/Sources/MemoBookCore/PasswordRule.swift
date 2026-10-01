import Foundation

/// La règle d'un mot de passe : au moins 8 caractères, une lettre et un
/// chiffre. La même que celle du serveur (`backend/src/routes/auth.ts`).
///
/// Elle vit dans `MemoBookCore` parce que **deux écrans la posent** :
/// l'inscription et le nouveau mot de passe après « Mot de passe oublié ».
/// Même raison que ``EmailAddress`` — deux copies auraient fini par diverger.
public enum PasswordRule {
    /// La phrase affichée sous le champ.
    public static let hint = "8 caractères, 1 lettre, 1 chiffre"

    public static func isValid(_ password: String) -> Bool {
        Criterion.allCases.allSatisfy { $0.isMet(by: password) }
    }

    /// Les trois critères, un par un, pour les cocher **pendant qu'on tape** —
    /// la feuille « Modifier mon mot de passe » du profil (Hugo, 29/09/2026).
    /// La même règle que ``isValid``, découpée : les deux ne peuvent pas
    /// diverger, l'une est la conjonction de l'autre.
    public enum Criterion: CaseIterable, Sendable, Hashable, Identifiable {
        case length
        case letter
        case digit

        public var id: Self { self }

        public var label: String {
            switch self {
            case .length: "8 caractères minimum"
            case .letter: "1 lettre"
            case .digit: "1 chiffre"
            }
        }

        public func isMet(by password: String) -> Bool {
            switch self {
            case .length: password.count >= 8
            case .letter: password.contains(where: \.isLetter)
            case .digit: password.contains(where: \.isNumber)
            }
        }
    }
}
