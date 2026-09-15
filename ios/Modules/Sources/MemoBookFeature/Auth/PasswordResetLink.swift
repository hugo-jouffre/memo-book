import Foundation

/// Le lien du bouton « Réinitialiser mon mot de passe » de l'e-mail, tel que
/// le back-end l'écrit (`passwordResetUrl`, dans `services/mailer.ts`) :
/// `memobook://password/reset?token=…`.
///
/// Le schéma n'est pas vérifié ici, seulement le chemin : le jour du lien
/// universel, `https://memo-book.com/app/password/reset?token=…` doit ouvrir
/// la même feuille sans qu'on touche à cette lecture.
enum PasswordResetLink {
    /// Le secret porté par le lien, ou `nil` si ce n'en est pas un.
    static func token(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        // Avec un schéma privé, « password » est lu comme l'hôte et le chemin
        // ne contient que « /reset » ; avec un domaine, tout est dans le chemin.
        // On regarde donc les deux morceaux mis bout à bout.
        let route = [components.host, components.path]
            .compactMap { $0 }
            .joined(separator: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "/")
        guard route.hasSuffix("password/reset") else { return nil }

        let token = components.queryItems?.first { $0.name == "token" }?.value ?? ""
        return token.isEmpty ? nil : token
    }
}
