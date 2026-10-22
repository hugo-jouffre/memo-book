package com.memobook.feature.recording

import com.memobook.core.ChatCopy
import com.memobook.core.DailyCredit
import com.memobook.core.DailyCreditCopy
import com.memobook.feature.chat.DailyCreditBanner
import com.memobook.recording.AudioRecorder
import com.memobook.recording.RecordedAudio
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.Locale

/**
 * Ce que la feuille d'enregistrement sait faire : ouvrir le micro, le
 * suspendre, tout reprendre depuis le début, et rendre le vocal. Jumeau de
 * `RecordingModel.swift`.
 *
 * Il ne tient plus que l'[AudioRecorder] — celui-là même que la conversation
 * emploie, et qui n'a jamais fait tomber l'app. Le `SpeechTranscriber`, qui
 * écrivait les mots à mesure qu'on parlait, **n'est plus branché ici** : c'est
 * lui qui faisait disparaître l'app à l'ouverture de la feuille sur l'iPhone
 * de Hugo (iPhone 13, iOS 18.7.2), et jamais sur le simulateur, où la
 * reconnaissance vocale n'est pas disponible et où il ne démarrait donc pas.
 * Le texte n'était qu'un retour visuel — c'est le vocal qui fait le carnet, et
 * le serveur qui le transcrit (T176). Sur Android, la forme d'onde seule, sur
 * tous les téléphones : voir `SpeechTranscriber.kt`.
 *
 * **Le crédit du jour s'y applique comme dans la conversation** (Hugo,
 * 03/10/2026) : le vocal de l'accueil vise le voyage en cours, et consomme son
 * crédit. Mêmes règles que la barre du chat — le bandeau rouge doux à trente
 * secondes, qui pulse sous cinq, l'arrêt net à zéro (le vocal part), et rien à
 * enregistrer quand le crédit est déjà épuisé.
 *
 * **Pas un `ViewModel`**, et c'est voulu : il vit et meurt avec la feuille,
 * comme le `@State` qui le tient sur iOS. Un `ViewModel` vivrait avec l'écran
 * qui présente la feuille, et rouvrir celle-ci retrouverait la frise du vocal
 * d'avant. [RecordingSheet] le construit et le referme ([close]).
 *
 * @param scope où tournent la frise et le crédit — le fil principal ; un test
 *   passe le sien.
 */
