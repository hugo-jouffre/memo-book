import Foundation
import GoogleSignIn
import UIKit

/// L'entrée par Google.
///
/// Google, contrairement à Apple, ne signe rien tant qu'on ne lui a pas dit
/// **quel** client OAuth demande : c'est le rôle de `GIDClientID`, posé dans
/// l'`Info.plist` par `project.yml`. L'identifiant de client iOS n'est pas un
/// secret — il part dans chaque binaire livré. Le *client secret*, lui, est
/// celui du client **web** et n'a rien à faire dans l'app : il ne sert qu'au
/// serveur, et seulement s'il échange des codes d'autorisation.
@MainActor
enum GoogleSignInService {
    /// Ouvre la feuille Google et rend de quoi identifier la personne.
    ///
    /// - Returns: `nil` si l'utilisateur a renoncé. Renoncer n'est pas un
    ///   échec, et ne doit rien afficher.
    static func signIn() async throws -> SocialCredential? {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.isEmpty, !clientID.hasPrefix("REMPLACER")
        else { throw GoogleSignInError.missingClientID }

        guard let presenter = topViewController() else {
            throw GoogleSignInError.noPresenter
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else {
                throw GoogleSignInError.noIdentityToken
            }

            let profile = result.user.profile
            return SocialCredential(
                provider: .google,
                userIdentifier: result.user.userID ?? idToken,
                identityToken: idToken,
                // Google ne pratique pas le nonce ici : c'est l'audience du
                // jeton, vérifiée côté serveur, qui joue ce rôle.
                nonce: nil,
                firstName: profile?.givenName,
                lastName: profile?.familyName,
                email: profile?.email
            )
        } catch let error as NSError
            where error.domain == kGIDSignInErrorDomain
            && error.code == GIDSignInError.canceled.rawValue {
            return nil
        }
    }

    /// À brancher sur `.onOpenURL` : c'est par cette adresse que Google renvoie
    /// sa réponse à l'app. Passer par ici évite que la cible app ait à importer
    /// le SDK — il reste rangé dans ce module.
    @discardableResult
    static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    /// La feuille Google a besoin d'un contrôleur qui la présente. SwiftUI n'en
    /// expose pas, on va donc le chercher dans la scène active.
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }

        var controller = scene?.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}

enum GoogleSignInError: LocalizedError {
    case missingClientID
    case noPresenter
    case noIdentityToken

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            // Message de développeur assumé : cet état ne peut pas arriver
            // dans une app livrée, seulement dans une build mal configurée.
            "Le client OAuth Google n'est pas configuré (GIDClientID dans project.yml)."
        case .noPresenter:
            "Impossible d'ouvrir la fenêtre Google. Réessaie."
        case .noIdentityToken:
            "Google n'a pas transmis d'identifiant utilisable. Réessaie."
        }
    }
}
