package com.memobook.feature.recording

import com.memobook.recording.RecordedAudio
import java.util.UUID

/**
 * Le vocal enregistré depuis l'accueil, le temps d'ouvrir la conversation qui
 * va le montrer. Jumeau de `RecordingHandoff.swift`.
 *
 * Il ne survit pas à la fermeture de celle-ci : `RootView` le jette quand la
 * conversation quitte la pile — rouvrir un fil ne doit pas y reposer un vocal
 * déjà posé.
 *
 * @property id l'identifiant de la bulle — et du tour qui part par la file.
 * @property levels la forme d'onde mesurée pendant l'enregistrement, pour que
 *   la bulle ne la recalcule pas.
 * @property stoppedAtLimit l'enregistrement s'est arrêté sur le crédit du jour.
 */
data class RecordingHandoff(
    val id: String = UUID.randomUUID().toString().lowercase(),
    val audio: RecordedAudio,
    val levels: List<Double>,
    val stoppedAtLimit: Boolean = false,
)
