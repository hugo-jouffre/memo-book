package com.memobook.feature.auth

import com.memobook.feature.InMemoryAppSettings
import com.memobook.networking.MemoBookApi
import java.lang.reflect.Proxy
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Les règles qui décident si « Continuer » s'allume. Elles vivent dans le
 * modèle précisément pour être vérifiables ici, sans émulateur. Porté de
 * `AuthModelTests.swift`, cas pour cas.
 */
class AuthModelTest {
    /**
     * Ces règles sont purement locales : elles décident si « Continuer »
     * s'allume, avant tout appel. L'API n'est là que parce que le modèle en
     * exige une — un double qui refuse tout appel.
     */
    private fun model(configure: AuthModel.() -> Unit): AuthModel =
        AuthModel(api = unreachableApi, settings = InMemoryAppSettings()).apply(configure)

    // MARK: - Email

    @Test fun emailNeedsAnAtSignAndADottedHost() {
        val cases = listOf(
            "hugo@memobook.app" to true,
            "hugo+voyage@memo.book.app" to true,
            "hugo@memobook" to false,
            "hugo.memobook.app" to false,
            "@memobook.app" to false,
            "hugo@.app" to false,
            "hugo@memobook." to false,
            "" to false,
        )

        for ((email, expected) in cases) {
            val model = model { this.email = email }
            assertEquals(expected, model.state.value.isEmailValid, "« $email »")
        }
    }

    // MARK: - Mot de passe

    @Test fun passwordNeedsEightCharactersALetterAndADigit() {
        val cases = listOf(
            "carnet2026" to true,
            "a1bcdefg" to true,
            "carnet26" to true,
            "carnets" to false, // trop court et sans chiffre
            "carnetsdevoyage" to false, // pas de chiffre
            "20260903" to false, // pas de lettre
            "a1bcdef" to false, // sept caractères
        )

        for ((password, expected) in cases) {
            val model = model { this.password = password }
            assertEquals(expected, model.state.value.isPasswordValid, "« $password »")
        }
    }

    @Test fun confirmationErrorOnlyShowsOnceSomethingIsTyped() {
        val model = model { password = "carnet2026" }
        assertNull(model.state.value.passwordConfirmationError, "Rien à signaler tant que le champ est vide.")

        model.passwordConfirmation = "carnet20"
        assertNotNull(model.state.value.passwordConfirmationError)

        model.passwordConfirmation = "carnet2026"
        assertNull(model.state.value.passwordConfirmationError)
    }

    // MARK: - Ce que « Continuer » attend

    @Test fun signUpNeedsEveryField() {
        val model = model {
            mode = AuthMode.SignUp
            firstName = "Hugo"
            lastName = "Jouffre"
            email = "hugo@memobook.app"
            password = "carnet2026"
            passwordConfirmation = "carnet2026"
        }
        assertTrue(model.state.value.canSubmit)

        model.passwordConfirmation = "carnet2027"
        assertFalse(model.state.value.canSubmit, "Deux mots de passe différents bloquent l'envoi.")

        model.passwordConfirmation = "carnet2026"
        model.firstName = "   "
        assertFalse(model.state.value.canSubmit, "Un prénom fait d'espaces ne compte pas.")
    }

    @Test fun signInOnlyNeedsAnEmailAndAPassword() {
        val model = model {
            mode = AuthMode.SignIn
            email = "hugo@memobook.app"
            password = "x"
        }
        // À la connexion on ne rejoue pas la règle de complexité : le mot de
        // passe a pu être créé sous d'autres règles, c'est au serveur de dire
        // s'il est bon.
        assertTrue(model.state.value.canSubmit)

        model.email = "hugo@memobook"
        assertFalse(model.state.value.canSubmit)
    }

    @Test fun switchingModeReusesWhatWasAlreadyTyped() {
        val model = model {
            mode = AuthMode.SignUp
            email = "hugo@memobook.app"
            password = "carnet2026"
        }
        assertFalse(model.state.value.canSubmit, "Il manque le nom et la confirmation.")

        model.mode = AuthMode.SignIn
        assertTrue(model.state.value.canSubmit, "L'email et le mot de passe suffisent en connexion.")
    }

    // MARK: - Enchaînement du clavier

    @Test fun keyboardChainsThroughTheVisibleFieldsOnly() {
        val signUp = model { mode = AuthMode.SignUp }
        assertEquals(AuthField.LastName, signUp.fieldAfter(AuthField.FirstName))
        assertEquals(AuthField.Email, signUp.fieldAfter(AuthField.LastName))
        assertEquals(AuthField.Password, signUp.fieldAfter(AuthField.Email))
        assertEquals(AuthField.PasswordConfirmation, signUp.fieldAfter(AuthField.Password))
        assertNull(signUp.fieldAfter(AuthField.PasswordConfirmation), "Dernier champ : on valide.")

        val signIn = model { mode = AuthMode.SignIn }
        assertEquals(AuthField.Password, signIn.fieldAfter(AuthField.Email))
        assertNull(signIn.fieldAfter(AuthField.Password))
        assertNull(signIn.fieldAfter(AuthField.FirstName), "Le prénom n'existe pas en connexion.")
    }
}

/** Un double d'API qui refuse tout appel : le `PreviewAPI(seeded: false)` des tests iOS, pour ce qu'ils en font. */
private val unreachableApi: MemoBookApi =
    Proxy.newProxyInstance(MemoBookApi::class.java.classLoader, arrayOf(MemoBookApi::class.java)) { proxy, method, arguments ->
        when (method.name) {
            "equals" -> proxy === arguments?.firstOrNull()
            "hashCode" -> System.identityHashCode(proxy)
            "toString" -> "MemoBookApi (test)"
            else -> throw UnsupportedOperationException("${method.name} n'est pas appelé par ces règles.")
        }
    } as MemoBookApi
