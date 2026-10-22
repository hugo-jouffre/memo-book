package com.memobook.feature.tripsettings

import com.memobook.core.BookCustomisation
import com.memobook.core.BookCustomisationEdit
import com.memobook.core.BookFontCombo
import com.memobook.core.BookFontRole
import com.memobook.core.BookPageTarget
import com.memobook.core.PageTargetAllowance
import com.memobook.core.PageTargetTripStage
import com.memobook.core.TripSettings
import com.memobook.feature.InMemoryAppSettings
import com.memobook.networking.ApiError
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Le **verrou des pointillés** dans l'écran des personnalisations : ce que le
 * modèle pose à l'écran, ce qu'il envoie, ce qu'il garde sur l'appareil.
 * Jumeau de `BookCustomisationModelTests.swift`, cas pour cas.
 *
 * La règle elle-même est testée dans `BookRulesLockTest` ; ici, on vérifie
 * qu'elle est appliquée et **envoyée** — après chaque geste, l'écran et le
 * serveur doivent dire la même chose.
 *
 * Le temps est celui du planificateur de test : les `waitUntil` d'iOS, qui
 * dormaient par tranches de 10 ms, sont ici un `advanceUntilIdle()` — tout ce
 * qui peut avancer avance, ce qui attend le serveur retenu reste en attente.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class BookCustomisationModelTest {
    @BeforeTest fun setUp() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @AfterTest fun tearDown() {
        Dispatchers.resetMain()
    }

    // MARK: Les deux assortiments contraints

    @Test fun choosingHandwrittenSendsFontsAndRulesInOneEdit() = runTest {
        val (model, server, memory) = open(rules = true)

        model.setFontCombo(BookFontCombo.handwritten)

        // Posé à l'écran avant toute réponse.
        val shown = model.customisation
        assertEquals(false, shown?.rulesEnabled)
        assertTrue(model.areRulesLocked)
        assertTrue(model.isRulesSwitchLocked)
        settled(model, server, edits = 1, shown = shown)

        // **Une** édition, qui porte les cinq valeurs : le serveur ne passe
        // jamais par un Manuscrit aux pointillés allumés.
        assertEquals(listOf<BookCustomisationEdit>(BookCustomisationEdit.FontCombo(BookFontCombo.handwritten, rulesEnabled = false)), server.received)
        assertEquals(true, memory.read(TRIP_ID))
        assertEquals(BookFontCombo.handwritten, model.rulesWithdrawnBy)
    }

    @Test fun choosingEditorialLocksTheSwitchToo() = runTest {
        val (model, server, memory) = open(rules = true)

        act(model, server, edits = 1) { model.setFontCombo(BookFontCombo.editorial) }

        assertEquals(listOf<BookCustomisationEdit>(BookCustomisationEdit.FontCombo(BookFontCombo.editorial, rulesEnabled = false)), server.received)
        assertTrue(model.areRulesLocked)
        assertEquals(true, memory.read(TRIP_ID))
    }

    @Test fun aLockedSwitchCannotBeRelit() = runTest {
        val (model, server, _) = open(rules = true)
        act(model, server, edits = 1) { model.setFontCombo(BookFontCombo.handwritten) }

        model.setRules(true)

        assertEquals(false, model.customisation?.rulesEnabled)
        advanceUntilIdle()
        assertEquals(1, server.received.size, "un rallumage verrouillé est parti au serveur")
    }

    @Test fun tappingTheChosenComboAgainSendsNothing() = runTest {
        // L'édition porterait les pointillés de l'écran : sur un écran resté
        // ouvert, elle rallumerait ceux qu'un co-voyageur vient d'éteindre.
        val (model, server, _) = open(rules = true)

        model.setFontCombo(BookFontCombo.travelJournal)

        advanceUntilIdle()
        assertEquals(0, server.attempts)
    }

    // MARK: Le retour au défaut

    @Test fun backToDefaultRelightsRulesThatWereOn() = runTest {
        val (model, server, memory) = open(rules = true)
        act(model, server, edits = 1) { model.setFontCombo(BookFontCombo.handwritten) }

        act(model, server, edits = 2) { model.setFontCombo(BookFontCombo.travelJournal) }

        assertEquals(BookCustomisationEdit.FontCombo(BookFontCombo.travelJournal, rulesEnabled = true), server.received.last())
        assertFalse(model.areRulesLocked)
        // Le verrou défait, il n'y a plus rien à rendre.
        assertNull(memory.read(TRIP_ID))
    }

    @Test fun backToDefaultKeepsOffRulesThatWereOff() = runTest {
        val (model, server, _) = open(rules = false)
        act(model, server, edits = 1) { model.setFontCombo(BookFontCombo.editorial) }
        // Rien n'a été retiré : pas de note sous les assortiments.
        assertNull(model.rulesWithdrawnBy)

        act(model, server, edits = 2) { model.setFontCombo(BookFontCombo.travelJournal) }

        assertEquals(BookCustomisationEdit.FontCombo(BookFontCombo.travelJournal, rulesEnabled = false), server.received.last())
    }

    @Test fun aRoundTripLeavesTheBookExactlyAsItWas() = runTest {
        for (rules in listOf(true, false)) {
            val (model, server, _) = open(rules = rules)
            val before = model.customisation

            act(model, server, edits = 1) { model.setFontCombo(BookFontCombo.handwritten) }
            act(model, server, edits = 2) { model.setFontCombo(BookFontCombo.editorial) }
            act(model, server, edits = 3) { model.setFontCombo(BookFontCombo.travelJournal) }

            assertEquals(before, model.customisation, "pointillés ${if (rules) "allumés" else "éteints"} au départ")
            assertEquals(before, server.settings.customisation)
        }
    }

    @Test fun theMemoryOutlivesTheScreen() = runTest {
        // On verrouille, on ferme l'écran, on le rouvre plus tard : la mémoire
        // est sur l'appareil, pas dans le modèle.
        val memory = BookRulesMemory.inMemory()
        val server = Server(rules = false)

        val first = open(server, memory)
        act(first, server, edits = 1) { first.setFontCombo(BookFontCombo.handwritten) }

        val second = open(server, memory)
        act(second, server, edits = 2) { second.setFontCombo(BookFontCombo.travelJournal) }

        assertEquals(false, second.customisation?.rulesEnabled)
    }

    @Test fun aFailedReturnToDefaultKeepsTheMemory() = runTest {
        val (model, server, memory) = open(rules = false)
        act(model, server, edits = 1) { model.setFontCombo(BookFontCombo.handwritten) }

        server.isFailing = true
        model.setFontCombo(BookFontCombo.travelJournal)
        // L'envoi échoue, l'écran relit : le carnet est encore verrouillé…
        waitUntil { server.attempts == 2 && model.areRulesLocked }
        // … et doit encore savoir quoi rendre au prochain essai.
        assertEquals(false, memory.read(TRIP_ID))
        assertEquals(server.settings.customisation, model.customisation)
    }

    // MARK: Les envois, un par un

    @Test fun aNeighbouringSettingDoesNotUndoTheOneBefore() = runTest {
        // Fun facts éteints, puis le quiz dans la foulée, pendant que le serveur
        // fait attendre la première requête. Annuler l'envoi des fun facts
        // laissait la réponse du quiz les rallumer — et l'aperçu bougeait pour
        // un réglage qu'il ne montre pas.
        val (model, server, _) = open(rules = true)
        server.holdsNext = true

        model.setFunFacts(false)
        val shown = model.previewURL
        model.setQuiz(false)
        waitUntil { server.attempts == 1 }
        advanceUntilIdle()
        assertEquals(1, server.attempts, "le quiz est parti avant la réponse des fun facts")

        server.release()
        waitUntil { server.received.size == 2 && model.customisation == server.settings.customisation }

        assertEquals(listOf<BookCustomisationEdit>(BookCustomisationEdit.FunFacts(false), BookCustomisationEdit.Quiz(false)), server.received)
        assertEquals(false, model.customisation?.funFactsEnabled)
        assertEquals(shown, model.previewURL)
    }

    @Test fun aSliderDragSendsItsFirstAndLastSteps() = runTest {
        // Un cran part ; ceux qui suivent attendent sa réponse, et seul le
        // dernier part après elle.
        val (model, server, _) = open(rules = true)
        server.holdsNext = true

        model.setPhotoTextRatio(25)
        waitUntil { server.attempts == 1 }
        model.setPhotoTextRatio(50)
        model.setPhotoTextRatio(75)

        server.release()
        waitUntil { server.received.size == 2 && model.customisation == server.settings.customisation }

        assertEquals(listOf<BookCustomisationEdit>(BookCustomisationEdit.PhotoTextRatio(25), BookCustomisationEdit.PhotoTextRatio(75)), server.received)
        assertEquals(75, model.customisation?.photoTextRatio)
    }

    @Test fun aFailedSettingDoesNotTakeTheNextOnesWithIt() = runTest {
        // Les fun facts échouent pendant que le quiz attend derrière : le quiz
        // part quand même, et l'écran finit sur ce que le serveur a vraiment.
        val (model, server, _) = open(rules = true)
        val funFacts = !(model.customisation?.funFactsEnabled ?: true)
        val quiz = !(model.customisation?.quizEnabled ?: true)
        server.holdsNext = true
        server.failsNext = true

        model.setFunFacts(funFacts)
        waitUntil { server.attempts == 1 }
        model.setQuiz(quiz)
        server.release()

        waitUntil { server.received.size == 1 && model.customisation == server.settings.customisation }
        assertEquals(listOf<BookCustomisationEdit>(BookCustomisationEdit.Quiz(quiz)), server.received)
        assertEquals(quiz, model.customisation?.quizEnabled)
        assertEquals(!funFacts, model.customisation?.funFactsEnabled, "le réglage raté reste affiché")
    }

    @Test fun aGestureDuringTheRereadAfterAFailureIsSent() = runTest {
        // L'envoi échoue, l'écran relit le serveur — lentement — et le voyageur
        // touche au quiz pendant ce temps. Le geste restait en file sans
        // partir, et la relecture l'effaçait de l'écran.
        val (model, server, _) = open(rules = true)
        val quiz = !(model.customisation?.quizEnabled ?: true)
        server.failsNext = true
        server.holdsNextRead = true

        model.setFunFacts(!(model.customisation?.funFactsEnabled ?: true))
        waitUntil { server.attempts == 1 && server.reads == 2 }
        model.setQuiz(quiz)
        server.releaseRead()

        waitUntil { server.received.size == 1 && model.customisation == server.settings.customisation }
        assertEquals(listOf<BookCustomisationEdit>(BookCustomisationEdit.Quiz(quiz)), server.received)
        assertEquals(quiz, model.customisation?.quizEnabled)
    }

    @Test fun aRereadDoesNotUndoASettingOnItsWay() = runTest {
        // « Réessayer », ou l'écran qui réapparaît, relit le serveur pendant
        // qu'un envoi attend sa réponse : la lecture est d'avant le geste.
        val (model, server, _) = open(rules = true)
        val quiz = !(model.customisation?.quizEnabled ?: true)
        server.holdsNext = true

        model.setQuiz(quiz)
        waitUntil { server.attempts == 1 }
        model.load()
        assertEquals(quiz, model.customisation?.quizEnabled, "la relecture a défait le geste")

        server.release()
        settled(model, server, edits = 1, shown = model.customisation)
    }

    // MARK: Les carnets d'avant le verrou

    @Test fun aBookLockedBeforeTheLockIsPutBackInLineOnOpening() = runTest {
        val server = Server(rules = true, combo = BookFontCombo.handwritten)
        val memory = BookRulesMemory.inMemory()

        val model = open(server, memory)
        // Éteints à l'écran dès l'ouverture, avant la réponse.
        val shown = model.customisation
        assertEquals(false, shown?.rulesEnabled)

        settled(model, server, edits = 1, shown = shown)
        assertEquals(listOf<BookCustomisationEdit>(BookCustomisationEdit.Rules(false)), server.received)
        assertEquals(true, memory.read(TRIP_ID))

        // Et le retour au défaut rend ce qu'ils étaient.
        act(model, server, edits = 2) { model.setFontCombo(BookFontCombo.travelJournal) }
        assertEquals(true, model.customisation?.rulesEnabled)
    }

    @Test fun aFailedNormalisationIsNotRetriedForever() = runTest {
        // La relecture qui suit un envoi raté ne remet rien dans le rang :
        // sinon, un serveur qui refuse ferait tourner l'écran en boucle.
        val server = Server(rules = true, combo = BookFontCombo.editorial)
        server.isFailing = true

        open(server, BookRulesMemory.inMemory())

        waitUntil { server.attempts >= 1 }
        advanceUntilIdle()
        assertEquals(1, server.attempts)
    }

    @Test fun rulesLeftOnUnderALockCanStillBeTurnedOff() = runTest {
        // La remise dans le rang a échoué : ce Manuscrit imprimera ses
        // pointillés. L'interrupteur ne doit ni pâlir ni dire le contraire — le
        // verrou interdit de les rallumer, pas de les éteindre.
        val server = Server(rules = true, combo = BookFontCombo.handwritten)
        server.isFailing = true
        val model = open(server, BookRulesMemory.inMemory())
        waitUntil { server.attempts == 1 && model.customisation?.rulesEnabled == true }

        assertTrue(model.areRulesLocked)
        assertFalse(model.isRulesSwitchLocked)

        server.isFailing = false
        act(model, server, edits = 1) { model.setRules(false) }
        assertTrue(model.isRulesSwitchLocked)
    }

    @Test fun openingAnUnlockedBookForgetsAStaleMemory() = runTest {
        // Le verrou a été défait ailleurs — un co-voyageur est revenu au
        // défaut : la mémoire de ce téléphone ne sert plus.
        val memory = BookRulesMemory.inMemory()
        memory.write(TRIP_ID, false)

        open(Server(rules = true), memory)

        assertNull(memory.read(TRIP_ID))
    }

    // MARK: Ce que l'écran dit

    @Test fun theWithdrawnNoticeLastsOneGesture() = runTest {
        val (model, server, _) = open(rules = true)
        model.setFontCombo(BookFontCombo.handwritten)
        assertEquals(BookFontCombo.handwritten, model.rulesWithdrawnBy)
        settled(model, server, edits = 1, shown = model.customisation)

        model.setPhotoTextRatio(75)

        assertNull(model.rulesWithdrawnBy)
    }

    @Test fun theLockNoticeAnswersATapAndLeavesWithTheLock() = runTest {
        val (model, server, _) = open(rules = true)
        act(model, server, edits = 1) { model.setFontCombo(BookFontCombo.handwritten) }
        assertFalse(model.showsRulesLockNotice, "la note répond à un appui, pas au verrou")

        model.explainRulesLock()
        assertTrue(model.showsRulesLockNotice)

        act(model, server, edits = 2) { model.setFontCombo(BookFontCombo.travelJournal) }
        assertFalse(model.showsRulesLockNotice)

        // Reverrouillé, elle ne revient pas d'elle-même.
        act(model, server, edits = 3) { model.setFontCombo(BookFontCombo.editorial) }
        assertFalse(model.showsRulesLockNotice)
    }

    @Test fun aFailedChoiceTakesTheNoticeAway() = runTest {
        // L'envoi de Manuscrit échoue, l'écran relit Carnet de voyage aux
        // pointillés allumés : « on les a retirés » serait faux.
        val (model, server, _) = open(rules = true)
        server.isFailing = true

        model.setFontCombo(BookFontCombo.handwritten)
        assertEquals(BookFontCombo.handwritten, model.rulesWithdrawnBy)
        waitUntil { server.attempts == 1 && !model.areRulesLocked }

        assertNull(model.rulesWithdrawnBy)
        assertEquals(true, model.customisation?.rulesEnabled)
    }

    // MARK: La mémoire de l'app

    @Test fun theDeviceMemoryIsKeptPerTripAndForgotten() {
        val settings = InMemoryAppSettings()
        val memory = BookRulesMemory.device(settings)

        memory.write("trip-a", false)
        memory.write("trip-b", true)

        // Relue par une autre instance, comme à la prochaine ouverture.
        val reopened = BookRulesMemory.device(settings)
        assertEquals(false, reopened.read("trip-a"))
        assertEquals(true, reopened.read("trip-b"))
        assertNull(reopened.read("trip-c"))

        reopened.write("trip-a", null)
        assertNull(memory.read("trip-a"))
        assertEquals(true, memory.read("trip-b"))
    }

    // MARK: Outils

    /**
     * Le serveur, en mémoire : il applique chaque édition comme la route
     * `PATCH /v1/trips/:id/settings`, et rend ce qu'il a.
     */
    private class Server(rules: Boolean, combo: BookFontCombo = BookFontCombo.travelJournal) {
        var settings: TripSettings
        val received = mutableListOf<BookCustomisationEdit>()
        var attempts = 0
            private set
        var isFailing = false

        /** La prochaine requête échoue, et elle seule. */
        var failsNext = false

        /**
         * La prochaine requête attend [release] avant d'être traitée : une
         * connexion lente, ou un pooler qui fait patienter.
         */
        var holdsNext = false
        private var held: CompletableDeferred<Unit>? = null

        /**
         * La prochaine lecture attend [releaseRead] : une relecture lente,
         * pendant laquelle le voyageur continue de régler.
         */
        var holdsNextRead = false
        var reads = 0
            private set
        private var heldRead: CompletableDeferred<Unit>? = null

        init {
            val customisation = BookFontRole.entries
                .fold(BookCustomisation.fixture) { written, role -> role.writing(combo.font(role), into = written) }
                .copy(rulesEnabled = rules)
            settings = TripSettings.fixture.copy(customisation = customisation)
        }

        fun release() {
            held?.complete(Unit)
            held = null
        }

        fun releaseRead() {
            heldRead?.complete(Unit)
            heldRead = null
        }

        /**
         * `GET /v1/trips/:id/settings` : ce que le serveur a **au moment où la
         * lecture part** — une lecture retenue rend un état d'avant.
         */
        suspend fun read(): TripSettings {
            reads += 1
            val snapshot = settings
            if (holdsNextRead) {
                holdsNextRead = false
                CompletableDeferred<Unit>().also { heldRead = it }.await()
            }
            return snapshot
        }

        suspend fun patch(edit: BookCustomisationEdit): TripSettings {
            attempts += 1
            if (holdsNext) {
                holdsNext = false
                CompletableDeferred<Unit>().also { held = it }.await()
            }
            if (isFailing) throw Refused()
            if (failsNext) {
                failsNext = false
                throw Refused()
            }
            received += edit
            val current = settings.customisation ?: BookCustomisation.fixture
            val customisation = when (edit) {
                is BookCustomisationEdit.PhotoTextRatio -> current.copy(photoTextRatio = edit.value)
                is BookCustomisationEdit.TargetPageCount -> current.copy(targetPageCount = edit.value)
                is BookCustomisationEdit.FunFacts -> current.copy(funFactsEnabled = edit.value)
                is BookCustomisationEdit.Rules -> current.copy(rulesEnabled = edit.value)
                is BookCustomisationEdit.DecorationQuota -> current.copy(decorationQuota = edit.value)
                is BookCustomisationEdit.FontDisplay -> current.copy(fontDisplay = edit.value)
                is BookCustomisationEdit.FontTitle -> current.copy(fontTitle = edit.value)
                is BookCustomisationEdit.FontHand -> current.copy(fontHand = edit.value)
                is BookCustomisationEdit.FontFacts -> current.copy(fontFacts = edit.value)
                is BookCustomisationEdit.FontCombo -> BookFontRole.entries
                    .fold(current) { written, role -> role.writing(edit.combo.font(role), into = written) }
                    .copy(rulesEnabled = edit.rulesEnabled)
                is BookCustomisationEdit.Quiz -> current.copy(quizEnabled = edit.value)
                is BookCustomisationEdit.FreeZones -> current.copy(freeZonesEnabled = edit.value)
                is BookCustomisationEdit.Crossword -> current.copy(crosswordEnabled = edit.value)
            }
            settings = settings.copy(customisation = customisation)
            return settings
        }

        class Refused : Exception()
    }

    private data class Opened(val model: BookCustomisationModel, val server: Server, val memory: BookRulesMemory)

    private suspend fun open(rules: Boolean): Opened {
        val server = Server(rules = rules)
        val memory = BookRulesMemory.inMemory()
        return Opened(open(server, memory), server, memory)
    }

    private suspend fun open(server: Server, memory: BookRulesMemory): BookCustomisationModel {
        val model = BookCustomisationModel(
            tripId = TRIP_ID,
            source = { server.read() },
            persist = { _, edit -> server.patch(edit) },
            rulesMemory = memory,
        )
        model.load()
        return model
    }

    /**
     * Fait le geste, garde ce que l'écran montre **aussitôt** — avant toute
     * réponse —, puis attend le serveur et vérifie qu'il a reçu exactement cet
     * état.
     */
    private fun TestScope.act(model: BookCustomisationModel, server: Server, edits: Int, gesture: () -> Unit) {
        gesture()
        settled(model, server, edits = edits, shown = model.customisation)
    }

    /**
     * Attend que le serveur ait reçu `edits` éditions et que l'écran ait relu sa
     * réponse, puis compare ce que le serveur a **reçu** à ce que l'écran
     * montrait avant de la relire : après la relecture, les deux sont égaux par
     * construction, et la comparaison ne prouverait rien.
     */
    private fun TestScope.settled(model: BookCustomisationModel, server: Server, edits: Int, shown: BookCustomisation?) {
        waitUntil { server.received.size == edits && model.customisation == server.settings.customisation }
        assertEquals(shown, server.settings.customisation, "le serveur a reçu autre chose que ce que l’écran montrait")
    }

    private companion object {
        const val TRIP_ID = "trip-rome"
    }
}

