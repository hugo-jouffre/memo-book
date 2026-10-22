package com.memobook.recording

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaRecorder
import android.os.Build
import android.os.SystemClock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File
import java.io.IOException
import java.time.Instant
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min

/**
 * Ce qui a empêché d'enregistrer, dit à l'utilisateur. Jumeau de
 * `RecordingError` (`AudioRecorder.swift`), aux mêmes cas.
 */
sealed class RecordingError(override val message: String, cause: Throwable? = null) : Exception(message, cause) {
    /** Les « Réglages » d'iOS sont ici les Paramètres du téléphone. */
    data object PermissionDenied : RecordingError(
        "MemoBook a besoin du micro pour enregistrer tes souvenirs. Autorise l’accès dans les Paramètres du téléphone.",
    )

    class SessionUnavailable(cause: Throwable?) : RecordingError("Le micro est occupé par une autre application.", cause)

    class RecorderUnavailable(cause: Throwable?) : RecordingError("L’enregistrement n’a pas pu démarrer.", cause)

    data object EmptyRecording : RecordingError("L’enregistrement est vide, réessaie.")
}

/**
 * Capture d'un vocal. Jumeau de `AudioRecorder.swift`.
 *
 * **Le même fichier que l'iPhone** ([VoiceNoteFormat]) : `MediaRecorder` en
 * MPEG-4 + AAC, 44,1 kHz, mono — lu tel quel par l'API de transcription, et
 * bien plus léger qu'un WAV pour l'envoi en itinérance.
 *
 * Confiné au fil principal, comme son jumeau l'est au `MainActor` : son état
 * alimente directement l'interface. Il se lit dans [state] ; les raccourcis
 * ([isRecording], [level]…) en lisent la dernière valeur.
 *
 * @param context de quoi ouvrir le micro et écrire le fichier temporaire.
 * @param requestPermission la demande d'accès au micro, posée par l'écran —
 *   sur Android, seule une activité sait la présenter (voir
 *   [RecordingPermission.request]). Rend `true` si l'app peut enregistrer.
 */
