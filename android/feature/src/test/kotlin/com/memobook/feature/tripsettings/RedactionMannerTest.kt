package com.memobook.feature.tripsettings

import com.memobook.core.MemoBookJson
import com.memobook.core.RedactionManner
import com.memobook.core.RedactionMannerReason
import com.memobook.core.RedactionSettings
import com.memobook.core.TripSettings
import com.memobook.core.TripSettingsEdit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * **La manière d'être rédigé** (T292) — le jumeau de
 * `RedactionMannerTests.swift`, cas pour cas.
 *
 * Le garde-fou lui-même — qui a le droit de changer de manière — est tranché
 * par le serveur (`services/redactionMannerAccess.ts`) et testé là-bas. Ici on
 * vérifie que l'app **lit** sa décision au lieu de la refaire, et qu'elle ne
 * reprend pas le carnet pour rien.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RedactionMannerTest {
    @BeforeTest fun setUp() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @AfterTest fun tearDown() {
        Dispatchers.resetMain()
    }

    // MARK: Le décodage

    @Test fun anUnknownMannerFallsBackToTheDefaultRatherThanFailing() {
        // Une version plus récente du serveur peut servir une manière que ce
        // build ne connaît pas : la ligne retombe sur le défaut, et **tout
        // l'écran** continue de décoder.
        val json = """{"manner":"en-alexandrins","notes":"Tutoie-moi.","isAvailable":true,"reason":"unlimited"}"""
        val decoded = MemoBookJson.decodeFromString(RedactionSettings.serializer(), json)

        assertNull(decoded.chosenManner, "Une clé inconnue n'est pas un choix.")
        assertEquals(RedactionManner.Spoken, decoded.manner)
        assertEquals("Tutoie-moi.", decoded.notes)
        assertTrue(decoded.isAvailable)
    }

    @Test fun anUnknownReasonClosesTheSettingRatherThanOpeningIt() {
        val json = """{"manner":null,"notes":null,"isAvailable":false,"reason":"parce-que"}"""
        val decoded = MemoBookJson.decodeFromString(RedactionSettings.serializer(), json)

        assertEquals(RedactionMannerReason.NeedsUnlimited, decoded.reason, "Le refus sûr.")
        assertFalse(decoded.isAvailable)
    }

    @Test fun aServerThatSaysNothingServesAClosedSetting() {
        // Un serveur plus ancien ne sert pas le bloc : mieux vaut une ligne qui
        // mène au paywall qu'un réglage que le serveur refusera.
        val settings = TripSettings.fixture.copy(redaction = null)

        assertFalse(settings.redactionSettings.isAvailable)
        assertEquals(RedactionManner.Spoken, settings.redactionSettings.manner)
    }

    @Test fun nobodyChoseAndSpokenChosenAreTheSameMannerButNotTheSameState() {
        // La distinction ne sert qu'à la pastille « Par défaut ».
        val untouched = RedactionSettings(isAvailable = true, storedReason = "unlimited")
        val chosen = RedactionSettings(storedManner = "spoken", isAvailable = true, storedReason = "unlimited")

        assertEquals(untouched.manner, chosen.manner)
        assertNull(untouched.chosenManner)
        assertEquals(RedactionManner.Spoken, chosen.chosenManner)
    }

    // MARK: Ce que le modèle envoie

    @Test fun choosingAMannerPostsItAndShowsItBeforeTheServerAnswers() = runTest {
        val server = MannerServer()
        val model = server.model()
        model.load()
        runCurrent()

        model.setRedactionManner(RedactionManner.Literary)

        // Posé à l'écran tout de suite : un réglage qui attend le réseau se lit
        // comme cassé.
        assertEquals(RedactionManner.Literary, model.state.value.settings?.redactionSettings?.manner)
        runCurrent()
        assertEquals(
            listOf<TripSettingsEdit>(TripSettingsEdit.RedactionMannerEdit(RedactionManner.Literary)),
            server.received,
        )
    }

    @Test fun choosingTheMannerAlreadyInPlaceSendsNothing() = runTest {
        // Le serveur ne reprendrait rien, mais le voyage pour rien se voit : un
        // 202 ferait clignoter l'écran.
        val server = MannerServer(manner = "factual")
        val model = server.model()
        model.load()
        runCurrent()

        model.setRedactionManner(RedactionManner.Factual)

        runCurrent()
        assertTrue(server.received.isEmpty())
    }

    @Test fun theDefaultMannerCountsAsChosenWhenNobodyChose() = runTest {
        // Personne n'a choisi : toucher « Comme je parle » ne reprend rien.
        val server = MannerServer()
        val model = server.model()
        model.load()
        runCurrent()

        model.setRedactionManner(RedactionManner.Spoken)

        runCurrent()
        assertTrue(server.received.isEmpty())
    }

    @Test fun notesAreTrimmedAndAnEmptyFieldErasesThem() = runTest {
        val server = MannerServer(notes = "Appelle-moi Max.")
        val model = server.model()
        model.load()
        runCurrent()

        model.setRedactionNotes("   ")

        assertNull(model.state.value.settings?.redactionSettings?.notes)
        runCurrent()
        assertEquals(listOf<TripSettingsEdit>(TripSettingsEdit.RedactionNotes(null)), server.received)
    }

    @Test fun writingTheSameNotesAgainSendsNothing() = runTest {
        val server = MannerServer(notes = "Garde mes mots.")
        val model = server.model()
        model.load()
        runCurrent()

        model.setRedactionNotes("  Garde mes mots.  ")

        runCurrent()
        assertTrue(server.received.isEmpty(), "Chaque envoi reprend le carnet.")
    }

    // MARK: Tout faire reprendre

    @Test fun rewritingAsksTheServerAndIsReplayable() = runTest {
        val server = MannerServer(manner = "literary")
        val model = server.model()
        model.load()
        runCurrent()

        model.rewriteRedaction()
        runCurrent()
        model.rewriteRedaction()
        runCurrent()

        // Rejouable, contrairement à la reprise d'un changement de cible : ici
        // le geste *est* la demande.
        assertEquals(2, server.rewrites)
    }

    // MARK: - Le double de serveur

    private class MannerServer(
        manner: String? = null,
        notes: String? = null,
        isAvailable: Boolean = true,
    ) {
        var settings: TripSettings = TripSettings.fixture.copy(
            redaction = RedactionSettings(
                storedManner = manner,
                notes = notes,
                isAvailable = isAvailable,
                storedReason = if (isAvailable) "unlimited" else "needs_unlimited",
            ),
        )
        val received = mutableListOf<TripSettingsEdit>()
        var rewrites = 0

        fun model() = TripSettingsModel(
            tripId = "preview",
            source = { settings },
            persist = { _, edit -> patch(edit) },
            rewriteRedaction = { rewrite() },
        )

        private fun patch(edit: TripSettingsEdit): TripSettings {
            received += edit
            val redaction = settings.redactionSettings
            settings = when (edit) {
                is TripSettingsEdit.RedactionMannerEdit ->
                    settings.copy(redaction = redaction.copy(storedManner = edit.value.rawValue))
                is TripSettingsEdit.RedactionNotes ->
                    settings.copy(redaction = redaction.copy(notes = edit.value))
                else -> settings
            }
            return settings
        }

        private fun rewrite(): TripSettings {
            rewrites += 1
            return settings
        }
    }
}
