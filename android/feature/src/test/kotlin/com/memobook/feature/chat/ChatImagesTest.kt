@file:OptIn(ExperimentalCoroutinesApi::class)

package com.memobook.feature.chat

import android.content.ContextWrapper
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.ImageBitmapConfig
import androidx.compose.ui.graphics.colorspace.ColorSpace
import androidx.compose.ui.graphics.colorspace.ColorSpaces
import com.memobook.core.ChatContext
import com.memobook.core.ChatThread
import com.memobook.core.ChatThreadUpdate
import com.memobook.core.ChatTurnStatus
import com.memobook.feature.until
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import java.awt.Color
import java.awt.image.BufferedImage
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.URI
import java.nio.file.Files
import java.time.Instant
import javax.imageio.ImageIO
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Les images du fil passent par le modèle (T206, 30/09/2026) : une photo du
 * voyage **avec la session**, par le transport — un `AsyncImage` se faisait
 * refuser `/v1/entries/:id/media` en `401` —, une photo qu'on vient de choisir
 * depuis le disque. Porté de `ChatImagesTests.swift`, cas pour cas.
 *
 * `BitmapFactory` ne tourne pas sur la JVM : le modèle reçoit ici un décodeur
 * `javax.imageio` qui suit les mêmes règles de taille que celui de l'app
 * ([ChatImage.sampleSize], [ChatImage.fittedSize]) — c'est le chemin des
 * octets qu'on vérifie, et la règle de taille à part.
 */
class ChatImagesTest {
    private val dispatcher = StandardTestDispatcher()
    private lateinit var cacheDirectory: File

    @BeforeTest
    fun setUp() {
        System.setProperty("java.awt.headless", "true")
        Dispatchers.setMain(dispatcher)
        cacheDirectory = Files.createTempDirectory("chat-images").toFile()
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
        cacheDirectory.deleteRecursively()
    }

    /** Ce que le transport a téléchargé, et pour qui. */
    private class Downloads {
        val urls = mutableListOf<URI>()
    }

    /** Une image de 2 000 × 1 500 px : plus grande que ce que le fil garde. */
    private val picture: ByteArray by lazy {
        val image = BufferedImage(2_000, 1_500, BufferedImage.TYPE_INT_RGB)
        image.createGraphics().apply {
            color = Color(0x30, 0xB0, 0xC7)
            fillRect(0, 0, 2_000, 1_500)
            dispose()
        }
        ByteArrayOutputStream().use { out ->
            ImageIO.write(image, "png", out)
            out.toByteArray()
        }
    }

    /** Le décodeur de la JVM, aux règles de taille de l'app. */
    private val decoder = ChatImageDecoder { data, maximumPixelSize ->
        val image = runCatching { ImageIO.read(ByteArrayInputStream(data)) }.getOrNull() ?: return@ChatImageDecoder null
        val (width, height) = ChatImage.fittedSize(image.width, image.height, maximumPixelSize)
        TestImageBitmap(width, height)
    }

    private fun model(downloads: Downloads): ChatModel {
        val picture = picture
        val thread = ChatThread(id = "trip", title = "Lisbonne 2024", context = ChatContext(tripId = "trip", stepId = null), now = Instant.now())
        return ChatModel(
            transport = ChatTransport(
                load = { thread },
                poll = { ChatThreadUpdate(messages = emptyList(), turn = ChatTurnStatus.Idle, now = Instant.now()) },
                send = { ChatSendOutcome.Queued },
                editTranscript = { _, _ -> throw CancellationException() },
                media = { url ->
                    downloads.urls += url
                    picture
                },
            ),
            audio = ChatAudio(ContextWrapper(null), cacheDirectory),
            imageDecoder = decoder,
            io = dispatcher,
        )
    }

    @Test
    fun aPhotoFromTheServerIsDownloadedWithTheSession() = runTest(dispatcher) {
        val downloads = Downloads()
        val model = model(downloads)
        val url = URI("https://api.test/v1/entries/souvenir-a/media")

        model.loadImage(url)
        until("l'image arrive") { model.image(url).value != null }

        assertEquals(listOf(url), downloads.urls, "Par le transport, donc avec la session.")

        // Réduite au décodage : le fil ne garde pas les pixels d'une photo de
        // téléphone pour une vignette.
        val image = assertNotNull(model.image(url).value)
        assertTrue(maxOf(image.width, image.height) <= ChatImage.maximumPixelSize)

        // Une seconde demande ne retélécharge pas.
        model.loadImage(url)
        delay(50)
        assertEquals(1, downloads.urls.size)
    }

    @Test
    fun aPhotoJustChosenIsReadFromTheDisk() = runTest(dispatcher) {
        val downloads = Downloads()
        val model = model(downloads)
        val file = File(cacheDirectory, "photo-${System.nanoTime()}.png").apply { writeBytes(picture) }

        model.loadImage(file.toURI())
        until("l'image arrive") { model.image(file.toURI()).value != null }

        assertTrue(downloads.urls.isEmpty(), "Rien ne part au serveur pour une photo sur le disque.")
    }

    @Test
    fun somethingThatIsNotAnImageIsNotKept() = runTest(dispatcher) {
        val downloads = Downloads()
        val model = model(downloads)
        val file = File(cacheDirectory, "rien-${System.nanoTime()}.png").apply { writeBytes("pas une image".toByteArray()) }

        model.loadImage(file.toURI())
        delay(200)
        assertNull(model.image(file.toURI()).value, "La bulle garde sa trame.")
    }

    /**
     * La règle de taille du décodeur de l'app : `BitmapFactory` réduit par
     * puissances de deux sans descendre sous le maximum, la mise à l'échelle
     * finale ramène le plus grand côté au maximum, et rien ne s'agrandit.
     */
    @Test
    fun theDecodedSizeNeverExceedsTheMaximum() {
        assertEquals(1, ChatImage.sampleSize(2_000, 1_500, maximumPixelSize = 1_024))
        assertEquals(2, ChatImage.sampleSize(4_032, 3_024, maximumPixelSize = 1_024))
        assertEquals(1_024 to 768, ChatImage.fittedSize(2_000, 1_500, maximumPixelSize = 1_024))
        assertEquals(768 to 1_024, ChatImage.fittedSize(1_008, 1_344, maximumPixelSize = 1_024))
        assertEquals(800 to 600, ChatImage.fittedSize(800, 600, maximumPixelSize = 1_024), "Une petite image garde sa taille.")
    }
}

/** Une image qui n'a que sa taille — de quoi la mesurer, sans pixels Android derrière. */
private class TestImageBitmap(override val width: Int, override val height: Int) : ImageBitmap {
    override val colorSpace: ColorSpace get() = ColorSpaces.Srgb
    override val hasAlpha: Boolean get() = false
    override val config: ImageBitmapConfig get() = ImageBitmapConfig.Argb8888

    override fun prepareToDraw() = Unit

    override fun readPixels(buffer: IntArray, startX: Int, startY: Int, width: Int, height: Int, bufferOffset: Int, stride: Int) = Unit
}
