import Foundation

/// Garde ce qu'Apple ne dit qu'une fois.
///
/// Apple ne transmet le nom et l'adresse qu'à la **toute première**
/// autorisation d'une app pour un compte donné. À la reconnexion suivante ces
/// champs sont vides, et le seul moyen de les revoir est d'aller révoquer l'app
/// dans *Réglages ▸ compte Apple ▸ Connexion avec Apple*.
///
/// Tant que le serveur n'existe pas pour les recevoir, ils sont conservés ici :
/// sans ça, la première connexion d'essai détruirait une information qu'on ne
/// peut plus redemander. Quand l'API d'authentification arrivera, ce fichier
/// disparaît — c'est le serveur qui gardera l'identité.
enum SocialIdentityStore {
    private static let key = "pendingSocialIdentities"

    /// Ce qu'un fournisseur a dit d'une personne, au moment où il l'a dit.
    struct Identity: Codable, Equatable {
        var firstName: String?
        var lastName: String?
        var email: String?
    }

    /// N'écrase jamais un nom déjà connu par un vide : la deuxième connexion
    /// Apple rapporte des champs nuls, et ce sont ceux de la première qu'on
    /// veut garder.
    static func remember(_ credential: SocialCredential, in defaults: UserDefaults = .standard) {
        guard credential.firstName != nil || credential.lastName != nil || credential.email != nil
        else { return }

        var all = identities(in: defaults)
        all[storageKey(for: credential)] = Identity(
            firstName: credential.firstName,
            lastName: credential.lastName,
            email: credential.email
        )
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: key)
    }

    static func identity(
        for credential: SocialCredential,
        in defaults: UserDefaults = .standard
    ) -> Identity? {
        identities(in: defaults)[storageKey(for: credential)]
    }

    private static func identities(in defaults: UserDefaults) -> [String: Identity] {
        guard
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([String: Identity].self, from: data)
        else { return [:] }
        return decoded
    }

    /// Le fournisseur et son identifiant stable. Deux comptes Apple sur le même
    /// appareil ne doivent pas se marcher dessus.
    private static func storageKey(for credential: SocialCredential) -> String {
        "\(credential.provider.rawValue):\(credential.userIdentifier)"
    }
}
