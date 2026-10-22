package com.memobook.feature.auth

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import java.net.URI
import java.net.URLDecoder
import java.util.Base64

/**
 * Le retour de la page web d'Apple, relayé par le serveur :
 * `memobook://auth/apple?id_token=…&state=…[&first_name=…&last_name=…&email=…]`,
 * ou `memobook://auth/apple?error=…&state=…`. Écrit par
 * `backend/src/routes/appleWebSignIn.ts` (lot B2). Pas de jumeau Swift : l'iPhone
 * a la feuille Apple du système.
 *
 * Ce n'est **qu'un relais** : rien ici n'est vérifié. Le `state` est comparé
 * par [AuthModel.finishAppleSignIn] à celui de la tentative en cours, et le
 * jeton par le serveur, à `POST /v1/auth/apple`.
 */
sealed interface AppleWebReturn {
    val state: String?

    data class Authorized(
        val identityToken: String,
        override val state: String,
        val firstName: String?,
        val lastName: String?,
        val email: String?,
    ) : AppleWebReturn

    /** `user_cancelled_authorize` quand la page d'Apple a été refermée. */
    data class Failed(val error: String, override val state: String?) : AppleWebReturn

    companion object {
        /** Le retour porté par ce lien, ou `null` si ce n'en est pas un. */
        fun from(uri: URI): AppleWebReturn? {
            if (uri.scheme?.lowercase() != "memobook") return null
            // « auth » est l'hôte, « /apple » le chemin, comme `memobook://password/reset`.
            if (uri.host != "auth" || uri.path.orEmpty().trim('/') != "apple") return null
            val query = query(uri)
            val state = query["state"]
            query["error"]?.let { return Failed(it, state) }
            val token = query["id_token"] ?: return Failed("invalid_request", state)
            if (state == null) return Failed("invalid_request", null)
            return Authorized(
                identityToken = token,
                state = state,
                firstName = query["first_name"],
                lastName = query["last_name"],
                email = query["email"],
            )
        }

        /** Les paramètres non vides du lien, décodés. `%20` y est une espace, et le `+` aussi. */
        private fun query(uri: URI): Map<String, String> = uri.rawQuery.orEmpty()
            .split('&')
            .mapNotNull { pair ->
                val parts = pair.split('=', limit = 2)
                val key = URLDecoder.decode(parts[0], Charsets.UTF_8.name())
                val value = URLDecoder.decode(parts.getOrElse(1) { "" }, Charsets.UTF_8.name()).trim()
                if (key.isEmpty() || value.isEmpty()) null else key to value
            }
            .toMap()
    }
}

/**
 * Le `sub` d'un jeton d'identité, **lu sans être vérifié** : il ne sert qu'à
 * ranger ce qu'Apple ne dit qu'une fois ([SocialIdentityStore]) sous la bonne
 * personne. Sur iOS, la feuille Apple le donne à part (`credential.user`) ; ici,
 * il n'est que dans le jeton. Ce n'est jamais une preuve — le serveur, lui,
 * vérifie la signature.
 */
internal fun unverifiedSubject(identityToken: String): String? = runCatching {
    val payload = identityToken.split('.').getOrNull(1) ?: return null
    val json = String(Base64.getUrlDecoder().decode(payload.trimEnd('=')), Charsets.UTF_8)
    (Json.parseToJsonElement(json) as? JsonObject)?.get("sub")?.jsonPrimitive?.contentOrNull
}.getOrNull()
