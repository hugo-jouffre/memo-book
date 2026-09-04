import AuthenticationServices
import CryptoKit
import Foundation

/// Ce qu'une entrée par fournisseur tiers rapporte, une fois le fournisseur
/// d'accord. C'est le seul objet que l'écran d'entrée transmet ensuite au
/// serveur, quel que soit le fournisseur.
///
/// > Important : le jeton n'est **pas** une preuve tant que le serveur ne l'a
/// > pas vérifié lui-même, contre les clés publiques d'Apple ou de Google.
/// > Un client peut envoyer ce qu'il veut ; c'est la signature du jeton, et
/// > elle seule, qui identifie quelqu'un.
struct SocialCredential: Equatable, Sendable {
    enum Provider: String, Sendable {
        case apple
        case google
    }

    let provider: Provider

    /// L'identifiant stable de la personne chez ce fournisseur — le `sub` du
    /// jeton. Il ne change jamais, et ne vaut que pour notre app : le même
    /// compte Apple donne un identifiant différent à chaque développeur.
    let userIdentifier: String

    /// Le JWT signé par le fournisseur. À transmettre tel quel.
    let identityToken: String

    /// Le nonce en clair de cette tentative, qu'Apple a recopié haché dans le
    /// jeton. Le serveur compare les deux. Google n'en utilise pas ici.
    let nonce: String?

    /// Apple ne donne l'identité qu'à la **toute première** autorisation, et
    /// jamais ensuite : ces trois champs sont vides à chaque reconnexion.
    let firstName: String?
    let lastName: String?
    let email: String?
}

/// Le nonce de Sign in with Apple : un secret à usage unique, tiré ici, envoyé
/// haché à Apple, et gardé en clair le temps de l'échange.
///
/// Apple recopie l'empreinte dans le jeton d'identité qu'il signe. Le serveur
/// rehache le nonce en clair que l'app lui transmet et compare : si les deux
/// concordent, ce jeton a bien été demandé par cette app, pour cette tentative
/// précise. C'est ce qui empêche de rejouer un jeton intercepté ailleurs.
///
/// Sans nonce, le jeton reste signé par Apple, donc authentique — mais plus
/// rien ne dit qu'il a été émis *pour nous*.
struct SignInNonce: Sendable {
    /// La valeur en clair, celle qui part vers notre serveur.
    let raw: String

    init() {
        // 32 octets de hasard cryptographique. `base64url` parce que la valeur
        // finit dans un JWT, où « + » et « / » demanderaient un échappement.
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Le générateur aléatoire du système a échoué.")
        raw = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// L'empreinte, celle qui part vers Apple.
    var hashed: String {
        SHA256.hash(data: Data(raw.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

extension SocialCredential {
    /// Traduit la réponse d'Apple. `nil` si elle n'est pas exploitable : sans
    /// jeton d'identité, il n'y a rien que le serveur puisse vérifier.
    init?(_ authorization: ASAuthorization, nonce: SignInNonce) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let token = String(data: tokenData, encoding: .utf8)
        else { return nil }

        self.init(
            provider: .apple,
            userIdentifier: credential.user,
            identityToken: token,
            nonce: nonce.raw,
            firstName: credential.fullName?.givenName,
            lastName: credential.fullName?.familyName,
            email: credential.email
        )
    }
}
