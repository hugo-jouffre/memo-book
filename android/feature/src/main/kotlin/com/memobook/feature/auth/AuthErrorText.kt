package com.memobook.feature.auth

import com.memobook.networking.ApiError

/**
 * Une erreur dont le texte est écrit pour être lu — le `LocalizedError` de
 * Swift. Les échecs propres à l'entrée ([SocialSignInError],
 * [GoogleSignInError]) la portent ; [ApiError] a déjà son `errorDescription`.
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
 * Les cas d'Apple vivent dans [AppleSignInError], que le retour du web
 * pose (`AuthModel.finishAppleSignIn`) : sur Android, Apple n'a pas de feuille du système, donc pas
 * d'`ASAuthorizationError`. Le cas « aucun compte Apple sur l'appareil » (1000
 * sur iOS) n'existe pas ici — on se connecte sur la page d'Apple elle-même.
 */
internal fun authErrorMessage(error: Throwable): String = when (error) {
    is AppleSignInError -> when (error) {
        // Ne devrait jamais s'afficher : renoncer n'est pas un échec, et
        // l'écran d'entrée filtre ce cas en amont.
        AppleSignInError.Canceled -> "Connexion avec Apple abandonnée."
        AppleSignInError.NotHandled -> "Apple n’a pas pu traiter la demande. Réessaie dans un instant."
        AppleSignInError.Failed -> "Apple a refusé la connexion. Réessaie dans un instant."
        AppleSignInError.Unknown -> "La connexion avec Apple n’a pas abouti. Réessaie dans un instant."
    }
    is ApiError -> error.errorDescription
    is LocalizedError -> error.errorDescription
    else -> "La connexion n’a pas abouti. Réessaie dans un instant."
}

/**
 * Ce que le retour d'Apple sur le web peut dire d'un échec — les familles de
 * `ASAuthorizationError.Code` que l'écran d'iOS distingue. Voir
 * [AppleSignInService].
 */
internal sealed class AppleSignInError : Exception() {
    /** La page d'Apple a été refermée, ou « Annuler » touché (`user_cancelled_authorize`). */
    data object Canceled : AppleSignInError()

    /** La demande n'a pas pu être traitée — `notHandled`, `notInteractive` sur iOS. */
    data object NotHandled : AppleSignInError()

    /** Apple a répondu par un refus — `invalidResponse`, `failed` sur iOS. */
    data object Failed : AppleSignInError()

    data object Unknown : AppleSignInError()
}
