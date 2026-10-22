package com.memobook.feature.auth

import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

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

/**
 * Le nonce de Sign in with Apple : un secret à usage unique, tiré ici, envoyé
 * haché à Apple, et gardé en clair le temps de l'échange.
 *
 * Apple recopie l'empreinte dans le jeton d'identité qu'il signe. Le serveur
 * rehache le nonce en clair que l'app lui transmet et compare : si les deux
 * concordent, ce jeton a bien été demandé par cette app, pour cette tentative
 * précise. C'est ce qui empêche de rejouer un jeton intercepté ailleurs.
 *
 * Sans nonce, le jeton reste signé par Apple, donc authentique — mais plus
 * rien ne dit qu'il a été émis *pour nous*.
 */
class SignInNonce(
    /** La valeur en clair, celle qui part vers notre serveur. */
    val raw: String = random(),
) {
    /** L'empreinte, celle qui part vers Apple. */
    val hashed: String
        get() = MessageDigest.getInstance("SHA-256")
            .digest(raw.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    private companion object {
        /**
         * 32 octets de hasard cryptographique. `base64url` parce que la valeur
         * finit dans un JWT, où « + » et « / » demanderaient un échappement.
         */
        fun random(): String {
            val bytes = ByteArray(32).also(SecureRandom()::nextBytes)
            return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
        }
    }
}
