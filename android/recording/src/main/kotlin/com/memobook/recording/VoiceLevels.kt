package com.memobook.recording

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.ByteOrder
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * La forme d'onde d'un vocal, **relue dans son fichier**. Jumeau de
 * `VoiceLevels.swift`.
 *
 * Les niveaux se relèvent d'ordinaire pendant l'enregistrement
 * ([AudioRecorder.level], échantillonné par l'écran). Mais tous les vocaux
 * n'en ont pas : ceux d'avant que le serveur les garde, ceux que la file
 * renvoie sans eux, ceux d'un co-voyageur enregistrés ailleurs. Leur bulle
 * dessinait alors une ligne plate, et on ne voyait plus la voix (Hugo,
 * 30/09/2026). Le fichier, lui, a tout : on le relit.
 *
 * **La même échelle que le micro** : une valeur tous les 90 ms, la puissance
 * moyenne de la tranche en décibels, ramenée de 0 à 1 par
 * [AudioRecorder.normalize]. Une onde relue et une onde relevée en direct se
 * ressemblent donc, et c'est `BrandWaveform` qui les ramène à la largeur de la
 * bulle.
 *
 * Sur Android, le fichier AAC se décode par `MediaExtractor` et `MediaCodec` ;
 * la mesure elle-même ([Meter]) ne voit que des échantillons, et se teste sur
 * la JVM.
 */
object VoiceLevels {
    /** L'intervalle de l'échantillonnage en direct, repris ici. */
    const val INTERVAL_SECONDS = 0.09

    /**
     * Les niveaux du fichier, lus hors du fil principal. Vide si le fichier ne
     * se lit pas : la bulle garde alors sa ligne plate.
     */
    suspend fun read(file: File): List<Double> = withContext(Dispatchers.IO) { measure(file) }

    internal fun measure(file: File): List<Double> {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(file.absolutePath)
            val track = (0 until extractor.trackCount).firstOrNull { index ->
                extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: return emptyList()
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: return emptyList()
            val decoder = MediaCodec.createDecoderByType(mime)
            codec = decoder
            decoder.configure(format, null, null, 0)
            decoder.start()

            var meter: Meter? = null
            var channels = format.getIntegerOrNull(MediaFormat.KEY_CHANNEL_COUNT) ?: 1
            var sampleRate = format.getIntegerOrNull(MediaFormat.KEY_SAMPLE_RATE) ?: VoiceNoteFormat.SAMPLE_RATE_HZ
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            // Un décodeur qui ne rend plus rien après la fin de l'entrée : on
            // s'arrête au lieu de l'attendre pour toujours.
            var idle = 0

            // Une tranche à la fois, et non le fichier entier : trois minutes de
            // PCM pèsent une trentaine de mégaoctets.
            while (true) {
                if (!inputDone) {
                    val inputIndex = decoder.dequeueInputBuffer(TIMEOUT_US)
                    if (inputIndex >= 0) {
                        val input = decoder.getInputBuffer(inputIndex) ?: return emptyList()
                        val size = extractor.readSampleData(input, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(inputIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(inputIndex, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                val outputIndex = decoder.dequeueOutputBuffer(info, TIMEOUT_US)
                if (outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER && inputDone && ++idle > MAX_IDLE_POLLS) break
                when {
                    outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val output = decoder.outputFormat
                        channels = output.getIntegerOrNull(MediaFormat.KEY_CHANNEL_COUNT) ?: channels
                        sampleRate = output.getIntegerOrNull(MediaFormat.KEY_SAMPLE_RATE) ?: sampleRate
                    }
                    outputIndex >= 0 -> {
                        val buffer = decoder.getOutputBuffer(outputIndex)
                        if (buffer != null && info.size > 0) {
                            val current = meter ?: Meter(sampleRate).also { meter = it }
                            // La vue commence à `info.offset` : le décodeur y a posé
                            // la position du tampon.
                            val pcm = buffer.order(ByteOrder.nativeOrder()).asShortBuffer()
                            val frames = (info.size / 2) / max(1, channels)
                            // Le premier canal, comme `floatChannelData[0]` d'iOS.
                            for (frame in 0 until frames) {
                                current.add(pcm.get(frame * channels) / 32_768f)
                            }
                        }
                        decoder.releaseOutputBuffer(outputIndex, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                    }
                }
            }
            return meter?.finish().orEmpty()
        } catch (_: Exception) {
            return emptyList()
        } finally {
            runCatching { codec?.stop() }
            runCatching { codec?.release() }
            extractor.release()
        }
    }

    /**
     * Les niveaux d'une suite d'échantillons, de -1 à 1 — la même règle que
     * `VoiceLevels.measure` d'iOS : la moyenne quadratique de chaque tranche de
     * 90 ms, en décibels, puis l'échelle du micro.
     */
    fun levels(samples: FloatArray, sampleRate: Int): List<Double> {
        val meter = Meter(sampleRate)
        samples.forEach(meter::add)
        return meter.finish()
    }

    /** La mesure au fil des échantillons, une tranche à la fois. */
    internal class Meter(sampleRate: Int) {
        private val window = max(1, (sampleRate * INTERVAL_SECONDS).roundToInt())
        private var energy = 0f
        private var count = 0
        private val levels = mutableListOf<Double>()

        fun add(sample: Float) {
            energy += sample * sample
            count += 1
            if (count == window) flush()
        }

        /** La dernière tranche compte, même incomplète — comme le dernier `read` d'iOS. */
        fun finish(): List<Double> {
            if (count > 0) flush()
            return levels.toList()
        }

        private fun flush() {
            val rms = sqrt(energy / count)
            levels += AudioRecorder.normalize(decibels = 20f * log10(max(rms, 1e-7f)))
            energy = 0f
            count = 0
        }
    }

    private const val TIMEOUT_US = 10_000L
    private const val MAX_IDLE_POLLS = 50

    private fun MediaFormat.getIntegerOrNull(key: String): Int? = if (containsKey(key)) getInteger(key) else null
}
