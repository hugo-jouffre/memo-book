package com.memobook.feature.auth

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import androidx.browser.customtabs.CustomTabsIntent
import androidx.core.net.toUri
import java.net.URI
import java.net.URLEncoder

/**
 * L'entrée par Apple **sur Android**, qui n'a pas de feuille Apple du système :
 * elle passe par la page web d'Apple. Pas de jumeau Swift — sur iOS, c'est
 * `SignInWithAppleButton` dans `WelcomeSocialButtons`.
 *
 * **Le bouton reste masqué** tant que `memobook.appleServicesId` est vide
 * (`gradle.properties`) : le Services ID se crée chez Apple (lot A0), et le
 * serveur doit connaître le même (`APPLE_SERVICES_ID`).
 *
 * ### Le flux (lot B2, 22/10/2026)
 *
 * 1. L'app tire un [SignInNonce] et un `state`, et ouvre
 *    `https://appleid.apple.com/auth/authorize` ([authorizationUri]) avec le
 *    **Services ID** pour `client_id`, l'empreinte du nonce, `scope=name email`
 *    et `response_mode=form_post`. Un Custom Tab de préférence (bibliothèque
 *    `androidx.browser`) ; le navigateur par défaut sinon.
 * 2. Apple poste sa réponse (`id_token`, `state`, et `user` — le nom et
 *    l'adresse, **à la toute première autorisation seulement**) au serveur,
 *    sur l'adresse de retour déclarée sur le Services ID :
 *    `POST /v1/auth/apple/callback` **du serveur de production** ([redirectUri]),
 *    même depuis un build Debug — Apple n'accepte que l'adresse déclarée, et
 *    pas un schéma privé : c'est pour ça que le serveur s'interpose.
 * 3. Le serveur renvoie l'app par `memobook://auth/apple?…` avec ce qu'Apple
 *    lui a posté ([AppleWebReturn]). `RootView` le reçoit comme les autres
 *    liens et le remet à l'écran d'entrée ; `AuthModel.finishAppleSignIn`
 *    vérifie le `state`, en fait un [SocialCredential] avec le nonce **en
 *    clair** qu'il a gardé, et le passe à `AuthModel.accept` — qui l'envoie
 *    à `POST /v1/auth/apple` comme l'iPhone. Le serveur y vérifie le jeton
 *    contre les clés d'Apple, l'audience (le Services ID, accepté par B2 à côté
 *    de l'App ID) et le nonce.
 *
 * ⚠️ **Un seul compte Apple pour une personne** : le Services ID doit être
 * groupé sous l'App ID `com.memobook.app`, sans quoi Apple rendrait un autre
 * `sub` que sur l'iPhone — et un second compte MemoBook (`docs/android.md`,
 * « Les risques »).
 */
internal object AppleSignInService {
    /**
     * L'adresse de la page d'autorisation d'Apple, pour cette tentative.
     *
     * @param redirectUri l'adresse du serveur qui reçoit le `form_post` ([redirectUri]).
     * @param state un jeton à usage unique, recopié par Apple dans sa réponse :
     *   il dit que le retour répond bien à **cette** demande.
     */
    fun authorizationUri(servicesId: String, redirectUri: URI, state: String, nonce: SignInNonce): String {
        val query = listOf(
            "client_id" to servicesId,
            "redirect_uri" to redirectUri.toString(),
            "response_type" to "code id_token",
            "response_mode" to "form_post",
            // Apple ne les donne qu'à la toute première autorisation, et les
            // ignore poliment ensuite. Les demander coûte donc une seule fois.
            "scope" to "name email",
            "state" to state,
            // Haché, jamais en clair : ce qui part chez Apple ne doit pas
            // suffire à rejouer la tentative.
            "nonce" to nonce.hashed,
        ).joinToString("&") { (key, value) -> "$key=${URLEncoder.encode(value, Charsets.UTF_8.name()).replace("+", "%20")}" }
        return "$AUTHORIZE_URL?$query"
    }

    /**
     * L'adresse où Apple poste sa réponse : celle déclarée sur le Services ID,
     * au caractère près. `null` sans adresse de production.
     */
    fun redirectUri(productionApiBaseUrl: URI?): URI? {
        val base = productionApiBaseUrl?.toString()?.trimEnd('/') ?: return null
        return URI("$base$CALLBACK_PATH")
    }

    /**
     * Ouvre la page d'Apple dans un Custom Tab — l'app reste derrière, et le
     * retour la rouvre là où elle était. Le navigateur par défaut si le
     * téléphone n'a aucun navigateur qui les sache. `false` si rien ne peut
     * l'ouvrir.
     */
    fun open(context: Context, authorizationUri: String): Boolean {
        val uri = authorizationUri.toUri()
        return try {
            CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(context, uri)
            true
        } catch (_: ActivityNotFoundException) {
            try {
                context.startActivity(Intent(Intent.ACTION_VIEW, uri))
                true
            } catch (_: ActivityNotFoundException) {
                false
            }
        }
    }

    /** La route de `backend/src/routes/appleWebSignIn.ts`. */
    internal const val CALLBACK_PATH = "/v1/auth/apple/callback"

    private const val AUTHORIZE_URL = "https://appleid.apple.com/auth/authorize"
}
