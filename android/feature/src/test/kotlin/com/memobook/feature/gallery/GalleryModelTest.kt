package com.memobook.feature.gallery

import com.memobook.core.Gallery
import com.memobook.core.GalleryCategory
import com.memobook.core.GalleryTrip
import com.memobook.feature.ContentFreshness
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
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
 * La mosaïque de la galerie. **Sans jumeau sur iOS**, où `GalleryModel` n'a pas
 * de suite : ces cas tiennent ce que l'écran promet — la grille relue du disque
 * se montre tout de suite, un filtre disparu du serveur ne laisse pas la grille
 * vide, et la mosaïque équilibre ses colonnes.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class GalleryModelTest {
    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private val rando = GalleryCategory(id = "cat-randonnee", slug = "randonnee", name = "Randonnée", iconKey = "footprints")
    private val gallery = Gallery(
        categories = listOf(rando),
        trips = listOf(
            GalleryTrip(id = "a", title = "Le GR20", categoryIds = listOf(rando.id)),
            GalleryTrip(id = "b", title = "Lisbonne"),
            GalleryTrip(id = "c", title = "Le tour du Mont-Blanc", categoryIds = listOf(rando.id)),
        ),
    )

    /** Ce qu'on avait se range **avant** que le serveur réponde : pas d'écran vide le temps de l'aller-retour. */
    @Test
    fun aRestoredGalleryIsLaidOutAtOnce() = runTest {
        val server = CompletableDeferred<Gallery>()
        val model = GalleryModel(source = { server.await() }, cached = { gallery })

        launch { model.load() }
        runCurrent()

        assertEquals(ContentFreshness.Restored, model.state.value.freshness)
        assertFalse(model.state.value.isEmpty, "La grille montre ce qu'elle avait.")
        assertEquals(3, model.state.value.columns.sumOf { it.size })

        server.complete(gallery)
    }

    /** Une catégorie qui a disparu du serveur ne laisse pas la grille filtrée sur rien. */
    @Test
    fun aVanishedCategoryFallsBackToEverything() = runTest {
        var served = gallery
        val model = GalleryModel(source = { served })
        model.load()

        model.select(rando.id)
        assertEquals(2, model.state.value.columns.sumOf { it.size })

        served = gallery.copy(categories = emptyList())
        model.load()
        assertNull(model.state.value.selectedCategoryId)
        assertEquals(3, model.state.value.columns.sumOf { it.size })
    }

    /** Chaque carnet va dans la colonne la plus courte ; à égalité, la plus à gauche. */
    @Test
    fun theMosaicFillsTheShortestColumn() {
        val columns = GalleryModel.balanced(gallery.trips, columns = 2)
        assertEquals(2, columns.size)
        assertEquals("a", columns[0].first().id, "La première vignette se pose à gauche.")
        assertEquals(3, columns.sumOf { it.size })
        assertTrue(GalleryModel.balanced(gallery.trips, columns = 1).single().size == 3)
        assertTrue(GalleryModel.balanced(gallery.trips, columns = 0).isEmpty())
    }
}
