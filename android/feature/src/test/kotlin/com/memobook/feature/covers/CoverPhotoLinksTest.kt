package com.memobook.feature.covers

import com.memobook.core.BookCovers
import com.memobook.core.CoverPhoto
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import java.io.File
import java.net.URI
import java.time.Instant
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * **Les photos de couverture passent par un lien signé d'une heure** (T237) :
 * un écran resté ouvert montrait des images cassées. Le modèle renouvelle les
 * liens — à l'échec d'une image, ou en revenant sur le parcours passé le délai —
 * sans toucher au plat qu'on compose. Jumeau de `CoverPhotoLinksTests.swift`.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class CoverPhotoLinksTest {
    @BeforeTest fun setUp() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @AfterTest fun tearDown() {
        Dispatchers.resetMain()
    }

    private class Server {
        var generation = 1
        var reads = 0

        val covers: BookCovers
            get() = BookCovers.fixture.let { fixture ->
                fixture.copy(photos = fixture.photos.map { CoverPhoto(id = it.id, url = "https://cdn.test/${it.id}?sig=$generation") })
            }
    }

    private fun model(server: Server, clock: () -> Instant): CoversModel {
        val model = CoversModel(tripId = "trip", source = {
            server.reads += 1
            server.covers
        })
        model.now = clock
        return model
    }

    private fun CoversModel.signatures(): List<String?> = covers?.photos.orEmpty().map { photo -> photo.url?.let { URI(it).query } }

    @Test fun staleLinksAreRenewedWithoutLosingTheCoverBeingComposed() = runTest {
        val server = Server()
        var now = Instant.ofEpochSecond(0)
        val model = model(server) { now }
        model.load()

        val otherStyle = assertNotNull(model.styles.firstOrNull { it.id != model.cover?.styleId })
        model.preview(style = otherStyle)

        server.generation = 2
        now = now.plusSeconds(50 * 60)
        model.load()

        assertEquals(2, server.reads)
        assertTrue(model.signatures().all { it == "sig=2" })
        assertEquals(otherStyle.id, model.cover?.styleId, "Le style choisi sans valider reste.")
    }

    @Test fun aFreshParcoursDoesNotRereadTheServer() = runTest {
        val server = Server()
        var now = Instant.ofEpochSecond(0)
        val model = model(server) { now }
        model.load()
        now = now.plusSeconds(10 * 60)
        model.load()

        assertEquals(1, server.reads)
    }

    @Test fun aBrokenImageDoesNotHammerTheServer() = runTest {
        val server = Server()
        val now = Instant.ofEpochSecond(0)
        val model = model(server) { now }
        model.load()

        server.generation = 2
        model.refreshPhotoLinks()
        model.refreshPhotoLinks()
        model.refreshPhotoLinks()

        assertEquals(2, server.reads, "Une seule relecture par délai de grâce.")
        assertTrue(model.signatures().all { it == "sig=2" })
    }

    @Test fun aPhotoImportedOnTheDeviceKeepsItsLocalAddress() = runTest {
        val server = Server()
        val model = model(server) { Instant.now() }
        model.load()
        val local = CoverPhoto(id = "local-1", url = File("/tmp/local-1.jpg").toURI().toString())
        model.add(local)

        model.refreshPhotoLinks()

        assertEquals(local, model.covers?.photos?.firstOrNull { it.id == "local-1" })
    }
}
