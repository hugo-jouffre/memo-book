package com.memobook.feature.auth

import com.memobook.networking.ApiError

/**
 * Une erreur dont le texte est écrit pour être lu — le `LocalizedError` de
 * Swift. Les échecs propres à l'entrée ([GoogleSignInError])
 * la portent ; [ApiError] a déjà son `errorDescription`.
 */
internal interface LocalizedError {
    val errorDescription: String
}

/**
 * Le message qu'on montre vraiment à l'utilisateur. Jumeau de `AuthErrorText.swift`.
 *
 * Le message brut d'une exception n'est pas écrit pour être lu : celui du
 * Credential Manager est en anglais, numéros de code compris, comme celui
 * d'`ASAuthorizationError` sur iOS rendait « L'opération n'a pas pu s'achever
 * (com.apple.AuthenticationServices.AuthorizationError erreur 1000) ». On nomme
 * donc les cas qu'on sait nommer, et on garde une phrase neutre pour le reste —
 * jamais un code d'erreur.
 *
 * Les cas d'`ASAuthorizationError` qu'iOS nomme n'ont pas de jumeau ici :
 * Android n'a pas d'entrée par Apple (Hugo, 22/10/2026).
 */
internal fun authErrorMessage(error: Throwable): String = when (error) {
    is ApiError -> error.errorDescription
    is LocalizedError -> error.errorDescription
    else -> "La connexion n’a pas abouti. Réessaie dans un instant."
}
