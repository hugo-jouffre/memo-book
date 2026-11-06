package com.memobook.feature.chat

import com.memobook.feature.InMemoryAppSettings
import com.memobook.feature.notifications.NotificationAuthorization
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * L'écran « Améliorons MemoBook ensemble » (03/11/2026) : à qui il se montre,
 * et ce qu'il retient. Porté de `NotificationsPrimerTests.swift`.
 */
class NotificationsPrimerTest {
    @Test fun shownOnlyAtTheFirstOpeningAndBeforeAnyAnswer() {
        // Une conversation ouverte pour la première fois, question jamais
        // posée : l'écran.
        assertTrue(
            NotificationsPrimer.isShown(
                isFirstOpeningOfANewTrip = true,
                authorization = NotificationAuthorization.NotDetermined,
            ),
        )
        // Déjà répondu — autorisé, refusé : la fenêtre ne reviendrait pas,
        // donc l'écran non plus. (Android n'a pas de « provisoire ».)
        assertFalse(
            NotificationsPrimer.isShown(
                isFirstOpeningOfANewTrip = true,
                authorization = NotificationAuthorization.Authorized,
            ),
        )
        assertFalse(
            NotificationsPrimer.isShown(
                isFirstOpeningOfANewTrip = true,
                authorization = NotificationAuthorization.Denied,
            ),
        )
        // Une conversation qu'on rouvre, ou un voyage rejoint par un code.
        assertFalse(
            NotificationsPrimer.isShown(
                isFirstOpeningOfANewTrip = false,
                authorization = NotificationAuthorization.NotDetermined,
            ),
        )
    }

    @Test fun onlyTheFirstOpeningOfATripCreatedHereCounts() {
        val settings = InMemoryAppSettings()
        NotificationsPrimer.markTripCreated("rome", settings)

        assertTrue(NotificationsPrimer.consumeFirstOpening("rome", settings))
        // La deuxième ouverture n'en est plus une.
        assertFalse(NotificationsPrimer.consumeFirstOpening("rome", settings))
        // Un voyage qu'on n'a pas créé ici n'a jamais été attendu.
        assertFalse(NotificationsPrimer.consumeFirstOpening("lisbonne", settings))
    }

    @Test fun correctingADraftDoesNotQueueTheTripTwice() {
        val settings = InMemoryAppSettings()
        // Revenir en arrière et revalider renvoie la création sur le même
        // identifiant : la liste ne doit pas le retenir deux fois, sinon la
        // seconde ouverture rouvrirait l'écran.
        NotificationsPrimer.markTripCreated("rome", settings)
        NotificationsPrimer.markTripCreated("rome", settings)

        assertTrue(NotificationsPrimer.consumeFirstOpening("rome", settings))
        assertFalse(NotificationsPrimer.consumeFirstOpening("rome", settings))
    }

    @Test fun severalTripsWaitSideBySide() {
        val settings = InMemoryAppSettings()
        NotificationsPrimer.markTripCreated("rome", settings)
        NotificationsPrimer.markTripCreated("lisbonne", settings)

        assertTrue(NotificationsPrimer.consumeFirstOpening("lisbonne", settings))
        // Ouvrir l'un n'oublie pas l'autre.
        assertTrue(NotificationsPrimer.consumeFirstOpening("rome", settings))
    }

    @Test fun theWordsOfTheScreen() {
        assertEquals("Améliorons MemoBook ensemble", NotificationsPrimer.TITLE)
        assertEquals(2, NotificationsPrimer.paragraphs.size)
        // La phrase de la maquette, mot pour mot.
        assertEquals(
            "Le contenu de ton carnet de voyage reste privé et nous n’allons jamais revendre tes données.",
            NotificationsPrimer.paragraphs.last(),
        )
    }
}
