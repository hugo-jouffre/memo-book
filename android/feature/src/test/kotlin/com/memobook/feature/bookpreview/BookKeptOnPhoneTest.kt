package com.memobook.feature.bookpreview

import com.memobook.core.BookCopy
import com.memobook.core.BookPreview
import com.memobook.core.BookPreviewStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import java.io.File
import java.nio.file.Files
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * **Le carnet composé reste sur le téléphone** (T299, Hugo, 08/11/2026 —
 * « l'aperçu ne doit pas se remettre en page à chaque ouverture ; la dernière
 * version est gardée sur le téléphone, donc lisible sans réseau, et un bouton à
 * flèche tournante la régénère »). Porté de `BookKeptOnPhoneTests.swift`.
 *
 * ⚠️ **Deux cas d'iOS ne se portent pas**, et c'est le framework qui le décide :
 * « le rendu qu'on a déjà ne se redescend pas » et « le carnet gardé s'ouvre
 * sans réseau » demandent qu'un PDF s'**ouvre**, donc `PdfRenderer`, une classe
 * du framework que les tests de la JVM n'ont pas. Côté iOS, PDFKit tourne dans
 * le simulateur et les deux cas sont tenus là-bas
 * (`testTheAnnouncedRenderWeAlreadyHaveIsNotDownloadedAgain`,
 * `testTheKeptBookOpensWithoutNetwork`). Ce qui se porte ici est tout le reste :
 * le magasin, les mots de l'écran, et la flèche.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class BookKeptOnPhoneTest {
    private lateinit var directory: File

    @BeforeTest fun setUp() {
        Dispatchers.setMain(StandardTestDispatcher())
        directory = Files.createTempDirectory("book-kept").toFile()
    }

    @AfterTest fun tearDown() {
        Dispatchers.resetMain()
        directory.deleteRecursively()
    }

    /** Un fichier qui tient la place du PDF : le magasin ne l'ouvre pas. */
    private fun document(name: String = "carnet.pdf"): File {
        val file = File(directory, name)
        file.writeBytes("%PDF-1.7 ce n'est pas un vrai carnet".encodeToByteArray())
        return file
    }

    private fun store() = BookDocumentStore(File(directory, "magasin"))

    // MARK: Ce que le magasin garde

    @Test fun aKeptBookComesBackWithTheRenderItShows() = runTest {
        val store = store()
        val hier = 1_764_000_000_000L

        store.keep(document(), renderId = "render-7", memoId = "memo-1", at = hier)

        val kept = store.kept("memo-1")
        assertEquals("render-7", kept?.renderId)
        assertEquals(hier, kept?.keptAt)
        assertNotNull(kept?.file)
        assertNull(store.kept("memo-2"), "Un carnet est gardé par voyage : celui-ci n'a rien.")
    }

    /**
     * **Un PDF sans sa fiche ne compte pas.** On ne saurait pas de quel rendu il
     * vient, donc ni s'il est à jour, ni de quand il date : autant le
     * redescendre.
     */
    @Test fun aKeptBookWithoutItsCardIsRefused() = runTest {
        val store = store()
        store.keep(document(), renderId = "render-7", memoId = "memo-1")

        File(directory, "magasin").listFiles { file -> file.extension == "json" }
            ?.forEach { it.delete() }

        assertNull(store.kept("memo-1"))
    }

    /** Une nouvelle composition remplace la précédente : le dossier ne grandit pas. */
    @Test fun aNewCompositionReplacesTheOldOne() = runTest {
        val store = store()
        store.keep(document("un.pdf"), renderId = "render-7", memoId = "memo-1")
        store.keep(document("deux.pdf"), renderId = "render-8", memoId = "memo-1")

        assertEquals("render-8", store.kept("memo-1")?.renderId)
        assertEquals(
            2,
            File(directory, "magasin").listFiles()?.size,
            "Un PDF et sa fiche, et rien de plus.",
        )
    }

    /** À la déconnexion : ce sont les voyages de quelqu'un. */
    @Test fun everythingGoesOnSignOut() = runTest {
        val store = store()
        store.keep(document(), renderId = "render-7", memoId = "memo-1")

        store.clearAll()

        assertNull(store.kept("memo-1"))
    }

    // MARK: Ce que l'écran en dit

    private fun TestScope.model(responses: List<BookPreview>): BookPreviewModel {
        val remaining = ArrayDeque(responses)
        return BookPreviewModel(
            memoId = "memo-1",
            source = { remaining.removeFirstOrNull() ?: throw Unreachable() },
            startComposition = { },
            workDirectory = directory,
        ).also { it.timeSource = testScheduler.timeSource }
    }

    private class Unreachable : Exception()

    private fun composed(upToDate: Boolean = true) = BookPreview(
        memoId = "memo-1",
        title = "Rome",
        status = BookPreviewStatus.Ready,
        pageCount = 3,
        readyRenderId = "render-7",
        isUpToDate = upToDate,
    )

    /**
     * Rien n'a changé : le serveur rend le carnet qu'on a, et le geste reçoit
     * une réponse — sans elle, une flèche qui tourne une seconde se lirait comme
     * une panne.
     */
    @Test fun theArrowSaysWhenThereWasNothingToRegenerate() = runTest {
        val model = model(listOf(composed(), composed()))
        model.run()

        model.regenerate()

        val state = model.state.value
        assertTrue(state.isAlreadyUpToDate)
        assertEquals(BookCopy.Preview.alreadyUpToDate, state.notice?.message)
        assertEquals(true, state.notice?.answersAGesture, "C'est la réponse à un appui.")
        assertFalse(state.isRefreshing)
    }

    /**
     * Et quand le serveur en lance une, la flèche **suit** la composition au
     * lieu de dire que tout va bien.
     */
    @Test fun theArrowFollowsTheCompositionItStarted() = runTest {
        val composing = BookPreview(
            memoId = "memo-1",
            title = "Rome",
            status = BookPreviewStatus.Composing,
            pageCount = 3,
            readyRenderId = "render-7",
            isUpToDate = false,
        )
        val model = model(listOf(composed(), composing))
        model.pacing = BookPreviewModel.Pacing.fast
        model.run()

        model.regenerate()

        val state = model.state.value
        assertFalse(
            state.isAlreadyUpToDate,
            "Une composition est partie : le carnet n'était pas à jour.",
        )
        assertNotEquals(
            BookCopy.Preview.alreadyUpToDate,
            state.notice?.message,
            "Dire « déjà à jour » après avoir lancé une mise en page serait un mensonge.",
        )
        assertFalse(state.isRefreshing, "La flèche s'arrête quand la composition s'arrête.")
    }

    /**
     * La flèche pâlie **répond**, comme « Partager » depuis T302 : un bouton
     * mort avalerait le geste sans un mot.
     */
    @Test fun thePaleArrowExplainsItself() = runTest {
        val model = model(
            listOf(
                BookPreview(
                    memoId = "memo-1",
                    title = "Rome",
                    status = BookPreviewStatus.Ready,
                    pageCount = 0,
                ),
            ),
        )
        model.run()
        assertFalse(model.state.value.canShare)

        model.explainRegenerateIsClosed()

        val state = model.state.value
        assertEquals(BookCopy.Preview.nothingToRegenerate, state.notice?.message)
        assertEquals(true, state.notice?.answersAGesture)
    }

    /**
     * **La version gardée passe avant « pas encore composé »** : un carnet gardé
     * est bien un carnet, et le serveur n'a simplement rien dit.
     */
    @Test fun theKeptVersionIsNamedRatherThanCalledUncomposed() {
        val hier = 1_764_000_000_000L
        val state = BookPreviewModel.State(
            stage = BookPreviewModel.Stage.Preview,
            keptAt = hier,
        )

        assertEquals(BookCopy.Preview.keptVersion(hier), state.notice?.message)
        assertEquals(
            false,
            state.notice?.answersAGesture,
            "C'est l'état des choses, au beige de la marque.",
        )
        assertNotEquals(BookCopy.Preview.notComposed, state.notice?.message)
    }

    // MARK: La date qu'on annonce

    /**
     * Le jour et le moment, pas une heure : personne ne se souvient avoir
     * composé son carnet à 21 h 47.
     */
    @Test fun theMomentIsSaidTheWayPeopleSayIt() {
        val zone = java.time.ZoneId.of("Europe/Paris")
        fun instant(jour: Int, heure: Int) =
            java.time.LocalDateTime.of(2026, 11, jour, heure, 0).atZone(zone).toInstant()
        val maintenant = instant(26, 15)

        assertEquals(
            "ce matin",
            BookCopy.Preview.moment(instant(26, 9).toEpochMilli(), maintenant, zone),
        )
        assertEquals(
            "hier soir",
            BookCopy.Preview.moment(instant(25, 21).toEpochMilli(), maintenant, zone),
        )
        assertEquals(
            "le 12 novembre",
            BookCopy.Preview.moment(instant(12, 10).toEpochMilli(), maintenant, zone),
            "Passé hier, c'est la date qui parle : « il y a 14 jours » demande un calcul.",
        )
    }
}
