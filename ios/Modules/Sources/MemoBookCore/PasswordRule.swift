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
        password.count >= 8
            && password.contains(where: \.isLetter)
            && password.contains(where: \.isNumber)
    }
}
