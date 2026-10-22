package com.memobook.recording

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File
import java.io.IOException

/** Ce qui a empêché de lire un vocal. Jumeau de `PlaybackError` (`AudioNotePlayer.swift`). */
sealed class PlaybackError(override val message: String, cause: Throwable? = null) : Exception(message, cause) {
    class SessionUnavailable(cause: Throwable?) : PlaybackError("Le son est occupé par une autre application.", cause)

    class Unreadable(cause: Throwable?) : PlaybackError("Ce vocal ne peut pas être lu.", cause)
}

/**
 * La lecture d'un vocal. Jumeau de `AudioNotePlayer.swift`.
 *
 * **Un seul vocal joue à la fois**, et c'est ce qui justifie un objet partagé
 * plutôt qu'un lecteur par bulle : lancer un vocal doit arrêter le précédent,
 * et une centaine de bulles ne doivent pas tenir une centaine de
 * `MediaPlayer`. La vue demande donc à ce lecteur *qui* joue ([isPlaying]) au
 * lieu de tenir son propre état.
 *
 * L'avancement est lu par une boucle sur le fil principal, comme
 * [AudioRecorder] le fait de son niveau de micro ; la fin du vocal, elle,
 * arrive par `setOnCompletionListener`, qu'Android rappelle sur ce même fil.
 */
class AudioNotePlayer(private val context: Context) {
    data class State(
        /** L'identifiant du vocal en cours, `null` si rien ne joue. */
        val playingId: String? = null,
        /** De 0 à 1 : où en est la lecture. C'est lui que la forme d'onde teinte. */
        val progress: Double = 0.0,
        /** En secondes. */
        val elapsed: Double = 0.0,
    )

    private val mutableState = MutableStateFlow(State())
    val state: StateFlow<State> = mutableState.asStateFlow()

    val playingId: String? get() = state.value.playingId

    private var player: MediaPlayer? = null
    private var ticker: Job? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var focusRequest: AudioFocusRequest? = null

    fun isPlaying(id: String): Boolean = playingId == id

    /**
     * Joue le vocal, ou l'arrête s'il est déjà en train de jouer.
     *
     * Un autre vocal en cours est arrêté sans cérémonie : deux récits qui se
     * parlent par-dessus ne s'écoutent ni l'un ni l'autre.
     */
    fun toggle(id: String, file: File) {
        if (playingId == id) {
            stop()
            return
        }

        stop()

        // Le média et non l'appel : le vocal sort du haut-parleur, pas de
        // l'écouteur d'oreille — la catégorie `.playback` d'iOS.
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
        val manager = context.getSystemService(AudioManager::class.java)
        if (manager != null) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT).setAudioAttributes(attributes).build()
            if (manager.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_FAILED) {
                throw PlaybackError.SessionUnavailable(null)
            }
            focusRequest = request
        }

        val player = MediaPlayer()
        try {
            player.setAudioAttributes(attributes)
            player.setDataSource(file.absolutePath)
            player.prepare()
            player.setOnCompletionListener { stop() }
            player.start()
        } catch (error: IOException) {
            player.release()
            abandonFocus()
            throw PlaybackError.Unreadable(error)
        } catch (error: RuntimeException) {
            player.release()
            abandonFocus()
            throw PlaybackError.Unreadable(error)
        }
        this.player = player

        mutableState.value = State(playingId = id)
        startTicking()
    }

    fun stop() {
        ticker?.cancel()
        ticker = null
        player?.let {
            runCatching { it.stop() }
            it.release()
        }
        player = null
        mutableState.value = State()

        // On rend la main aux autres apps audio ; un échec ici n'a rien à
        // rattraper, la lecture est déjà terminée.
        abandonFocus()
    }

    private fun abandonFocus() {
        val request = focusRequest ?: return
        context.getSystemService(AudioManager::class.java)?.abandonAudioFocusRequest(request)
        focusRequest = null
    }

    /**
     * Trente fois par seconde : assez fin pour que la forme d'onde se remplisse
     * sans saccade, assez lâche pour ne pas peser sur le défilement du fil.
     */
    private fun startTicking() {
        ticker = scope.launch {
            while (isActive) {
                delay(33)
                val player = player ?: return@launch
                val position = runCatching { player.currentPosition }.getOrDefault(0)
                val duration = runCatching { player.duration }.getOrDefault(0)
                mutableState.value = state.value.copy(
                    elapsed = position / 1000.0,
                    progress = if (duration > 0) position.toDouble() / duration else 0.0,
                )
            }
        }
    }
}

/**
 * Où vivent les vocaux le temps qu'on les réécoute. Jumeau de `VoiceNoteFile`
 * (`AudioNotePlayer.swift`).
 *
 * [AudioRecorder.stop] **efface** son fichier temporaire et ne rend que des
 * octets : sans cette étape, un vocal qu'on vient d'enregistrer ne serait plus
 * jouable une seconde après. L'écran qui affiche une bulle vocale doit donc
 * écrire l'audio quelque part, et c'est ici.
 *
 * Dans le **cache** (`cacheDir`) et non dans `filesDir` : un vocal parti vers le
 * serveur n'a plus à être gardé, et le système peut reprendre la place s'il en
 * manque.
 *
 * Une classe sur son dossier et non un objet : Android ne donne le dossier du
 * cache qu'à qui tient un `Context`.
 */
class VoiceNoteFile(cacheDirectory: File) {
    private val directory = File(cacheDirectory, "VoiceNotes")

    /**
     * Le vocal déjà écrit pour cet identifiant, s'il est encore là — Android
     * vide le cache sous pression disque. C'est ce qui évite de retélécharger
     * un vocal à chaque ouverture du fil, pour l'écouter comme pour relire sa
     * forme d'onde ([VoiceLevels]).
     */
    fun existing(id: String): File? = File(directory, "$id.${VoiceNoteFormat.EXTENSION}").takeIf { it.exists() }

    /** Écrit le vocal et rend son fichier. */
    fun save(audio: RecordedAudio, id: String): File {
        directory.mkdirs()
        val file = File(directory, "$id.${VoiceNoteFormat.EXTENSION}")
        val partial = File(directory, "$id.partial")
        partial.writeBytes(audio.data)
        if (!partial.renameTo(file)) {
            partial.delete()
            throw IOException("Le vocal n’a pas pu être écrit.")
        }
        return file
    }

    /**
     * Efface tous les vocaux gardés. À appeler quand une conversation est
     * close : ce qui compte est parti sur le serveur.
     */
    fun removeAll() {
        directory.deleteRecursively()
    }
}
