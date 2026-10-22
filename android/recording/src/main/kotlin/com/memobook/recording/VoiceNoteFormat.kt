package com.memobook.recording

import java.util.UUID

/**
 * Le fichier d'un vocal, tel que le serveur l'attend — **le même** que celui de
 * l'iPhone (`AudioRecorder.swift`) : AAC dans un conteneur MPEG-4, 44,1 kHz,
 * mono, `memo-<UUID>.m4a`, envoyé en `audio/mp4`.
 *
 * Le serveur relit la durée dans le conteneur, et c'est elle qui fait descendre
 * le crédit du jour : un autre format changerait ce qu'il mesure. Sur Android,
 * `MediaRecorder` en `MPEG_4` + `AAC` produit ce fichier.
 */
object VoiceNoteFormat {
    const val SAMPLE_RATE_HZ = 44_100
    const val CHANNELS = 1
    const val MIME_TYPE = "audio/mp4"
    const val EXTENSION = "m4a"

    /** `memo-<UUID>.m4a`, l'UUID en majuscules comme `UUID().uuidString` côté iOS. */
    fun fileName(id: UUID = UUID.randomUUID()): String = "memo-${id.toString().uppercase()}.$EXTENSION"
}
