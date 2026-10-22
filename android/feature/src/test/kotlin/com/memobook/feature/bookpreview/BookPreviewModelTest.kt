package com.memobook.feature.bookpreview

import com.memobook.core.BookCopy
import com.memobook.core.BookCovers
import com.memobook.core.BookPreview
import com.memobook.core.BookPreviewStatus
import com.memobook.core.BookRenderPhase
import com.memobook.core.BookRenderProgress
import com.memobook.core.CoverFace
import com.memobook.feature.covers.fixture
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.currentTime
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withTimeout
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

/**
 * Le premier chargement de l'aperçu — avec ou sans cascade —, et sa mise à
 * jour silencieuse quand une étape validée recompose le carnet en fond. Porté
 * de `BookPreviewModelTests.swift`, cas pour cas.
 *
 * Le temps est **virtuel** : les attentes du modèle (la cascade, les sondages)
 * passent par l'ordonnanceur du test, et son horloge ([BookPreviewModel.timeSource]).
 * « Moins d'une seconde » se mesure donc en temps du modèle, et non à la
 * montre comme sur iOS — c'est la même promesse : aucun plancher n'a été
 * traversé pour rien.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class BookPreviewModelTest {
    /**
     * Rend ses réponses dans l'ordre, une par appel — de quoi rejouer un
     * sondage précis sans double de réseau.
     */
    private class QueuedSource(responses: List<BookPreview>) {
        private val responses = ArrayDeque(responses)

        fun next(): BookPreview = responses.removeFirstOrNull() ?: throw Empty()

        class Empty : Exception()
    }

    private class Refused(message: String) : Exception(message)

    private class Gate {
        var isOpen = false
    }

    /**
     * Sans `pdfUrl` — comme `BookPreview.fixture` de la maquette — pour que ces
     * tests n'ouvrent jamais de vraie connexion réseau : seul l'état du modèle
     * est en jeu ici, pas le téléchargement ni `PdfRenderer`.
     */
    private fun preview(status: BookPreviewStatus, pageCount: Int = 4) =
        BookPreview(memoId = "memo-1", title = "Rome", status = status, pageCount = pageCount)

    /**
     * Le modèle, à l'horloge du test. Les pages blanches sont permises par
     * défaut : les tests iOS tournent en debug, où elles le sont aussi — ceux
     * de l'app livrée les éteignent, comme `model.opensBlankPages = false`.
     */
    private fun TestScope.model(
        source: suspend (String) -> BookPreview,
        startComposition: (suspend (String) -> Unit)? = null,
        covers: (suspend (String) -> BookCovers)? = null,
        opensBlankPages: Boolean = true,
    ) = BookPreviewModel(
        memoId = "memo-1",
        source = source,
        startComposition = startComposition,
        covers = covers,
        opensBlankPages = opensBlankPages,
    ).also { it.timeSource = testScheduler.timeSource }

    private suspend fun waitUntil(timeout: Duration = 2.seconds, condition: () -> Boolean) {
        withTimeout(timeout) {
            while (!condition()) delay(10)
        }
    }

    @BeforeTest fun setUp() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @AfterTest fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test fun anAlreadyReadyBookSkipsTheComposingCascade() = runTest {
        val source = QueuedSource(listOf(preview(BookPreviewStatus.Ready)))
        val model = model(source = { source.next() })

        val started = currentTime
        model.run()

        assertEquals(BookPreviewModel.Stage.Preview, model.stage)
        // Le plancher de la cascade est de 4,2 s : rester bien en dessous
        // prouve qu'il n'a pas été traversé pour rien.
        assertTrue(currentTime - started < 1_000)
    }

    @Test fun theFirstCompositionStillPlaysTheCascade() = runTest {
        val source = QueuedSource(listOf(preview(BookPreviewStatus.Composing), preview(BookPreviewStatus.Ready)))
        val model = model(source = { source.next() })

        model.run()

        assertEquals(BookPreviewModel.Stage.Preview, model.stage)
        assertEquals(1.0, model.compositionProgress, 0.001)
    }

    @Test fun aBackgroundRegenerationDoesNotReplayTheComposingStage() = runTest {
        val source = QueuedSource(listOf(preview(BookPreviewStatus.Ready), preview(BookPreviewStatus.Composing)))
        val model = model(source = { source.next() })
        model.run()
        assertEquals(BookPreviewModel.Stage.Preview, model.stage)

        // `refreshIfNeeded()` sonde une fois, voit « composing », puis entre en
        // veille (`watchRecomposition()`) — on n'a besoin que du tout début de
        // cette veille, pas de son terme.
        val refresh = launch { model.refreshIfNeeded() }
        waitUntil { model.isRecomposing }
        refresh.cancel()

        assertEquals(BookPreviewModel.Stage.Preview, model.stage)
        assertTrue(model.isRecomposing)
    }

    @Test fun aBackgroundRegenerationCompletesAndFlashes() = runTest {
        val source = QueuedSource(
            listOf(
                preview(BookPreviewStatus.Ready, pageCount = 4),
                preview(BookPreviewStatus.Composing),
                preview(BookPreviewStatus.Ready, pageCount = 5),
            ),
        )
        val model = model(source = { source.next() })
        model.run()

        // Une seule veille suffit : le troisième appel de la file répond déjà
        // « prêt », donc `watchRecomposition()` s'arrête à son premier
        // sondage — quatre secondes du modèle, sa propre cadence.
        model.refreshIfNeeded()

        assertEquals(BookPreviewModel.Stage.Preview, model.stage)
        assertFalse(model.isRecomposing)
        assertTrue(model.freshness.isUpdated)
        assertEquals(5, model.preview?.pageCount)
    }

    @Test fun aBackgroundRegenerationFailureKeepsTheOldDocument() = runTest {
        val source = QueuedSource(
            listOf(
                preview(BookPreviewStatus.Ready, pageCount = 4),
                preview(BookPreviewStatus.Failed("Erreur")),
            ),
        )
        val model = model(source = { source.next() })
        model.run()

        model.refreshIfNeeded()

        // Un échec de régénération en fond ne doit rien afficher sur un aperçu
        // déjà là : ni bandeau d'erreur, ni recul de la page comptée.
        assertEquals(BookPreviewModel.Stage.Preview, model.stage)
        assertFalse(model.isRecomposing)
        assertNull(model.errorMessage)
        assertEquals(4, model.preview?.pageCount)
    }

    // MARK: - La composition se lance à l'ouverture (T224)

    /** Ouvrir l'aperçu lance la composition **une fois**, puis la suit jusqu'au carnet. */
    @Test fun openingThePreviewLaunchesTheComposition() = runTest {
        val source = QueuedSource(listOf(preview(BookPreviewStatus.Composing), preview(BookPreviewStatus.Ready)))
        var launches = 0
        val model = model(source = { source.next() }, startComposition = { launches += 1 })

        model.run()

        assertEquals(1, launches)
        assertEquals(BookPreviewModel.Stage.Preview, model.stage)
    }

    /**
     * Un carnet sans souvenir : le serveur refuse de composer (`400
     * empty_memo`) et rien ne tourne. L'écran le dit au lieu d'attendre une
     * composition qui ne viendra jamais.
     */
    @Test fun aRefusedLaunchOnANeverComposedBookIsShown() = runTest {
        val refusal = "Ce carnet ne contient encore aucun souvenir."
        val source = QueuedSource(listOf(preview(BookPreviewStatus.Composing, pageCount = 0)))
        val model = model(
            source = { source.next() },
            startComposition = { throw Refused(refusal) },
            opensBlankPages = false,
        )

        model.run()

        assertEquals(BookPreviewModel.Stage.Composing, model.stage)
        assertEquals(refusal, model.errorMessage)
    }

    // MARK: - Une composition qui ne finit pas (19/10/2026)

    /**
     * Un rendu que personne ne finit : la page ne se remonte plus sans fin,
     * l'écran dit que c'est long et propose de réessayer.
     */
    @Test fun aCompositionThatNeverMovesStopsWaiting() = runTest {
        val stuck = BookPreview(
            memoId = "memo-1",
            title = "Rome",
            status = BookPreviewStatus.Composing,
            render = BookRenderProgress(id = "r1", phase = BookRenderPhase.Queued),
        )
        var reads = 0
        val model = model(
            source = {
                reads += 1
                stuck
            },
            startComposition = {},
            opensBlankPages = false,
        )
        model.pacing = BookPreviewModel.Pacing.fast

        model.run()

        assertEquals(BookPreviewModel.Stage.Composing, model.stage)
        assertEquals(BookCopy.Composition.tooLong, model.errorMessage)
        assertEquals(BookPreviewModel.Pacing.fast.maxUnchangedCompositionPolls + 1, reads)
    }

    /**
     * Une composition qui avance — la file, puis la mise en page — n'est pas
     * bloquée : le compte repart à chaque changement.
     */
    @Test fun aCompositionThatMovesKeepsBeingFollowed() = runTest {
        fun step(phase: BookRenderPhase) = BookPreview(
            memoId = "memo-1",
            title = "Rome",
            status = BookPreviewStatus.Composing,
            render = BookRenderProgress(id = "r1", phase = phase),
        )
        val source = QueuedSource(
            listOf(
                step(BookRenderPhase.Queued),
                step(BookRenderPhase.Queued),
                step(BookRenderPhase.Writing),
                step(BookRenderPhase.Writing),
                step(BookRenderPhase.Composing),
                step(BookRenderPhase.Composing),
                preview(BookPreviewStatus.Ready),
            ),
        )
        val model = model(source = { source.next() }, startComposition = {}, opensBlankPages = false)
        model.pacing = BookPreviewModel.Pacing.fast

        model.run()

        assertEquals(BookPreviewModel.Stage.Preview, model.stage)
        assertNull(model.errorMessage)
    }

    // MARK: - Debug : prévisualiser sans vrai contenu (Hugo, 19/10/2026)

    /**
     * Un carnet sans souvenir, en debug : l'aperçu s'ouvre sur des pages
     * blanches, le refus du serveur en bandeau.
     */
    @Test fun debugOpensBlankPagesForABookWithoutContent() = runTest {
        val refusal = "Ce carnet ne contient encore aucun souvenir."
        val model = model(
            source = { BookPreview(memoId = "memo-1", title = "Rome", pageCount = 0) },
            startComposition = { throw Refused(refusal) },
        )
        model.pacing = BookPreviewModel.Pacing.fast

        model.run()

        assertEquals(BookPreviewModel.Stage.Preview, model.stage)
        assertTrue(model.showsBlankPages)
        assertEquals(BookPreviewModel.BLANK_PAGE_COUNT, model.sheetCount)
        assertEquals(refusal, model.errorMessage)
        assertFalse(model.isComposed, "Des pages blanches ne se commandent pas.")
    }

    /** Le serveur injoignable, en debug : des pages blanches quand même. */
    @Test fun debugOpensBlankPagesWithoutAServer() = runTest {
        val model = model(source = { throw Refused("Injoignable") })
        model.pacing = BookPreviewModel.Pacing.fast

        model.run()

        assertEquals(BookPreviewModel.Stage.Preview, model.stage)
        assertEquals(BookCopy.Preview.blankTitle, model.preview?.title)
        assertEquals(BookPreviewModel.BLANK_PAGE_COUNT, model.sheetCount)
    }

    /**
     * Une composition trop longue pour le debug : les pages blanches, puis le
     * vrai carnet quand il arrive, sans rien toucher.
     */
    @Test fun debugShowsBlankPagesWhileACompositionTakesTooLong() = runTest {
        val composing = BookPreview(
            memoId = "memo-1",
            title = "Rome",
            status = BookPreviewStatus.Composing,
            render = BookRenderProgress(id = "r1", phase = BookRenderPhase.Writing),
        )
        val gate = Gate()
        val model = model(
            source = { if (gate.isOpen) preview(BookPreviewStatus.Ready, pageCount = 12) else composing },
            startComposition = {},
        )
        model.pacing = BookPreviewModel.Pacing.fast.copy(
            maxUnchangedCompositionPolls = 1_000,
            maxUnchangedRecompositionPolls = 1_000,
            debugBlankPagesAfter = 100.milliseconds,
        )

        val running = launch { model.run() }
        waitUntil { model.stage == BookPreviewModel.Stage.Preview }
        assertTrue(model.showsBlankPages)
        assertTrue(model.isRecomposing)
        assertNull(model.errorMessage)

        gate.isOpen = true
        running.join()

        assertFalse(model.isRecomposing)
        assertEquals(12, model.sheetCount)
        assertTrue(model.isComposed)
    }

    /** Un refus ne cache pas un carnet déjà composé : on le feuillette quand même. */
    @Test fun aRefusedLaunchStillOpensAComposedBook() = runTest {
        val source = QueuedSource(listOf(preview(BookPreviewStatus.Ready)))
        val model = model(source = { source.next() }, startComposition = { throw Refused("Panne") })

        model.run()

        assertEquals(BookPreviewModel.Stage.Preview, model.stage)
        assertNull(model.errorMessage)
    }

    /**
     * Le récit a changé depuis le dernier rendu : la remise à jour tourne, mais
     * l'aperçu s'ouvre **tout de suite** sur le carnet d'avant, avec son
     * bandeau — et ce carnet reste commandable.
     */
    @Test fun aRecompositionOpensOnTheBookWeAlreadyHave() = runTest {
        val recomposing = BookPreview(
            memoId = "memo-1",
            title = "Rome",
            status = BookPreviewStatus.Composing,
            pageCount = 4,
            render = BookRenderProgress(id = "r2", phase = BookRenderPhase.Writing),
            readyRenderId = "r1",
        )
        val model = model(source = { recomposing }, startComposition = {})

        val started = currentTime
        val running = launch { model.run() }
        waitUntil { model.stage == BookPreviewModel.Stage.Preview }
        running.cancel()

        assertTrue(currentTime - started < 1_000, "Pas de cascade.")
        assertTrue(model.isRecomposing)
        assertTrue(model.isComposed)
        assertEquals(BookRenderPhase.Writing, model.compositionPhase)
    }

    // MARK: - Les couvertures choisies (T223)

    /**
     * Couvertures réglées : la première page montre la première de
     * couverture, la dernière la quatrième, et le reste les pages du carnet.
     */
    @Test fun configuredCoversShowOnTheFirstAndLastPages() = runTest {
        val configured = BookPreview(
            memoId = "memo-1",
            title = "Rome",
            status = BookPreviewStatus.Ready,
            pageCount = 10,
            hasConfiguredCovers = true,
        )
        val model = model(source = { configured }, covers = { BookCovers.fixture })

        model.run()
        waitUntil { model.covers != null }

        assertEquals(CoverFace.Front, model.coverFace(0))
        assertEquals(CoverFace.Back, model.coverFace(9))
        assertNull(model.coverFace(4))
        assertEquals(CoverCallToAction.Edit, model.coverCallToAction, "« Configurer » reste sur la page.")
    }

    /** Pas encore réglées : la page du PDF et son invitation, sans même lire les plats. */
    @Test fun unconfiguredCoversKeepThePdfPage() = runTest {
        var reads = 0
        val model = model(
            source = { BookPreview(memoId = "memo-1", title = "Rome", status = BookPreviewStatus.Ready, pageCount = 10) },
            covers = {
                reads += 1
                BookCovers.fixture
            },
        )

        model.run()

        assertNull(model.coverFace(0))
        assertEquals(CoverCallToAction.Invitation, model.coverCallToAction)
        assertEquals(0, reads)
    }
}

/**
 * Le parcours en accéléré : une cascade et des sondages de quelques
 * millisecondes, et une borne atteinte en cinq sondages.
 */
internal val BookPreviewModel.Pacing.Companion.fast: BookPreviewModel.Pacing
    get() = BookPreviewModel.Pacing(
        compositionDuration = 20.milliseconds,
        progressTick = 5.milliseconds,
        pollInterval = 5.milliseconds,
        maxUnchangedCompositionPolls = 5,
        recompositionPollInterval = 5.milliseconds,
        maxUnchangedRecompositionPolls = 5,
    )