class RecordingModel(
    val recorder: AudioRecorder,
    credit: DailyCredit? = null,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
) {
    /** Un retour haptique que la feuille joue — `UIFeedbackGenerator` d'iOS. */
    enum class Feedback {
        /** `UINotificationFeedbackGenerator().notificationOccurred(.warning)`. */
        Warning,

        /** `UIImpactFeedbackGenerator(style: .light)`. */
        Light,

        /** `UIImpactFeedbackGenerator(style: .medium)`. */
        Medium,
    }

    private val mutableLevels = MutableStateFlow<List<Double>>(emptyList())

    /**
     * Les niveaux relevés depuis le début, pour la frise. On n'en garde que ce
     * qui se voit : la frise n'est pas un historique, et une heure de vocal ne
     * doit pas faire grossir un tableau qu'on ne dessinera jamais.
     */
    val levels: StateFlow<List<Double>> = mutableLevels.asStateFlow()

    private val captured = mutableListOf<Double>()

    /**
     * Le relevé **entier**, lui, sert à la bulle du vocal une fois qu'il est
     * dit : c'est la forme d'onde du souvenir, et elle doit dessiner tout ce
     * qui a été raconté.
     *
     * Deux tableaux et non un seul parce qu'ils ne répondent pas à la même
     * question. [levels] dit « qu'est-ce qui passe sous le micro en ce
     * moment » — les quarante dernières barres, qui défilent. Celui-ci dit
     * « à quoi ressemble ce vocal » — du premier mot au dernier. Réduire le
     * second au premier donnerait à un vocal de deux minutes la silhouette de
     * ses trois dernières secondes.
     */
    val capturedLevels: List<Double> get() = captured.toList()

    private val mutableErrorMessage = MutableStateFlow<String?>(null)

    /**
     * Ce qui a empêché d'enregistrer, dit à l'utilisateur. Le micro refusé,
     * surtout : c'est le seul cas où il y a quelque chose à faire.
     */
    val errorMessage: StateFlow<String?> = mutableErrorMessage.asStateFlow()

    private val mutableIsBusy = MutableStateFlow(false)

    /**
     * Un aller-retour est en cours (démarrage, arrêt) : le bouton ne doit pas
     * être pressé deux fois.
     */
    val isBusy: StateFlow<Boolean> = mutableIsBusy.asStateFlow()

    private var sampler: Job? = null

    /**
     * Le crédit du jour du voyage visé, lu sur le flux d'accueil
     * (`Trip.dailyCredit`) et relu avec le dernier geste d'abonnement de la
     * session. `null` : on ne sait rien, on enregistre sans compter et le
     * serveur tranche. Lu **rechargé** — voir [currentCredit].
     */
    var credit: DailyCredit? = credit

    /**
     * Le crédit tel qu'il vaut maintenant : celui de l'accueil vient souvent du
     * cache, et épuisé hier soir, il est plein ce matin — même dans l'avion, où
     * la file gardera le vocal (03/10/2026, [DailyCredit.refreshed]).
     */
    val currentCredit: DailyCredit? get() = credit?.refreshed()

    private val mutableShowsExhaustedNotice = MutableStateFlow(false)

    /** Le disque pâli a été touché, crédit épuisé : le bandeau dit pourquoi. */
    val showsExhaustedNotice: StateFlow<Boolean> = mutableShowsExhaustedNotice.asStateFlow()

    /** La limite a coupé le dernier vocal — il est parti quand même. */
    var stoppedAtLimit = false
        private set

    /**
     * Ce que fait l'arrêt net : rendre le vocal capturé et ses niveaux, pour
     * qu'il parte comme si on avait touché « Envoyer ». Posé par la feuille.
     */
    var onLimitReached: ((RecordedAudio, List<Double>) -> Unit)? = null

    /** Le retour haptique, joué par la feuille — elle seule tient la vue. */
    var onFeedback: ((Feedback) -> Unit)? = null

    /** L'annonce à TalkBack — l'`UIAccessibility.post(notification: .announcement)` d'iOS. */
    var onAnnouncement: ((String) -> Unit)? = null

    /** La phase du bandeau au dernier relevé — on ne vibre qu'aux changements. */
    private var lastPhase = DailyCredit.Phase.Calm

    val isRecording: Boolean get() = recorder.isRecording
    val isPaused: Boolean get() = recorder.isPaused
    val isCapturing: Boolean get() = recorder.isCapturing
    val elapsed: Double get() = recorder.elapsed
    val level: Double get() = recorder.level

    /**
     * Rien n'a encore été enregistré : ni son, ni temps. C'est l'état
     * d'ouverture de la feuille, et celui où « Recommencer » n'a rien à faire.
     */
    val isUntouched: Boolean get() = !isRecording && levels.value.isEmpty()

    /**
     * Plus de crédit aujourd'hui pour ce voyage : le disque pâlit — sans se
     * désactiver — et le toucher montre le bandeau. Jamais pour un abonné.
     */
    val isCreditExhausted: Boolean get() = currentCredit?.isExhausted == true

    /**
     * Le bandeau au-dessus du disque — [DailyCreditBanner]. Pendant qu'on
     * parle, le compte à rebours ; crédit épuisé, « Crédit du jour épuisé ».
     */
    val creditBanner: DailyCreditBanner?
        get() {
            val credit = currentCredit ?: return null
            if (credit.isUnlimited) return null
            if (isRecording) return DailyCreditBanner.whileRecording(credit, elapsedMs = recorder.elapsedMilliseconds)
            return if (credit.isExhausted) DailyCreditBanner.Exhausted else null
        }

    /**
     * Le chrono, en `m:ss`. Les minutes ne sont pas complétées à deux
     * chiffres : la maquette écrit « 0:06 », pas « 00:06 ».
     */
    val elapsedLabel: String
        get() {
            val total = elapsed.toInt()
            return String.format(Locale.ROOT, "%d:%02d", total / 60, total % 60)
        }

    // MARK: - Les gestes

    /**
     * Le geste du gros bouton : ouvrir le micro, reprendre après une pause, ou
     * refermer et envoyer.
     *
     * **En pause, il reprend.** Il disait « Reprendre » et envoyait le vocal
     * (Hugo, 29/09/2026) : `isRecording` reste vrai pendant une pause, et le
     * geste tombait dans « refermer ». La pause se lève d'abord ; envoyer
     * demande alors un second appui, sur un disque qui dit « Envoyer ».
     */
    suspend fun toggle(): RecordedAudio? {
        if (isPaused) {
            togglePause()
            return null
        }
        if (isRecording) return finish()
        start()
        return null
    }

    suspend fun start() {
        if (isRecording || isBusy.value) return
        // Plus de crédit : ni micro, ni demande d'accès pour rien. Le bandeau
        // est déjà là ; le toucher du disque le fait vibrer.
        if (isCreditExhausted) {
            if (showsExhaustedNotice.value) onFeedback?.invoke(Feedback.Warning)
            mutableShowsExhaustedNotice.value = true
            return
        }

        mutableIsBusy.value = true
        try {
            // C'est cet appel qui fait apparaître la demande d'accès au micro.
            recorder.start()
        } catch (error: kotlinx.coroutines.CancellationException) {
            throw error
        } catch (error: Exception) {
            mutableErrorMessage.value = error.message
            return
        } finally {
            mutableIsBusy.value = false
        }

        mutableErrorMessage.value = null
        mutableLevels.value = emptyList()
        captured.clear()
        lastPhase = DailyCredit.Phase.Calm
        stoppedAtLimit = false
        startSampling()
    }

    fun togglePause() {
        if (!isRecording) return

        if (isPaused) {
            recorder.resume()
            startSampling()
        } else {
            recorder.pause()
            stopSampling()
        }
    }

    /**
     * Tout jeter et repartir de zéro : le vocal en cours et la frise. C'est le
     * geste qu'on fait quand on s'est emmêlé dans sa phrase.
     */
    suspend fun restart() {
        recorder.cancel()
        stopSampling()
        mutableLevels.value = emptyList()
        captured.clear()
        mutableErrorMessage.value = null
        start()
    }

    /** Referme tout et rend le vocal. `null` si rien n'a été capturé. */
    fun finish(): RecordedAudio? {
        stopSampling()
        return try {
            recorder.stop()
        } catch (error: Exception) {
            mutableErrorMessage.value = error.message
            null
        }
    }

    /**
     * La feuille se referme sans qu'on ait rien validé : on n'invente pas un
     * souvenir à partir d'un enregistrement abandonné.
     */
    fun discard() {
        stopSampling()
        recorder.cancel()
        mutableLevels.value = emptyList()
        captured.clear()
    }

    /** La feuille est partie : le micro se referme, rien ne tourne plus. */
    fun close() {
        discard()
        scope.cancel()
    }

    // MARK: - La frise

    private fun startSampling() {
        stopSampling()
        sampler = scope.launch {
            while (isActive) {
                delay(SAMPLING_INTERVAL_MS)
                if (!isCapturing) return@launch
                val level = level
                captured += level
                // On ne garde que ce que la frise peut montrer, plus une poignée
                // de barres d'avance pour que le défilé reste continu.
                mutableLevels.value = (mutableLevels.value + level).takeLast(BrandWaveformCapacity.maximum)
                watchCredit()
            }
        }
    }

    // MARK: - Le crédit du jour

    /**
     * Ce que le crédit fait à l'enregistrement, à chaque relevé — la même
     * règle que `ChatModel` : un retour haptique et une annonce quand le
     * bandeau paraît, un autre quand il pulse, l'arrêt net à zéro.
     */
    private fun watchCredit() {
        val credit = currentCredit ?: return
        if (credit.isUnlimited || !isCapturing) return
        val remaining = credit.remainingMs(whileRecording = recorder.elapsedMilliseconds)
        val phase = credit.phase(remainingMs = remaining)
        if (phase == lastPhase) return
        lastPhase = phase

        when (phase) {
            DailyCredit.Phase.Calm -> Unit
            DailyCredit.Phase.Warning -> {
                onFeedback?.invoke(Feedback.Light)
                onAnnouncement?.invoke(DailyCreditCopy.warning(remainingMs = remaining))
            }
            DailyCredit.Phase.Urgent -> onFeedback?.invoke(Feedback.Medium)
            DailyCredit.Phase.Exhausted -> stopAtLimit()
        }
    }

    /**
     * **L'arrêt net** : ce qui a été dit part — jamais on ne jette la fin d'un
     * récit parce que la minute est passée. Les niveaux sont lus avant de
     * refermer, comme pour « Envoyer ».
     */
    private fun stopAtLimit() {
        val levels = capturedLevels
        val audio = finish() ?: return
        stoppedAtLimit = true
        onFeedback?.invoke(Feedback.Warning)
        onAnnouncement?.invoke(ChatCopy.Credit.stoppedAnnouncement)
        onLimitReached?.invoke(audio, levels)
    }

    private fun stopSampling() {
        sampler?.cancel()
        sampler = null
    }

    private companion object {
        /**
         * Un échantillon toutes les 80 ms. C'est la cadence de la frise, et donc
         * sa vitesse : plus court, elle défile trop vite pour qu'on suive ;
         * plus long, elle saute d'une barre à l'autre.
         */
        const val SAMPLING_INTERVAL_MS = 80L
    }
}

/**
 * Le nombre d'échantillons qu'on garde. Il vit ici et non dans la vue parce
 * que c'est le modèle qui remplit le tableau.
 *
 * **Assez pour remplir la plus large des deux frises.** La feuille
 * d'enregistrement en tient une quarantaine sur un iPhone 17, et davantage sur
 * un Max : en dessous, la frise s'arrêtait avant le bord droit faute
 * d'échantillons à dessiner (Hugo, 19/09/2026). Ce sont des `Double` — en
 * garder soixante-quatre ne coûte rien.
 */
internal object BrandWaveformCapacity {
    const val maximum = 64
}
