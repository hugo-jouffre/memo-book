package com.memobook.feature.chat

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.ByteArrayInputStream
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * La case d'une image du fil : vide tant qu'elle charge. Observée **seule** —
 * voir `ChatModel.image(url)`. Jumeau de `ChatImageSlot` (`ChatImage.swift`).
 */
class ChatImageSlot {
    internal val mutableImage = MutableStateFlow<ImageBitmap?>(null)

    val image: StateFlow<ImageBitmap?> = mutableImage.asStateFlow()
}

/**
 * Ce qui décode les octets d'une image du fil. [ChatImage.android] dans l'app ;
 * un test sur la JVM passe le sien — `BitmapFactory` n'y tourne pas.
 */
fun interface ChatImageDecoder {
    /** L'image réduite à [maximumPixelSize] sur son plus grand côté, ou `null` si les octets ne sont pas une image. */
    fun decode(data: ByteArray, maximumPixelSize: Int): ImageBitmap?
}

/**
 * Une image du fil, décodée **à la taille où elle se montre**. Jumeau de
 * `ChatImage.swift`.
 *
 * Une photo de téléphone pèse plusieurs mégaoctets et décode en dizaines de
 * mégaoctets de pixels ; la bulle en montre une vignette de 180 dp. On la
 * réduit donc en la décodant — `inSampleSize` de `BitmapFactory`, sans passer
 * par l'image entière, le `CGImageSourceCreateThumbnailAtIndex` d'iOS —, hors
 * du fil principal : un fil de vingt photos ne doit ni ramer ni se faire tuer
 * pour mémoire.
 */
object ChatImage {
    /**
     * Le plus grand côté gardé, en pixels : trois fois la plus grande vignette
     * du fil, arrondi.
     */
    const val maximumPixelSize = 1_024

    /**
     * Le plus grand côté d'une photo **ouverte en plein écran** : de quoi
     * remplir un grand téléphone et zoomer d'un cran sans flou.
     */
    const val fullScreenPixelSize = 2_800

    /** Le décodeur de l'app : `BitmapFactory`, l'orientation EXIF appliquée. */
    val android: ChatImageDecoder = ChatImageDecoder { data, maximumPixelSize -> thumbnail(data, maximumPixelSize) }

    /**
     * Le pas d'échantillonnage du décodage : la plus grande puissance de deux
     * qui laisse encore au moins [maximumPixelSize] pixels sur le plus grand
     * côté — `BitmapFactory` ne sait réduire que par deux, la mise à l'échelle
     * finale ([fittedSize]) fait le reste sans perdre de netteté.
     */
    fun sampleSize(width: Int, height: Int, maximumPixelSize: Int): Int {
        val longest = max(width, height)
        var sample = 1
        while (longest / (sample * 2) >= maximumPixelSize) sample *= 2
        return sample
    }

    /** La taille finale : le plus grand côté ramené à [maximumPixelSize], jamais agrandi. */
    fun fittedSize(width: Int, height: Int, maximumPixelSize: Int): Pair<Int, Int> {
        val longest = max(width, height)
        if (longest <= maximumPixelSize || longest <= 0) return width to height
        val scale = maximumPixelSize.toDouble() / longest
        return max(1, (width * scale).roundToInt()) to max(1, (height * scale).roundToInt())
    }

    /** L'image réduite, ou `null` si les octets ne sont pas une image. */
    fun thumbnail(data: ByteArray, maximumPixelSize: Int = ChatImage.maximumPixelSize): ImageBitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight, maximumPixelSize)
        }
        val decoded = BitmapFactory.decodeByteArray(data, 0, data.size, options) ?: return null
        val (width, height) = fittedSize(decoded.width, decoded.height, maximumPixelSize)
        val scaled = if (width != decoded.width || height != decoded.height) {
            Bitmap.createScaledBitmap(decoded, width, height, true)
        } else {
            decoded
        }
        // L'orientation EXIF appliquée : une photo prise en portrait ne doit
        // pas se coucher dans la bulle.
        return scaled.upright(orientation(data)).asImageBitmap()
    }

    private fun orientation(data: ByteArray): Int =
        runCatching {
            ExifInterface(ByteArrayInputStream(data)).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)

    private fun Bitmap.upright(orientation: Int): Bitmap {
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> matrix.apply { postRotate(90f); postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_TRANSVERSE -> matrix.apply { postRotate(270f); postScale(-1f, 1f) }
            else -> return this
        }
        return Bitmap.createBitmap(this, 0, 0, width, height, matrix, true)
    }
}
