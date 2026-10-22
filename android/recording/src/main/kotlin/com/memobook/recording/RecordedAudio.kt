package com.memobook.recording

import java.time.Instant

/**
 * Un vocal enregistré, prêt à partir. Jumeau de `RecordedAudio`
 * (`AudioRecorder.swift`) : le fichier entier en mémoire, son nom
 * (`memo-<UUID>.m4a`, voir [VoiceNoteFormat]), son type et sa durée.
 *
 * Une classe et non une `data class` : l'égalité d'un tableau d'octets serait
 * celle de sa référence. Deux vocaux sont le même quand ils portent le même
 * fichier — son nom contient l'UUID tiré à l'enregistrement.
 */
class RecordedAudio(
    val data: ByteArray,
    val filename: String,
    val mimeType: String = VoiceNoteFormat.MIME_TYPE,
    /** En secondes, comme le `TimeInterval` d'iOS. */
    val duration: Double,
    val recordedAt: Instant,
) {
    override fun equals(other: Any?): Boolean =
        other is RecordedAudio && other.filename == filename && other.data.size == data.size && other.recordedAt == recordedAt

    override fun hashCode(): Int = filename.hashCode()

    override fun toString(): String = "RecordedAudio($filename, ${data.size} octets, ${duration}s)"
}
