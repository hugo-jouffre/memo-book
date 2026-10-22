package com.memobook.feature.onboarding

import com.memobook.core.Account
import com.memobook.core.CalendarDay
import com.memobook.core.ProfileEdit
import com.memobook.core.Some
import com.memobook.feature.InMemoryAppSettings
import com.memobook.networking.ApiError
import kotlinx.coroutines.test.runTest
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Les « Dernières questions » : qui les voit, ce que « Valider » attend, ce
 * qui part au profil, et l'accueil qui suit. Sans émulateur — le modèle reçoit
 * sa fonction d'écriture comme l'app la lui branche. Porté de
 * `LastQuestionsModelTests.swift`, cas pour cas (`HomeJoinTests`, qui vit dans
 * le même fichier Swift, suit `HomeModel`).
 */
class LastQuestionsModelTest {
    private fun account(createdAt: Instant = Instant.now()): Account =
        Account(id = UUID.randomUUID().toString(), email = "camille@memobook.app", firstName = "camille", createdAt = createdAt)

    @Test fun onlyAFreshAccountIsAskedAndOnlyOnce() {
        val settings = InMemoryAppSettings()

        val fresh = account()
        assertTrue(LastQuestionsModel.shouldAsk(fresh, settings))
        assertFalse(LastQuestionsModel.shouldAsk(account(createdAt = Instant.now().minusSeconds(3600)), settings))

        LastQuestionsModel.markAnswered(fresh, settings)
        assertFalse(LastQuestionsModel.shouldAsk(fresh, settings))
    }

    @Test fun theBirthDateTakesItsSlashesAsItIsTyped() {
        assertEquals("12", LastQuestionsModel.maskedBirthDate("12"))
        assertEquals("12/05", LastQuestionsModel.maskedBirthDate("1205"))
        assertEquals("12/05/1994", LastQuestionsModel.maskedBirthDate("12051994"))
        assertEquals("12/05/1994", LastQuestionsModel.maskedBirthDate("12/05/19945"))
        assertEquals("12", LastQuestionsModel.maskedBirthDate("ab12"))
    }

    @Test fun eachQuestionSavesWhatItAskedThenMovesOn() = runTest {
        val sent = mutableListOf<ProfileEdit>()
        val model = LastQuestionsModel(account()) { sent += it }

        // Le prénom du fournisseur est là ; il manque le nom.
        assertFalse(model.state.value.canValidate)
        model.lastName = "Dupont"
        model.firstName = "Camille"
        val afterName = model.validate()
        assertNull(afterName)
        assertEquals(LastQuestionsModel.Step.BirthDate, model.state.value.step)

        model.birthDateText = "31/06/1994"
        assertFalse(model.state.value.canValidate)
        assertNotNull(model.state.value.birthDateProblem)
        model.birthDateText = "12051994"
        assertEquals("12/05/1994", model.state.value.birthDateText)
        assertTrue(model.state.value.canValidate)
        model.validate()
        assertEquals(LastQuestionsModel.Step.Phone, model.state.value.step)

        model.phoneNumber = "+33 6 12 34 56 78"
        val finished = assertNotNull(model.validate())
        assertEquals("Camille", finished.firstName)
        assertEquals("Dupont", finished.lastName)

        assertEquals(3, sent.size)
        assertEquals(ProfileEdit(firstName = Some("Camille"), lastName = Some("Dupont")), sent[0])
        assertEquals(ProfileEdit(birthDate = Some(CalendarDay(year = 1994, month = 5, day = 12))), sent[1])
        assertEquals(ProfileEdit(phoneNumber = Some("+33 6 12 34 56 78")), sent[2])
    }

    @Test fun skippingSavesNothingAndStillEnters() {
        val sent = mutableListOf<ProfileEdit>()
        val model = LastQuestionsModel(account()) { sent += it }

        assertNull(model.skip())
        assertNull(model.skip())
        assertNotNull(model.skip())
        assertTrue(sent.isEmpty())
    }

    @Test fun aFailedSaveKeepsTheQuestionOpen() = runTest {
        val model = LastQuestionsModel(account()) {
            throw ApiError.Server(statusCode = 400, code = null, message = "Refusé.")
        }
        model.lastName = "Dupont"

        val result = model.validate()
        assertNull(result)
        assertEquals(LastQuestionsModel.Step.Name, model.state.value.step)
        assertEquals("Refusé.", model.state.value.errorMessage)
    }

    @Test fun theArrowGoesBackButNotBeforeTheFirstQuestion() {
        val model = LastQuestionsModel(account())
        assertFalse(model.state.value.canGoBack)
        model.skip()
        assertTrue(model.state.value.canGoBack)
        assertTrue(model.goBack())
        assertEquals(LastQuestionsModel.Step.Name, model.state.value.step)
        assertFalse(model.goBack())
    }

    /**
     * Le glissé vers la gauche : valide un écran rempli, passe un écran vide,
     * et ne jette jamais un écran à moitié rempli.
     */
    @Test fun theSwipeValidatesSkipsOrStays() = runTest {
        val sent = mutableListOf<ProfileEdit>()
        val model = LastQuestionsModel(Account(id = "a", createdAt = Instant.now())) { sent += it }

        // À moitié rempli : on reste, rien ne part.
        model.firstName = "Camille"
        model.swipeForward()
        assertEquals(LastQuestionsModel.Step.Name, model.state.value.step)
        assertTrue(sent.isEmpty())

        // Rempli : il valide.
        model.lastName = "Dupont"
        model.swipeForward()
        assertEquals(LastQuestionsModel.Step.BirthDate, model.state.value.step)
        assertEquals(1, sent.size)

        // Vide : il passe, sans rien envoyer.
        assertTrue(model.state.value.isStepUntouched)
        model.swipeForward()
        assertEquals(LastQuestionsModel.Step.Phone, model.state.value.step)
        assertEquals(1, sent.size)

        // Le dernier écran passé au doigt fait entrer.
        val finished = model.swipeForward()
        assertNotNull(finished)
    }
}
