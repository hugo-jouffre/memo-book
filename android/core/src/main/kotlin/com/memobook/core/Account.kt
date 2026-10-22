package com.memobook.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant

// Le compte et sa session. Le jumeau de `MemoBookCore/Account.swift`.

/**
 * La personne connectée, telle que le serveur la décrit.
 *
 * L'adresse est facultative : quelqu'un entré par Apple avec l'adresse masquée
 * et le partage refusé n'en a pas. Ce n'est pas une anomalie à corriger, c'est
 * un choix que l'app doit savoir respecter.
 */
@Serializable
data class Account(
    val id: String,
    val email: String? = null,
    val firstName: String? = null,
    val lastName: String? = null,
    @Serializable(with = InstantSerializer::class) val createdAt: Instant,
) {
    /** De quoi accueillir quelqu'un par son prénom, ou rien plutôt qu'un
     *  « Bonjour  » avec un trou dedans. */
    val displayName: String?
        get() {
            val joined = listOfNotNull(firstName, lastName)
                .map { it.trimSwiftWhitespaces() }
                .filter { it.isNotEmpty() }
                .joinToString(" ")
            return joined.ifEmpty { null }
        }
}

/** `trimmingCharacters(in: .whitespaces)` : les espaces et la tabulation, pas
 *  les retours à la ligne. */
internal fun String.trimSwiftWhitespaces(): String =
    trim { it == '\t' || Character.getType(it) == Character.SPACE_SEPARATOR.toInt() }

/**
 * Une session ouverte : le jeton porteur et le compte auquel il donne accès.
 *
 * Le jeton n'arrive en clair qu'une fois, dans la réponse qui l'émet. Il part
 * ensuite au trousseau et n'en ressort que pour être posé dans un en-tête.
 */
@Serializable
data class AuthSession(
    val token: String,
    @Serializable(with = InstantSerializer::class) val expiresAt: Instant,
    val account: Account,
)

/** Les fournisseurs d'identité tiers, côté app. */
@Serializable
enum class AuthProvider(val rawValue: String) {
    @SerialName("apple") Apple("apple"),
    @SerialName("google") Google("google"),
    ;

    /** Le nom de la marque, tel qu'on l'écrit à l'utilisateur. */
    val displayName: String
        get() = when (this) {
            Apple -> "Apple"
            Google -> "Google"
        }

    /** L'autocollant de la marque dans le catalogue — le logo cerné de bleu
     *  des boutons d'entrée, que la ligne « E-mail » du profil reprend en
     *  petit. */
    val logoAsset: String
        get() = when (this) {
            Apple -> "LogoApple"
            Google -> "LogoGoogle"
        }
}
