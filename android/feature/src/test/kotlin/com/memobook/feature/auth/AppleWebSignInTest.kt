package com.memobook.feature.auth

import com.memobook.core.Account
import com.memobook.core.AuthProvider
import com.memobook.core.AuthSession
import com.memobook.feature.InMemoryAppSettings
import com.memobook.feature.welcome.SocialSignInError
import com.memobook.networking.MemoBookApi
import com.memobook.networking.SocialSignIn
import kotlinx.coroutines.test.runTest
import java.lang.reflect.Proxy
import java.net.URI
import java.time.Instant
import java.util.Base64
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * « Continuer avec Apple » par la page web d'Apple (lot B2) : le lien que le
 * serveur renvoie (`backend/src/routes/appleWebSignIn.ts`), et ce que le modèle
 * en fait. Pas de jumeau iOS — l'iPhone a la feuille Apple du système.
 */
class AppleWebSignInTest {
    // MARK: - Le lien

    @Test fun readsTheTokenStateAndFirstConsentIdentity() {
        // La forme exacte qu'écrit `appleReturnPath` côté serveur.
        val uri = URI("memobook://auth/apple?id_token=eyJ.jeton.sign%C3%A9&state=s-42&first_name=Marie%20Claire&last_name=Jouffre&email=hugo%40example.com")
        assertEquals(
            AppleWebReturn.Authorized(
                identityToken = "eyJ.jeton.signé",
                state = "s-42",
                firstName = "Marie Claire",
                lastName = "Jouffre",
                email = "hugo@example.com",
            ),
            AppleWebReturn.from(uri),
        )
    }

    @Test fun laterSignInsCarryNoIdentity() {
        val result = AppleWebReturn.from(URI("memobook://auth/apple?id_token=jwt&state=s"))
        assertEquals(AppleWebReturn.Authorized("jwt", "s", null, null, null), result)
    }

    @Test fun errorsAndMissingPiecesAreFailures() {
        assertEquals(
            AppleWebReturn.Failed("user_cancelled_authorize", "s"),
            AppleWebReturn.from(URI("memobook://auth/apple?error=user_cancelled_authorize&state=s")),
        )
        assertEquals(AppleWebReturn.Failed("invalid_request", "s"), AppleWebReturn.from(URI("memobook://auth/apple?state=s")))
        assertEquals(AppleWebReturn.Failed("invalid_request", null), AppleWebReturn.from(URI("memobook://auth/apple?id_token=jwt")))
    }

    @Test fun otherLinksAreNotAppleReturns() {
        assertNull(AppleWebReturn.from(URI("memobook://password/reset?token=abc")))
        assertNull(AppleWebReturn.from(URI("memobook://auth/google?id_token=jwt&state=s")))
        assertNull(AppleWebReturn.from(URI("https://api.memo-book.com/auth/apple?id_token=jwt&state=s")))
    }

    @Test fun theRedirectIsTheProductionCallback() {
        assertEquals(
            URI("https://api-production-9f35a.up.railway.app/v1/auth/apple/callback"),
            AppleSignInService.redirectUri(URI("https://api-production-9f35a.up.railway.app/")),
        )
        assertNull(AppleSignInService.redirectUri(null))
    }

    @Test fun theAuthorizationPageAsksForAFormPostWithTheHashedNonce() {
        val nonce = SignInNonce("en-clair")
        val page = AppleSignInService.authorizationUri(
            "com.memobook.app.web",
            URI("https://api.example.com/v1/auth/apple/callback"),
            "s-1",
            nonce,
        )
        assertTrue(page.startsWith("https://appleid.apple.com/auth/authorize?client_id=com.memobook.app.web&"))
        assertTrue("response_type=code%20id_token" in page)
        assertTrue("response_mode=form_post" in page)
        assertTrue("state=s-1" in page)
        assertTrue("nonce=${nonce.hashed}" in page)
        assertTrue("en-clair" !in page, "Le nonce en clair ne part jamais chez Apple.")
    }

    @Test fun readsTheSubjectWithoutVerifying() {
        assertEquals("000123.apple", unverifiedSubject(jwt("""{"sub":"000123.apple","aud":"x"}""")))
        assertNull(unverifiedSubject("pas-un-jeton"))
    }

    // MARK: - Le modèle

    @Test fun aMatchingReturnSignsInWithTheRawNonceAndTheNames() = runTest {
        val api = RecordingApi()
        val model = AuthModel(api.proxy, InMemoryAppSettings())
        model.beginAppleSignIn("com.memobook.app.web", URI("https://api.example.com/v1/auth/apple/callback"))
        val attempt = assertNotNull(model.appleAttempt)

        val account = model.finishAppleSignIn(
            AppleWebReturn.Authorized(jwt("""{"sub":"s1"}"""), attempt.state, "Hugo", "Jouffre", "hugo@example.com"),
        )

        assertEquals("compte-1", account?.id)
        val sent = assertNotNull(api.sent.singleOrNull())
        assertEquals(AuthProvider.Apple, sent.provider)
        assertEquals(attempt.nonce.raw, sent.nonce, "Le serveur rehache le nonce en clair.")
        assertEquals("Hugo", sent.firstName)
        assertEquals("Jouffre", sent.lastName)
        assertNull(model.appleAttempt, "Une tentative ne sert qu'une fois.")
    }

