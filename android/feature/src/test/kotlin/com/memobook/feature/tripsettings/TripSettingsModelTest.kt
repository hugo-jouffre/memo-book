package com.memobook.feature.tripsettings

import com.memobook.core.BookCopy
import com.memobook.core.TripSettings
import com.memobook.core.TripSettingsEdit
import com.memobook.feature.ContentFreshness
import com.memobook.networking.ApiError
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import java.io.IOException
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Les règles que `TripSettingsModel.swift` écrit dans ses commentaires, et que
 * le portage en coroutines pouvait perdre : un réglage part seul et l'écran a
 * déjà bougé, l'échec remet ce que le serveur a, la dernière bascule l'emporte,
 * le propriétaire ne se retire pas. Aucune suite iOS ne les teste ; elles
 * tiennent ici à la place du simulateur.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class TripSettingsModelTest {
    @BeforeTest fun setUp() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @AfterTest fun tearDown() {
        Dispatchers.resetMain()
    }

    private val serverError = ApiError.Server(statusCode = 500, code = null, message = "Erreur interne du serveur")

    /** Le serveur relit le nom qu'on lui envoie ; la coche verte dure quatre secondes. */
    @Test fun theNameIsTrimmedSentAloneAndAcknowledged() = runTest {
        val sent = mutableListOf<TripSettingsEdit>()
        val model = TripSettingsModel(
            tripId = "rome",
            persist = { _, edit ->
                sent += edit
                TripSettings.fixture.copy(name = (edit as TripSettingsEdit.Name).value)
            },
        )
        model.load()

        // Un nom vide n'est pas un nom, et le même nom n'est pas un changement.
        model.setName("   ")
        model.setName(TripSettings.fixture.name)
        runCurrent()
        assertTrue(sent.isEmpty())

        model.setName("  Rome entre amis ")
        assertEquals("Rome entre amis", model.state.value.settings?.name)
        runCurrent()
        assertEquals(listOf<TripSettingsEdit>(TripSettingsEdit.Name("Rome entre amis")), sent)
        assertEquals(TripSettingsModel.SavedField.Name, model.state.value.justSaved)

        advanceTimeBy(4_001)
        runCurrent()
        assertNull(model.state.value.justSaved)
    }

    /** L'interrupteur a bougé tout de suite ; l'échec remet ce que le serveur a vraiment. */
    @Test fun aFailedSaveBringsBackTheServerValues() = runTest {
        val model = TripSettingsModel(
            tripId = "rome",
            persist = { _, _ -> throw serverError },
        )
        model.load()
        val before = assertNotNull(model.state.value.settings).isPublicGallery

        model.setPublicGallery(!before)
        assertEquals(!before, model.state.value.settings?.isPublicGallery)

        runCurrent()
        assertEquals(before, model.state.value.settings?.isPublicGallery)
        // La relecture a réussi : l'écran est à jour, l'erreur s'efface avec elle.
        assertNull(model.state.value.errorMessage)
    }

    /** Deux bascules d'affilée : la réponse de la première ne réécrit pas l'écran. */
    @Test fun theLastToggleWins() = runTest {
        val first = CompletableDeferred<TripSettings>()
        var calls = 0
        val model = TripSettingsModel(
            tripId = "rome",
            persist = { _, edit ->
                calls += 1
                if (calls == 1) first.await() else TripSettings.fixture.copy(wantsNotifications = (edit as TripSettingsEdit.Notifications).value)
            },
        )
        model.load()

        model.setNotifications(false)
        runCurrent()
        model.setNotifications(true)
        runCurrent()
        first.complete(TripSettings.fixture.copy(wantsNotifications = false))
        runCurrent()

        assertEquals(true, model.state.value.settings?.wantsNotifications)
    }

    /**
     * Le propriétaire ne se retire pas ; un co-voyageur quitte la liste tout de
     * suite, et la réponse du serveur la remet d'aplomb.
     */
    @Test fun onlyACompanionIsRemovedAndAtOnce() = runTest {
        val removed = mutableListOf<String>()
        val model = TripSettingsModel(
            tripId = "rome",
            removeCompanion = { _, id ->
                removed += id
                TripSettings.fixture.copy(companions = TripSettings.fixture.companions.filter { it.id != id })
            },
        )
        model.load()
        val companions = assertNotNull(model.state.value.settings).companions
        val owner = companions.first { it.isOwner }
        val guest = companions.first { !it.isOwner }

        model.remove(owner)
        runCurrent()
        assertTrue(removed.isEmpty())
        assertTrue(model.state.value.settings!!.companions.any { it.id == owner.id })

        model.remove(guest)
        assertFalse(model.state.value.settings!!.companions.any { it.id == guest.id })
        runCurrent()
        assertEquals(listOf(guest.id), removed)
    }

    /** On ne renvoie un lien qu'à quelqu'un qui n'est jamais entré ; le mot s'efface tout seul. */
    @Test fun anInvitationIsResentOnlyToSomeoneWhoNeverCameIn() = runTest {
        val resent = mutableListOf<String>()
        val model = TripSettingsModel(tripId = "rome", resendInvitation = { _, id -> resent += id })
        model.load()
        val companions = assertNotNull(model.state.value.settings).companions
        val joined = companions.first { !it.isPending }
        val pending = companions.firstOrNull { it.isPending } ?: joined.copy(id = "pending", name = "Sacha Blin", isPending = true)

        model.resendInvitation(joined)
        model.resendInvitation(pending)
        runCurrent()
        assertEquals(listOf(pending.id), resent)
        assertEquals(BookCopy.Invite.resent(pending.name), model.state.value.confirmation)

        advanceTimeBy(4_001)
        runCurrent()
        assertNull(model.state.value.confirmation)
    }

    /**
     * Supprimer le voyage : rien sans fonction (un aperçu ne supprime rien) ; un
     * refus du serveur reste dans la feuille. Supprimer la conversation, sans
     * fonction, se joue comme si c'était fait.
     */
    @Test fun deletionsReportWhatHappened() = runTest {
        val preview = TripSettingsModel(tripId = "rome")
        assertFalse(preview.delete())
        assertTrue(preview.clearConversation())

        val refused = TripSettingsModel(
            tripId = "rome",
            delete = { throw ApiError.Server(statusCode = 403, code = null, message = "Seul le propriétaire peut supprimer ce voyage.") },
            clearConversation = { },
        )
        assertFalse(refused.delete())
        assertEquals("Seul le propriétaire peut supprimer ce voyage.", refused.state.value.errorMessage)
        assertFalse(refused.state.value.isDeleting)
        assertTrue(refused.clearConversation())
        assertNull(refused.state.value.errorMessage)
    }

    /**
     * L'écran s'ouvre sur ce qu'on avait, puis dit si le serveur a changé
     * quelque chose ; une panne de lecture laisse le cache en place avec son
     * bandeau.
     */
    @Test fun theScreenOpensOnTheCacheAndSaysWhatChanged() = runTest {
        val stored = TripSettings.fixture.copy(name = "Rome 2025")
        val updated = TripSettingsModel(tripId = "rome", cached = { stored })
        updated.load()
        assertEquals(TripSettings.fixture.name, updated.state.value.settings?.name)
        assertEquals(ContentFreshness.Updated, updated.state.value.freshness)

        val offline = TripSettingsModel(
            tripId = "rome",
            source = { throw ApiError.Transport(IOException("hors ligne"), url = null) },
            cached = { stored },
        )
        offline.load()
        assertEquals("Rome 2025", offline.state.value.settings?.name)
        assertEquals(ContentFreshness.Restored, offline.state.value.freshness)
        assertNotNull(offline.state.value.errorMessage)
        assertFalse(offline.state.value.isLoading)
    }

    /** Les thèmes ne se chargent qu'une fois, et un échec laisse la rangée vide. */
    @Test fun themesLoadOnceAndFailQuietly() = runTest {
        var reads = 0
        val model = TripSettingsModel(tripId = "rome", themes = { reads += 1; com.memobook.core.TripTheme.fixtures })
        model.loadThemes()
        model.loadThemes()
        assertEquals(1, reads)
        assertEquals(com.memobook.core.TripTheme.fixtures, model.state.value.themes)

        val failing = TripSettingsModel(tripId = "rome", themes = { throw serverError })
        failing.loadThemes()
        assertTrue(failing.state.value.themes.isEmpty())
    }
}
