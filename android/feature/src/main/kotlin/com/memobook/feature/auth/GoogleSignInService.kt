package com.memobook.feature.auth

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.libraries.identity.googleid.GoogleIdTokenParsingException

/**
 * L'entrée par Google. Jumeau de `GoogleSignInService.swift`.
 *
 * Sur iOS, c'est le SDK Google et sa feuille ; ici, le **Credential Manager**
 * d'Android et sa feuille « Se connecter avec Google », qui rendent la même
 * chose : un jeton d'identité signé par Google, que le serveur vérifie comme
 * celui de l'iPhone (`POST /v1/auth/google`).
 *
 * Google ne signe rien tant qu'on ne lui a pas dit **pour qui** : c'est le rôle
 * de l'identifiant client **web** (`serverClientId`), l'audience des jetons —
 * `memobook.googleWebClientId` dans `gradle.properties`, que le serveur connaît
 * sous `GOOGLE_WEB_CLIENT_ID` (lot B1). Il n'est pas un secret : il part dans
 * chaque APK. Le client **Android** du même projet (nom de paquet et SHA-1 de
 * la signature, lot A0) n'apparaît nulle part dans le code : Google le retrouve
 * à la signature de l'app. Le *client secret*, lui, n'a rien à faire ici.
 */
internal object GoogleSignInService {
    /**
     * Ouvre la feuille Google et rend de quoi identifier la personne.
     *
     * @return `null` si l'utilisateur a renoncé. Renoncer n'est pas un échec,
     *   et ne doit rien afficher.
     */
    suspend fun signIn(context: Context, webClientId: String?): SocialCredential? {
        val clientId = webClientId?.takeIf { it.isNotBlank() } ?: throw GoogleSignInError.MissingClientId
        // La feuille a besoin d'une activité qui la présente, comme le
        // contrôleur de la scène active sur iOS.
        val activity = context.findActivity() ?: throw GoogleSignInError.NoPresenter

        val request = GetCredentialRequest.Builder()
            .addCredentialOption(GetSignInWithGoogleOption.Builder(serverClientId = clientId).build())
            .build()
        val response = try {
            CredentialManager.create(activity).getCredential(activity, request)
        } catch (_: GetCredentialCancellationException) {
            return null
        } catch (_: NoCredentialException) {
            // Aucun compte Google sur le téléphone, ou les services Google
            // absents : la fenêtre n'a rien à montrer.
            throw GoogleSignInError.NoPresenter
        } catch (_: GetCredentialException) {
            throw GoogleSignInError.NoPresenter
        }

        // Deux types pour le même jeton : celui de la feuille du bouton
        // « Se connecter avec Google », et celui de la liste des comptes.
        val credential = response.credential
        if (credential !is CustomCredential || credential.type !in googleTokenTypes) {
            throw GoogleSignInError.NoIdentityToken
        }
        val google = try {
            GoogleIdTokenCredential.createFrom(credential.data)
        } catch (_: GoogleIdTokenParsingException) {
            throw GoogleSignInError.NoIdentityToken
        }

        return SocialCredential(
            provider = SocialCredential.Provider.Google,
            // Le `sub` du jeton, l'identifiant stable de la personne chez Google.
            userIdentifier = google.uniqueId.ifBlank { google.idToken },
            identityToken = google.idToken,
            // Google ne pratique pas le nonce ici : c'est l'audience du jeton,
            // vérifiée côté serveur, qui joue ce rôle.
            nonce = null,
            firstName = google.givenName,
            lastName = google.familyName,
            email = google.email,
        )
    }

    private val googleTokenTypes = setOf(
        GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL,
        GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_SIWG_CREDENTIAL,
    )

    private tailrec fun Context.findActivity(): Activity? = when (this) {
        is Activity -> this
        is ContextWrapper -> baseContext.findActivity()
        else -> null
    }
}

internal sealed class GoogleSignInError : Exception(), LocalizedError {
    data object MissingClientId : GoogleSignInError() {
        // Message de développeur assumé : le bouton ne s'affiche pas sans
        // identifiant, cet état ne peut donc arriver que dans un build mal configuré.
        override val errorDescription = "Le client OAuth Google n’est pas configuré (memobook.googleWebClientId dans gradle.properties)."
    }

    data object NoPresenter : GoogleSignInError() {
        override val errorDescription = "Impossible d’ouvrir la fenêtre Google. Réessaie."
    }

    data object NoIdentityToken : GoogleSignInError() {
        override val errorDescription = "Google n’a pas transmis d’identifiant utilisable. Réessaie."
    }

    override val message: String get() = errorDescription
}