    @Test fun theFirstConsentNamesSurviveAFailedCall() = runTest {
        // Apple ne redonne jamais le nom : un premier appel raté ne doit pas le perdre.
        val settings = InMemoryAppSettings()
        val failing = RecordingApi(fails = true)
        val first = AuthModel(failing.proxy, settings)
        first.beginAppleSignIn("id", URI("https://x/v1/auth/apple/callback"))
        val token = jwt("""{"sub":"s1"}""")
        assertNull(first.finishAppleSignIn(AppleWebReturn.Authorized(token, first.appleAttempt!!.state, "Hugo", "Jouffre", null)))

        val api = RecordingApi()
        val second = AuthModel(api.proxy, settings)
        second.beginAppleSignIn("id", URI("https://x/v1/auth/apple/callback"))
        second.finishAppleSignIn(AppleWebReturn.Authorized(token, second.appleAttempt!!.state, null, null, null))
        assertEquals("Hugo", api.sent.single().firstName)
    }

    @Test fun aReturnForAnotherAttemptIsRefusedAndKeepsTheAttempt() = runTest {
        val api = RecordingApi()
        val model = AuthModel(api.proxy, InMemoryAppSettings())
        model.beginAppleSignIn("id", URI("https://x/v1/auth/apple/callback"))

        val account = model.finishAppleSignIn(AppleWebReturn.Authorized(jwt("""{"sub":"s"}"""), "un-autre-state", null, null, null))

        assertNull(account)
        assertTrue(api.sent.isEmpty(), "Un jeton qui ne répond pas à notre demande ne part pas au serveur.")
        assertNotNull(model.appleAttempt, "La vraie réponse d'Apple peut encore arriver.")
        assertNotNull(model.state.value.errorMessage)
    }

    @Test fun aReturnWithoutAnAttemptIsRefused() = runTest {
        val api = RecordingApi()
        val model = AuthModel(api.proxy, InMemoryAppSettings())
        assertNull(model.finishAppleSignIn(AppleWebReturn.Authorized("jwt", "s", null, null, null)))
        assertTrue(api.sent.isEmpty())
        assertNotNull(model.state.value.errorMessage)
    }

    @Test fun cancellingSaysNothing() = runTest {
        val model = AuthModel(RecordingApi().proxy, InMemoryAppSettings())
        model.beginAppleSignIn("id", URI("https://x/v1/auth/apple/callback"))
        val state = model.appleAttempt!!.state

        assertNull(model.finishAppleSignIn(AppleWebReturn.Failed("user_cancelled_authorize", state)))
        assertNull(model.state.value.errorMessage, "Renoncer n'est pas un échec.")
        assertNull(model.appleAttempt)
    }

    @Test fun anAppleRefusalIsSaid() = runTest {
        val model = AuthModel(RecordingApi().proxy, InMemoryAppSettings())
        model.beginAppleSignIn("id", URI("https://x/v1/auth/apple/callback"))

        model.finishAppleSignIn(AppleWebReturn.Failed("invalid_request", model.appleAttempt!!.state))
        assertEquals(SocialSignInError.UnusableAppleCredential.errorDescription, model.state.value.errorMessage)
    }
}

/** Un JWT non signé, pour ce que l'app en lit sans le vérifier. */
private fun jwt(payload: String): String {
    val encoder = Base64.getUrlEncoder().withoutPadding()
    return listOf("""{"alg":"none"}""", payload).joinToString(".") { encoder.encodeToString(it.toByteArray()) } + ".signature"
}

/** Un double d'API qui garde chaque entrée par fournisseur, et ouvre une session — ou échoue. */
private class RecordingApi(private val fails: Boolean = false) {
    val sent = mutableListOf<SocialSignIn>()

    val proxy: MemoBookApi =
        Proxy.newProxyInstance(MemoBookApi::class.java.classLoader, arrayOf(MemoBookApi::class.java)) { proxy, method, arguments ->
            when (method.name) {
                "equals" -> proxy === arguments?.firstOrNull()
                "hashCode" -> System.identityHashCode(proxy)
                "toString" -> "MemoBookApi (test)"
                "signIn" -> {
                    val social = arguments?.firstOrNull() as? SocialSignIn
                        ?: throw UnsupportedOperationException("Seule l'entrée par fournisseur est attendue.")
                    sent += social
                    if (fails) throw java.io.IOException("hors ligne")
                    AuthSession(
                        token = "jeton",
                        expiresAt = Instant.EPOCH,
                        account = Account(id = "compte-1", firstName = social.firstName, createdAt = Instant.EPOCH),
                    )
                }
                else -> throw UnsupportedOperationException("${method.name} n'est pas appelé ici.")
            }
        } as MemoBookApi
}
