import Foundation

/// La règle qui dit si une adresse est plausible.
///
/// **Volontairement permissive** : une adresse n'est vraiment validée que par
/// l'envoi d'un message. Ce qu'on écarte ici, ce sont les fautes de frappe
/// grossières — l'arobase oubliée, le domaine sans point — et rien d'autre.
/// Une règle plus stricte refuserait des adresses valides, ce qui coûte plus
/// cher qu'un aller-retour serveur.
///
/// Elle vit dans `MemoBookCore` parce que **deux écrans la posent** : l'entrée
/// dans l'app et la correction de l'adresse depuis le profil. Deux copies
/// auraient fini par diverger, et un formulaire aurait accepté ce que l'autre
/// refuse.
public enum EmailAddress {
    public static func isValid(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)

        guard parts.count == 2, !parts[0].isEmpty else { return false }

        let host = parts[1]
        return host.contains(".") && !host.hasPrefix(".") && !host.hasSuffix(".")
    }
}
