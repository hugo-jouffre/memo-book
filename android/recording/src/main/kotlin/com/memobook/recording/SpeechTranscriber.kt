package com.memobook.recording

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.Locale

/**
 * La transcription **en direct** de ce qu'on est en train de dire. Jumeau de
 * `SpeechTranscriber.swift` — **qui ne transcrit rien sur Android**.
 *
 * Elle n'est pas la transcription du carnet : celle-là est faite par le
 * serveur, sur le fichier complet, et c'est elle qui fait foi. Celle-ci est un
 * **retour visuel** — les mots qui s'écrivent pendant qu'on parle. Et **elle a
 * le droit de ne pas marcher** : l'enregistrement continue sans elle.
 *
 * ### La décision (A5c, 22/10/2026) : la forme d'onde seule, sur tous les Android
 *
 * Le risque « Un micro, deux écoutes » de `docs/android.md` : sur iOS, la
 * reconnaissance lit l'entrée de la session audio que l'enregistreur partage.
 * Le `SpeechRecognizer` d'Android **ouvre le micro lui-même**, et
 * `MediaRecorder` le tient déjà : avant Android 13, les deux se disputent
 * l'entrée, et c'est le vocal — le cœur du produit — qui risque d'être coupé.
 * Des trois choix posés à Clara (`docs/android-reprise.md`), le recommandé pour
 * le 6/11 : **la forme d'onde seule partout**. Le texte du serveur arrive comme
 * aujourd'hui, sur la bulle du vocal.
 *
 * C'est aussi ce que fait l'iPhone depuis le 29/09/2026 : la feuille
 * d'enregistrement n'y branche plus ce transcripteur (T176, voir
 * `RecordingModel`). Le type reste, avec son interface, pour que l'écran qui
 * voudra un jour l'afficher compile sans attendre.
 *
 * ### Pour passer à l'option 2 — la transcription sur Android 13+
 *
 * 1. **Un seul lecteur du micro** : enregistrer par `AudioRecord` (PCM 16 bits,
 *    44,1 kHz, mono) au lieu de `MediaRecorder`, et encoder soi-même en AAC par
 *    `MediaCodec` + `MediaMuxer` (MPEG-4) — le fichier doit rester celui de
 *    [VoiceNoteFormat], le serveur y relit la durée qui décompte le crédit.
 * 2. **Nourrir la reconnaissance du même flux** : sur Android 13+
 *    (`Build.VERSION_CODES.TIRAMISU`), `RecognizerIntent.EXTRA_AUDIO_SOURCE`
 *    reçoit un `ParcelFileDescriptor` (un tube, `createPipe()`) dans lequel on
 *    recopie chaque tampon PCM, avec `EXTRA_AUDIO_SOURCE_CHANNEL_COUNT`,
 *    `EXTRA_AUDIO_SOURCE_ENCODING` (`ENCODING_PCM_16BIT`) et
 *    `EXTRA_AUDIO_SOURCE_SAMPLING_RATE`.
 * 3. **Sur l'appareil d'abord** : `SpeechRecognizer.createOnDeviceSpeechRecognizer`
 *    (Android 12+), `fr-FR` (`EXTRA_LANGUAGE`), les hypothèses partielles
 *    (`EXTRA_PARTIAL_RESULTS`) — ce sont elles qu'on affiche. Sans modèle
 *    français installé, une seule seconde chance par le moteur en ligne, comme
 *    sur iOS (`hasFallenBackToServer`).
 * 4. **En dessous d'Android 13**, cette classe-ci : la forme d'onde seule.
 * 5. Rebrancher [transcript] sous la frise de la feuille, et vérifier sur deux
 *    téléphones réels qu'un vocal de cinq minutes arrive entier au serveur.
 *
 * @param locale la langue attendue — le français, et non celle du téléphone :
 *   quelqu'un dont le téléphone est en anglais raconte quand même en français.
 */
class SpeechTranscriber(@Suppress("unused") private val locale: Locale = Locale.FRANCE) {
    private val mutableTranscript = MutableStateFlow("")

    /** Ce qui a été reconnu depuis le début de l'enregistrement. Toujours vide ici. */
    val transcript: StateFlow<String> = mutableTranscript.asStateFlow()

    private val mutableIsTranscribing = MutableStateFlow(false)

    /**
     * La reconnaissance tourne vraiment. **Toujours faux ici** : l'interface s'en
     * sert pour ne pas réserver la place d'un texte qui ne viendra jamais.
     */
    val isTranscribing: StateFlow<Boolean> = mutableIsTranscribing.asStateFlow()

    /**
     * Démarre la reconnaissance. Ne lève rien, et ne fait rien : voir la
     * décision en tête du fichier. À appeler, le jour venu, **après**
     * [AudioRecorder.start].
     */
    suspend fun start() = Unit

    /** Arrête la reconnaissance et garde le texte obtenu. */
    fun stop() {
        mutableIsTranscribing.value = false
    }

    /** Repart de zéro : plus de texte, plus de moteur. */
    fun reset() {
        stop()
        mutableTranscript.value = ""
    }

    companion object {
        /**
         * L'autorisation de reconnaissance vocale. Sur Android, elle n'existe
         * pas à part du micro ([RecordingPermission]) : rien à demander tant que
         * rien n'est reconnu.
         */
        suspend fun requestAuthorization(): Boolean = false
    }
}