/**
 * Le **changement de nombre de pages cible** (Hugo, 15/10/2026) : libre tant
 * qu'aucune étape n'est écrite, puis deux fois par voyage, chaque fois à travers
 * la feuille [PageTargetChangeSheet] — avertissement, stade du voyage, puis ce
 * qui est fait. Jumeau de `BookPageTargetChangeTests`.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class BookPageTargetChangeTest {
    @BeforeTest fun setUp() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @AfterTest fun tearDown() {
        Dispatchers.resetMain()
    }

    // MARK: La durée du voyage

    @Test fun withoutEndDateTheTripHasNoDuration() = runTest {
        val (model, _) = open(PageServer(allowance = null, endDate = null))
        assertNull(model.tripDays, "sans date de fin, le voyage durait un jour et le palier par défaut tombait à 30")
        assertEquals(60, BookPageTarget.Standard.pageCount(model.tripDays))
    }

    // MARK: Avant la première étape écrite

    @Test fun aChangeBeforeAnyStoryIsSentSilently() = runTest {
        val (model, server) = open(PageServer(allowance = PageTargetAllowance(changesCount = false)))

        model.setTargetPageCount(80)

        assertNull(model.pageTargetChange)
        assertEquals(80, model.customisation?.targetPageCount)
        waitUntil { server.patches == listOf(80) }
    }

    // MARK: Un changement qui compte

    @Test fun aCountedChangeAsksFirstAndCancellingChangesNothing() = runTest {
        val (model, server) = open(PageServer(allowance = PageTargetAllowance(changesLeft = 2, changesCount = true)))

        model.setTargetPageCount(80)

        assertEquals(PageTargetChange.Step.Confirm(changesLeft = 2), model.pageTargetChange?.step)
        assertEquals(60, model.customisation?.targetPageCount, "la cible a bougé avant la confirmation")

        model.dismissPageTargetChange()

        assertNull(model.pageTargetChange)
        assertEquals(60, model.customisation?.targetPageCount)
        advanceUntilIdle()
        assertTrue(server.patches.isEmpty())
    }

    @Test fun confirmingNearTheEndSavesAndOffersTheRewrite() = runTest {
        // Le jeu d'essai finit le 15/09/2026 : le 15/10, le voyage est fini.
        val (model, server) = open(
            PageServer(allowance = PageTargetAllowance(changesLeft = 2, changesCount = true)),
            today = day(15, 10),
        )
        model.setTargetPageCount(80)

        model.confirmPageTargetChange()

        waitUntil { model.pageTargetChange?.step == PageTargetChange.Step.Done(PageTargetTripStage.End) }
        assertEquals(listOf(80), server.patches)
        assertEquals(80, model.customisation?.targetPageCount)
        assertEquals(1, model.pageTargetAllowance.changesLeft)
        assertTrue(model.pageTargetChange?.isLonger == true)

        model.rewriteWrittenSteps()

        assertEquals(1, server.rewrites)
        assertNull(model.pageTargetChange)
        assertTrue(model.hasStartedRewrite)
        assertFalse(model.offersRewrite)
    }

    @Test fun earlyInTheTripTheSheetEndsWithoutRewrite() = runTest {
        val (model, _) = open(
            PageServer(allowance = PageTargetAllowance(changesLeft = 1, changesCount = true)),
            today = day(28, 8),
        )
        model.setTargetPageCount(40)
        assertEquals(PageTargetChange.Step.Confirm(changesLeft = 1), model.pageTargetChange?.step)

        model.confirmPageTargetChange()

        waitUntil { model.pageTargetChange?.step == PageTargetChange.Step.Done(PageTargetTripStage.BeginningOrMiddle) }
        assertEquals(false, model.pageTargetChange?.isLonger)
    }

    @Test fun withoutEndDateTheSheetAsksTheStage() = runTest {
        val (model, server) = open(
            PageServer(allowance = PageTargetAllowance(changesLeft = 2, changesCount = true), endDate = null),
        )
        model.setTargetPageCount(80)

        model.confirmPageTargetChange()

        assertEquals(PageTargetChange.Step.Stage, model.pageTargetChange?.step)
        assertTrue(server.patches.isEmpty(), "on envoie avant de savoir où en est le voyage")

        model.choosePageTargetStage(PageTargetTripStage.End)

        waitUntil { model.pageTargetChange?.step == PageTargetChange.Step.Done(PageTargetTripStage.End) }
        assertEquals(listOf(80), server.patches)
    }

    // MARK: La limite

    @Test fun noChangeLeftSendsNothingAndExplains() = runTest {
        val (model, server) = open(PageServer(allowance = PageTargetAllowance(changesLeft = 0, changesCount = true)))
        assertTrue(model.isPageTargetLocked)

        model.setTargetPageCount(80)

        assertNull(model.pageTargetChange)
        assertTrue(model.showsPageTargetLimitNotice)
        assertEquals(60, model.customisation?.targetPageCount)
        advanceUntilIdle()
        assertTrue(server.patches.isEmpty())
    }

    @Test fun aRefusalMovesTheSheetToTheLimit() = runTest {
        // L'écran croit qu'il reste un changement ; un co-voyageur l'a pris.
        val server = PageServer(allowance = PageTargetAllowance(changesLeft = 1, changesCount = true))
        val (model, _) = open(server, today = day(15, 10))
        server.refusesWithLimit = true
        model.setTargetPageCount(80)

        model.confirmPageTargetChange()

        waitUntil { model.pageTargetChange?.step == PageTargetChange.Step.LimitReached }
        waitUntil { model.isPageTargetLocked }
        assertEquals(60, model.customisation?.targetPageCount)
        assertNull(model.errorMessage, "un refus de la limite n'est pas une panne")
    }

    // MARK: Outils

    private suspend fun open(server: PageServer, today: Instant = day(15, 10)): Pair<BookCustomisationModel, PageServer> {
        val model = BookCustomisationModel(
            tripId = "trip-rome",
            source = { server.settings },
            persist = { _, edit -> server.patch(edit) },
            rewrite = { server.rewrite() },
            today = { today },
        )
        model.load()
        return model to server
    }

    /** Midi, le jour dit de 2026, dans le fuseau du téléphone — le `Calendar.current` d'iOS. */
    private fun day(day: Int, month: Int): Instant =
        LocalDateTime.of(2026, month, day, 12, 0).atZone(ZoneId.systemDefault()).toInstant()

    /** Le serveur de la règle des deux changements, en mémoire — comme `services/pageTarget.ts`. */
    private class PageServer(allowance: PageTargetAllowance?, endDate: Instant? = TripSettings.fixture.endDate) {
        var settings: TripSettings = TripSettings.fixture.let { fixture ->
            fixture.copy(
                endDate = endDate,
                pageTarget = allowance,
                customisation = fixture.customisation?.copy(targetPageCount = 60),
            )
        }
        val patches = mutableListOf<Int>()
        var rewrites = 0
            private set
        var refusesWithLimit = false

        fun patch(edit: BookCustomisationEdit): TripSettings {
            val pages = (edit as? BookCustomisationEdit.TargetPageCount)?.value ?: return settings
            var allowance = settings.pageTargetAllowance
            if (allowance.changesCount) {
                if (refusesWithLimit) {
                    settings = settings.copy(pageTarget = allowance.copy(changesLeft = 0))
                    throw ApiError.Server(statusCode = 409, code = ApiError.PAGE_TARGET_LIMIT_REACHED_CODE, message = "Limite")
                }
                allowance = allowance.copy(changesLeft = allowance.changesLeft - 1, rewriteAvailable = true)
                settings = settings.copy(pageTarget = allowance)
            }
            patches += pages
            settings = settings.copy(customisation = settings.customisation?.copy(targetPageCount = pages))
            return settings
        }

        fun rewrite(): TripSettings {
            rewrites += 1
            settings = settings.copy(pageTarget = settings.pageTarget?.copy(rewriteAvailable = false))
            return settings
        }
    }
}

/**
 * Le `waitUntil` d'iOS : tout ce qui peut avancer avance — ce que le serveur
 * retient reste en attente —, et la condition doit tenir.
 */
@OptIn(ExperimentalCoroutinesApi::class)
private fun TestScope.waitUntil(condition: () -> Boolean) {
    advanceUntilIdle()
    assertTrue(condition(), "Condition non remplie")
}
