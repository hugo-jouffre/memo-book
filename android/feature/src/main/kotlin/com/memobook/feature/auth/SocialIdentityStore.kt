package com.memobook.feature.auth

import com.memobook.feature.AppSettings
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json

/**
 * Garde ce qu'Apple ne dit qu'une fois. Jumeau de `SocialIdentityStore.swift`.
 *
 * Apple ne transmet le nom et l'adresse qu'à la **toute première**
 * autorisation d'une app pour un compte donné. À la reconnexion suivante ces
 * champs sont vides, et le seul moyen de les revoir est d'aller révoquer l'app
 * dans les réglages du compte Apple. Sur le web aussi (lot B2) : le `user` du
 * retour d'Apple n'arrive qu'une fois.
 *
 * Tant que le serveur n'existe pas pour les recevoir, ils sont conservés ici :
 * sans ça, la première connexion d'essai détruirait une information qu'on ne
 * peut plus redemander. Quand l'API d'authentification arrivera, ce fichier
 * disparaît — c'est le serveur qui gardera l'identité.
 */
internal object SocialIdentityStore {
    private const val KEY = "pendingSocialIdentities"

    private val coder = Json { ignoreUnknownKeys = true }
    private val mapSerializer = MapSerializer(String.serializer(), Identity.serializer())

    /** Ce qu'un fournisseur a dit d'une personne, au moment où il l'a dit. */
    @Serializable
    data class Identity(
        val firstName: String? = null,
        val lastName: String? = null,
        val email: String? = null,
    )

    /**
     * N'écrase jamais un nom déjà connu par un vide : la deuxième connexion
     * Apple rapporte des champs nuls, et ce sont ceux de la première qu'on
     * veut garder.
     */
    fun remember(credential: SocialCredential, settings: AppSettings) {
        if (credential.firstName == null && credential.lastName == null && credential.email == null) return

        val all = identities(settings).toMutableMap()
        all[storageKey(credential)] = Identity(
            firstName = credential.firstName,
            lastName = credential.lastName,
            email = credential.email,
        )
        val data = runCatching { coder.encodeToString(mapSerializer, all) }.getOrNull() ?: return
        settings.putString(KEY, data)
    }

    fun identity(credential: SocialCredential, settings: AppSettings): Identity? =
        identities(settings)[storageKey(credential)]

    private fun identities(settings: AppSettings): Map<String, Identity> {
        val data = settings.getString(KEY) ?: return emptyMap()
        return runCatching { coder.decodeFromString(mapSerializer, data) }.getOrDefault(emptyMap())
    }

    /**
     * Le fournisseur et son identifiant stable. Deux comptes Apple sur le même
     * appareil ne doivent pas se marcher dessus.
     */
    private fun storageKey(credential: SocialCredential): String =
        "${credential.provider.rawValue}:${credential.userIdentifier}"
}
