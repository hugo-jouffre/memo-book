package com.memobook.feature.profile

import com.memobook.networking.ApiError
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * « Modifier mon mot de passe » : ce que le bouton attend, et la phrase de
 * chaque issue. iOS n'a pas de suite à elle ; ces cas tiennent les quatre
 * issues que l'en-tête de `PasswordChangeSheet.swift` énonce.
 */
class PasswordChangeModelTest {
    private fun filled(model: PasswordChangeModel) {
        model.currentPassword = "ancien2026"
        model.newPassword = "nouveau2026"
        model.confirmation = "nouveau2026"
    }

    @Test
    fun theButtonWaitsForThreeAgreeingFields() {
        val model = PasswordChangeModel(email = "camille@memobook.app")
        assertFalse(model.state.value.canSubmit)

        model.newPassword = "court1"
        model.confirmation = "court1"
        model.currentPassword = "ancien2026"
        assertFalse(model.state.value.canSubmit, "Huit caractères minimum.")

        filled(model)
        assertTrue(model.state.value.canSubmit)

        model.confirmation = "nouveau2027"
        assertFalse(model.state.value.canSubmit)
        assertEquals(com.memobook.feature.auth.AuthModel.passwordMismatchMessage, model.state.value.confirmationError)

        // L'ancien répété n'est pas un nouveau mot de passe.
        model.confirmation = "ancien2026"
        model.newPassword = "ancien2026"
        assertFalse(model.state.value.canSubmit)
    }

    /** Le lien de l'e-mail ne demande pas l'ancien mot de passe. */
    @Test
    fun aResetLinkAsksOnlyTheNewPassword() = runTest {
        var sent: Pair<String, String>? = null
        val model = PasswordChangeModel(
            mode = PasswordChangeModel.Mode.Reset("secret"),
            email = "",
            reset = { token, password -> sent = token to password },
        )
        model.newPassword = "nouveau2026"
        model.confirmation = "nouveau2026"
        assertTrue(model.state.value.canSubmit)

        model.submit()

        assertEquals("secret" to "nouveau2026", sent)
        assertEquals(PasswordChangeModel.Step.Done, model.state.value.step)
    }

    /** Un mot de passe actuel faux se dit sous son champ, et s'efface quand on le corrige. */
    @Test
    fun aWrongPasswordIsSaidUnderItsField() = runTest {
        val model = PasswordChangeModel(
            email = "camille@memobook.app",
            change = { _, _ -> throw ApiError.Server(statusCode = 400, code = "wrong_password", message = "Mot de passe incorrect") },
        )
        filled(model)

        model.submit()

        assertEquals(PasswordChangeModel.Failure.WrongPassword, model.state.value.failure)
        assertNull(model.state.value.failure?.message, "La phrase est sous le champ, pas sous le bouton.")
        assertEquals(PasswordChangeModel.Step.Form, model.state.value.step)

        model.currentPassword = "ancien2027"
        assertNull(model.state.value.failure)
    }

    @Test
    fun eachRefusalHasItsSentence() = runTest {
        suspend fun failure(error: Exception): PasswordChangeModel.Failure? {
            val model = PasswordChangeModel(email = "camille@memobook.app", change = { _, _ -> throw error })
            filled(model)
            model.submit()
            return model.state.value.failure
        }

        assertEquals(PasswordChangeModel.Failure.SamePassword, failure(ApiError.Server(400, "same_password", "Même mot de passe")))
        assertEquals(PasswordChangeModel.Failure.NoPassword, failure(ApiError.Server(400, "no_password", "Pas de mot de passe")))
        assertEquals(PasswordChangeModel.Failure.SessionExpired, failure(ApiError.Server(401, null, "Session expirée")))
        assertEquals(PasswordChangeModel.Failure.SessionExpired, failure(ApiError.NotAuthenticated))
        assertEquals(PasswordChangeModel.Failure.Unavailable, failure(ApiError.Server(500, null, "Erreur")))
        assertEquals(PasswordChangeModel.Failure.Unavailable, failure(IllegalStateException("panne")))
    }

    /** « Mot de passe oublié ? » envoie l'e-mail à l'adresse du compte, et le dit. */
    @Test
    fun theForgottenLinkSendsTheMail() = runTest {
        var sentTo: String? = null
        val model = PasswordChangeModel(email = "camille@memobook.app", requestReset = { sentTo = it })

        model.requestReset()

        assertEquals("camille@memobook.app", sentTo)
        assertEquals(PasswordChangeModel.Step.ResetSent, model.state.value.step)
        assertFalse(model.state.value.isWorking)
    }
}
