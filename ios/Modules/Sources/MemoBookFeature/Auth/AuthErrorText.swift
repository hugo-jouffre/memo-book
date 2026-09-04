import AuthenticationServices
import Foundation

/// Le message qu'on montre vraiment à l'utilisateur.
///
/// `localizedDescription` d'`ASAuthorizationError` n'est pas écrit pour être
/// lu : sur un appareil sans compte Apple connecté, il rend « L'opération n'a
/// pas pu s'achever (com.apple.AuthenticationServices.AuthorizationError
/// erreur 1000) ». On nomme donc les cas qu'on sait nommer, et on garde une
/// phrase neutre pour le reste — jamais un code d'erreur.
func authErrorMessage(for error: any Error) -> String {
    guard let appleError = error as? ASAuthorizationError else {
        return (error as? LocalizedError)?.errorDescription
            ?? "La connexion n'a pas abouti. Réessaie dans un instant."
    }

    switch appleError.code {
    // 1000 en pratique : aucun compte Apple sur l'appareil. Le système ne le
    // dit pas, mais c'est la cause dans l'immense majorité des cas.
    case .unknown:
        return "Connecte-toi à ton compte Apple dans les Réglages, puis réessaie."
    case .canceled:
        // Ne devrait jamais s'afficher : renoncer n'est pas un échec, et
        // ``SocialSignInSection`` filtre ce cas en amont.
        return "Connexion avec Apple abandonnée."
    case .notHandled, .notInteractive:
        return "Apple n'a pas pu traiter la demande. Réessaie dans un instant."
    case .invalidResponse, .failed:
        return "Apple a refusé la connexion. Réessaie dans un instant."
    default:
        return "La connexion avec Apple n'a pas abouti. Réessaie dans un instant."
    }
}
