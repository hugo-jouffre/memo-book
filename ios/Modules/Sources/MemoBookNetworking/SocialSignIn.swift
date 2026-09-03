import Foundation
import MemoBookCore

/// Ce que l'app transmet au serveur pour entrer par Apple ou Google.
///
/// Volontairement un simple porteur de données : c'est l'écran d'entrée qui
/// sait parler à `AuthenticationServices` et au SDK Google, et il traduit sa
/// réponse en ceci. La couche réseau n'a pas à connaître ces frameworks.
///
/// > Important : rien ici n'est une preuve d'identité. `identityToken` est un
/// > JWT signé par le fournisseur, que **seul le serveur** peut vérifier, et
/// > qu'il vérifie effectivement — signature, émetteur, audience, expiration,
/// > et le nonce du côté d'Apple.
public struct SocialSignIn: Codable, Sendable, Hashable {
    public let provider: AuthProvider
    public let identityToken: String

    /// Le nonce en clair de cette tentative. Requis par Apple, inutilisé par
    /// Google, dont c'est l'audience du jeton qui joue ce rôle.
    public let nonce: String?

    /// Apple ne les donne qu'à la toute première autorisation. Les transmettre
    /// est donc la seule occasion de les enregistrer.
    public let firstName: String?
    public let lastName: String?

    public init(
        provider: AuthProvider,
        identityToken: String,
        nonce: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil
    ) {
        self.provider = provider
        self.identityToken = identityToken
        self.nonce = nonce
        self.firstName = firstName
        self.lastName = lastName
    }
}
