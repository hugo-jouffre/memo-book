package com.memobook.feature.tripsettings

import com.memobook.core.BookCustomisation
import com.memobook.core.BookCustomisationPreview
import com.memobook.core.BookFontCombo
import com.memobook.core.TripSettings
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import java.io.IOException
import java.net.URI
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

/**
 * L'aperçu de personnalisation en tête de l'écran : quelle image, quand elle
 * change, et ce qui reste à l'écran pendant qu'elle arrive — ou n'arrive pas.
 * Jumeau de `BookCustomisationPreviewLoaderTests.swift`, cas pour cas.
 *
 * Les attentes sont celles du planificateur de test : « 80 ms » est un `delay`
 * du corps du test, et le temps ne passe que quand plus rien d'autre n'avance.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class BookCustomisationPreviewLoaderTest {
    @BeforeTest fun setUp() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @AfterTest fun tearDown() {
        Dispatchers.resetMain()
    }

    // MARK: L'adresse suit cinq réglages, et cinq seulement

    @Test fun theAddressIgnoresTheFourSettingsOutsideThePreview() = runTest {
        val model = openedModel()
        val opening = model.previewURL
        assertNotNull(opening)

        model.setTargetPageCount(120)
        model.setQuiz(false)
        model.setFreeZones(false)
        model.setCrossword(false)

        assertEquals(opening, model.previewURL, "l’image se rechargerait pour un réglage qu’elle ne montre pas")
    }

    @Test fun theAddressFollowsEachOfTheFiveSettings() = runTest {
        val gestures: List<Pair<String, (BookCustomisationModel) -> Unit>> = listOf(
            "pointillés" to { it.setRules(false) },
            "ratio" to { it.setPhotoTextRatio(75) },
            "fun facts" to { it.setFunFacts(false) },
            "stickers" to { it.setDecorationQuota(4) },
            "typographie" to { it.setFontCombo(BookFontCombo.editorial) },
        )
        for ((setting, gesture) in gestures) {
            val model = openedModel()
            val opening = model.previewURL
            gesture(model)
            assertNotEquals(opening, model.previewURL, setting)
        }
    }

    @Test fun theOpeningAddressIsTheDefaultPreview() = runTest {
        val model = openedModel()
        assertEquals(BookCustomisationPreview.imageURL(BookCustomisation()), model.previewURL)
    }

    // MARK: Ce que la tête montre

    @Test fun theOpeningImageArrivesWithoutWaiting() = runTest {
        // Une attente de cinq secondes, qu'on mesure : la première image ne
        // doit pas la faire.
        val downloads = Downloads()
        val loader = BookCustomisationPreviewLoader(settle = 5.seconds, fetch = downloads::fetch)
        val start = testScheduler.currentTime

        loader.show(url(0))

        assertTrue(testScheduler.currentTime - start < 1_000)
        assertSame(downloads.image(url(0)), loader.image)
        assertEquals(url(0), loader.shownURL)
    }

    @Test fun nothingIsShownBeforeTheSettingsAreRead() = runTest {
        val downloads = Downloads()
        val loader = BookCustomisationPreviewLoader(fetch = downloads::fetch)

        loader.show(null)

        assertNull(loader.image)
        assertEquals(emptyList(), downloads.requested)
    }

    @Test fun aSliderDragOnlyLoadsWhereItStops() = runTest {
        // Le ratio glisse de 0 à 75 % : quatre crans en rafale. Comme
        // `LaunchedEffect(url)`, chaque cran annule le précédent ; seul le
        // dernier arrive au bout de son attente.
        val downloads = Downloads()
        val loader = BookCustomisationPreviewLoader(settle = 150.milliseconds, fetch = downloads::fetch)
        val screen = Screen(this, loader)
        screen.change(url(0)).join()

        screen.change(url(25))
        screen.change(url(50))
        screen.change(url(75)).join()

        assertEquals(listOf(url(0), url(75)), downloads.requested)
        assertSame(downloads.image(url(75)), loader.image)
    }

    @Test fun aSlowDragAtTheRealPaceOnlyLoadsWhereItStops() = runTest {
        // Le même glissé, à l'attente de l'app et à un cran toutes les 80 ms —
        // un doigt qui traverse le curseur. Une attente trop courte ferait
        // charger les crans du milieu.
        val downloads = Downloads()
        val loader = BookCustomisationPreviewLoader(fetch = downloads::fetch)
        val screen = Screen(this, loader)
        screen.change(url(0)).join()

        screen.change(url(25))
        delay(80)
        screen.change(url(50))
        delay(80)
        screen.change(url(75)).join()

        assertEquals(listOf(url(0), url(75)), downloads.requested)
    }

    @Test fun aDragOnBarePaperOnlyLoadsWhereItStops() = runTest {
        // L'ouverture a échoué : la tête est le papier nu. Un glissé qui suit ne
        // doit pas en profiter pour charger chaque cran.
        val downloads = Downloads()
        downloads.failing = setOf(url(0))
        val loader = BookCustomisationPreviewLoader(fetch = downloads::fetch)
        val screen = Screen(this, loader)
        screen.change(url(0)).join()
        assertNull(loader.image)

        screen.change(url(25))
        delay(80)
        screen.change(url(50))
        delay(80)
        screen.change(url(75)).join()

        assertEquals(listOf(url(0), url(75)), downloads.requested)
        assertSame(downloads.image(url(75)), loader.image)
    }

    @Test fun thePreviousImageStaysUntilTheNextIsReady() = runTest {
        val downloads = Downloads()
        val loader = BookCustomisationPreviewLoader(settle = 10.milliseconds, fetch = downloads::fetch)
        val screen = Screen(this, loader)
        screen.change(url(0)).join()

        downloads.hold(url(25))
        val task = screen.change(url(25))
        advanceUntilIdle()
        assertTrue(url(25) in downloads.requested)

        // Elle se télécharge : la tête montre toujours la précédente, pas le
        // papier nu.
        assertSame(downloads.image(url(0)), loader.image)

        downloads.release(url(25))
        task.join()
        assertSame(downloads.image(url(25)), loader.image)
    }

    @Test fun aFailureKeepsWhatIsShownAndIsRetriedLater() = runTest {
        val downloads = Downloads()
        val loader = BookCustomisationPreviewLoader(settle = 10.milliseconds, fetch = downloads::fetch)
        val screen = Screen(this, loader)
        screen.change(url(0)).join()

        downloads.failing = setOf(url(25))
        screen.change(url(25)).join()
        assertEquals(url(0), loader.shownURL)
        assertSame(downloads.image(url(0)), loader.image, "un échec a vidé la tête")

        // Le réseau revient ; le réglage suivant redemande l'image.
        downloads.failing = emptySet()
        screen.change(url(50)).join()
        screen.change(url(25)).join()
        assertSame(downloads.image(url(25)), loader.image)
    }

    @Test fun aFailureAtOpeningLeavesThePaper() = runTest {
        val downloads = Downloads()
        downloads.failing = setOf(url(0))
        val loader = BookCustomisationPreviewLoader(fetch = downloads::fetch)

        loader.show(url(0))

        assertNull(loader.image)
    }

    @Test fun aRecentImageIsNotDownloadedAgain() = runTest {
        val downloads = Downloads()
        val loader = BookCustomisationPreviewLoader(settle = 10.milliseconds, fetch = downloads::fetch)
        val screen = Screen(this, loader)

        screen.change(url(0)).join()
        screen.change(url(25)).join()
        screen.change(url(0)).join()

        assertEquals(listOf(url(0), url(25)), downloads.requested)
        assertEquals(url(0), loader.shownURL)
    }

    // MARK: Outils

    private fun url(ratio: Int): URI = URI("https://apercus.test/$ratio.webp")

    private suspend fun openedModel(): BookCustomisationModel {
        val model = BookCustomisationModel(tripId = "trip-rome", source = { TripSettings.fixture })
        model.load()
        return model
    }

    /** Ce que fait `LaunchedEffect(url)` : une nouvelle adresse annule la tâche en cours et en lance une autre. */
    private class Screen(private val scope: CoroutineScope, private val loader: BookCustomisationPreviewLoader<Any>) {
        private var current: Job? = null

        fun change(url: URI): Job {
            current?.cancel()
            return scope.launch { loader.show(url) }.also { current = it }
        }
    }

    /** Les téléchargements, que le test fait échouer ou retient. */
    private class Downloads {
        val requested = mutableListOf<URI>()
        var failing: Set<URI> = emptySet()
        private val held = mutableSetOf<URI>()
        private val waiting = mutableMapOf<URI, CompletableDeferred<Unit>>()
        private val images = mutableMapOf<URI, Any>()

        /** Une image par adresse, toujours la même : on les compare par identité. */
        fun image(url: URI): Any = images.getOrPut(url) { Any() }

        suspend fun fetch(url: URI): Any {
            requested += url
            if (url in held) CompletableDeferred<Unit>().also { waiting[url] = it }.await()
            if (url in failing) throw IOException("Pas de réseau")
            return image(url)
        }

        fun hold(url: URI) {
            held += url
        }

        fun release(url: URI) {
            held -= url
            waiting.remove(url)?.complete(Unit)
        }
    }
}
