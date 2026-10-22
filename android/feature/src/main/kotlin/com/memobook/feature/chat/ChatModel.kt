package com.memobook.feature.chat

import android.content.Context
import androidx.compose.ui.graphics.ImageBitmap
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.memobook.core.ChatAuthor
import com.memobook.core.ChatCallToAction
import com.memobook.core.ChatCallToActionState
import com.memobook.core.ChatCopy
import com.memobook.core.ChatDelivery
import com.memobook.core.ChatMessage
import com.memobook.core.ChatMessageBody
import com.memobook.core.ChatPhotoUpload
import com.memobook.core.ChatSuggestion
import com.memobook.core.ChatThread
import com.memobook.core.ChatThreadUpdate
import com.memobook.core.ChatTurnReceipt
import com.memobook.core.DailyCredit
import com.memobook.core.DailyCreditCopy
import com.memobook.core.Entry
import com.memobook.core.MemoResponderError
import com.memobook.core.PhotoAttachment
import com.memobook.core.TranscriptCard
import com.memobook.core.VoiceNote
import com.memobook.feature.ChatPhotoFile
import com.memobook.feature.RecordingOutbox
import com.memobook.feature.SubscriptionSession
import com.memobook.feature.recording.RecordingHandoff
import com.memobook.networking.ApiError
import com.memobook.recording.AudioNotePlayer
import com.memobook.recording.AudioRecorder
import com.memobook.recording.RecordedAudio
import com.memobook.recording.RecordingError
import com.memobook.recording.RecordingPermission
import com.memobook.recording.SpeechReader
import com.memobook.recording.VoiceLevels
import com.memobook.recording.VoiceNoteFile
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.net.URI
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import java.util.UUID
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

/**
 * Où en est le tour de parole en cours. Jumeau de `ChatTurnState`.
 *
 * **Un seul état, porté par l'identifiant de la bulle concernée.** La vue ne
 * tient pas de second état parallèle : c'est ce qui garantit qu'un échec ne
 * puisse pas laisser l'indicateur d'attente allumé pendant que le composeur se
 * croit disponible.
 */
sealed interface ChatTurnState {
    /** Rien en vol. Le composeur est ouvert, les suggestions sont là. */
    data object Idle : ChatTurnState

    /** La bulle du voyageur est posée, l'envoi n'est pas confirmé. */
    data class Sending(val messageId: String) : ChatTurnState

    /**
     * MEMO réfléchit. Trois points qui respirent à gauche, à la place de la
     * bulle qui vient — jamais une roue centrée, qui ferait sauter le fil.
     */
    data object Thinking : ChatTurnState

    /**
     * Échec. La bulle du voyageur reste, marquée « Non envoyé », et le tour est
     * rejouable tel quel.
     */
    data class Failed(val messageId: String, val message: String) : ChatTurnState
}

/**
 * Ce que la barre d'envoi propose. Jumeau de `ChatComposerMode`.
 *
 * Trois modes et pas quatre : « en train d'enregistrer » se lit sur
 * [AudioRecorder.isRecording] et n'a pas à être dupliqué ici — deux sources
 * pour le même fait finissent toujours par se contredire.
 */
enum class ChatComposerMode {
    /** Les trois commandes de la maquette : photo, clavier, micro. */
    Tools,

    /** Le champ de saisie est ouvert. */
    Writing,

    /** Le micro est armé : le bouton « Record » occupe la barre. */
    Speaking,
}

/** Les photos d'une bulle ouvertes en plein écran — [ChatModel.viewedPhotos]. */
data class ChatPhotoViewing(val attachments: List<PhotoAttachment>, val index: Int) {
    val id: String get() = attachments.joinToString("|") { it.id } + "#$index"
}

/**
 * Ce que la conversation tient du téléphone pour parler et écouter : le micro,
 * le lecteur des vocaux, la voix qui lit les bulles, et où garder les fichiers.
 *
 * **Sur iOS, `ChatModel` les crée lui-même** (`AudioRecorder()`,
 * `AudioNotePlayer()`, `SpeechReader()`) ; sur Android, chacun demande un
 * `Context`, que ni le modèle ni `AppDependencies` ne tiennent. La porte
 * d'entrée les construit sur le contexte de l'**application** — un `ViewModel`
 * survit à son activité — et les confie au modèle.
 *
 * La question du micro, elle, ne se pose que depuis une activité
 * (`rememberRecordingPermissionRequest()`) : l'écran la prête à
 * [requestPermission] le temps qu'il est à l'écran, et la reprend en partant.
 *
 * @param cacheDirectory les caches de l'app : les vocaux qu'on réécoute
 *   ([VoiceNoteFile]) et les photos qu'on vient de choisir ([ChatPhotoFile]).
 */
class ChatAudio(private val context: Context, val cacheDirectory: File) {
    /** La demande d'accès au micro, prêtée par l'écran. Sans elle, l'accès tel qu'il est. */
    var requestPermission: (suspend () -> Boolean)? = null

    /**
     * Où en est l'accès au micro, lu par l'écran — seule une activité sait dire
     * « refusé pour de bon » ([RecordingPermission.current]). Sans elle, le
     * contexte de l'app, qui ne le dit jamais.
     */
    var permissionState: (() -> RecordingPermission.State)? = null

    val recorder: AudioRecorder = AudioRecorder(context) {
        requestPermission?.invoke() ?: (RecordingPermission.current(context) == RecordingPermission.State.Granted)
    }
    val player: AudioNotePlayer = AudioNotePlayer(context)
    val voiceNotes: VoiceNoteFile = VoiceNoteFile(cacheDirectory)

    private var speechReader: SpeechReader? = null

    /**
     * La voix qui lit les bulles, ouverte la première fois qu'on la demande :
     * son moteur `TextToSpeech` se lie à un service du système, et rien ne sert
     * de le réveiller pour un écran qui ne lira rien.
     */
    val reader: SpeechReader get() = speechReader ?: SpeechReader(context).also { speechReader = it }

    /** Arrête la voix, si elle a été ouverte. */
    internal fun stopReading() {
        speechReader?.stop()
    }

    /** Ferme la voix — l'écran ne reviendra pas. */
    internal fun shutdownReader() {
        speechReader?.shutdown()
        speechReader = null
    }

    fun microphoneState(): RecordingPermission.State = permissionState?.invoke() ?: RecordingPermission.current(context)
}

/**
 * Ce que l'écran de chat sait faire : charger sa conversation, envoyer ce que
 * le voyageur raconte, et laisser MEMO répondre — `docs/conversation.md`.
 * Jumeau de `ChatModel.swift`.
 *
 * **Même construction que `HomeModel`, `TripHomeModel` et `ProfileModel`** :
 * le modèle ne connaît pas l'API, il reçoit un [ChatTransport] — des
 * fonctions-sources — et ne sait pas si derrière il y a le serveur ou le
 * moteur local des aperçus. Un seul chemin de code, deux transports.
 *
 * **Tout le déroulé d'un tour est ici, jamais dans la vue.** La bulle du
 * voyageur se pose avant le réseau et passe « envoyée » dès le reçu du
 * serveur ; MEMO répond dans un job, que le modèle **sonde** toutes les deux
 * secondes tant qu'un tour est en vol ou qu'une fiche n'est pas prête ; ses
 * bulles arrivent une par une, chacune après le silence que le serveur a
 * décidé pour elle, avec l'indicateur qui se rallume entre deux ; un échec
 * garde le message pour qu'on puisse le renvoyer, sous le **même**
 * identifiant. Une vue qui aurait à orchestrer ça se remettrait à clignoter au
 * premier refactoring.
 *
 * ### Ce qui change sur Android
 *
 * L'`@Observable` d'iOS devient **un** [StateFlow], [state], que la vue
 * collecte ; les propriétés d'iOS (`thread`, `turn`, `draft`…) le lisent, et
 * les propriétés calculées (`credit`, `canSendDraft`, `creditBanner`…) avec
 * lui. Trois choses ont leur propre flux, parce qu'elles bougent plusieurs
 * fois par seconde et qu'une bulle n'a pas à se redessiner pour elles : les
 * niveaux du micro ([capturedLevels]), chaque image du fil ([image]), et
 * l'état des trois objets audio ([recorder], [player], [reader]).
 *
 * Ce que le modèle d'iOS demande au système — vibrer, parler à VoiceOver,
 * copier, ouvrir les Réglages — passe ici par des rappels que la vue pose
 * ([onFeedback], [onAnnouncement], [onCopy], [onOpenSettings],
 * [isScreenReaderOn]) : seul l'écran tient l'activité. C'est le motif de
 * `RecordingModel`.
 *
 * @param transport ce qui relie le modèle au monde — le serveur, ou le moteur
 *   local des aperçus. Voir [ChatTransport].
 * @param audio le micro, le lecteur et la voix — voir [ChatAudio].
 * @param focusStepId l'étape sur laquelle le fil s'ouvre, quand on vient d'une
 *   carte d'étape.
 * @param callToActionMemory où retenir ce qu'on a fait des boutons des bulles
 *   — les réglages de l'appareil, sauf dans un test.
 * @param imageDecoder ce qui décode les images du fil — [ChatImage.android],
 *   sauf dans un test sur la JVM.
 * @param io où se lisent les fichiers et se décodent les images — hors du fil
 *   principal ; un test passe le sien, pour rester dans son temps virtuel.
 */
