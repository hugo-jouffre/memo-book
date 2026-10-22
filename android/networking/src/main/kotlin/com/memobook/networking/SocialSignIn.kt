package com.memobook.networking

import com.memobook.core.AuthProvider
import kotlinx.serialization.Serializable

/**
 * Ce que l'app transmet au serveur pour entrer par Apple ou Google. Le jumeau
 * de `MemoBookNetworking/SocialSignIn.swift`.
 *
 * Volontairement un simple porteur de données : c'est l'écran d'entrée qui
 * sait parler au Credential Manager et à Google, et il traduit sa réponse en
 * ceci. La couche réseau n'a pas à connaître ces bibliothèques.
 *
 * **Important** : rien ici n'est une preuve d'identité. [identityToken] est un
 * JWT signé par le fournisseur, que **seul le serveur** peut vérifier, et qu'il
 * vérifie effectivement — signature, émetteur, audience, expiration, et le
 * nonce du côté d'Apple.
 *
 * @property nonce Le nonce en clair de cette tentative. Requis par Apple,
 *   inutilisé par Google, dont c'est l'audience du jeton qui joue ce rôle.
 * @property firstName Apple ne les donne qu'à la toute première autorisation.
 *   Les transmettre est donc la seule occasion de les enregistrer.
 */
@Serializable
data class SocialSignIn(
    val provider: AuthProvider,
    val identityToken: String,
    val nonce: String? = null,
    val firstName: String? = null,
    val lastName: String? = null,
)
