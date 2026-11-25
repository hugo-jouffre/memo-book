package com.memobook.feature.bookpreview

import com.memobook.core.BookCopy
import com.memobook.core.BookPreview
import com.memobook.core.BookPreviewStatus
import com.memobook.feature.tripsettings.composingFixture
import com.memobook.feature.tripsettings.fixture
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * **On ne partage pas un carnet qui n'existe pas encore** (T302, Hugo,
 * 08/11/2026 — « un carnet non composé se présente comme prêt : page blanche,
 * aucun chargement visible, et “Partager” envoie un PDF qui dit lui-même qu'il
 * n'est pas composé »). Porté de `BookShareClosedTests.swift`, cas pour cas.
 *
 * L'état en cause est précis, et le serveur le produit : `status` vient du
 * **dernier** rendu, `pdfUrl` du dernier rendu **prêt**
 * (`appSerializers.ts`). Un rendu marqué prêt dont le fichier n'a jamais été
 * écrit annonce donc « ready » sans PDF — et c'est exactement le carnet que
 * ces tests posent.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class BookShareClosedTest {
    /** Le carnet du ticket : le serveur le dit prêt, et il n'y a rien derrière. */
    private fun announcedReady() =
        BookPreview(memoId = "memo-1", title = "Rome", status = BookPreviewStatus.Ready, pageCount = 10)

    /**
     * Le même, composé pour de bon. **Sans `pdfUrl`** : un rendu prêt suffit à
     * dire qu'il y a un carnet, et ces tests n'ouvrent ainsi aucune connexion.
     */
    private fun composed() = BookPreview(
        memoId = "memo-1",
        title = "Rome",
        status = BookPreviewStatus.Ready,
        pageCount = 10,
        readyRenderId = "render-1",
    )

    private fun TestScope.model(responses: List<BookPreview>): BookPreviewModel {
        val remaining = ArrayDeque(responses)
        return BookPreviewModel(
            memoId = "memo-1",
            source = { remaining.removeFirstOrNull() ?: throw Empty() },
        ).also { it.timeSource = testScheduler.timeSource }
    }

    private class Empty : Exception()

    @BeforeTest fun setUp() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @AfterTest fun tearDown() {
        Dispatchers.resetMain()
    }

    /**
     * Le cas de Hugo : « Partager » est fermé, et l'écran ne se présente plus
     * comme prêt.
     */
    @Test fun aBookAnnouncedReadyWithoutItsPdfDoesNotOpenSharing() = runTest {
        val model = model(listOf(announcedReady()))

        model.run()

        val state = model.state.value
        assertEquals(BookPreviewModel.Stage.Preview, state.stage)
        assertFalse(state.canShare, "Un carnet annoncé prêt sans PDF n'a ni fichier ni lien à envoyer.")
        assertEquals(BookCopy.Preview.notComposed, state.notice?.message)
        assertEquals(
            false,
            state.notice?.answersAGesture,
            "Personne n'a rien demandé : c'est l'état des choses, au beige de la marque.",
        )
    }

    /** Ce qu'un bouton mort ne faisait pas : répondre. */
    @Test fun theClosedShareButtonExplainsItself() = runTest {
        val model = model(listOf(announcedReady()))
        model.run()

        model.explainShareIsClosed()

        val notice = model.state.value.notice
        assertEquals(BookCopy.Share.notComposedYet, notice?.message)
        assertEquals(
            true,
            notice?.answersAGesture,
            "La phrase répond à un geste : c'est le ton d'information, pas le beige.",
        )
    }

    /** Un carnet composé ne dit rien de lui-même — il se feuillette. */
    @Test fun aComposedBookSharesWithoutAWord() = runTest {
        val model = model(listOf(composed()))

        model.run()

        assertTrue(model.state.value.canShare)
        assertNull(model.state.value.notice)
    }

    /** L'explication ne survit pas à la raison qui l'a posée. */
    @Test fun theExplanationGoesAwayWhenTheBookArrives() = runTest {
        val model = model(listOf(announcedReady(), composed()))
        model.run()
        model.explainShareIsClosed()
        assertNotNull(model.state.value.notice)

        model.refreshIfNeeded()

        assertTrue(model.state.value.canShare)
        assertNull(model.state.value.notice, "Le carnet est là : le bouton s'est ouvert, le mot n'a plus d'objet.")
    }

    /**
     * **L'écran de composition ne se répète pas.** Il dit déjà sous sa page où
     * en est la composition, et bien mieux que ce bandeau — qui n'y paraît
     * donc qu'en réponse à un appui sur « Partager ».
     */
    @Test fun theComposingScreenOnlySpeaksWhenAsked() = runTest {
        val model = model(emptyList())

        assertEquals(BookPreviewModel.Stage.Composing, model.state.value.stage)
        assertFalse(model.state.value.canShare)
        assertNull(model.state.value.notice)

        model.explainShareIsClosed()

        assertEquals(BookCopy.Share.notComposedYet, model.state.value.notice?.message)
    }

    /**
     * **L'en-tête ne compte pas des pages qui n'existent pas.** Le compte vient
     * du serveur et survit à un rendu qui n'a pas abouti : « 10 pages
     * composées » au-dessus d'une page vide est la première chose qui fait
     * prendre ce carnet pour un carnet prêt.
     */
    @Test fun theHeaderDoesNotCountPagesThatAreNotComposed() = runTest {
        val open = model(listOf(announcedReady()))
        open.run()

        assertEquals("Rome", open.state.value.headerSubtitle)

        val ready = model(listOf(composed()))
        ready.run()

        assertEquals(
            BookCopy.Preview.subtitle(title = "Rome", pages = 10),
            ready.state.value.headerSubtitle,
        )
    }

    /**
     * Le jeu d'essai est un carnet **composé** : sans ça, le bac à sable
     * n'aurait plus montré ni la feuille de partage ni le choix des étapes
     * (T285).
     */
    @Test fun theSandboxBookIsStillShareable() {
        assertTrue(BookPreview.fixture.hasComposedDocument)
        assertFalse(
            BookPreview.composingFixture.hasComposedDocument,
            "Celui qui se compose, lui, n'a encore rien à partager.",
        )
    }
}
