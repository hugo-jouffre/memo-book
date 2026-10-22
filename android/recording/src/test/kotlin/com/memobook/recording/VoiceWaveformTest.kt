package com.memobook.recording

import java.io.File
import java.util.UUID
import kotlin.math.PI
import kotlin.math.sin
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * La forme d'onde d'un vocal arrivé **sans relevé** : relue dans son fichier
 * (Hugo, 30/09/2026 — les vocaux des voyages passés n'avaient plus qu'une
 * ligne plate). Porté de `VoiceWaveformTests.swift`.
 *
 * Sur iOS, le test fabrique un vrai fichier AAC et le relit. Ici, la JVM n'a
 * pas de décodeur : la mesure se vérifie sur les échantillons que le décodeur
 * rendrait — une seconde de silence, puis une seconde de la à mi-volume, à
 * 44,1 kHz. Le décodage lui-même (`MediaExtractor`, `MediaCodec`) se vérifie
 * sur un téléphone. Le troisième cas — le fil qui descend le fichier d'un
 * vocal sans niveaux — se portera avec `ChatModel`.
 */
class VoiceWaveformTest {
    /** Une seconde de silence, puis une seconde de la à mi-volume. */
    private fun voiceSamples(): FloatArray {
        val rate = VoiceNoteFormat.SAMPLE_RATE_HZ
        return FloatArray(rate * 2) { index ->
            if (index < rate) 0f else (0.5 * sin(2 * PI * 440 * index / rate)).toFloat()
        }
    }

    @Test
    fun theLevelsAreReadBackOnTheMicrophoneScale() {
        val levels = VoiceLevels.levels(voiceSamples(), VoiceNoteFormat.SAMPLE_RATE_HZ)

        // Une valeur tous les 90 ms, comme en direct : deux secondes en font
        // vingt-deux, à la dernière tranche près.
        assertTrue(levels.size in 20..26, "${levels.size} niveaux")

        val half = levels.size / 2
        val silence = levels.subList(2, half - 2)
        val voice = levels.subList(half + 2, levels.size - 1)
        assertEquals(0.0, silence.max(), 0.05, "Le silence reste au plancher.")
        assertTrue(voice.min() > 0.6, "Le son se lit comme une voix.")
    }

    @Test
    fun anUnreadableFileGivesNoLevels() {
        val file = File(System.getProperty("java.io.tmpdir"), "rien-${UUID.randomUUID()}.m4a")
        file.writeText("pas un son")

        val levels = VoiceLevels.measure(file)
        assertTrue(levels.isEmpty(), "La bulle garde sa ligne plate plutôt qu'une onde inventée.")
    }

    /** L'échelle du micro : sous -50 dB, rien ; 0 dB, tout ; un silence numérique, rien. */
    @Test
    fun theMicrophoneScaleIgnoresTheBackgroundNoise() {
        assertEquals(0.0, AudioRecorder.normalize(decibels = -160f))
        assertEquals(0.0, AudioRecorder.normalize(decibels = -50f))
        assertEquals(0.5, AudioRecorder.normalize(decibels = -25f), 1e-9)
        assertEquals(1.0, AudioRecorder.normalize(decibels = 0f))
        assertEquals(0.0, AudioRecorder.normalize(decibels = Float.NEGATIVE_INFINITY))
        assertEquals(1.0, AudioRecorder.normalize(decibels = AudioRecorder.decibels(32_767)), 1e-6)
    }
}
