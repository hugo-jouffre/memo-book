package com.memobook.recording

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.Locale

/**
 * La lecture à voix haute d'un message. Jumeau de `SpeechReader.swift`.
 *
 * C'est le haut-parleur que la maquette pose à côté de chaque bulle de MEMO.
 * Il ne remplace pas TalkBack et ne lui parle pas : c'est une commande de
 * **confort**, pour écouter ce que MEMO a écrit en gardant les yeux sur la
 * route — et c'est exactement l'usage d'une app de voyage.
 *
 * Confiné au fil principal, comme les deux autres objets audio du module : son
 * état alimente directement le bouton qui le pilote. La fin de la lecture
 * arrive par `UtteranceProgressListener` — Android a le délégué qu'iOS ne
 * pouvait pas prendre —, rappelé sur un fil du moteur et ramené ici.
 *
 * Le moteur `TextToSpeech` s'ouvre à la construction et se ferme par
 * [shutdown] : l'écran qui le tient l'appelle en partant.
 */
class SpeechReader(context: Context) {
    private val mutableReadingId = MutableStateFlow<String?>(null)

    /** L'identifiant du message en cours de lecture, `null` si rien ne parle. */
    val readingId: StateFlow<String?> = mutableReadingId.asStateFlow()

    private val main = Handler(Looper.getMainLooper())
    private val audioManager = context.getSystemService(AudioManager::class.java)
    private var focusRequest: AudioFocusRequest? = null

    /** Le moteur est prêt. Une lecture demandée avant attend ici. */
    private var isReady = false
    private var waiting: Pair<String, String>? = null

    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    private val engine: TextToSpeech = TextToSpeech(context.applicationContext) { status ->
        main.post { engineDidStart(status == TextToSpeech.SUCCESS) }
    }

    fun isReading(id: String): Boolean = readingId.value == id

    /**
     * Lit le texte, ou s'arrête s'il est déjà en train d'être lu.
     *
     * La voix suit la langue de l'app et non celle du système : MemoBook parle
     * français, et un texte français lu par une voix anglaise est
     * incompréhensible.
     */
    fun toggle(id: String, text: String) {
        if (readingId.value == id) {
            stop()
            return
        }

        stop()

        // `.duckOthers` : la lecture baisse la musique au lieu de la couper, et
        // la rend intacte en s'arrêtant.
        if (audioManager != null) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(attributes)
                .build()
            audioManager.requestAudioFocus(request)
            focusRequest = request
        }

        mutableReadingId.value = id
        if (isReady) speak(id, text) else waiting = id to text
    }

    fun stop() {
        waiting = null
        if (isReady) engine.stop()
        mutableReadingId.value = null
        focusRequest?.let { audioManager?.abandonAudioFocusRequest(it) }
        focusRequest = null
    }

    /** Ferme le moteur. Le lecteur ne sert plus après. */
    fun shutdown() {
        stop()
        engine.shutdown()
    }

    private fun speak(id: String, text: String) {
        engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, id)
    }

    private fun engineDidStart(succeeded: Boolean) {
        if (!succeeded) {
            // Pas de moteur : le bouton s'éteint, rien d'autre ne casse.
            waiting = null
            mutableReadingId.value = null
            return
        }
        engine.language = Locale.FRANCE
        engine.setAudioAttributes(attributes)
        engine.setOnUtteranceProgressListener(
            object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) = Unit

                override fun onDone(utteranceId: String?) {
                    main.post { finished(utteranceId) }
                }

                @Deprecated("Remplacé par la variante à code d'erreur, toujours appelée par les anciens moteurs.")
                override fun onError(utteranceId: String?) {
                    main.post { finished(utteranceId) }
                }

                override fun onError(utteranceId: String?, errorCode: Int) {
                    main.post { finished(utteranceId) }
                }
            },
        )
        isReady = true
        waiting?.let { (id, text) -> speak(id, text) }
        waiting = null
    }

    /** La lecture de ce message est finie : on n'éteint que s'il est encore celui qu'on lit. */
    private fun finished(utteranceId: String?) {
        if (utteranceId != null && utteranceId == readingId.value) stop()
    }
}
