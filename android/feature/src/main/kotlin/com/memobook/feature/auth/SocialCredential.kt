package com.memobook.feature.auth

/**
 * Ce qu'une entrée par fournisseur tiers rapporte, une fois le fournisseur
 * d'accord. C'est le seul objet que l'écran d'entrée transmet ensuite au
 * serveur, quel que soit le fournisseur. Jumeau de `SocialCredential.swift`.
 *
 * **Important** : le jeton n'est **pas** une preuve tant que le serveur ne l'a
 * pas vérifié lui-même, contre les clés publiques d'Apple ou de Google. Un
 * client peut envoyer ce qu'il veut ; c'est la signature du jeton, et elle
 * seule, qui identifie quelqu'un.
 *
 * @property userIdentifier l'identifiant stable de la personne chez ce
 *   fournisseur — le `sub` du jeton. Il ne change jamais, et ne vaut que pour
 *   notre app : le même compte Apple donne un identifiant différent à chaque
 *   développeur.
 * @property identityToken le JWT signé par le fournisseur. À transmettre tel quel.
 * @property nonce le nonce en clair de cette tentative, qu'Apple a recopié
 *   haché dans le jeton. Le serveur compare les deux. Google n'en utilise pas ici.
 * @property firstName Apple ne donne l'identité qu'à la **toute première**
 *   autorisation, et jamais ensuite : ces trois champs sont vides à chaque
 *   reconnexion.
 */
data class SocialCredential(
    val provider: Provider,
    val userIdentifier: String,
    val identityToken: String,
    val nonce: String?,
    val firstName: String?,
    val lastName: String?,
    val email: String?,
) {
    enum class Provider(val rawValue: String) {
        Apple("apple"),
        Google("google"),
    }
}