class AudioRecorder(
    private val context: Context,
    private val requestPermission: suspend () -> Boolean = { RecordingPermission.current(context) == RecordingPermission.State.Granted },
) {
    /** L'état observé — les `@Observable` de la classe Swift, réunis. */
    data class State(
        /**
         * Un enregistrement est **ouvert** : il tourne, ou il est en pause. Ce
         * n'est pas la même chose que « le micro capte » — voir [isCapturing].
         */
        val isRecording: Boolean = false,
        /**
         * L'enregistrement est ouvert mais suspendu. Le fichier est conservé, la
         * reprise écrit à la suite.
         */
        val isPaused: Boolean = false,
        /** Niveau normalisé entre 0 et 1, pour la waveform. */
        val level: Double = 0.0,
        /** Ce que le fichier contient déjà, en secondes, pauses déduites — voir [elapsed]. */
        val elapsed: Double = 0.0,
    ) {
        /** Le micro capte en ce moment : ni arrêté, ni en pause. C'est ce que l'interface anime. */
        val isCapturing: Boolean get() = isRecording && !isPaused
    }

    private val mutableState = MutableStateFlow(State())
    val state: StateFlow<State> = mutableState.asStateFlow()

    val isRecording: Boolean get() = state.value.isRecording
    val isPaused: Boolean get() = state.value.isPaused
    val level: Double get() = state.value.level

    /**
     * Ce que le **fichier** contient déjà, en secondes, pauses déduites.
     *
     * Sur iOS, lu sur `AVAudioRecorder.currentTime` (03/10/2026) : le crédit du
     * jour se compte sur ce chiffre pendant qu'on parle, et le serveur relit la
     * durée dans le fichier. `MediaRecorder` ne dit pas le temps de son
     * fichier : on le compte au chronomètre monotone, **seulement pendant que
     * le micro capte** — les pauses n'y entrent pas, et le serveur tranche de
     * toute façon sur le fichier.
     */
    val elapsed: Double get() = state.value.elapsed

    /** [elapsed] en millisecondes — l'unité du crédit du jour. */
    val elapsedMilliseconds: Int get() = (elapsed * 1000).toInt()

    /** Le micro capte en ce moment : ni arrêté, ni en pause. */
    val isCapturing: Boolean get() = state.value.isCapturing

    private var recorder: MediaRecorder? = null
    private var file: File? = null

    /** Le jour raconté : l'instant où l'enregistrement s'est ouvert. */
    private var openedAt: Instant? = null

    /** Le temps capté avant la reprise en cours, en millisecondes. */
    private var capturedBeforeMs = 0L

    /** L'instant (chronomètre monotone) de la dernière reprise, `null` en pause. */
    private var runningSinceMs: Long? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var meterJob: Job? = null

    private val audioManager: AudioManager? get() = context.getSystemService(AudioManager::class.java)
    private var focusRequest: AudioFocusRequest? = null

    suspend fun start() {
        if (isRecording) return
        if (!requestPermission()) throw RecordingError.PermissionDenied

        // Le `.duckOthers` de la session iOS : la musique baisse pendant qu'on
        // parle. Refusé — un appel en cours —, le micro n'est pas à nous.
        if (!requestFocus()) throw RecordingError.SessionUnavailable(null)

        val output = File(context.cacheDir, VoiceNoteFormat.fileName())
        val recorder = try {
            newRecorder().apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioSamplingRate(VoiceNoteFormat.SAMPLE_RATE_HZ)
                setAudioChannels(VoiceNoteFormat.CHANNELS)
                // `AVAudioQuality.high` d'iOS, pour une voix mono.
                setAudioEncodingBitRate(ENCODING_BIT_RATE)
                setOutputFile(output.absolutePath)
                prepare()
                start()
            }
        } catch (error: IOException) {
            abandonFocus()
            output.delete()
            throw RecordingError.RecorderUnavailable(error)
        } catch (error: RuntimeException) {
            abandonFocus()
            output.delete()
            throw RecordingError.RecorderUnavailable(error)
        }

        this.recorder = recorder
        file = output
        openedAt = Instant.now()
        capturedBeforeMs = 0
        runningSinceMs = SystemClock.elapsedRealtime()
        mutableState.value = State(isRecording = true)
        startMetering()
    }

    /**
     * Suspend la capture sans rien perdre : le fichier reste ouvert et
     * [resume] écrit à la suite. C'est le geste du bouton « pause » de la
     * feuille d'enregistrement — on reprend son souffle, on ne s'arrête pas.
     */
    fun pause() {
        if (!isRecording || isPaused) return

        // Le temps relevé **avant** la pause : c'est lui que la barre affiche
        // pendant qu'elle dure, et la reprise repart de là.
        refreshElapsed()
        capturedBeforeMs = currentCapturedMs()
        runningSinceMs = null
        runCatching { recorder?.pause() }
        stopMetering()
        // Le niveau retombe : une waveform figée à mi-hauteur laisserait croire
        // que le micro entend encore quelque chose.
        mutableState.update { it.copy(isPaused = true, level = 0.0) }
    }

    fun resume() {
        if (!isRecording || !isPaused) return

        runCatching { recorder?.resume() }
        runningSinceMs = SystemClock.elapsedRealtime()
        mutableState.update { it.copy(isPaused = false) }
        startMetering()
    }

    /** Le temps capté jusqu'ici, pauses déduites. */
    private fun currentCapturedMs(): Long =
        capturedBeforeMs + (runningSinceMs?.let { SystemClock.elapsedRealtime() - it } ?: 0L)

    /**
     * Relève le temps capté. Il ne recule jamais : en pause ou arrêté, on garde
     * le dernier relevé, qui ne bouge pas plus que le fichier.
     */
    private fun refreshElapsed() {
        if (recorder == null) return
        val seconds = currentCapturedMs() / 1000.0
        mutableState.update { it.copy(elapsed = max(it.elapsed, seconds)) }
    }

    /** Arrête et renvoie le vocal. `null` si aucun enregistrement n'était en cours. */
    fun stop(): RecordedAudio? {
        val recorder = recorder ?: return null
        val output = file ?: return null
        val openedAt = openedAt ?: return null

        refreshElapsed()
        val duration = elapsed

        // `stop()` lève quand rien n'a été écrit — un arrêt dans la seconde du
        // départ : c'est un enregistrement vide, pas une panne.
        val stopped = runCatching { recorder.stop() }.isSuccess
        recorder.release()
        stopMetering()

        this.recorder = null
        file = null
        this.openedAt = null
        runningSinceMs = null
        capturedBeforeMs = 0
        mutableState.update { it.copy(isRecording = false, isPaused = false, level = 0.0) }

        // On rend la main aux autres apps audio ; un échec ici n'invalide pas
        // l'enregistrement déjà capturé.
        abandonFocus()

        try {
            val data = if (stopped && output.exists()) output.readBytes() else ByteArray(0)
            if (data.isEmpty()) throw RecordingError.EmptyRecording
            return RecordedAudio(
                data = data,
                filename = output.name,
                mimeType = VoiceNoteFormat.MIME_TYPE,
                // La durée **captée**, pauses déduites : c'est elle que le
                // serveur retrouvera, à peu de chose près, en relisant le fichier.
                duration = duration,
                recordedAt = openedAt,
            )
        } finally {
            output.delete()
        }
    }

    /** Abandonne l'enregistrement en cours sans rien conserver. */
    fun cancel() {
        recorder?.let { runCatching { it.stop() }; it.release() }
        stopMetering()
        file?.delete()
        recorder = null
        file = null
        openedAt = null
        runningSinceMs = null
        capturedBeforeMs = 0
        mutableState.value = State()
        abandonFocus()
    }

    private fun startMetering() {
        meterJob?.cancel()
        meterJob = scope.launch {
            while (isActive) {
                delay(METER_INTERVAL_MS)
                val recorder = recorder ?: return@launch
                // `maxAmplitude` est le **pic** depuis le relevé précédent, de 0
                // à 32 767 — iOS lit une puissance moyenne. Ramené en décibels,
                // il passe par la même échelle que sur l'iPhone.
                val amplitude = runCatching { recorder.maxAmplitude }.getOrDefault(0)
                mutableState.update { it.copy(level = normalize(decibels = decibels(amplitude))) }
                refreshElapsed()
            }
        }
    }

    private fun stopMetering() {
        meterJob?.cancel()
        meterJob = null
    }

    private fun newRecorder(): MediaRecorder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(context) else @Suppress("DEPRECATION") MediaRecorder()

    private fun requestFocus(): Boolean {
        val manager = audioManager ?: return true
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            .build()
        focusRequest = request
        return manager.requestAudioFocus(request) != AudioManager.AUDIOFOCUS_REQUEST_FAILED
    }

    private fun abandonFocus() {
        val request = focusRequest ?: return
        audioManager?.abandonAudioFocusRequest(request)
        focusRequest = null
    }

    companion object {
        /** Le niveau est relevé toutes les 50 ms, comme sur iOS. */
        private const val METER_INTERVAL_MS = 50L

        /** 128 kbit/s : la « haute » qualité d'iOS, pour une voix mono. */
        private const val ENCODING_BIT_RATE = 128_000

        /** Le pic de `maxAmplitude`, ramené en décibels de pleine échelle. */
        internal fun decibels(amplitude: Int): Float =
            if (amplitude <= 0) Float.NEGATIVE_INFINITY else 20f * log10(amplitude / 32_767f)

        /**
         * De -160 dB (silence) à 0 dB (saturation). En dessous de -50 dB il n'y
         * a rien d'audible : on écrase cette plage pour que la waveform réagisse
         * à la voix, pas au bruit de fond.
         *
         * Une fonction pure, que [VoiceLevels] appelle aussi en relisant un fichier.
         */
        fun normalize(decibels: Float): Double {
            val floor = -50f
            if (!decibels.isFinite()) return 0.0
            if (decibels <= floor) return 0.0
            return min((decibels - floor) / -floor, 1f).toDouble()
        }
    }
}