class ChatModel(
    private val transport: ChatTransport,
    val audio: ChatAudio,
    val focusStepId: String? = null,
    private val callToActionMemory: ChatCallToActionMemory = ChatCallToActionMemory.inMemory(),
    private val imageDecoder: ChatImageDecoder = ChatImage.android,
    private val io: CoroutineDispatcher = Dispatchers.IO,
) : ViewModel() {
    /**
     * Ce que la vue dessine, en un seul état. Les champs marqués `internal`
     * sont les états privés d'iOS : la vue n'a pas à les lire, mais les
     * propriétés calculées qu'elle lit en dépendent.
     *
     * @property isOffline le fil affiché n'est pas celui du serveur, mais le
     *   fil **local** — sans réseau, ou pour un voyage créé hors ligne que le
     *   serveur n'a pas encore reçu (`ChatThread.offline(trip, traveller,
     *   isNew)`). On y raconte quand même : tout part dans la file. L'écran le
     *   dit, et le vrai fil revient dès qu'un message est arrivé.
     * @property microphoneIsDenied l'enregistrement a été refusé. Le seul
     *   recours est les Paramètres du téléphone, et l'écran doit le dire au lieu
     *   de redemander en boucle.
     * @property copiedMessageId le message dont le texte vient d'être copié. Il
     *   porte la coche verte pendant une seconde — voir [copy].
     * @property showsExhaustedNotice le bandeau « Crédit du jour épuisé » est
     *   demandé : on a touché le micro ou le clavier pâlis. **Il passe, il ne
     *   reste pas** (recette du 03/10/2026) — voir [showExhaustedNotice].
     * @property callToActionStates ce qu'on a fait des boutons posés sous les
     *   bulles de MEMO — touché, ignoré —, par identifiant de bulle. Retenu sur
     *   l'appareil ([ChatCallToActionMemory]) : c'est l'état d'un geste, pas un
     *   fait du récit.
     * @property isEditingTranscript le brouillon est une retranscription qu'on
     *   corrige, et non un message qu'on écrit. Le champ s'y étire plus haut —
     *   corriger un texte de cinquante mots demande de le **lire**, et six
     *   lignes en cachent la moitié. Retombe à faux dès que le brouillon part
     *   ou se jette.
     * @property returnsToWritingAfterRecording le vocal en cours a été commencé
     *   clavier levé : à sa fin, la barre revient au champ — voir [tapMicrophone].
     * @property viewedPhotos les photos ouvertes en plein écran (Hugo,
     *   18/10/2026 : « quand on clique sur une photo qu'on a envoyée, elle
     *   s'affiche en plein écran »), et celle par laquelle on est entré.
     * @property servedCredit **le crédit servi**, et lui seul : le fil, une mise
     *   à jour, un reçu, un refus — ou, sans réseau, le dernier qu'on a connu
     *   pour ce voyage. Les estimations ne s'y mêlent jamais (03/10/2026) : un
     *   fil rouvert hors ligne repart de ce chiffre-ci, moins ce qui attend dans
     *   la file, et rouvrir dix fois ne décompte pas dix fois le même vocal.
     * @property unreceivedCosts ce que coûte chaque tour parti d'ici que le
     *   serveur n'a **pas encore reçu** — en vol, ou en file —, par identifiant
     *   de bulle. Le serveur le comptera en le recevant : d'ici là, le crédit
     *   qu'il sert ne le contient pas, et la barre ne doit pas promettre ce
     *   qu'il prendra. Un tour sort d'ici à son reçu, à son refus, ou quand une
     *   lecture du fil le rend. Un dictionnaire et non un total : le même tour
     *   vu deux fois — rouvert depuis la file, renvoyé — ne coûte qu'une fois.
     * @property queuedTurnIds les tours partis d'ici que la file garde **faute
     *   de réseau** — envoyés hors ligne depuis un fil ouvert en ligne. Tant
     *   qu'il y en a, la barre d'envoi le dit ([showsQueuedNotice]).
     * @property editingEntryId le souvenir que le brouillon corrige — « à la
     *   main ». Envoyer le brouillon passe alors par
     *   [ChatTransport.editTranscript] et non par un nouveau message : la fiche
     *   change, le fil n'en gagne pas une copie.
     * @property editingOriginalText le texte de la fiche qu'on corrige « à la
     *   main », tel qu'il était : le serveur ne fait payer que ce qu'une
     *   correction **ajoute**.
     * @property railWasShowing la bande montrait des puces quand le tour est
     *   parti. Retenu à part : l'envoi vide les suggestions du fil dès le
     *   départ — celles du tour d'avant ne veulent plus rien dire —, et la
     *   bande n'aurait plus de raison de garder sa place.
     * @property derivedLevels les niveaux **relus dans le fichier** des vocaux
     *   arrivés sans relevé — voir [VoiceLevels]. Gardés ici et non dans le fil :
     *   chaque relecture du serveur rend ces vocaux sans niveaux, et les
     *   écraserait.
     */
    data class State(
        val thread: ChatThread? = null,
        val errorMessage: String? = null,
        val turn: ChatTurnState = ChatTurnState.Idle,
        val isOffline: Boolean = false,
        val microphoneIsDenied: Boolean = false,
        val copiedMessageId: String? = null,
        val showsExhaustedNotice: Boolean = false,
        val callToActionStates: Map<String, ChatCallToActionState> = emptyMap(),
        val composer: ChatComposerMode = ChatComposerMode.Tools,
        val draft: String = "",
        val isEditingTranscript: Boolean = false,
        val returnsToWritingAfterRecording: Boolean = false,
        val viewedPhotos: ChatPhotoViewing? = null,
        internal val servedCredit: DailyCredit? = null,
        internal val unreceivedCosts: Map<String, Int> = emptyMap(),
        internal val queuedTurnIds: Set<String> = emptySet(),
        internal val editingEntryId: String? = null,
        internal val editingOriginalText: String? = null,
        internal val railWasShowing: Boolean = false,
        internal val derivedLevels: Map<String, List<Double>> = emptyMap(),
    )

    /** Un retour haptique que la vue joue — les `UIFeedbackGenerator` d'iOS. */
    enum class Feedback {
        /** `UINotificationFeedbackGenerator().notificationOccurred(.warning)`. */
        Warning,

        /** `UIImpactFeedbackGenerator(style: .light)`. */
        Light,

        /** `UIImpactFeedbackGenerator(style: .medium)`. */
        Medium,

        /** `UINotificationFeedbackGenerator().notificationOccurred(.success)`. */
        Success,
    }

    private val mutableState = MutableStateFlow(
        State(microphoneIsDenied = audio.microphoneState() == RecordingPermission.State.Denied),
    )

    /** Tout ce que l'écran dessine. Les propriétés ci-dessous le lisent. */
    val state: StateFlow<State> = mutableState.asStateFlow()

    private var current: State
        get() = mutableState.value
        set(value) {
            mutableState.value = value
        }

    private inline fun change(transform: State.() -> State) {
        current = current.transform()
    }

    private inline fun changeThread(transform: (ChatThread) -> ChatThread) {
        val thread = current.thread ?: return
        change { copy(thread = transform(thread)) }
    }

    // MARK: Ce que la vue pose

    /** Le retour haptique, joué par la vue — elle seule tient l'activité. */
    var onFeedback: ((Feedback) -> Unit)? = null

    /** L'annonce à TalkBack — l'`UIAccessibility.post(notification: .announcement)` d'iOS. */
    var onAnnouncement: ((String) -> Unit)? = null

    /** Le presse-papiers — `UIPasteboard.general.string` sur iOS. */
    var onCopy: ((String) -> Unit)? = null

    /** La page de MemoBook dans les Paramètres du téléphone — `UIApplication.openSettingsURLString`. */
    var onOpenSettings: (() -> Unit)? = null

    /** TalkBack est allumé — `UIAccessibility.isVoiceOverRunning`. */
    var isScreenReaderOn: () -> Boolean = { false }

    /**
     * L'abonnement de la session, posé par l'écran : un achat fait passer en
     * illimité **tout de suite**, sans attendre que le serveur le redise —
     * [SubscriptionSession.applied].
     */
    var subscription: SubscriptionSession? = null

    // MARK: Les objets audio

    val recorder: AudioRecorder get() = audio.recorder
    val player: AudioNotePlayer get() = audio.player
    val reader: SpeechReader get() = audio.reader

    private val mutableCapturedLevels = MutableStateFlow<List<Double>>(emptyList())

    /**
     * Les niveaux du micro, accumulés pendant qu'on parle.
     *
     * [AudioRecorder] ne publie qu'un niveau **instantané** : sans cette
     * collecte, la forme d'onde d'un vocal terminé n'aurait aucune donnée et il
     * faudrait en dessiner une fausse. C'est la seule raison de cette boucle.
     */
    val capturedLevels: StateFlow<List<Double>> = mutableCapturedLevels.asStateFlow()

    // MARK: Ce que la vue lit

    val thread: ChatThread? get() = current.thread
    val errorMessage: String? get() = current.errorMessage
    val turn: ChatTurnState get() = current.turn
    val isOffline: Boolean get() = current.isOffline
    val microphoneIsDenied: Boolean get() = current.microphoneIsDenied
    val copiedMessageId: String? get() = current.copiedMessageId
    val showsExhaustedNotice: Boolean get() = current.showsExhaustedNotice
    val callToActionStates: Map<String, ChatCallToActionState> get() = current.callToActionStates
    val isEditingTranscript: Boolean get() = current.isEditingTranscript
    val returnsToWritingAfterRecording: Boolean get() = current.returnsToWritingAfterRecording

    var composer: ChatComposerMode
        get() = current.composer
        set(value) {
            if (current.composer != value) change { copy(composer = value) }
        }

    var draft: String
        get() = current.draft
        set(value) {
            if (current.draft != value) change { copy(draft = value) }
        }

    /** Les photos ouvertes en plein écran — `null` : rien d'ouvert. */
    var viewedPhotos: ChatPhotoViewing?
        get() = current.viewedPhotos
        set(value) {
            change { copy(viewedPhotos = value) }
        }

    /**
     * « Tu es hors ligne, mais tu peux continuer » au-dessus de la barre : un
     * message vient de partir dans la file au lieu du serveur (Hugo,
     * 12/10/2026). Pas sur un fil local — sa boîte en tête du fil le dit déjà,
     * depuis l'ouverture.
     */
    val showsQueuedNotice: Boolean get() = current.queuedTurnIds.isNotEmpty() && !current.isOffline

    // MARK: - Le crédit du jour

    /**
     * **Le crédit du jour du voyage** (Hugo, 03/10/2026) — [DailyCredit] :
     * celui que le serveur a servi en dernier (`servedCredit`), rechargé si
     * minuit est passé depuis ([DailyCredit.refreshed]), et **décompté ici**
     * des tours partis d'ici que le serveur n'a pas encore reçus
     * (`unreceivedCosts`). Le serveur tranche, l'app prévient : ce chiffre fait
     * compter la barre pendant qu'on parle et pâlir le micro et l'envoi quand
     * il n'y a plus rien — jamais il ne décide seul.
     *
     * `null` : on ne sait rien — un serveur d'avant, un fil local ouvert sans
     * souvenir du crédit. Le serveur refusera ce qui dépasse
     * ([ChatDelivery.WaitingForCredit]) ; hors ligne, l'écran plafonne quand
     * même au crédit du catalogue ([credit]).
     */
    val dailyCredit: DailyCredit? get() = dailyCredit(current)

    private fun dailyCredit(state: State): DailyCredit? =
        state.servedCredit?.refreshed(now = Instant.now())?.consuming(state.unreceivedCosts.values.sum())

    /**
     * Le crédit qui fait foi à l'écran : celui du serveur, relu avec le dernier
     * geste de la session.
     *
     * **Hors ligne et sans rien savoir du crédit, le pot du catalogue**
     * (03/10/2026) : cinq minutes pleines, moins ce qui attend dans la file,
     * tant que la session ne sait pas le compte illimité — elle l'apprend au
     * lancement du cache de l'accueil, ou du profil. Ne rien compter laissait
     * dicter un vocal de six minutes, sans bandeau ni coupure, que le serveur
     * aurait refusé chaque jour ; plafonner à la limite ne retire rien qu'une
     * journée aurait laissé passer. En ligne, le serveur sert toujours le sien :
     * un serveur qui n'en sert pas ne compte pas, et l'app non plus.
     */
    val credit: DailyCredit? get() = credit(current)

    private fun credit(state: State): DailyCredit? {
        dailyCredit(state)?.let { known -> return subscription?.applied(known) ?: known }
        if (!state.isOffline || state.thread == null || subscription?.isUnlimited == true) return null
        return DailyCredit(resetsAt = RecordingOutbox.creditReturns(null)).consuming(state.unreceivedCosts.values.sum())
    }

    /** Le retrait différé du bandeau « épuisé ». */
    private var exhaustedNoticeTimer: Job? = null

    /**
     * Combien de temps le bandeau « épuisé » reste, une fois paru : de quoi le
     * lire et le toucher, pas de quoi encombrer le pied. Une variable pour
     * qu'un test n'attende pas cinq secondes.
     */
    var exhaustedNoticeLinger: Duration = 5.seconds

    /** La phase du bandeau au dernier relevé, pour ne faire vibrer qu'à son apparition — voir [watchCredit]. */
    private var lastRecordingPhase = DailyCredit.Phase.Calm

    /**
     * Le vocal que la limite vient de couper. Hors ligne, il n'y a pas de reçu
     * pour apporter la bulle de MEMO : l'app pose la sienne — voir
     * [postLocalExhaustedNotice].
     */
    private var limitTurnId: String? = null

    /**
     * Ce que le bandeau du crédit montre dans un aperçu, où le micro ne tourne
     * pas. Jamais posé hors de [preview].
     */
    private var previewCreditBanner: DailyCreditBanner? = null

    // MARK: Le tour

    /** Le curseur du sondage : le `now` de la dernière lecture, en temps **serveur** — jamais l'horloge du téléphone, qui peut être fausse. */
    private var cursor: Instant? = null

    private var levelSampler: Job? = null
    private var exchange: Job? = null
    private var poller: Job? = null

    /**
     * Le tour dont l'envoi a échoué. [retry] le renvoie **tel quel**, sous le
     * même identifiant : le serveur reconnaît un renvoi et ne crée pas un
     * second souvenir.
     */
    private var pending: OutgoingTurn? = null

    /** L'écoute de la file — voir [markDelivery]. Une tâche, qui meurt avec l'écran. */
    private var deliveryWatcher: Job? = null

    /**
     * Le dernier mot de la file, gardé au cas où il arrive **avant** le fil —
     * l'écran s'ouvre pendant que le vocal de l'accueil part. Il est rejoué dès
     * que le fil est là.
     */
    private var latestDelivery: ChatTurnDelivery? = null

    /** Le vrai fil est en cours de relecture, après un fil local. */
    private var isReloading = false

    /**
     * L'étape à laquelle rattacher un nouveau message : celle qu'on est venu
     * voir depuis sa carte, **et elle seule** (Hugo, 12/10/2026).
     *
     * Elle retombait sur l'étape où le voyage en était (`thread.context.stepId`) :
     * chaque récit partait épinglé sur la dernière étape, et « ton carnet
     * compte une étape de plus » n'en ajoutait aucune sur l'accueil du voyage.
     * Le serveur ne la sert plus, et ne range de toute façon un récit nulle part
     * ailleurs que dans sa propre étape — seules les photos suivent l'étape
     * choisie.
     */
    private val activeStepId: String? get() = focusStepId

    // MARK: - Charger

    /**
     * `true` tant qu'on n'a rien à montrer. L'écran dessine alors son squelette
     * plutôt qu'une demi-conversation.
     */
    val isLoading: Boolean get() = current.thread == null && current.errorMessage == null

    suspend fun load() {
        try {
            val (loaded, offline) = try {
                transport.load() to false
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                // Sans réseau, ou sur un voyage que le serveur n'a pas encore
                // reçu : on raconte quand même, dans un fil local. Le transport
                // décide s'il y en a un — une panne du serveur ne se cache pas.
                (transport.offlineThread(error) ?: throw error) to true
            }
            change { copy(thread = loaded, isOffline = offline, errorMessage = null) }
            cursor = loaded.now
            // Ce que le serveur rend, il l'a reçu : son crédit le compte déjà.
            // Et le téléphone le garde, pour rouvrir le fil sans réseau.
            if (!offline) {
                forgetCosts(loaded.messages)
                rememberThread()
            }
            // Le crédit du serveur ; sans lui — un fil local —, **le plus
            // avancé** de ce qu'on sait : le dernier servi ici pour ce voyage,
            // et celui des caches de l'écran du voyage et de l'accueil, que le
            // fil local porte ([DailyCredit.merged], 03/10/2026). Le premier
            // passait devant d'office : retenu à 9 h, il effaçait ce que
            // l'accueil avait relu à 14 h après le vocal d'un co-voyageur.
            // Rechargé à la lecture s'il date d'hier ([dailyCredit]).
            setServerCredit(
                if (offline) {
                    rememberedCredit(loaded.context.tripId)?.merged(with = loaded.dailyCredit) ?: loaded.dailyCredit
                } else {
                    loaded.dailyCredit
                },
            )

            // Le serveur dit si un tour est encore en vol — on l'a quitté au
            // milieu d'une réponse, ou un co-voyageur vient de parler.
            setTurn(if (loaded.turn.isReplying) ChatTurnState.Thinking else ChatTurnState.Idle)
            if (needsPolling) startPolling()

            // Relu à chaque ouverture : l'accès peut avoir été retiré depuis
            // les Paramètres pendant que l'app était en arrière-plan.
            val denied = audio.microphoneState() == RecordingPermission.State.Denied
            if (current.microphoneIsDenied != denied) change { copy(microphoneIsDenied = denied) }

            // Le vocal de l'accueil, s'il y en a un, se pose maintenant — il
            // fallait un fil pour l'y poser. Une fois, et une seule.
            pendingHandoff?.let { handoff ->
                pendingHandoff = null
                receive(handoff)
            }

            // Ce qui attend le réseau sur le disque pour ce fil se pose en
            // bulles « en cours d'envoi » : on a quitté l'écran sur un texte dit
            // dans le métro, il est encore là quand on revient.
            for (turn in transport.waiting()) {
                if (messages.any { it.id == turn.id }) continue
                keepLocalFiles(turn)
                append(optimisticMessage(turn))
                // Le serveur ne l'a pas encore compté : il le comptera en le
                // recevant, et la barre ne doit pas promettre ce qu'il prendra.
                // Sauf ce qui est retenu — demain, ou l'illimité : ce n'est pas
                // le crédit d'aujourd'hui. Une attente échue, elle, ne retient
                // plus : le tour partira aujourd'hui, il compte aujourd'hui.
                if (turn.isOnHold) forgetCost(turn.id) else expectCost(turn)
            }

            // Et si la file a parlé pendant qu'on chargeait, on l'écoute
            // maintenant — puis on l'écoute tout court. Un mot déjà entendu
            // avant cette lecture : son crédit ne passe pas devant elle.
            latestDelivery?.let { markDelivery(it.replayed) }
            watchDeliveries()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            change { copy(errorMessage = describe(error)) }
        }
    }

    /**
     * Suit ce que la file fait des tours partis par elle — le vocal de
     * l'accueil, un message d'ici qui attendait le réseau. Une seule écoute à la
     * fois ; elle repart avec le prochain chargement quand l'écran revient.
     */
    private fun watchDeliveries() {
        if (deliveryWatcher != null) return
        deliveryWatcher = viewModelScope.launch {
            transport.deliveries().collect { delivery -> markDelivery(delivery) }
        }
    }

    /**
     * Tout arrêter en quittant l'écran : la lecture, la voix de synthèse, le
     * tour en vol, le sondage, l'écoute de la file et la collecte de niveaux.
     * Un écran de chat laissé derrière soi ne doit ni parler ni enregistrer.
     */
    fun teardown() {
        // Ce qu'on vient de lire, gardé tel qu'on le quitte : les réponses de
        // MEMO arrivées depuis l'ouverture comprises.
        rememberThread()
        exchange?.cancel()
        exchange = null
        poller?.cancel()
        poller = null
        deliveryWatcher?.cancel()
        deliveryWatcher = null
        levelSampler?.cancel()
        player.stop()
        audio.stopReading()
        recorder.cancel()
    }

    override fun onCleared() {
        teardown()
        audio.shutdownReader()
    }

    /**
     * Garde le fil sur le téléphone — voir [ChatTransport.remember]. Rien d'un
     * fil local : il ne contient que ce qu'on avait déjà gardé.
     *
     * Hors de la portée de l'écran ([detached]), comme la `Task` détachée
     * d'iOS : c'est en partant qu'on le garde, et l'écran qui part annule ce
     * qu'il a lancé.
     */
    private fun rememberThread() {
        val thread = current.thread ?: return
        if (current.isOffline) return
        val remember = transport.remember
        detached.launch { remember(thread) }
    }

    /**
     * Ce qui doit aller au bout même si l'écran s'en va — la `Task { … }` non
     * structurée d'iOS. Rien d'autre que l'écriture du fil gardé n'y passe.
     */
    private val detached = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    // MARK: - Ce que la vue lit

    val messages: List<ChatMessage> get() = current.thread?.messages ?: emptyList()

    val suggestions: List<ChatSuggestion> get() = current.thread?.suggestions ?: emptyList()

    val isThinking: Boolean get() = current.turn == ChatTurnState.Thinking

    /**
     * Le composeur reste utilisable en cas d'échec : on ne piège personne
     * derrière un message qui ne passe pas.
     */
    val isComposerEnabled: Boolean
        get() = when (current.turn) {
            ChatTurnState.Idle, is ChatTurnState.Failed -> true
            is ChatTurnState.Sending, ChatTurnState.Thinking -> false
        }

    /**
     * Les suggestions ne s'affichent qu'au repos. Un rail encore tapable
     * pendant que MEMO réfléchit invite au double envoi.
     *
     * Crédit épuisé, « Raconter à l'oral » se tait (03/10/2026) : elle
     * n'armerait qu'un micro qui ne s'ouvre pas.
     */
    val visibleSuggestions: List<ChatSuggestion>
        get() {
            if (current.turn != ChatTurnState.Idle) return emptyList()
            if (!isCreditExhausted) return suggestions
            return suggestions.filter { it.intent != ChatSuggestion.Intent.SendThenSpeak }
        }

    /**
     * La bande de suggestions **garde sa place** pendant le tour : ses puces
     * s'effacent, sa hauteur reste. Sans ça, la barre du bas raccourcissait au
     * moment même où le message partait, et le fil, épinglé en bas, se tassait
     * d'autant sous le message qu'on venait de poser — puis remontait quand
     * MEMO répondait (Hugo, 30/09/2026, T207).
     */
    val reservesSuggestionRail: Boolean get() = current.turn != ChatTurnState.Idle && current.railWasShowing

    val canSendDraft: Boolean
        get() = current.draft.isNotBlank() && isComposerEnabled && !draftExceedsCredit

    // MARK: - Le crédit du jour, à l'écran

    /**
     * Le crédit est épuisé pour aujourd'hui : le micro et le clavier pâlissent
     * — **sans se désactiver** (règle du design system) : les toucher dit
     * pourquoi. Jamais pour un abonné.
     */
    val isCreditExhausted: Boolean get() = credit?.isExhausted == true

    /**
     * Ce que le brouillon coûterait au crédit : ses caractères, ou — pour une
     * fiche corrigée « à la main » — ce que la correction modifie au-delà des
     * 200 caractères offerts à la fiche (Hugo, 19/10/2026, QA D8 ;
     * [DailyCredit.cost] `(ofCorrection, replacing, freeLeft)`).
     */
    private val draftCost: Int
        get() {
            val credit = credit ?: return 0
            val text = current.draft.trim()
            val original = current.editingOriginalText ?: return credit.cost(ofText = text)
            return credit.cost(ofCorrection = text, replacing = original, freeLeft = editingFreeCharactersLeft)
        }

    /**
     * Ce qui reste des 200 caractères offerts à la fiche qu'on corrige — lu sur
     * sa fiche dans le fil, que le serveur redessine à chaque lecture.
     */
    private val editingFreeCharactersLeft: Int?
        get() {
            val entryId = current.editingEntryId ?: return null
            for (message in messages) {
                val body = message.body
                if (body is ChatMessageBody.Transcript && body.card.entryId == entryId) {
                    return body.card.freeCorrectionCharactersLeft
                }
            }
            return null
        }

    /**
     * On corrige une fiche « à la main » : pot vide, le champ ne pâlit pas —
     * les 200 caractères offerts par fiche passent encore (QA D8).
     */
    val isWritingCorrection: Boolean get() = current.isEditingTranscript && current.editingOriginalText != null

    /**
     * Le brouillon dépasse ce qu'il reste aujourd'hui : l'envoi pâlit, et une
     * boîte d'information dit combien de caractères il reste. Le serveur le
     * refuserait en entier — l'app l'en empêche avant (Hugo, 03/10/2026).
     */
    val draftExceedsCredit: Boolean
        get() {
            val credit = credit ?: return false
            if (credit.isUnlimited) return false
            return draftCost > credit.remainingMs
        }

    /**
     * La boîte d'information au-dessus du champ, quand on écrit : le brouillon
     * est trop long ([DailyCreditCopy.textTooLong]), ou — plus discret — il
     * reste moins d'une minute de crédit, et on dit combien de caractères cela
     * fait. `null` le reste du temps, et toujours pour un abonné.
     */
    val creditTextNotice: ChatCreditTextNotice?
        get() {
            if (current.composer != ChatComposerMode.Writing) return null
            val credit = credit ?: return null
            if (credit.isUnlimited) return null
            // Pot vide, une correction au-delà des 200 offerts attend
            // l'illimité : la même phrase que le refus du serveur.
            if (credit.isExhausted && isWritingCorrection && draftExceedsCredit) {
                return ChatCreditTextNotice.TooLong(DailyCreditCopy.correctionBeyondFree)
            }
            if (credit.isExhausted) return null
            if (draftExceedsCredit) {
                return ChatCreditTextNotice.TooLong(DailyCreditCopy.textTooLong(charactersLeft = credit.charactersLeft))
            }
            if (credit.remainingMs < CHARACTER_REMINDER_BELOW_MS) {
                return ChatCreditTextNotice.Reminder(ChatCopy.Credit.charactersLeft(credit.charactersLeft))
            }
            return null
        }

    /**
     * Le bandeau rouge doux au-dessus de la barre — [DailyCreditBanner] :
     * pendant qu'on parle, le compte à rebours à partir de 30 secondes, qui
     * pulse sous 5 ; à l'arrêt, « Crédit du jour épuisé » quand on a touché le
     * micro ou le clavier pâlis, ou qu'on écrit. Rien pour un abonné.
     */
    val creditBanner: DailyCreditBanner?
        get() {
            previewCreditBanner?.let { return it }
            val credit = credit ?: return null
            if (credit.isUnlimited) return null
            if (recorder.isRecording) {
                return DailyCreditBanner.whileRecording(credit, elapsedMs = recorder.elapsedMilliseconds)
            }
            if (!credit.isExhausted) return null
            if (!current.showsExhaustedNotice && current.composer != ChatComposerMode.Writing) return null
            return DailyCreditBanner.Exhausted
        }

    /**
     * Le micro ou le clavier pâlis ont été touchés : le bandeau « épuisé »
     * paraît, avec un retour haptique — on a voulu faire quelque chose, et il
     * se passe quelque chose.
     *
     * TalkBack l'**annonce à chaque toucher** : le bandeau s'insère ailleurs
     * dans la pile, et sans annonce le micro resterait muet. Le bandeau
     * s'efface seul après quelques secondes — sauf sous TalkBack, où il faut le
     * temps d'aller le toucher : il attend alors le geste suivant.
     */
    fun showExhaustedNotice() {
        if (!current.showsExhaustedNotice) onFeedback?.invoke(Feedback.Warning)
        change { copy(showsExhaustedNotice = true) }
        onAnnouncement?.invoke(ChatCopy.Credit.exhaustedAnnouncement)

        exhaustedNoticeTimer?.cancel()
        exhaustedNoticeTimer = null
        if (isScreenReaderOn()) return
        val linger = exhaustedNoticeLinger
        exhaustedNoticeTimer = viewModelScope.launch {
            delay(linger)
            change { copy(showsExhaustedNotice = false) }
            exhaustedNoticeTimer = null
        }
    }

    /** Le geste suivant emporte le bandeau « épuisé ». */
    private fun hideExhaustedNotice() {
        exhaustedNoticeTimer?.cancel()
        exhaustedNoticeTimer = null
        // N'écrit que ce qui change : le sondage passe ici toutes les deux
        // secondes, et chaque écriture redessinerait la barre.
        if (current.showsExhaustedNotice) change { copy(showsExhaustedNotice = false) }
    }

    /**
     * Le micro de la barre : il arme l'enregistrement, ou — crédit épuisé — dit
     * pourquoi il ne le fait pas.
     *
     * @param keepingKeyboard le clavier était levé au moment de l'appui. **Il
     *   le reste** pendant qu'on parle (Hugo, 12/10/2026 — il se baissait au
     *   milieu du vocal), et le vocal parti, la barre revient au champ de
     *   saisie qu'on avait sous les doigts. C'est l'écran qui tient le clavier
     *   (`ChatSendingBar`) ; le modèle retient seulement où revenir.
     */
    fun tapMicrophone(keepingKeyboard: Boolean = false) {
        if (isCreditExhausted) {
            showExhaustedNotice()
            return
        }
        change { copy(returnsToWritingAfterRecording = keepingKeyboard, composer = ChatComposerMode.Speaking) }
        startRecording()
    }

    /** La disposition où revenir quand un vocal se termine, et l'oubli du clavier qu'on tenait pour lui. */
    private fun composerAfterRecording(): ChatComposerMode {
        val mode = if (current.returnsToWritingAfterRecording) ChatComposerMode.Writing else ChatComposerMode.Tools
        if (current.returnsToWritingAfterRecording) change { copy(returnsToWritingAfterRecording = false) }
        return mode
    }

    /**
     * Le clavier de la barre au repos : il ouvre le champ, ou — crédit épuisé —
     * dit pourquoi écrire ne mènerait nulle part.
     *
     * @return le champ s'est ouvert, et l'écran peut lui donner le clavier.
     */
    fun tapKeyboard(): Boolean {
        if (isCreditExhausted) {
            showExhaustedNotice()
            return false
        }
        composer = ChatComposerMode.Writing
        return true
    }

    /**
     * Un abonnement vient d'être pris : on relit le crédit du serveur — la
     * session a déjà basculé l'écran en illimité, le serveur le confirme.
     */
    fun refreshAfterSubscribing() {
        hideExhaustedNotice()
        refreshOnce()
    }

    /**
     * **Le seul chemin du crédit servi** (03/10/2026) : le fil, une mise à
     * jour, un reçu, un refus. Retenu pour ce voyage, le temps que l'app vive ;
     * l'écran, lui, le lit décompté de ce qui n'est pas encore arrivé
     * ([dailyCredit]).
     */
    private fun setServerCredit(served: DailyCredit?) {
        // Le même crédit, relu à chaque sondage : ne rien réécrire, sans quoi
        // la barre d'envoi se redessinait toutes les deux secondes.
        if (current.servedCredit != served) change { copy(servedCredit = served) }
        val tripId = current.thread?.context?.tripId
        if (served != null && tripId != null) rememberCredit(served, tripId)
        // Le serveur dit « illimité » et la session ne le tenait pas de lui —
        // un achat restauré, un abonnement pris sur un autre appareil, ou un
        // achat que le serveur vient seulement d'apprendre : elle l'apprend, et
        // ce qui attendait dans la file repart (`RootView`).
        val session = subscription
        if (served?.isUnlimited == true && session != null && session.known != true) {
            session.learn(isUnlimited = true, hasSubscribedBefore = true)
        }
        if (dailyCredit?.isExhausted != true) hideExhaustedNotice()
    }

    /** Un tour part, ou se rouvre depuis la file : son coût attend le reçu. */
    private fun expectCost(turn: OutgoingTurn) {
        val cost = turn.creditCost(current.servedCredit ?: DailyCredit())
        change { copy(unreceivedCosts = unreceivedCosts + (turn.id to cost)) }
    }

    private fun forgetCost(id: String) {
        if (current.unreceivedCosts.containsKey(id)) change { copy(unreceivedCosts = unreceivedCosts - id) }
    }

    /** Le serveur a ces bulles : leur coût est dans son crédit, plus dans le nôtre. */
    private fun forgetCosts(messages: List<ChatMessage>) {
        val ids = messages.map { it.id }.filter { current.unreceivedCosts.containsKey(it) }
        if (ids.isNotEmpty()) change { copy(unreceivedCosts = unreceivedCosts - ids.toSet()) }
    }

    /**
     * Le crédit d'un mot **rejoué** par la file (03/10/2026) : le reçu ou le
     * refus du dernier tour parti de cet appareil, qu'elle redonne à chaque fil
     * qui s'ouvre. Il ne remplace pas ce que le fil vient de lire — rejoué à
     * 15 h, le reçu de 10 h rendait 4:00 à qui n'avait plus que 0:30, et un
     * vocal de 2:00 partait sans avertissement vers un refus.
     *
     * Un reçu plus ancien que la dernière lecture (`servedAt` avant `lastRead`,
     * deux heures du serveur) ne dit rien de neuf : ignoré. Sinon — un refus,
     * qui n'a pas d'heure ; un fil local, qui n'a pas lu le serveur —, il se
     * fond dans le crédit tenu ([DailyCredit.merged]) : le jour le plus tardif,
     * le plus consommé. Un refus d'aujourd'hui dit toujours « épuisé », un reçu
     * d'hier ne dit plus rien.
     */
    private fun takeReplayedCredit(replayed: DailyCredit?, servedAt: Instant? = null, lastRead: Instant? = null) {
        replayed ?: return
        if (servedAt != null && lastRead != null && servedAt < lastRead) return
        setServerCredit(current.servedCredit?.merged(with = replayed) ?: replayed)
    }

    /** Le serveur a dit « plus rien aujourd'hui » : son solde s'il l'a rendu, sinon le dernier qu'il a servi, vidé. */
    private fun exhaustCredit(served: DailyCredit?) {
        if (served != null) {
            setServerCredit(served)
        } else {
            val known = current.servedCredit?.refreshed(now = Instant.now()) ?: return
            setServerCredit(known.copy(usedMs = known.limitMs))
        }
    }

    // MARK: - Envoyer

    fun sendDraft() {
        val text = current.draft.trim()
        // Trop long pour ce qu'il reste aujourd'hui : le serveur le refuserait
        // en entier. Le brouillon reste, la boîte d'information dit pourquoi.
        if (text.isEmpty() || draftExceedsCredit) return
        val cost = draftCost
        val original = current.editingOriginalText
        val entryId = current.editingEntryId
        change { copy(draft = "", isEditingTranscript = false, editingOriginalText = null, editingEntryId = null) }

        // « À la main » : la correction va au souvenir, pas dans le fil.
        if (entryId != null) {
            submitTranscriptEdit(entryId = entryId, text = text, original = original, growthCost = cost)
            return
        }

        send(OutgoingTurn.Body.Text(text))
    }

    /**
     * Referme l'outil ouvert et ramène la barre à ses trois boutons.
     *
     * C'est la croix qui remplace le burger. Elle **jette** un enregistrement
     * en cours : c'est le seul geste de la barre qui puisse perdre quelque
     * chose, et c'est aussi ce qu'on attend d'une croix — sinon elle laisserait
     * le micro tourner derrière une barre au repos.
     */
    fun collapseComposer() {
        if (recorder.isRecording) cancelRecording()
        change {
            copy(
                returnsToWritingAfterRecording = false,
                draft = "",
                isEditingTranscript = false,
                editingEntryId = null,
                editingOriginalText = null,
            )
        }
        hideExhaustedNotice()
        composer = ChatComposerMode.Tools
    }

    /**
     * Android ne présente plus la demande d'accès une fois refusée pour de bon :
     * le seul recours est la page de MemoBook dans les Paramètres du
     * téléphone. Le bouton micro barré y mène.
     */
    fun openMicrophoneSettings() {
        onOpenSettings?.invoke()
    }

    /**
     * Ce qu'une puce de suggestion déclenche.
     *
     * Elle **envoie son libellé** comme un message — la maquette la montre bien
     * posée en bulle bleue dans le fil — et ouvre en plus l'outil qui va avec.
     * Le serveur reçoit aussi son identifiant : c'est lui qui dit qu'une puce
     * est une commande, sans modèle et sans souvenir. Seul l'import de photos
     * n'envoie rien : on ne dit pas « j'importe des photos », on les importe.
     */
    fun choose(suggestion: ChatSuggestion, addPhotos: () -> Unit, openPreview: () -> Unit = {}) {
        // Une puce est le geste suivant : le bandeau « épuisé » s'en va.
        hideExhaustedNotice()
        when (suggestion.intent) {
            ChatSuggestion.Intent.ImportPhotos -> addPhotos()
            ChatSuggestion.Intent.OpenPreview -> openPreview()
            ChatSuggestion.Intent.Send, is ChatSuggestion.Intent.Unknown -> {
                composer = ChatComposerMode.Tools
                // « Ça me convient » vise la dernière fiche du fil : c'est elle
                // que le serveur valide, dans la même requête.
                val entryId = if (suggestion.id == "accept") latestTranscriptCard?.entryId else null
                send(OutgoingTurn.Body.Text(suggestion.label, suggestionId = suggestion.id, entryId = entryId))
            }
            ChatSuggestion.Intent.SendThenWrite -> {
                composer = ChatComposerMode.Writing
                send(OutgoingTurn.Body.Text(suggestion.label, suggestionId = suggestion.id))
            }
            ChatSuggestion.Intent.SendThenEditTranscript -> {
                // Le texte de la fiche est posé dans le champ **avant** d'envoyer
                // la puce : la bulle bleue part, MEMO répond « je te laisse la
                // main », et le voyageur a déjà le texte sous les doigts. S'il n'y
                // a aucune fiche remplie — la puce vient du serveur sous un tour
                // qui n'en a pas —, le champ s'ouvre simplement vide.
                val card = latestTranscriptCard
                val text = card?.text
                if (card != null && !text.isNullOrEmpty()) {
                    change {
                        copy(draft = text, isEditingTranscript = true, editingEntryId = card.entryId, editingOriginalText = text)
                    }
                }
                composer = ChatComposerMode.Writing
                send(OutgoingTurn.Body.Text(suggestion.label, suggestionId = suggestion.id))
            }
            ChatSuggestion.Intent.SendThenSpeak -> {
                // Crédit épuisé, elle est cachée ; et si elle part quand même —
                // une puce en vol au moment où le crédit tombe —, elle n'arme
                // pas un micro qui ne s'ouvrirait pas.
                composer = if (isCreditExhausted) ChatComposerMode.Tools else ChatComposerMode.Speaking
                send(OutgoingTurn.Body.Text(suggestion.label, suggestionId = suggestion.id))
            }
        }
    }

    /**
     * Pose la bulle du voyageur et lance le tour.
     *
     * @param id l'identifiant de la bulle, quand il vient d'ailleurs — le vocal
     *   de l'accueil porte le sien. Sinon un UUID, qui sera aussi celui du
     *   message côté serveur.
     */
    private fun send(body: OutgoingTurn.Body, id: String = newId()) {
        if (current.thread == null) return
        val outgoing = OutgoingTurn(id = id, stepId = activeStepId, body = body)
        append(optimisticMessage(outgoing))
        start(outgoing)
    }

    /**
     * La bulle bleue telle qu'elle se dessine avant le reçu du serveur. Le
     * serveur la remplacera par la sienne, sous le même identifiant — sans
     * perdre le fichier local d'un vocal ou d'une photo.
     */
    private fun optimisticMessage(outgoing: OutgoingTurn): ChatMessage {
        val body = when (val turnBody = outgoing.body) {
            is OutgoingTurn.Body.Text -> ChatMessageBody.Text(turnBody.text)
            is OutgoingTurn.Body.Voice -> ChatMessageBody.Voice(
                VoiceNote(
                    id = outgoing.id,
                    duration = turnBody.audio.durationSeconds,
                    levels = turnBody.audio.levels,
                    localUrl = localVoiceUrls[outgoing.id]?.toURI(),
                ),
            )
            is OutgoingTurn.Body.Photos -> ChatMessageBody.Photos(
                turnBody.photos.indices.map { index ->
                    val id = "${outgoing.id}-$index"
                    PhotoAttachment(id = id, localUrl = localPhotoUrls[id]?.toURI())
                },
            )
        }
        return ChatMessage(
            id = outgoing.id,
            author = ChatAuthor.Traveller,
            body = body,
            sentAt = Instant.now(),
            stepId = outgoing.stepId,
            delivery = delivery(outgoing),
        )
    }

    /**
     * Les fichiers écrits dans les caches pour ce qu'on vient d'envoyer, par
     * identifiant — ce que le serveur ne rend jamais et qu'on ne veut pas
     * perdre en fusionnant sa réponse.
     */
    private val localVoiceUrls = mutableMapOf<String, File>()
    private val localPhotoUrls = mutableMapOf<String, File>()

    /**
     * « Réessayer » sous la bulle : le tour repart **tel quel**, sous le même
     * identifiant. Celui dont l'envoi vient d'échouer ici ; sinon celui que la
     * file a vu refuser — rebâti depuis la bulle et ses fichiers locaux,
     * puisque la file l'a déjà oublié.
     */
    fun retry() {
        val turn = pending ?: refusedTurn() ?: return
        mark(turn.id, ChatDelivery.Sending)
        start(turn)
    }

    private fun refusedTurn(): OutgoingTurn? {
        val message = messages.lastOrNull { it.author.isTraveller && it.delivery.hasFailed } ?: return null
        return outgoingTurn(message)
    }

    /**
     * Le tour qu'une bulle du voyageur représente, avec ses octets relus des
     * caches. `null` quand ils n'y sont plus : il n'y a alors rien à renvoyer.
     */
    private fun outgoingTurn(message: ChatMessage): OutgoingTurn? = when (val body = message.body) {
        is ChatMessageBody.Text -> OutgoingTurn(id = message.id, stepId = message.stepId, body = OutgoingTurn.Body.Text(body.value))
        is ChatMessageBody.Voice -> {
            val data = body.note.localUrl?.let(::readFile)
            data?.let {
                OutgoingTurn(
                    id = message.id,
                    stepId = message.stepId,
                    body = OutgoingTurn.Body.Voice(
                        RecordedTurnAudio(
                            data = it,
                            filename = "${message.id}.m4a",
                            mimeType = "audio/mp4",
                            capturedAt = message.sentAt,
                            durationSeconds = body.note.duration,
                            levels = body.note.levels,
                            placeLabel = current.thread?.context?.placeName,
                        ),
                    ),
                )
            }
        }
        is ChatMessageBody.Photos -> {
            val photos = body.attachments.mapNotNull { attachment ->
                val data = attachment.localUrl?.let(::readFile) ?: return@mapNotNull null
                ChatPhotoUpload(data = data, filename = "${attachment.id}.jpg", mimeType = "image/jpeg")
            }
            if (photos.isEmpty() || photos.size != body.attachments.size) {
                null
            } else {
                OutgoingTurn(id = message.id, stepId = message.stepId, body = OutgoingTurn.Body.Photos(photos, capturedAt = message.sentAt))
            }
        }
        is ChatMessageBody.Transcript -> null
    }

    // MARK: - Le tour de parole

    private fun start(outgoing: OutgoingTurn) {
        pending = outgoing
        // Décompté **ici**, sans attendre le reçu : hors ligne, il n'y en aura
        // pas avant longtemps, et la barre doit savoir ce qui reste pour le
        // prochain vocal. Le reçu remettra le chiffre du serveur.
        expectCost(outgoing)
        exchange?.cancel()
        exchange = viewModelScope.launch { run(outgoing) }
    }

    private suspend fun run(outgoing: OutgoingTurn) {
        val thread = current.thread ?: return

        // La bande garde sa place si elle montrait des puces — ou si elle la
        // gardait déjà, pour un renvoi après un échec. Voir
        // [reservesSuggestionRail].
        val railWasShowing = thread.suggestions.isNotEmpty() || (current.railWasShowing && current.turn != ChatTurnState.Idle)

        // Les suggestions du tour précédent ne veulent plus rien dire.
        change {
            copy(
                railWasShowing = railWasShowing,
                thread = thread.copy(suggestions = emptyList()),
                turn = ChatTurnState.Sending(messageId = outgoing.id),
            )
        }

        try {
            val outcome = transport.send(outgoing)
            currentCoroutineContext().ensureActive()
            pending = null

            when (outcome) {
                is ChatSendOutcome.Received -> {
                    accept(outcome.receipt, outgoing.id)
                    if (limitTurnId == outgoing.id) limitTurnId = null
                }
                ChatSendOutcome.Queued -> {
                    // Le tour attend le réseau sur le disque. Ce n'est pas un
                    // échec : la bulle reste « en cours d'envoi », le composeur
                    // se rouvre, et c'est la file qui la terminera — par son
                    // identifiant, voir [markDelivery].
                    //
                    // Et l'écran **le dit** (Hugo, 12/10/2026) : sans ça, on
                    // envoyait hors ligne sans savoir que c'était gardé.
                    change { copy(turn = ChatTurnState.Idle, queuedTurnIds = queuedTurnIds + outgoing.id) }
                    // Le vocal que la limite a coupé, parti dans la file : pas
                    // de reçu pour apporter la bulle de MEMO, l'app pose la sienne.
                    if (limitTurnId == outgoing.id) {
                        limitTurnId = null
                        postLocalExhaustedNotice()
                    }
                }
            }
        } catch (error: CancellationException) {
            // L'écran s'est refermé, ou un nouveau tour a démarré. Rien à dire
            // — et rien à défaire du tour qui a pris la place de celui-ci.
            if (owns(outgoing.id)) setTurn(ChatTurnState.Idle)
            throw error
        } catch (error: Exception) {
            val apiError = error as? ApiError
            when {
                apiError != null && (
                    apiError.isDailyCreditTooLong ||
                        (apiError.isDailyCreditExhausted && RecordingOutbox.neverFitsADay(outgoing, refusal = apiError.dailyCredit))
                    ) -> {
                    // Plus long qu'une journée de crédit : demain n'y changerait
                    // rien. La bulle propose l'illimité, comme la file la ferait
                    // attendre.
                    pending = null
                    forgetCost(outgoing.id)
                    apiError.dailyCredit?.let { setServerCredit(it) }
                    mark(outgoing.id, ChatDelivery.WaitingForUnlimited)
                    setTurn(ChatTurnState.Idle)
                }
                apiError != null && apiError.isDailyCreditExhausted -> {
                    // Un transport sans file — les aperçus — rend le refus tel
                    // quel. Ce n'est pas un échec à réessayer : la bulle attend
                    // demain, comme la file la ferait attendre.
                    pending = null
                    forgetCost(outgoing.id)
                    exhaustCredit(apiError.dailyCredit)
                    mark(outgoing.id, ChatDelivery.WaitingForCredit(until = RecordingOutbox.creditReturns(apiError.dailyCredit?.resetsAt)))
                    setTurn(ChatTurnState.Idle)
                    if (limitTurnId == outgoing.id) {
                        limitTurnId = null
                        postLocalExhaustedNotice()
                    }
                    refreshOnce()
                }
                else -> {
                    val message = describe(error)
                    forgetCost(outgoing.id)
                    mark(outgoing.id, ChatDelivery.Failed(message))
                    setTurn(ChatTurnState.Failed(messageId = outgoing.id, message = message))
                }
            }
        }
        if (exchange == currentCoroutineContext()[Job]) exchange = null
    }

    /**
     * Ce que le serveur a écrit en recevant un tour : la bulle du voyageur avec
     * son rang, l'ouverture de MEMO si elle vient d'être posée, la fiche d'un
     * vocal. On fusionne ; on ne remplace pas le fil.
     *
     * Le curseur ne recule jamais : un reçu arrivé en retard — un tour parti de
     * la file après une lecture plus récente — ne fait pas relire ce qu'on a
     * déjà.
     *
     * @param isReplay le reçu vient d'un mot **rejoué** par la file — le
     *   dernier tour parti de cet appareil, peut-être ce matin. Voir
     *   [takeReplayedCredit].
     */
    private fun accept(receipt: ChatTurnReceipt, id: String, isReplay: Boolean = false) {
        merge(receipt.messages)
        mark(id, ChatDelivery.Sent)
        val lastRead = cursor
        cursor = maxOf(cursor ?: distantPast, receipt.now)
        // Le crédit **après** ce tour, tel que le serveur l'a compté — il
        // remplace l'estimation faite à l'envoi, et ne garde que celle des
        // tours qu'il n'a pas encore reçus.
        forgetCost(id)
        forgetCosts(receipt.messages)
        if (isReplay) {
            takeReplayedCredit(receipt.dailyCredit, servedAt = receipt.now, lastRead = lastRead)
        } else {
            receipt.dailyCredit?.let { setServerCredit(it) }
        }

        if (receipt.turn.isReplying) {
            setTurn(ChatTurnState.Thinking)
        } else if (owns(id)) {
            setTurn(ChatTurnState.Idle)
        }
        if (needsPolling) startPolling()
    }

    /**
     * Le tour en cours est celui de cette bulle. Un reçu venu de la file pour
     * un tour d'hier ne doit pas rouvrir le composeur pendant qu'un autre part.
     */
    private fun owns(id: String): Boolean = when (val turn = current.turn) {
        is ChatTurnState.Sending -> turn.messageId == id
        is ChatTurnState.Failed -> turn.messageId == id
        ChatTurnState.Idle, ChatTurnState.Thinking -> false
    }

    private fun setTurn(turn: ChatTurnState) {
        if (current.turn != turn) change { copy(turn = turn) }
    }

    // MARK: - Le sondage

    /** Tant qu'un tour est en vol, ou qu'une fiche attend sa transcription ou sa rédaction. */
    private val needsPolling: Boolean
        get() {
            if (current.turn == ChatTurnState.Thinking) return true
            return messages.any { message ->
                val body = message.body
                body is ChatMessageBody.Transcript && (body.card.isSettling || body.card.text == null)
            }
        }

    /**
     * Une tâche, et une seule : relire la suite du fil toutes les deux
     * secondes, jouer ce qui arrive, s'arrêter dès qu'il n'y a plus rien à
     * attendre ou après trois minutes sans changement.
     */
    private fun startPolling() {
        if (poller != null) return
        poller = viewModelScope.launch {
            var quietTicks = 0
            while (isActive) {
                delay(POLLING_INTERVAL)
                if (!needsPolling) break

                try {
                    val update = transport.poll(cursor ?: distantPast)
                    ensureActive()
                    val changed = apply(update)
                    quietTicks = if (changed) 0 else quietTicks + 1
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Exception) {
                    // Un sondage qui rate n'est pas une erreur d'écran : on
                    // réessaie au tour suivant, et on renonce comme un fil
                    // silencieux.
                    quietTicks += 1
                }

                if (quietTicks >= POLLING_GIVES_UP_AFTER) break
            }
            if (poller == coroutineContext[Job]) poller = null
            // On renonce sans réponse : le composeur se rouvre, le fil ne ment
            // pas — MEMO n'a simplement pas répondu à temps.
            if (current.turn == ChatTurnState.Thinking) setTurn(ChatTurnState.Idle)
        }
    }

    /**
     * Fusionne la suite du fil. Les bulles d'un co-voyageur et les fiches mises
     * à jour entrent tout de suite ; les bulles de MEMO **une par une,
     * rythmées** par le silence que le serveur a décidé — c'est ce qui les fait
     * arriver comme une réponse et non comme un chargement.
     *
     * @return `true` si quelque chose a changé.
     */
    private suspend fun apply(update: ChatThreadUpdate): Boolean {
        cursor = update.now

        val arrivals = mutableListOf<ChatMessage>()
        var changed = false

        for (message in update.messages.sortedWith(byRank)) {
            if (messages.any { it.id == message.id }) {
                // Un message relu **à l'identique** ne change rien : le serveur
                // rend tout ce qui a bougé depuis le curseur, et une fiche qui
                // se rédige revient à chaque sondage. Réécrire le fil pour rien
                // redessinait toute la conversation toutes les deux secondes
                // (Hugo, 08/10/2026 : « mini latences, scroll pas toujours
                // fluide »), et repoussait la fin du sondage.
                if (replace(message)) changed = true
            } else if (message.author.isTraveller) {
                insert(message)
                changed = true
            } else {
                arrivals += message
            }
        }

        for (bubble in arrivals) {
            setTurn(ChatTurnState.Thinking)
            val pause = (bubble.pauseMilliseconds ?: 700).milliseconds
            delay(maxOf(pause, MINIMUM_THINKING))
            if (!currentCoroutineContext().isActive) return changed
            insert(bubble)
            changed = true
        }

        val preview = update.preview
        if (preview != null && preview != current.thread?.preview) changeThread { it.copy(preview = preview) }
        // Ce qu'un co-voyageur vient de raconter a pu entamer le pot commun. Le
        // chiffre servi ne compte pas ce qui est encore en route d'ici — un
        // vocal qui monte en 3G, un tour en file : [dailyCredit] le retire
        // toujours, la barre ne remonte pas d'autant.
        forgetCosts(update.messages)
        update.dailyCredit?.let { setServerCredit(it) }
        // Posé **après** les bulles : la pastille se remplit au moment où MEMO
        // dit ce qu'il a compris, pas avant qu'il l'ait dit.
        val tripContext = update.tripContext
        if (tripContext != null && tripContext != current.thread?.tripContext) {
            changeThread { it.copy(tripContext = tripContext) }
            changed = true
        }

        if (update.turn.isReplying) {
            setTurn(ChatTurnState.Thinking)
        } else if (current.turn == ChatTurnState.Thinking) {
            changeThread { it.copy(suggestions = update.suggestions) }
            setTurn(ChatTurnState.Idle)
        } else if (current.turn == ChatTurnState.Idle && update.suggestions.isNotEmpty() && update.suggestions != current.thread?.suggestions) {
            changeThread { it.copy(suggestions = update.suggestions) }
        }

        return changed
    }

    // MARK: - Le fil

    private fun merge(received: List<ChatMessage>) {
        for (message in received.sortedWith(byRank)) {
            if (messages.any { it.id == message.id }) replace(message) else insert(message)
        }
    }

    private fun insert(message: ChatMessage) {
        changeThread { thread ->
            var list = thread.messages
            // La bulle « reviens demain » du serveur remplace celle que l'app
            // avait posée hors ligne : une seule, et la vraie.
            if (message.callToAction?.id == ChatCallToAction.dailyCreditSubscribe.id) {
                list = list.filterNot { it.id.startsWith(localNoticePrefix) && it.id != message.id }
            }
            thread.copy(messages = (list + message).sortedWith(byRank))
        }
    }

    /**
     * Remplace par identifiant, en gardant ce que l'app seule sait : le fichier
     * local. L'état d'envoi, lui, est celui du serveur — un message qu'il rend
     * est un message qu'il a : une bulle restée « en cours d'envoi » parce
     * qu'on a raté le mot de la file se répare au sondage suivant.
     *
     * @return vrai si le message a changé. Un message identique ne touche pas
     *   au fil : l'écrire quand même invaliderait tout ce qui le lit.
     */
    private fun replace(message: ChatMessage): Boolean {
        val thread = current.thread ?: return false
        val index = thread.messages.indexOfFirst { it.id == message.id }
        if (index < 0) return false
        val merged = message.keepingLocalFiles(previous = thread.messages[index])
        if (merged == thread.messages[index]) return false
        val list = thread.messages.toMutableList().apply { set(index, merged) }
        change { copy(thread = thread.copy(messages = list.sortedWith(byRank))) }
        return true
    }

    // MARK: - « À la main »

    /**
     * La correction part au souvenir ; la fiche se redessine avec elle ; puis
     * une commande silencieuse fait accuser réception à MEMO — sans modèle,
     * sans souvenir de plus.
     *
     * **Un refus garde le brouillon** (03/10/2026) : le champ a été vidé à
     * l'envoi, et un `429` — un co-voyageur a raconté entre-temps — ou une
     * panne le remettent sous les doigts, tel qu'il était, avec la fiche qu'il
     * corrige. Jamais une correction tapée ne se perd parce que le serveur a
     * dit non.
     */
    private fun submitTranscriptEdit(entryId: String, text: String, original: String?, growthCost: Int = 0) {
        exchange?.cancel()
        setTurn(ChatTurnState.Sending(messageId = entryId))
        exchange = viewModelScope.launch {
            try {
                val entry = transport.editTranscript(entryId, text)
                ensureActive()
                refreshCard(entry)
                // Ce que la correction modifie au-delà des 200 offerts se paie,
                // comme un texte — et le serveur l'a déjà compté : c'est son
                // chiffre, pas une attente.
                val served = current.servedCredit
                if (growthCost > 0 && served != null) setServerCredit(served.refreshed(now = Instant.now()).consuming(growthCost))
                setTurn(ChatTurnState.Idle)
                send(OutgoingTurn.Body.Text(ChatCopy.editedByHand, suggestionId = "transcript_edited", entryId = entryId))
            } catch (error: CancellationException) {
                if (owns(entryId)) setTurn(ChatTurnState.Idle)
                throw error
            } catch (error: Exception) {
                val apiError = error as? ApiError
                if (apiError != null && apiError.isDailyCreditExhausted) exhaustCredit(apiError.dailyCredit)
                // Le brouillon revient — sauf si l'on s'est déjà remis à écrire.
                if (current.draft.isEmpty()) {
                    change {
                        copy(
                            draft = text,
                            editingEntryId = entryId,
                            editingOriginalText = original,
                            isEditingTranscript = true,
                            composer = ChatComposerMode.Writing,
                        )
                    }
                }
                change { copy(errorMessage = describe(error)) }
                setTurn(ChatTurnState.Idle)
            }
        }
    }

    /** La fiche d'un souvenir, une fois le serveur repassé dessus. */
    private fun refreshCard(entry: Entry) {
        changeThread { thread ->
            thread.copy(
                messages = thread.messages.map { message ->
                    val body = message.body
                    if (body !is ChatMessageBody.Transcript || body.card.entryId != entry.id) return@map message
                    val card = body.card
                    message.copy(
                        body = ChatMessageBody.Transcript(
                            TranscriptCard(
                                title = card.title,
                                capturedAt = entry.capturedAt,
                                placeLabel = entry.placeLabel ?: card.placeLabel,
                                duration = card.duration,
                                text = entry.displayText ?: card.text,
                                isSimulated = false,
                                entryId = entry.id,
                                footnote = card.footnote,
                                phase = TranscriptCard.Phase.Ready,
                                isValidated = entry.validatedAt != null || card.isValidated,
                                freeCorrectionCharactersLeft = entry.freeCorrectionCharactersLeft ?: card.freeCorrectionCharactersLeft,
                            ),
                        ),
                    )
                },
            )
        }
    }

    // MARK: - Le vocal

    /**
     * Le vocal enregistré depuis l'accueil, en attendant que le fil soit là
     * pour le recevoir. Voir [RecordingHandoff].
     */
    private var pendingHandoff: RecordingHandoff? = null

    /**
     * Annonce un vocal venu de l'accueil. Il sera posé dans le fil au
     * chargement, exactement comme s'il avait été dit ici : même bulle, même
     * forme d'onde.
     */
    fun expect(handoff: RecordingHandoff) {
        pendingHandoff = handoff
    }

    /**
     * Pose un vocal déjà enregistré, **sans l'envoyer** : il est parti avant
     * que cet écran n'existe, par la file de l'accueil, et c'est elle qui dira
     * où il en est — par [markDelivery]. Le fichier est gardé pour la réécoute.
     *
     * S'il est déjà dans le fil — le serveur l'a reçu avant qu'on ait fini de
     * charger —, la bulle du serveur reste, et ne gagne que le fichier local.
     */
    private fun receive(handoff: RecordingHandoff) {
        val file = runCatching { audio.voiceNotes.save(handoff.audio, id = handoff.id) }.getOrNull()
        if (file != null) localVoiceUrls[handoff.id] = file

        if (messages.any { it.id == handoff.id }) {
            if (file != null) rememberLocalUrl(file, voiceId = handoff.id)
            return
        }

        // Le serveur ne l'a pas encore compté : la barre le décompte d'avance.
        // Coupé par la limite, il a vidé le crédit — et sans réseau, aucun reçu
        // n'apportera la bulle de MEMO : l'app pose la sienne.
        val spent = (handoff.audio.duration * 1000).roundToInt()
        val cost = if (handoff.stoppedAtLimit) max(spent, current.servedCredit?.limitMs ?: spent) else spent
        change { copy(unreceivedCosts = unreceivedCosts + (handoff.id to cost)) }
        var postsNotice = false
        if (handoff.stoppedAtLimit) {
            limitTurnId = handoff.id
            if (current.isOffline) postsNotice = true
        }

        append(
            ChatMessage(
                id = handoff.id,
                author = ChatAuthor.Traveller,
                body = ChatMessageBody.Voice(
                    VoiceNote(id = handoff.id, duration = handoff.audio.duration, levels = handoff.levels, localUrl = file?.toURI()),
                ),
                sentAt = Instant.now(),
                stepId = activeStepId,
                delivery = ChatDelivery.Sending,
            ),
        )
        // Après la bulle du vocal, et pas avant : MEMO répond à ce qu'on a dit.
        if (postsNotice) {
            limitTurnId = null
            postLocalExhaustedNotice()
        }
    }

    /**
     * Ce que la file dit d'un tour — le vocal de l'accueil, ou un message d'ici
     * qui attendait le réseau. La bulle suit **la file**, pas l'écran : hors
     * ligne elle reste sur « envoi en cours », et c'est la reconnexion qui la
     * termine, par son identifiant.
     *
     * Arrivé, le tour a un reçu : les bulles que le serveur a écrites — la
     * sienne avec son rang, sa fiche — entrent dans le fil, et le sondage prend
     * la suite si MEMO répond. Un tour d'un autre voyage ne touche à rien ici.
     */
    fun markDelivery(delivery: ChatTurnDelivery) {
        latestDelivery = delivery
        val thread = current.thread ?: return
        if (delivery.tripId != thread.context.tripId) return
        // Parti, refusé ou en attente de crédit : plus « en attente du réseau ».
        if (delivery.state != ChatDelivery.Sending && delivery.id in current.queuedTurnIds) {
            change { copy(queuedTurnIds = queuedTurnIds - delivery.id) }
        }

        when (val state = delivery.state) {
            ChatDelivery.Sending -> mark(delivery.id, ChatDelivery.Sending)
            is ChatDelivery.Failed -> {
                forgetCost(delivery.id)
                mark(delivery.id, ChatDelivery.Failed(state.message))
            }
            ChatDelivery.WaitingForUnlimited -> {
                // Plus long qu'une journée : la bulle propose l'illimité. Le
                // crédit d'aujourd'hui n'est pas pour autant épuisé — le solde
                // rendu le dit.
                forgetCost(delivery.id)
                mark(delivery.id, ChatDelivery.WaitingForUnlimited)
                if (delivery.isReplay) {
                    takeReplayedCredit(delivery.credit)
                } else {
                    delivery.credit?.let { setServerCredit(it) }
                }
            }
            is ChatDelivery.WaitingForCredit -> {
                // Refusé faute de crédit : la bulle attend demain, la barre
                // passe à « épuisé », et la bulle « reviens demain » que le
                // serveur vient de poser se lit tout de suite. Rejoué à
                // l'ouverture d'un fil, le refus ne fait que se fondre dans ce
                // que le fil vient de lire.
                forgetCost(delivery.id)
                mark(delivery.id, ChatDelivery.WaitingForCredit(until = state.until))
                if (delivery.isReplay) takeReplayedCredit(delivery.credit) else exhaustCredit(delivery.credit)
                if (limitTurnId == delivery.id) {
                    limitTurnId = null
                    if (current.isOffline) postLocalExhaustedNotice()
                }
                if (!delivery.isReplay) refreshOnce()
            }
            ChatDelivery.Sent -> {
                val receipt = delivery.receipt
                if (receipt != null) {
                    accept(receipt, delivery.id, isReplay = delivery.isReplay)
                } else {
                    forgetCost(delivery.id)
                    mark(delivery.id, ChatDelivery.Sent)
                }
                // Un message est arrivé : le serveur répond, et il connaît le
                // voyage. Le fil local cède la place au vrai. Pas sur un mot
                // rejoué : il date d'avant la lecture qui vient d'échouer.
                if (current.isOffline && !delivery.isReplay) reloadFromServer()
            }
        }
    }

    /**
     * Relit le fil du serveur après un fil local. Une fois à la fois : trois
     * tours qui arrivent ensemble au retour du réseau ne font qu'une lecture.
     */
    private fun reloadFromServer() {
        if (isReloading) return
        isReloading = true
        viewModelScope.launch {
            try {
                load()
            } finally {
                isReloading = false
            }
        }
    }

    /**
     * Écrit dans les caches les fichiers d'un tour relu du disque de la file,
     * pour que sa bulle se réécoute et se regarde comme celle d'un tour dit ici.
     */
    private fun keepLocalFiles(turn: OutgoingTurn) {
        when (val body = turn.body) {
            is OutgoingTurn.Body.Text -> Unit
            is OutgoingTurn.Body.Voice -> {
                if (localVoiceUrls[turn.id] != null) return
                val recorded = RecordedAudio(
                    data = body.audio.data,
                    filename = body.audio.filename,
                    mimeType = body.audio.mimeType,
                    duration = body.audio.durationSeconds,
                    recordedAt = body.audio.capturedAt,
                )
                runCatching { audio.voiceNotes.save(recorded, id = turn.id) }.getOrNull()?.let { localVoiceUrls[turn.id] = it }
            }
            is OutgoingTurn.Body.Photos -> body.photos.forEachIndexed { index, photo ->
                val id = "${turn.id}-$index"
                if (localPhotoUrls[id] != null) return@forEachIndexed
                runCatching { ChatPhotoFile.save(audio.cacheDirectory, photo.data, id) }.getOrNull()?.let { localPhotoUrls[id] = it }
            }
        }
    }

    fun startRecording() {
        // Plus de crédit aujourd'hui : ni micro, ni niveaux, ni permission
        // demandée pour rien — le bandeau dit pourquoi.
        if (isCreditExhausted) {
            showExhaustedNotice()
            return
        }
        if (recorder.isRecording) return

        viewModelScope.launch {
            try {
                recorder.start()
                if (current.microphoneIsDenied) change { copy(microphoneIsDenied = false) }
                lastRecordingPhase = DailyCredit.Phase.Calm
                startSamplingLevels()
            } catch (error: CancellationException) {
                throw error
            } catch (_: RecordingError.PermissionDenied) {
                change { copy(microphoneIsDenied = true) }
            } catch (error: Exception) {
                change { copy(errorMessage = describe(error)) }
            }
        }
    }

    fun finishRecording() {
        finishRecording(atLimit = false)
    }

    /** @param atLimit c'est la limite du jour qui coupe, pas le voyageur — voir [stopAtLimit]. */
    private fun finishRecording(atLimit: Boolean) {
        levelSampler?.cancel()
        val levels = mutableCapturedLevels.value

        try {
            val recorded = recorder.stop() ?: return
            val id = newId()
            if (atLimit) limitTurnId = id

            // `AudioRecorder.stop()` efface son fichier temporaire et ne rend
            // que des octets : sans cette écriture, le vocal ne serait plus
            // réécoutable une seconde après l'avoir dit.
            runCatching { audio.voiceNotes.save(recorded, id = id) }.getOrNull()?.let { localVoiceUrls[id] = it }

            composer = composerAfterRecording()
            send(
                OutgoingTurn.Body.Voice(
                    RecordedTurnAudio(
                        data = recorded.data,
                        filename = recorded.filename,
                        mimeType = recorded.mimeType,
                        capturedAt = recorded.recordedAt,
                        durationSeconds = recorded.duration,
                        levels = levels,
                        placeLabel = current.thread?.context?.placeName,
                    ),
                ),
                id = id,
            )
        } catch (error: Exception) {
            change { copy(errorMessage = describe(error)) }
        }
    }

    fun pauseRecording() {
        recorder.pause()
        levelSampler?.cancel()
    }

    fun resumeRecording() {
        recorder.resume()
        startSamplingLevels(resetting = false)
    }

    fun cancelRecording() {
        levelSampler?.cancel()
        mutableCapturedLevels.value = emptyList()
        recorder.cancel()
        composer = composerAfterRecording()
    }

    /**
     * Onze relevés par seconde : assez pour dessiner le grain d'une voix, assez
     * peu pour qu'un vocal de trois minutes reste un tableau de deux mille
     * valeurs.
     *
     * La même boucle **guette le crédit du jour** : c'est elle qui fait vibrer
     * le bandeau à son apparition et qui coupe net à zéro — voir
     * [watchCredit]. 90 ms de grain : le serveur tolère trois secondes au-delà
     * du reste (`VOICE_TOLERANCE_MS`), la coupure tombe bien avant.
     */
    private fun startSamplingLevels(resetting: Boolean = true) {
        if (resetting) mutableCapturedLevels.value = emptyList()
        levelSampler?.cancel()
        levelSampler = viewModelScope.launch {
            while (isActive) {
                delay(90)
                if (!recorder.isRecording || recorder.isPaused) return@launch
                mutableCapturedLevels.value = mutableCapturedLevels.value + recorder.level
                watchCredit()
            }
        }
    }

    /**
     * Ce que le crédit du jour fait à l'enregistrement en cours, à chaque
     * relevé : un léger retour haptique et une annonce TalkBack quand le
     * bandeau paraît (30 s), un second quand il se met à pulser (5 s), et
     * l'**arrêt net** à zéro. Rien pour un abonné, rien sans crédit connu.
     */
    private fun watchCredit() {
        val credit = credit ?: return
        if (credit.isUnlimited || !recorder.isCapturing) return
        val remaining = credit.remainingMs(whileRecording = recorder.elapsedMilliseconds)
        val phase = credit.phase(remainingMs = remaining)
        if (phase == lastRecordingPhase) return
        lastRecordingPhase = phase

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
     * **L'arrêt net**, à zéro (Hugo, 03/10/2026) : ce qui a été dit **part** —
     * jamais on ne jette la fin d'un récit parce que la minute est passée. Le
     * serveur répond avec sa bulle « reviens demain » dans le reçu ; hors
     * ligne, l'app pose la sienne ([postLocalExhaustedNotice]).
     */
    private fun stopAtLimit() {
        if (!recorder.isRecording) return
        onFeedback?.invoke(Feedback.Warning)
        onAnnouncement?.invoke(ChatCopy.Credit.stoppedAnnouncement)
        finishRecording(atLimit = true)
    }

    // MARK: - Les commandes d'un message

    /**
     * Joue un vocal. Le fichier local d'abord ; sinon le serveur le sert **avec
     * la session** — une URL nue ne suffirait pas —, et on le garde dans les
     * caches pour la fois suivante.
     */
    fun togglePlayback(note: VoiceNote) {
        audio.stopReading()

        cachedAudio(note)?.let { file ->
            play(note.id, file)
            return
        }

        if (note.remoteUrl == null) {
            change { copy(errorMessage = MemoResponderError.TranscriptionUnavailable.errorDescription) }
            return
        }

        viewModelScope.launch {
            val file = downloadAudio(note)
            if (file == null) {
                change { copy(errorMessage = MemoResponderError.TranscriptionUnavailable.errorDescription) }
                return@launch
            }
            rememberLocalUrl(file, voiceId = note.id)
            play(note.id, file)
        }
    }

    /**
     * Le fichier d'un vocal déjà sur l'appareil : celui de la bulle, celui
     * qu'on a écrit pendant cette session, ou celui qu'une session d'avant a
     * laissé dans les caches.
     */
    private fun cachedAudio(note: VoiceNote): File? =
        note.localUrl?.let(::fileOf)?.takeIf { it.exists() } ?: localVoiceUrls[note.id] ?: audio.voiceNotes.existing(note.id)

    /** Descend le vocal du serveur et l'écrit dans les caches. `null` si le serveur ne le rend pas. */
    private suspend fun downloadAudio(note: VoiceNote): File? {
        val remote = note.remoteUrl ?: return null
        return try {
            val data = transport.media(remote)
            val recorded = RecordedAudio(
                data = data,
                filename = "${note.id}.m4a",
                mimeType = "audio/mp4",
                duration = note.duration,
                recordedAt = Instant.now(),
            )
            withContext(io) { audio.voiceNotes.save(recorded, id = note.id) }.also { localVoiceUrls[note.id] = it }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            null
        }
    }

    // MARK: - La forme d'onde d'un vocal qui n'en a pas

    private val derivingLevels = mutableSetOf<String>()

    /**
     * Ce que la bulle dessine : le relevé du serveur, sinon celui qu'on a relu
     * dans le fichier, sinon rien — la ligne plate, le temps de le relire.
     */
    fun levels(note: VoiceNote): List<Double> =
        note.levels.ifEmpty { current.derivedLevels[note.id] ?: emptyList() }

    /**
     * Relit la forme d'onde d'un vocal qui n'en a pas (Hugo, 30/09/2026 : les
     * vocaux des voyages passés n'avaient plus qu'une ligne plate). Une fois par
     * vocal et par écran ; le fichier descendu sert ensuite à l'écoute.
     */
    suspend fun deriveLevelsIfNeeded(note: VoiceNote) {
        if (note.levels.isNotEmpty() || current.derivedLevels.containsKey(note.id) || note.id in derivingLevels) return

        derivingLevels += note.id
        try {
            val file = cachedAudio(note) ?: downloadAudio(note) ?: return
            val levels = VoiceLevels.read(file)
            if (levels.isEmpty()) return
            change { copy(derivedLevels = derivedLevels + (note.id to levels)) }
        } finally {
            derivingLevels -= note.id
        }
    }

    // MARK: - Les images du fil

    /**
     * Les images du fil — les portraits des vocaux, les photos —, chargées
     * **par le modèle** et non par un `AsyncImage` dans la bulle.
     *
     * Deux raisons, vues dans les journaux de Railway le 30/09/2026. **Les
     * annulations** : le fil se recompose en s'ouvrant — il relit, fusionne,
     * anime — et chaque recomposition recréait les `AsyncImage` des bulles ;
     * leurs requêtes partaient annulées en 5 ms (des `499`) et le rond restait
     * sur ses initiales pour de bon. **La session** : une photo du voyage se
     * sert par `/v1/entries/:id/media`, qui la demande, et un `AsyncImage`
     * n'envoie aucun en-tête — des `401`, et la bulle restait sur sa trame.
     * Ici, une requête par adresse, qui survit aux recompositions, par le bon
     * chemin, et un résultat gardé tant que l'écran est ouvert.
     *
     * **Une case observée par image**, et non un dictionnaire observé
     * (08/10/2026) : chaque image arrivée réécrivait le dictionnaire entier, et
     * toutes les bulles qui en lisaient une — photos, portraits — se
     * redessinaient à chaque arrivée, pendant qu'on faisait défiler le fil. Une
     * bulle ne collecte plus que la case de **son** image.
     */
    private val imageSlots = mutableMapOf<URI, ChatImageSlot>()
    private val loadingImages = mutableSetOf<URI>()

    /** L'image chargée à cette adresse, ou `null` tant qu'elle ne l'est pas. Collectée par la bulle : seule l'arrivée de **cette** image la redessine. */
    fun image(url: URI): StateFlow<ImageBitmap?> = slot(url).image

    private fun slot(url: URI): ChatImageSlot = imageSlots.getOrPut(url) { ChatImageSlot() }

    /** Charge une image du fil, une fois. Un échec n'est pas retenu : la bulle garde sa trame ou ses initiales, et redemande en réapparaissant. */
    fun loadImage(url: URI) {
        val slot = slot(url)
        if (slot.image.value != null || url in loadingImages) return
        loadingImages += url

        viewModelScope.launch {
            try {
                val data = imageData(url)
                val image = data?.let { withContext(io) { imageDecoder.decode(it, ChatImage.maximumPixelSize) } }
                if (image != null) slot.mutableImage.value = image
            } finally {
                loadingImages -= url
            }
        }
    }

    // MARK: La photo en plein écran

    /** Ouvre les photos d'une bulle, sur celle qu'on a touchée. */
    fun viewPhotos(attachments: List<PhotoAttachment>, index: Int) {
        if (index !in attachments.indices) return
        viewedPhotos = ChatPhotoViewing(attachments, index)
    }

    /**
     * La photo **à sa taille d'écran**, et non la vignette du fil : relue par
     * le même chemin ([imageData]), décodée plus grand. La vignette reste en
     * cache pour le fil ; celle-ci vit avec la vue qui la montre.
     */
    suspend fun fullScreenImage(url: URI): ImageBitmap? {
        val data = imageData(url) ?: return null
        return withContext(io) { imageDecoder.decode(data, ChatImage.fullScreenPixelSize) }
    }

    /**
     * Les octets d'une image, par le chemin qu'elle demande : le disque pour
     * une photo qui vient d'être choisie ; **le transport, avec la session**,
     * pour un média du voyage (`…/media`) — comme l'écoute d'un vocal ; une
     * requête nue pour un avatar (`GET /v1/avatars/:file`), servi sans session
     * parce qu'il se montre à ceux qui partagent le voyage.
     */
    private suspend fun imageData(url: URI): ByteArray? = try {
        when {
            url.scheme == "file" -> withContext(io) { readFile(url) }
            url.path.orEmpty().substringAfterLast('/') == "media" -> transport.media(url)
            else -> withContext(io) { url.toURL().readBytes() }
        }
    } catch (error: CancellationException) {
        throw error
    } catch (_: Exception) {
        null
    }

    private fun play(id: String, file: File) {
        try {
            player.toggle(id, file)
        } catch (error: Exception) {
            change { copy(errorMessage = describe(error)) }
        }
    }

    private fun rememberLocalUrl(file: File, voiceId: String) {
        changeThread { thread ->
            thread.copy(
                messages = thread.messages.map { message ->
                    val body = message.body
                    if (body is ChatMessageBody.Voice && body.note.id == voiceId) {
                        message.copy(body = ChatMessageBody.Voice(body.note.copy(localUrl = file.toURI())))
                    } else {
                        message
                    }
                },
            )
        }
    }

    fun toggleReading(message: ChatMessage) {
        val text = message.spokenText ?: return
        player.stop()
        reader.toggle(message.id, text)
    }

    /**
     * Copie le message. Le retour est un retour haptique et non une alerte : on
     * ne pose pas une fenêtre pour dire qu'un texte est dans le presse-papiers.
     */
    fun copy(message: ChatMessage) {
        val text = message.spokenText ?: return
        onCopy?.invoke(text)
        onFeedback?.invoke(Feedback.Success)

        // La coche verte prend la place de l'icône pendant une seconde. Une
        // seconde parce que c'est le temps qu'il faut pour la voir sans qu'elle
        // devienne un état : au-delà, on se demande si elle attend un second
        // geste.
        val id = message.id
        change { copy(copiedMessageId = id) }
        viewModelScope.launch {
            delay(1.seconds)
            if (current.copiedMessageId == id) change { copy(copiedMessageId = null) }
        }
    }

    /**
     * Poste les photos choisies.
     *
     * Les images sont écrites dans les caches avant d'entrer dans le fil : une
     * bulle qui garderait ses octets en mémoire ferait grossir la conversation
     * à chaque photo, et les perdrait au premier passage en arrière-plan.
     */
    fun sendPhotos(images: List<ByteArray>) {
        if (images.isEmpty()) return
        hideExhaustedNotice()
        val id = newId()

        val uploads = mutableListOf<ChatPhotoUpload>()
        images.take(ChatMetrics.visiblePhotoCount).forEachIndexed { index, data ->
            val photoId = "$id-$index"
            val file = runCatching { ChatPhotoFile.save(audio.cacheDirectory, data, photoId) }.getOrNull() ?: return@forEachIndexed
            localPhotoUrls[photoId] = file
            uploads += ChatPhotoUpload(data = data, filename = "$photoId.jpg", mimeType = "image/jpeg")
        }

        if (uploads.isEmpty()) {
            change { copy(errorMessage = ChatCopy.photosUnreadable) }
            return
        }

        composer = ChatComposerMode.Tools
        send(OutgoingTurn.Body.Photos(uploads, capturedAt = Instant.now()), id = id)
    }

    /**
     * « Modifier » : le texte revient dans le champ de saisie, le clavier
     * s'ouvre. Sur une fiche, c'est « à la main » sans la puce : envoyer
     * corrige le souvenir. Sur une bulle de texte, c'est un nouveau message.
     */
    fun edit(message: ChatMessage) {
        val text = message.spokenText ?: return
        hideExhaustedNotice()
        val body = message.body
        change {
            if (body is ChatMessageBody.Transcript) {
                copy(draft = text, isEditingTranscript = true, editingEntryId = body.card.entryId, editingOriginalText = text)
            } else {
                copy(draft = text)
            }
        }
        composer = ChatComposerMode.Writing
    }

    // MARK: - Le bouton sous une bulle de MEMO

    /**
     * Le bouton d'une bulle se montre-t-il ? Jamais pour un genre que cette
     * version ne sait pas ouvrir ; et « s'abonner » pas à qui l'est déjà — le
     * serveur le taira à la prochaine lecture, l'écran n'attend pas.
     */
    fun showsCallToAction(callToAction: ChatCallToAction?): Boolean {
        if (callToAction == null || !callToAction.kind.isSupported) return false
        if (callToAction.kind == ChatCallToAction.Kind.Subscribe &&
            (credit?.isUnlimited == true || subscription?.isUnlimited == true)
        ) {
            return false
        }
        return true
    }

    /** Où en est le bouton d'une bulle : rien encore, touché, ignoré. */
    fun callToActionState(messageId: String): ChatCallToActionState =
        current.callToActionStates[messageId] ?: callToActionMemory.state(messageId)

    /**
     * Le bouton a été touché — l'écran a ouvert ce qu'il ouvre. Il passe au
     * bleu, « Ignorer » s'en va, et c'est retenu.
     */
    fun followCallToAction(messageId: String) {
        remember(ChatCallToActionState.Followed, messageId)
    }

    /** « Ignorer » : le bouton et « Ignorer » s'en vont, la bulle redevient une bulle — et le reste. */
    fun dismissCallToAction(messageId: String) {
        remember(ChatCallToActionState.Dismissed, messageId)
    }

    private fun remember(state: ChatCallToActionState, messageId: String) {
        change { copy(callToActionStates = callToActionStates + (messageId to state)) }
        callToActionMemory.remember(state, messageId)
    }

    // MARK: - Supprimer un tour qui attend l'illimité

    /**
     * « Supprimer », sous une bulle « Trop long pour une journée », une fois
     * confirmé (03/10/2026) : sans abonnement, rien ne la ferait jamais partir.
     * Le tour quitte la file — fiche et fichiers — et la bulle le fil. Jamais
     * une autre bulle : un tour qui part, ou qui attend le réseau, ne se
     * supprime pas d'ici.
     */
    fun discardWaitingTurn(id: String) {
        val message = messages.firstOrNull { it.id == id } ?: return
        if (!message.delivery.isWaitingForUnlimited) return
        changeThread { thread -> thread.copy(messages = thread.messages.filterNot { it.id == id }) }
        forgetCost(id)
        if (pending?.id == id) pending = null
        val discard = transport.discard
        viewModelScope.launch { discard(id) }
    }

    // MARK: - La bulle « reviens demain », hors ligne

    /**
     * Pose la bulle « reviens demain » **sans le serveur** : la limite vient de
     * couper un vocal parti dans la file, et aucun reçu n'apportera celle de
     * MEMO. Le même texte et le même bouton que le serveur
     * ([DailyCreditCopy.exhaustedMessage], [ChatCallToAction.dailyCreditSubscribe]) ;
     * **jamais gardée** — le vrai fil la remplace au retour du réseau, et la
     * bulle du serveur la chasse dès qu'elle arrive ([insert]).
     *
     * Une par jour : l'identifiant porte le jour du crédit, pour qu'un
     * « Ignorer » d'hier ne fasse pas disparaître le bouton de demain.
     */
    private fun postLocalExhaustedNotice() {
        if (current.thread == null || hasExhaustedNoticeToday) return
        val day = credit?.day ?: localDay(Instant.now())
        append(
            ChatMessage(
                id = localNoticePrefix + day,
                author = ChatAuthor.Memo,
                body = ChatMessageBody.Text(DailyCreditCopy.exhaustedMessage),
                sentAt = Instant.now(),
                callToAction = ChatCallToAction.dailyCreditSubscribe,
            ),
        )
    }

    /** Le fil porte déjà une bulle « reviens demain » d'aujourd'hui. */
    private val hasExhaustedNoticeToday: Boolean
        get() {
            val today = LocalDate.now(ZoneId.systemDefault())
            return messages.any {
                it.callToAction?.id == ChatCallToAction.dailyCreditSubscribe.id &&
                    it.sentAt.atZone(ZoneId.systemDefault()).toLocalDate() == today
            }
        }

    /**
     * Une lecture de la suite du fil, hors du sondage : après un refus de
     * crédit (la bulle de MEMO vient d'être posée), après un achat (le crédit
     * devient illimité). Rien hors ligne, rien si le sondage tourne déjà.
     */
    private fun refreshOnce() {
        if (current.isOffline || poller != null || current.thread == null) return
        viewModelScope.launch {
            val update = try {
                transport.poll(cursor ?: distantPast)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                return@launch
            }
            apply(update)
        }
    }

    /**
     * La fiche que visent les puces de validation — le trio « Ça me convient /
     * à la main / à l'oral » : celle dont MEMO vient de demander « Il te
     * convient ? » quand il le dit ([ChatMessage.entryId] — il revient parfois
     * à une étape sautée, 12/10/2026), sinon la dernière fiche remplie du fil.
     * La dernière et non la première : on corrige ce qu'on vient d'entendre,
     * pas la fiche d'hier.
     */
    private val latestTranscriptCard: TranscriptCard?
        get() {
            val asked = messages.lastOrNull { it.author == ChatAuthor.Memo && it.entryId != null }?.entryId
            var latest: TranscriptCard? = null
            for (message in messages.asReversed()) {
                val body = message.body as? ChatMessageBody.Transcript ?: continue
                if (body.card.text.isNullOrEmpty()) continue
                if (asked == null || body.card.entryId == asked) return body.card
                latest = latest ?: body.card
            }
            return latest
        }

    // MARK: -

    private fun append(message: ChatMessage) {
        changeThread { it.copy(messages = it.messages + message) }
    }

    private fun mark(id: String, delivery: ChatDelivery) {
        val thread = current.thread ?: return
        val index = thread.messages.indexOfFirst { it.id == id }
        if (index < 0 || thread.messages[index].delivery == delivery) return
        val list = thread.messages.toMutableList().apply { set(index, get(index).copy(delivery = delivery)) }
        change { copy(thread = thread.copy(messages = list)) }
    }

    companion object {
        /**
         * Le début de l'identifiant d'une bulle « reviens demain » posée par
         * l'app — jamais par le serveur, qui tire des UUID.
         */
        const val localNoticePrefix = "local-daily-credit-"

        /** Le `.distantPast` d'iOS : avant tout curseur que le serveur rendra. */
        internal val distantPast: Instant = Instant.parse("0001-01-01T00:00:00Z")

        /**
         * Le silence minimal avant une bulle de MEMO. Sans lui, une réponse
         * arriverait dans la même image que le message du voyageur : c'est le
         * premier signe qu'il n'y a personne en face.
         */
        private val MINIMUM_THINKING = 450.milliseconds

        /**
         * La cadence du sondage, et le moment où il renonce : le motif de la
         * feuille Statistiques — pas de connexion ouverte, pas de minuterie
         * globale, une tâche qui meurt avec l'écran.
         */
        private val POLLING_INTERVAL = 2.seconds
        private const val POLLING_GIVES_UP_AFTER = 90 // × 2 s = trois minutes sans changement

        /** Sous une minute de crédit, le champ rappelle ce qu'il reste. */
        private const val CHARACTER_REMINDER_BELOW_MS = 60_000

        /** L'ordre du serveur d'abord ; ce qui n'en a pas encore — une bulle optimiste — reste en bas, où il est. */
        private val byRank: Comparator<ChatMessage> = compareBy { it.seq ?: Int.MAX_VALUE }

        /**
         * Le dernier crédit **servi** de chaque voyage, le temps que l'app vive :
         * un fil rouvert sans réseau dans le métro garde de quoi compter, au
         * lieu de laisser parler sans limite jusqu'à un refus. En mémoire
         * seulement, et jamais une estimation (`servedCredit`) : ce qui attend
         * dans la file se redécompte à chaque ouverture, depuis ce chiffre-ci.
         *
         * **Il appartient au compte qui l'a lu** (03/10/2026) : il porte son
         * `isUnlimited`. Oublié à chaque changement de compte —
         * [forgetRememberedCredits] —, sans quoi le fil hors ligne de B,
         * connecté après A sur le même téléphone, se croyait illimité et
         * apprenait à la session un abonnement que B n'a jamais pris.
         */
        private val rememberedCredits = mutableMapOf<String, DailyCredit>()

        private fun rememberedCredit(tripId: String): DailyCredit? = synchronized(rememberedCredits) { rememberedCredits[tripId] }

        private fun rememberCredit(credit: DailyCredit, tripId: String) {
            synchronized(rememberedCredits) { rememberedCredits[tripId] = credit }
        }

        /**
         * Oublie le dernier crédit servi de chaque voyage — à chaque changement
         * de compte, avec ce que l'app garde du compte qui s'en va
         * (`AppDependencies.forgetAccountContent()`), là même où la session
         * d'abonnement est remise à zéro.
         */
        fun forgetRememberedCredits() {
            synchronized(rememberedCredits) { rememberedCredits.clear() }
        }

        /**
         * Ce qui attend le crédit de demain, ou l'illimité, le dit dès
         * l'ouverture du fil. Une attente **échue** — refusé hier soir, rouvert
         * ce matin — ne dit plus « Partira demain » : le tour partira à la
         * reconnexion, il est « en cours d'envoi » (03/10/2026).
         */
        private fun delivery(outgoing: OutgoingTurn): ChatDelivery {
            if (outgoing.waitingForUnlimited) return ChatDelivery.WaitingForUnlimited
            val until = outgoing.waitingForCreditUntil
            if (outgoing.isWaitingForCredit() && until != null) return ChatDelivery.WaitingForCredit(until = until)
            return ChatDelivery.Sending
        }

        /** `AAAA-MM-JJ`, le jour local — le format du `day` du serveur. */
        private fun localDay(date: Instant): String {
            val day = date.atZone(ZoneId.systemDefault()).toLocalDate()
            return String.format(Locale.ROOT, "%04d-%02d-%02d", day.year, day.monthValue, day.dayOfMonth)
        }

        private fun newId(): String = UUID.randomUUID().toString().lowercase()

        private fun fileOf(url: URI): File? = runCatching { File(url) }.getOrNull()

        private fun readFile(url: URI): ByteArray? = fileOf(url)?.takeIf { it.isFile }?.let { runCatching { it.readBytes() }.getOrNull() }

        /**
         * La phrase d'un échec, à montrer telle quelle — le `localizedDescription`
         * d'iOS. Les erreurs de l'API et de l'enregistrement portent déjà la
         * leur ; une autre, sans phrase, prend celle de MEMO injoignable.
         */
        internal fun describe(error: Throwable): String =
            (error as? ApiError)?.errorDescription ?: error.message ?: MemoResponderError.Unreachable.errorDescription

        /**
         * Une conversation déjà remplie, pour les aperçus. Dans le fichier du
         * modèle, parce que l'état ne s'ouvre qu'ici.
         *
         * @param dailyCredit le crédit du jour ; à défaut, celui du fil.
         * @param showsExhaustedNotice le bandeau « épuisé » est déjà demandé.
         * @param creditBanner le bandeau à montrer comme si le micro tournait —
         *   un aperçu n'enregistre pas.
         */
        internal fun preview(
            thread: ChatThread,
            audio: ChatAudio,
            turn: ChatTurnState = ChatTurnState.Idle,
            composer: ChatComposerMode = ChatComposerMode.Tools,
            draft: String = "",
            microphoneIsDenied: Boolean = false,
            focusStepId: String? = null,
            dailyCredit: DailyCredit? = null,
            showsExhaustedNotice: Boolean = false,
            creditBanner: DailyCreditBanner? = null,
        ): ChatModel {
            // Le fil de l'aperçu est celui qu'on lui donne, même relu : l'écran
            // recharge en s'ouvrant, et le jeu d'essai du voyage remplacerait
            // l'état qu'on voulait montrer — le crédit épuisé, le tour trop long.
            val shown = thread.copy(dailyCredit = dailyCredit ?: thread.dailyCredit)
            val model = ChatModel(
                transport = ChatTransport.local(tripId = thread.id, box = PreviewChatBox()).copy(load = { shown }),
                audio = audio,
                focusStepId = focusStepId,
                callToActionMemory = ChatCallToActionMemory.inMemory(),
            )
            model.current = model.current.copy(
                thread = thread,
                turn = turn,
                composer = composer,
                draft = draft,
                microphoneIsDenied = microphoneIsDenied,
                servedCredit = dailyCredit ?: thread.dailyCredit,
                showsExhaustedNotice = showsExhaustedNotice,
            )
            model.previewCreditBanner = creditBanner
            return model
        }
    }
}
