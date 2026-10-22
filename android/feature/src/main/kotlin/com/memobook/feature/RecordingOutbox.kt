package com.memobook.feature

import com.memobook.core.ChatDelivery
import com.memobook.core.ChatPhotoUpload
import com.memobook.core.ChatTurnReceipt
import com.memobook.core.ChatTurnStatus
import com.memobook.core.CreatedTrip
import com.memobook.core.DailyCredit
import com.memobook.core.HomeFeed
import com.memobook.core.Trip
import com.memobook.core.TripDraft
import com.memobook.core.local
import com.memobook.feature.chat.ChatTurnDelivery
import com.memobook.feature.chat.OutgoingTurn
import com.memobook.feature.chat.RecordedTurnAudio
import com.memobook.networking.ApiError
import com.memobook.networking.Connectivity
import com.memobook.recording.PendingRecordingStore
import com.memobook.recording.PendingTurn
import com.memobook.recording.RecordedAudio
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.consumeAsFlow
import kotlinx.coroutines.flow.onCompletion
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import kotlin.coroutines.ContinuationInterceptor

/**
 * La file de départ de ce qu'on raconte : ce qui garantit qu'un souvenir dit
 * hors ligne finit dans le carnet. Jumeau de `RecordingOutbox.swift`.
 *
 * **Elle vit au-dessus des écrans**, dans [AppDependencies], et pas dans
 * `HomeModel` : un envoi commencé depuis l'accueil doit se terminer même si on
 * file dans son profil pendant ce temps, et un vocal mis de côté dans le métro
 * doit repartir tout seul à la sortie, quel que soit l'écran affiché.
 *
 * **Tout ce qu'on dit passe par elle** — le vocal de l'accueil comme un texte,
 * un vocal ou des photos envoyés depuis la conversation (`docs/
 * conversation.md` § 9). Un tour est un [OutgoingTurn] : il porte
 * l'identifiant que le serveur reprendra, donc un tour parti deux fois n'est
 * jamais dans le fil deux fois.
 *
 * **Et les voyages créés hors ligne** (Hugo, 01/10/2026) : on crée un voyage
 * dans l'avion, on l'ouvre, on y raconte, et tout part à l'atterrissage. Le
 * voyage passe **avant** ce qu'on y a dit — un vocal envoyé à un carnet que le
 * serveur ne connaît pas encore serait refusé (404) et perdu. Voir [saveTrip].
 *
 * **Et le crédit du jour** (Hugo, 03/10/2026) : un `429
 * daily_credit_exhausted` n'est pas un refus définitif. Le tour reste sur le
 * disque, marqué « attend le crédit » jusqu'à l'heure où il se recharge
 * (`PendingTurn.waitingForCreditUntil`), puis repart tout seul ; sa bulle dit
 * « Partira demain » ([ChatDelivery.WaitingForCredit]). Un tour qui coûte
 * **plus qu'une journée entière** — ou que le serveur refuse en
 * `daily_credit_too_long` — n'attend pas demain, qui ne changerait rien : il
 * attend l'illimité (`PendingTurn.waitingForUnlimited`). Et tout ce qui est
 * retenu repart dès que le compte passe en illimité ([releaseCreditHolds]) —
 * ou se supprime, si la personne le demande depuis sa bulle ([discardTurn]).
 *
 * Elle tient trois choses, et rien d'autre :
 *
 * 1. **l'état du réseau** ([Connectivity]), pour savoir s'il faut essayer ;
 * 2. **la file sur le disque** ([PendingRecordingStore] pour les tours,
 *    [PendingTripStore] pour les voyages), pour que ce qui n'est pas parti
 *    survive à la fermeture de l'app ;
 * 3. **l'envoi lui-même**, une fonction qui rend le reçu du serveur — elle ne
 *    connaît pas `MemoBookApi`, comme les modèles d'écran ne connaissent pas
 *    leur route.
 *
 * **Sur Android, un envoi survit à l'arrière-plan** — c'est ce qui manquait à
 * iOS, où ce qui n'avait pas eu le temps de partir attendait le retour dans
 * l'app. Chaque fois qu'un tour ou un voyage se met à attendre, [onPending]
 * planifie un travail de WorkManager sous la contrainte « réseau connecté »
 * ([RecordingOutboxWorker]), qui vide la file même app fermée.
 *
 * Confinée au fil principal, comme son jumeau l'est au `MainActor` : son état
 * se lit dans des `StateFlow`, ses fonctions suspendues y reviennent d'elles-
 * mêmes, ses fonctions ordinaires s'appellent depuis lui.
 *
 * @param scope la portée de l'app entière — celle d'[AppDependencies] : un
 *   envoi lancé ici survit à l'écran qui l'a demandé. Son répartiteur est
 *   celui où la file vit.
 * @param onPending un tour ou un voyage vient de se mettre à attendre :
 *   planifier le vidage en arrière-plan — au retour du réseau (`null`), ou à
 *   l'heure où le crédit du jour se recharge. Rien par défaut — les tests,
 *   les aperçus.
 */
class RecordingOutbox(
    private val store: PendingRecordingStore = PendingRecordingStore.temporary(),
    private val trips: PendingTripStore = PendingTripStore.temporary(),
    private val connectivity: Connectivity = Connectivity.online,
    private val send: suspend (OutgoingTurn, String) -> ChatTurnReceipt = { _, _ ->
        ChatTurnReceipt(messages = emptyList(), turn = ChatTurnStatus.Idle, now = Instant.now())
    },
    private val createTrip: suspend (TripDraft) -> CreatedTrip = { draft ->
        CreatedTrip(trip = Trip.local(draft, id = draft.id ?: UUID.randomUUID().toString().lowercase()), accessCode = "JHKFDA")
    },
    private val scope: CoroutineScope,
    private val onPending: (until: Instant?) -> Unit = {},
) {
    /** Ce qu'il est advenu d'un tour qu'on vient de confier. */
    sealed interface Delivery {
        /**
         * Il est arrivé, et voici ce que le serveur a écrit. Sans reçu quand
         * l'appel a abouti mais que sa réponse n'a pas pu se lire — le tour est
         * bien là-bas, on ne le renvoie pas.
         */
        data class Delivered(val receipt: ChatTurnReceipt?) : Delivery

        /**
         * Il attend le réseau, sur le disque. Ce n'est **pas** un échec : la
         * boîte d'information de l'accueil le dit, il n'y a rien à faire.
         *
         * C'est aussi ce que rend un tour que le serveur a refusé **faute de
         * crédit du jour** : il attend sur le disque, comme sous un tunnel,
         * seulement plus longtemps — jusqu'à minuit, ou jusqu'à l'illimité
         * s'il est plus long qu'une journée. La différence voyage par
         * [turnDeliveries] ([ChatDelivery.WaitingForCredit],
         * [ChatDelivery.WaitingForUnlimited]) — un cas de plus ici aurait
         * obligé chaque appelant à le traiter pour faire la même chose.
         */
        data object Queued : Delivery

        /** Le serveur a dit non, et le redire ne changerait rien. */
        data class Rejected(val message: String) : Delivery
    }

    /**
     * Un refus définitif, tel que la conversation le reçoit : le libellé est
     * déjà écrit pour l'utilisateur, le code du serveur suit quand il y en a
     * un — l'écran peut ainsi distinguer un refus d'un autre sans relire la
     * phrase.
     */
    data class Rejection(override val message: String, val code: String? = null) : Exception(message)

    /** Le répartiteur de la file : celui de sa portée, le fil principal dans l'app. */
    private val confined: CoroutineDispatcher =
        scope.coroutineContext[ContinuationInterceptor] as? CoroutineDispatcher ?: Dispatchers.Main.immediate

    private val mutableIsOnline = MutableStateFlow(true)

    /**
     * Le réseau est disponible. Il part de `true` : tant que le moniteur n'a
     * pas parlé, on n'affiche pas « hors ligne » à quelqu'un qui ne l'est pas.
     */
    val isOnline: StateFlow<Boolean> = mutableIsOnline.asStateFlow()

    private val mutablePending = MutableStateFlow(0)

    /** Combien de tours attendent **le réseau** sur le disque. */
    val pending: StateFlow<Int> = mutablePending.asStateFlow()

    private val mutableWaitingForCredit = MutableStateFlow(0)

    /**
     * Combien de tours attendent **le crédit de demain** sur le disque — voir
     * `PendingTurn.waitingForCreditUntil`. Comptés à part de [pending] : la
     * boîte de l'accueil promet de les envoyer « dès la reconnexion », et eux
     * partiront à minuit, réseau ou pas.
     */
    val waitingForCredit: StateFlow<Int> = mutableWaitingForCredit.asStateFlow()

    private val mutableWaitingForUnlimited = MutableStateFlow(0)

    /**
     * Combien de tours attendent **l'illimité** sur le disque — voir
     * `PendingTurn.waitingForUnlimited`. Ni le réseau ni minuit ne les feront
     * partir : comptés à part, eux aussi.
     */
    val waitingForUnlimited: StateFlow<Int> = mutableWaitingForUnlimited.asStateFlow()

    private val mutableSending = MutableStateFlow(0)

    /** Combien de tours sont en train de partir. Zéro quand rien n'est en vol. */
    val sending: StateFlow<Int> = mutableSending.asStateFlow()

    private val mutableJustDelivered = MutableStateFlow<Int?>(null)

    /** Ce que le dernier envoi a fait arriver, le temps de le dire — voir [CONFIRMATION_DELAY_MS]. `null` le reste du temps. */
    val justDelivered: StateFlow<Int?> = mutableJustDelivered.asStateFlow()

    private val mutableDeliveries = MutableStateFlow(0)

    /**
     * Compteur monotone des tours arrivés. Il ne sert qu'à une chose : que
     * l'accueil sache qu'il doit se recharger, parce que ses compteurs et sa
     * jauge viennent de vieillir.
     */
    val deliveries: StateFlow<Int> = mutableDeliveries.asStateFlow()

    private val mutableRejection = MutableStateFlow<String?>(null)

    /**
     * Un refus **définitif** du serveur, à montrer à l'utilisateur. Ce qui
     * tient au réseau n'arrive jamais ici : ça retourne dans la file.
     */
    val rejection: StateFlow<String?> = mutableRejection.asStateFlow()

    private val mutableLastDelivery = MutableStateFlow<ChatTurnDelivery?>(null)

    /**
     * Où en est le dernier tour dont le sort a changé — et le reçu du serveur,
     * quand il est arrivé.
     *
     * La bulle s'affiche **dans la conversation**, sur un écran que la file ne
     * connaît pas — et le tour peut très bien attendre le réseau sur le
     * disque. La bulle suit donc la file au lieu de décider elle-même : une
     * bulle qui se déclarerait envoyée parce que MEMO a répondu mentirait à
     * chaque fois qu'on raconte dans le métro. La conversation écoute
     * [turnDeliveries] ; cette valeur-ci est le dernier mot, pour qui arrive
     * après. Voir `ChatModel.markDelivery`.
     */
    val lastDelivery: StateFlow<ChatTurnDelivery?> = mutableLastDelivery.asStateFlow()

    private val mutableLocalTrips = MutableStateFlow<List<PendingTrip>>(emptyList())

    /**
     * Les voyages du compte ouvert que le serveur n'a pas encore vus. C'est ce
     * que l'accueil, l'écran du voyage et la conversation montrent à leur
     * place, en attendant — voir [mergingLocalTrips]. `RootView` en tire
     * `LocalTripsAwaitingServer`.
     */
    val localTrips: StateFlow<List<PendingTrip>> = mutableLocalTrips.asStateFlow()

    /**
     * Les voyages créés sur le téléphone que le serveur n'a pas encore vus,
     * **tous comptes confondus** — voir [localTrips].
     */
    private var storedTrips: List<PendingTrip> = emptyList()

    /** Ils ont été lus du disque — au démarrage, ou au premier vidage s'il passe avant. */
    private var hasLoadedTrips = false

    /**
     * Les voyages arrivés pendant cette session, avec leur code d'accès :
     * revenir sur la création ne fait pas attendre un code déjà reçu.
     */
    private val createdTrips = mutableMapOf<String, CreatedTrip>()
    private val tripListeners = mutableMapOf<Any, Channel<TripSyncEvent>>()

    /**
     * Le compte ouvert : ses voyages en attente sont les seuls qu'on montre et
     * qu'on envoie. `null` avant l'ouverture de la session, et dans le bac à
     * sable.
     */
    var accountId: String? = null
        private set

    /**
     * Un vidage a été demandé pendant qu'un autre tournait : il repassera, pour
     * prendre ce qui est arrivé entre-temps.
     */
    private var drainsAgain = false

    /** Les conversations à l'écoute — voir [turnDeliveries]. */
    private val listeners = mutableMapOf<Any, Channel<ChatTurnDelivery>>()

    private var monitor: Job? = null
    private var flushing: Deferred<Unit>? = null
    private var confirmation: Job? = null

    /**
     * Le réveil des tours qui attendent le crédit du jour : une tâche qui dort
     * jusqu'à la plus proche recharge, puis vide la file. Une seule à la fois —
     * voir [scheduleCreditWake].
     */
    private var creditWake: Job? = null

    /** Ce que dit le moniteur, avant que le bac à sable ne s'en mêle. */
    private var networkIsUp = true

    /**
     * Le « Passer hors ligne » du bac à sable. Il **prime** sur le moniteur, et
     * le reste — file, envois, reprise — se comporte exactement comme sous un
     * vrai tunnel. Seul le panneau du bac à sable, en Debug, le lève.
     */
    private var forcedOffline = false

    /**
     * Ouvre la file et se met à l'écoute du réseau. Idempotent : l'appeler deux
     * fois ne pose pas deux moniteurs.
     *
     * À appeler **au démarrage** et non à l'ouverture d'un écran : c'est ce qui
     * permet de savoir qu'on est hors ligne avant de dessiner l'accueil, et de
     * repartir avec ce qu'un lancement précédent avait laissé en file.
     */
    fun start() {
        if (monitor != null) return

        // Cette boucle ne s'arrête pas : la file vit aussi longtemps que l'app.
        monitor = scope.launch {
            refreshCounts()
            loadTripsIfNeeded()
            // Un tour mis de côté hier soir faute de crédit repart à l'heure
            // dite, même si l'app a été relancée entre-temps.
            scheduleCreditWake()

            var isFirstPath = true
            connectivity.updates().collect { isUp ->
                // La reconnexion, c'est aussi le tout premier état connu : une
                // app relancée en ligne avec une file pleine doit la vider sans
                // attendre une coupure suivie d'un retour.
                val reconnected = isUp && (isFirstPath || !networkIsUp)
                networkIsUp = isUp
                isFirstPath = false
                refreshOnline()

                if (reconnected && isOnline.value) flush()
            }
        }
    }

    /**
     * Confie un tour à un carnet.
     *
     * Hors ligne, il part directement dans la file — on n'essaie même pas, et
     * on ne fait donc pas attendre quelqu'un devant un échec annoncé. En
     * ligne, on essaie, et **ce qui échoue au transport retourne dans la
     * file** : le moniteur dit qu'une interface est montée, pas que l'API
     * répond.
     */
    suspend fun submit(turn: OutgoingTurn, tripId: String): Delivery = withContext(confined) {
        mutableRejection.value = null
        publish(ChatTurnDelivery(id = turn.id, tripId = tripId, state = ChatDelivery.Sending))

        // **Une tâche à elle**, détachée de celle de l'appelant : quitter la
        // conversation annule son tour en vol (`ChatModel.teardown()`), et
        // l'envoi annulé avec lui retombait dans la file — où rien ne le
        // relançait avant le prochain retour au premier plan. Le vocal part
        // donc jusqu'au bout, écran fermé ou non — et sa bulle l'apprend.
        scope.async {
            deliverOrQueue(turn, tripId).also { note(it, turn.id, tripId) }
        }.await()
    }

    /**
     * Le sort des tours, au fil de l'eau — ce que la conversation écoute.
     *
     * Un flux et non une valeur observée : deux tours qui partent dans la même
     * seconde font deux événements, et une bulle ne doit rater ni l'un ni
     * l'autre. Il commence par le dernier connu : un écran ouvert après
     * l'arrivée du vocal de l'accueil ne l'attend pas pour rien. Il est à
     * l'écoute **dès cet appel**, et s'arrête quand la collecte s'arrête ; il
     * se collecte une fois.
     *
     * Ce premier mot est **marqué rejoué** ([ChatTurnDelivery.isReplay]) : il
     * vit autant que l'app, et son reçu peut dater du matin — le fil qui vient
     * de lire un crédit plus frais ne doit pas le reprendre.
     *
     * À appeler depuis le fil principal.
     */
    fun turnDeliveries(): Flow<ChatTurnDelivery> {
        val channel = Channel<ChatTurnDelivery>(Channel.UNLIMITED)
        val key = Any()
        lastDelivery.value?.let { channel.trySend(it.replayed) }
        listeners[key] = channel
        return channel.consumeAsFlow().onCompletion {
            scope.launch { listeners.remove(key) }
        }
    }

    private fun publish(delivery: ChatTurnDelivery) {
        mutableLastDelivery.value = delivery
        for (listener in listeners.values) listener.trySend(delivery)
    }

    /**
     * Les tours qui attendent le réseau pour un carnet, le plus ancien
     * d'abord — ce que la conversation pose en bulles « en cours d'envoi »
     * quand on l'ouvre. Relus du disque, fichiers compris : la bulle d'un
     * vocal doit se réécouter.
     */
    suspend fun waiting(tripId: String): List<OutgoingTurn> = withContext(confined) {
        store.all().filter { it.tripId == tripId }.mapNotNull { record ->
            val files = attempt { store.files(record) } ?: return@mapNotNull null
            turn(record, files)
        }
    }

    private suspend fun deliverOrQueue(turn: OutgoingTurn, tripId: String): Delivery {
        // Un carnet que le serveur ne connaît pas encore : le tour attend son
        // voyage, qui partira avant lui.
        if (!isOnline.value || isWaitingForServer(tripId)) return queue(turn, tripId)

        mutableSending.value += 1
        val outcome = deliver(turn, tripId)
        mutableSending.value -= 1

        return when (outcome) {
            is Outcome.Sent -> {
                noteDelivery(1)
                Delivery.Delivered(outcome.receipt)
            }
            Outcome.Deferred -> queue(turn, tripId)
            is Outcome.WaitingForCredit -> {
                // Pas un refus : le tour attend sur le disque, marqué, et sa
                // bulle dit « Partira demain ». Le disque qui refuse, lui, reste
                // le seul cas où il se perdrait — et `queue` le dit.
                val delivery = queue(turn, tripId, waitingForCreditUntil = outcome.until)
                if (delivery == Delivery.Queued) {
                    publish(
                        ChatTurnDelivery(turn.id, tripId, ChatDelivery.WaitingForCredit(outcome.until), credit = outcome.credit),
                    )
                }
                delivery
            }
            is Outcome.WaitingForUnlimited -> {
                // Plus long qu'une journée : gardé, marqué, et sa bulle propose
                // l'illimité au lieu de promettre demain.
                val delivery = queue(turn, tripId, waitingForUnlimited = true)
                if (delivery == Delivery.Queued) {
                    publish(ChatTurnDelivery(turn.id, tripId, ChatDelivery.WaitingForUnlimited, credit = outcome.credit))
                }
                delivery
            }
            is Outcome.Rejected -> {
                val message = message(turn, outcome.reason)
                mutableRejection.value = message
                Delivery.Rejected(message)
            }
        }
    }

    /**
     * Ce que la bulle de la conversation doit montrer.
     *
     * ⚠️ `Queued` **n'est pas un échec, et n'est pas une arrivée** : le tour
     * attend le réseau sur le disque, et la bulle reste donc sur « envoi en
     * cours ». C'est [drain] qui la terminera, au retour de la connexion, **par
     * son identifiant**.
     */
    private fun note(outcome: Delivery, id: String, tripId: String) {
        when (outcome) {
            is Delivery.Delivered -> publish(ChatTurnDelivery(id, tripId, ChatDelivery.Sent, receipt = outcome.receipt))
            Delivery.Queued -> Unit
            is Delivery.Rejected -> publish(ChatTurnDelivery(id, tripId, ChatDelivery.Failed(outcome.message)))
        }
    }

    /**
     * Vide la file. Sans effet hors ligne, et un seul vidage à la fois : deux
     * déclencheurs simultanés — le retour du réseau et le retour dans l'app, ou
     * le travail d'arrière-plan — ne doivent pas envoyer deux fois le même
     * souvenir.
     */
    suspend fun flush(): Unit = withContext(confined) {
        // Un vidage déjà en cours repassera pour ce qui vient d'arriver — et
        // celui qui attend attend **tous** les passages : rendre la main avant
        // le dernier, ce serait dire « parti » d'un voyage encore sur le disque.
        flushing?.let {
            drainsAgain = true
            return@withContext it.await()
        }

        val task = scope.async {
            do {
                drainsAgain = false
                drain()
            } while (drainsAgain && isOnline.value)
            // **Ici**, dans la même foulée que le dernier passage : levé après
            // coup par l'appelant, il laissait un instant où un vidage tout
            // juste demandé attendait une tâche déjà finie — et ne repassait
            // pas.
            flushing = null
        }
        flushing = task
        task.await()
    }

    /**
     * Oublie le dernier refus. C'est ce que demande « Réessayer » du bandeau
     * d'erreur : un message qui survit au geste censé le traiter fait douter
     * du geste.
     */
    fun dismissRejection() {
        mutableRejection.value = null
    }

    // MARK: - L'envoi

    private suspend fun drain() {
        if (!isOnline.value) return

        // Les voyages d'abord : ce qu'on y a raconté ne peut partir qu'après.
        // Un voyage qui n'est pas passé ne retient que ses propres tours — ceux
        // des carnets que le serveur connaît partent quand même.
        drainTrips()
        if (!isOnline.value) return

        // Ce qui attend le crédit de demain reste de côté jusqu'à l'heure dite,
        // ce qui attend l'illimité jusqu'à l'abonnement : le renvoyer
        // maintenant, c'est le même refus — et une requête de plus à chaque
        // retour dans l'app.
        val now = Instant.now()
        val waiting = store.all().filter { !it.isOnHold(now) }
        refreshCounts()
        if (waiting.isEmpty()) return

        mutableSending.value += waiting.size
        try {
            var delivered = 0

            // Les voyages refusés faute de crédit pendant ce vidage, avec
            // l'heure de la recharge et le solde que le serveur a rendu. Leurs
            // tours suivants ne partent que s'ils tiennent dans ce reste — une
            // puce, des photos, un texte assez court ; les autres sont marqués
            // « Partira demain » tout de suite, sans un aller-retour pour le
            // même refus.
            val heldTrips = mutableMapOf<String, Pair<Instant, DailyCredit?>>()

            for (record in waiting) {
                if (!isOnline.value) break

                // Son voyage attend encore : il partira au prochain vidage, après lui.
                if (isWaitingForServer(record.tripId)) continue

                val turn = attempt { store.files(record) }?.let { turn(record, it) }
                if (turn == null) {
                    // Le fichier a disparu sous la fiche : elle ne sert plus à rien.
                    store.remove(record)
                    continue
                }

                val held = heldTrips[record.tripId]

                // Le voyage vient d'être refusé, et ce tour-ci coûte plus qu'une
                // journée entière : demain ne le ferait pas passer non plus. Il
                // attend l'illimité tout de suite, comme si le serveur l'avait
                // dit — annoncé « Partira demain », il l'aurait été toute la
                // journée avant d'être reconnu trop long au renvoi de minuit
                // (03/10/2026).
                if (held != null && turn.exceedsAWholeDay(held.second ?: DailyCredit())) {
                    attempt { store.update(record.copy(waitingForCreditUntil = null, waitingForUnlimited = true)) }
                    publish(ChatTurnDelivery(record.id, record.tripId, ChatDelivery.WaitingForUnlimited, credit = held.second))
                    continue
                }

                // Le voyage vient d'être refusé : ce tour-ci tient-il encore dans
                // ce qui reste ? Sinon il attend demain, marqué et dit comme tel
                // — laissé sans marque, il resterait compté « hors ligne » et sa
                // bulle « en cours d'envoi », alors qu'on est en ligne.
                if (held != null && !fits(turn, held.second)) {
                    attempt { store.update(record.copy(waitingForCreditUntil = held.first)) }
                    publish(
                        ChatTurnDelivery(record.id, record.tripId, ChatDelivery.WaitingForCredit(held.first), credit = held.second),
                    )
                    continue
                }

                when (val outcome = deliver(turn, record.tripId)) {
                    is Outcome.Sent -> {
                        store.remove(record)
                        delivered += 1
                        note(Delivery.Delivered(outcome.receipt), record.id, record.tripId)
                    }
                    is Outcome.WaitingForCredit -> {
                        // Gardé, marqué, et sa bulle passe à « Partira demain ».
                        attempt { store.update(record.copy(waitingForCreditUntil = outcome.until)) }
                        heldTrips[record.tripId] = outcome.until to outcome.credit
                        publish(
                            ChatTurnDelivery(
                                record.id,
                                record.tripId,
                                ChatDelivery.WaitingForCredit(outcome.until),
                                credit = outcome.credit,
                            ),
                        )
                    }
                    is Outcome.WaitingForUnlimited -> {
                        // Plus long qu'une journée : il attend l'illimité. Le
                        // voyage, lui, n'est pas retenu — le reste du jour sert
                        // aux suivants.
                        attempt { store.update(record.copy(waitingForCreditUntil = null, waitingForUnlimited = true)) }
                        publish(ChatTurnDelivery(record.id, record.tripId, ChatDelivery.WaitingForUnlimited, credit = outcome.credit))
                    }
                    is Outcome.Rejected -> {
                        store.remove(record)
                        val message = message(turn, outcome.reason)
                        mutableRejection.value = message
                        note(Delivery.Rejected(message), record.id, record.tripId)
                    }
                    Outcome.Deferred -> {
                        // Rien n'est passé : le réseau est reparti. Inutile de
                        // faire subir la même attente aux suivants.
                        refreshCounts()
                        scheduleCreditWake()
                        return
                    }
                }
            }

            refreshCounts()
            scheduleCreditWake()
            if (delivered > 0) noteDelivery(delivered)
        } finally {
            mutableSending.value -= waiting.size
        }
    }

    /** Recompte la file : ce qui attend le réseau, ce qui attend le crédit, ce qui attend l'illimité. */
    private suspend fun refreshCounts() {
        val now = Instant.now()
        val all = store.all()
        val unlimited = all.count { it.waitingForUnlimited }
        val credit = all.count { !it.waitingForUnlimited && it.isWaitingForCredit(now) }
        mutableWaitingForUnlimited.value = unlimited
        mutableWaitingForCredit.value = credit
        mutablePending.value = all.size - credit - unlimited
    }

    /**
     * **Le compte vient de passer en illimité** (03/10/2026) : ce qui attendait
     * le crédit de demain ou l'illimité repart tout de suite. On vient de
     * payer pour raconter sans limite — le vocal refusé à 15 h ne doit pas
     * attendre minuit pour autant.
     *
     * Les bulles quittent « Partira demain » et « Trop long pour une journée »
     * pour « en cours d'envoi », puis la file se vide — hors ligne, elles
     * partiront au retour du réseau. Tout est relâché, sans trier par compte :
     * un tour d'un autre compte resté sans abonnement reprendra son refus, et
     * sa marque, au premier envoi.
     */
    suspend fun releaseCreditHolds(): Unit = withContext(confined) {
        val released = mutableListOf<PendingTurn>()
        for (record in store.all()) {
            if (record.waitingForCreditUntil == null && !record.waitingForUnlimited) continue
            val freed = record.copy(waitingForCreditUntil = null, waitingForUnlimited = false)
            attempt { store.update(freed) }
            released += freed
        }
        if (released.isEmpty()) return@withContext

        refreshCounts()
        scheduleCreditWake()
        for (record in released) publish(ChatTurnDelivery(record.id, record.tripId, ChatDelivery.Sending))
        if (isOnline.value) flush() else onPending(null)
    }

    /**
     * Pose le réveil des tours qui attendent le crédit du jour : à la plus
     * proche recharge, la file se vide d'elle-même — pas besoin de rouvrir
     * l'app ni de toucher « Réessayer ». Quelques secondes de marge : le
     * serveur tranche le jour à son horloge, et arriver une seconde trop tôt
     * ferait reposer le tour pour une nuit de plus.
     *
     * Ce réveil-ci vit avec le processus ; app fermée, c'est
     * [RecordingOutboxWorker] qui repasse à la même heure — [onPending] le
     * planifie.
     */
    private suspend fun scheduleCreditWake() {
        creditWake?.cancel()
        creditWake = null

        val next = nextCreditReturn() ?: return
        onPending(next)

        creditWake = scope.launch {
            val delayMs = maxOf(0L, Duration.between(Instant.now(), next).toMillis()) + CREDIT_WAKE_MARGIN_MS
            delay(delayMs)
            refreshCounts()
            if (isOnline.value) flush()
        }
    }

    /** La plus proche recharge qu'un tour attend, s'il y en a une à venir. */
    suspend fun nextCreditReturn(): Instant? = withContext(confined) {
        val now = Instant.now()
        store.all().mapNotNull { it.waitingForCreditUntil }.filter { it > now }.minOrNull()
    }

    private suspend fun deliver(turn: OutgoingTurn, tripId: String): Outcome =
        try {
            Outcome.Sent(send(turn, tripId))
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            val outcome = outcome(error)
            // Un refus faute de crédit pour un tour qu'aucune journée ne
            // laissera passer : demain donnerait le même refus.
            if (outcome is Outcome.WaitingForCredit && neverFitsADay(turn, refusal = outcome.credit)) {
                Outcome.WaitingForUnlimited(outcome.credit)
            } else {
                outcome
            }
        }

    private suspend fun queue(
        turn: OutgoingTurn,
        tripId: String,
        waitingForCreditUntil: Instant? = null,
        waitingForUnlimited: Boolean = false,
    ): Delivery = try {
        val record = record(turn, tripId).copy(
            waitingForCreditUntil = waitingForCreditUntil,
            waitingForUnlimited = waitingForUnlimited,
        )
        store.enqueue(record, files(turn))
        refreshCounts()
        if (waitingForCreditUntil != null) scheduleCreditWake() else if (!waitingForUnlimited) onPending(null)
        Delivery.Queued
    } catch (error: CancellationException) {
        throw error
    } catch (_: Exception) {
        // Le disque a refusé : c'est le seul cas où un tour se perd, et il faut
        // le dire tout de suite — la personne peut encore recommencer.
        val message = "${subject(turn)} n’a pas pu être gardé sur ton téléphone. Réessaie."
        mutableRejection.value = message
        Delivery.Rejected(message)
    }

    private fun noteDelivery(count: Int) {
        mutableDeliveries.value += count
        mutableJustDelivered.value = count

        confirmation?.cancel()
        confirmation = scope.launch {
            delay(CONFIRMATION_DELAY_MS)
            mutableJustDelivered.value = null
        }
    }

    private fun refreshOnline() {
        mutableIsOnline.value = networkIsUp && !forcedOffline
    }

    // MARK: - Les voyages créés hors ligne

    /** Le voyage en attente qui porte cet identifiant, s'il y en a un. */
    fun localTrip(id: String): PendingTrip? = localTrips.value.firstOrNull { it.id == id }

    /**
     * Le serveur ne connaît pas encore ce carnet : rien de ce qu'on y dit ne
     * doit partir avant lui. Tous comptes confondus — le vocal d'un voyage
     * qu'un autre compte a créé attend que ce compte revienne.
     */
    private fun isWaitingForServer(tripId: String): Boolean = storedTrips.any { it.id == tripId }

    private fun publishLocalTrips() {
        mutableLocalTrips.value = storedTrips.filter { it.accountId == accountId }
    }

    /**
     * Les voyages en attente, relus du disque **avant** le premier vidage : un
     * processus relancé par WorkManager vide la file sans attendre le
     * moniteur, et un tour ne doit jamais partir avant son voyage.
     */
    private suspend fun loadTripsIfNeeded() {
        if (hasLoadedTrips) return
        storedTrips = trips.all()
        hasLoadedTrips = true
        publishLocalTrips()
    }

    /**
     * Le compte de la session ouverte — `null` à la déconnexion. Ses voyages
     * en attente partent alors, s'il y a du réseau. À appeler depuis le fil
     * principal.
     */
    fun setAccount(id: String?) {
        if (id == accountId) return
        accountId = id
        publishLocalTrips()
        if (id != null && isOnline.value) scope.launch { flush() }
    }

    /**
     * Confie un voyage à la file — la création, et chaque correction qui la
     * suit.
     *
     * Le voyage est **gardé sur le disque d'abord**, et la fonction rend dès
     * que c'est fait : la création passe à l'étape du code d'accès sans
     * attendre personne, réseau ou pas. L'envoi part derrière ; son issue — le
     * code d'accès, ou un refus — arrive par [tripSync].
     *
     * Corriger un voyage déjà parti le remet dans la file : `POST /v1/trips`
     * se rejoue sur son identifiant, et pose le dernier brouillon.
     *
     * @throws Rejection quand le disque refuse — le seul cas où le voyage se
     *   perdrait, et il faut le dire tant qu'on est sur l'écran.
     */
    suspend fun saveTrip(draft: TripDraft): Trip = withContext(confined) {
        val id = draft.id ?: UUID.randomUUID().toString().lowercase()
        // Une copie, et non le brouillon de l'écran : il continue de changer
        // sous les doigts, et la file compare le brouillon qu'elle a envoyé.
        val saved = draft.copy(id = id)

        loadTripsIfNeeded()
        try {
            trips.save(PendingTrip(id = id, draft = saved, accountId = accountId))
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            throw Rejection("Ton voyage n’a pas pu être gardé sur ton téléphone. Réessaie.")
        }
        storedTrips = trips.all()
        publishLocalTrips()

        onPending(null)
        if (isOnline.value) scope.launch { flush() }
        Trip.local(saved, id = id)
    }

    /**
     * Ce que le serveur a fait du voyage : son code d'accès, ou son refus.
     *
     * **Attend** tant que le voyage n'est pas parti — hors ligne, jusqu'au
     * retour du réseau. Quitter l'écran annule l'attente (l'annulation se
     * propage, comme toute coroutine) : le voyage, lui, reste dans la file.
     * `null` ne revient que si la file cesse d'émettre.
     */
    suspend fun tripSync(id: String): TripSync? = withContext(confined) {
        createdTrips[id]?.let { return@withContext TripSync.Created(it) }

        val channel = Channel<TripSyncEvent>(Channel.UNLIMITED)
        val key = Any()
        tripListeners[key] = channel
        try {
            for (event in channel) {
                if (event.tripId == id) return@withContext event.sync
            }
            null
        } finally {
            tripListeners.remove(key)
        }
    }

    /**
     * Oublie un voyage que le serveur n'a jamais vu, et ce qu'on y a raconté
     * en attendant. `false` quand il n'est pas en attente : c'est alors au
     * serveur de le supprimer.
     */
    suspend fun discardLocalTrip(id: String): Boolean = withContext(confined) {
        if (localTrip(id) == null) return@withContext false

        trips.remove(id)
        for (record in store.all()) if (record.tripId == id) store.remove(record)
        storedTrips = trips.all()
        publishLocalTrips()
        refreshCounts()
        true
    }

    /**
     * **Oublie un tour retenu** (03/10/2026) — « Supprimer », sous une bulle
     * qui attend l'illimité : sans abonnement, rien ne le ferait jamais
     * partir, et il resterait sur le disque, compté, sa bulle reposée à chaque
     * ouverture du fil. La personne l'a demandé, et confirmé.
     *
     * Seulement un tour **retenu** — par l'illimité ou par le crédit de
     * demain : un tour qui n'attend que le réseau peut être en train de
     * partir, et l'effacer sous un envoi ne le rattraperait pas. `false` quand
     * il n'y est pas, ou ne l'est plus.
     */
    suspend fun discardTurn(id: String): Boolean = withContext(confined) {
        val record = store.all().firstOrNull { it.id == id }
        if (record == null || !record.isOnHold(Instant.now())) return@withContext false
        store.remove(record)
        refreshCounts()
        scheduleCreditWake()
        true
    }

    /**
     * L'accueil du serveur, et les voyages qu'il ne connaît pas encore devant :
     * ils viennent d'être créés — avec leur crédit du jour, plein
     * ([withFreshCredit]) : la feuille d'enregistrement de l'accueil compte et
     * coupe à la limite sur un voyage créé hors ligne comme sur les autres.
     */
    fun mergingLocalTrips(feed: HomeFeed): HomeFeed {
        val known = feed.trips.map { it.id }.toSet()
        val waiting = localTrips.value.filter { it.id !in known }.map {
            withFreshCredit(it.trip, isUnlimited = feed.traveller.isUnlimited)
        }
        if (waiting.isEmpty()) return feed
        return HomeFeed(traveller = feed.traveller, trips = waiting + feed.trips, showcase = feed.showcase)
    }

    /**
     * Envoie les voyages qui attendent, le plus ancien d'abord. S'arrête au
     * premier qui ne passe pas : le suivant n'aurait pas plus de chance.
     */
    private suspend fun drainTrips() {
        loadTripsIfNeeded()
        for (waiting in localTrips.value) {
            if (!isOnline.value) break

            when (val outcome = deliver(waiting.draft)) {
                is TripOutcome.Created -> {
                    val created = outcome.created
                    // Retiré **seulement** s'il n'a pas changé pendant l'envoi :
                    // une correction faite entre-temps doit partir à son tour.
                    trips.remove(waiting.id, ifDraftIs = waiting.draft)
                    createdTrips[waiting.id] = created
                    // Un serveur d'avant le 01/10 ignore l'identifiant de l'app
                    // et en tire un autre : ce qu'on a raconté le suit, au lieu
                    // de partir vers un carnet qui n'existe pas — et d'y être
                    // perdu.
                    if (created.trip.id != waiting.id) {
                        for (record in store.all()) {
                            if (record.tripId == waiting.id) attempt { store.update(record.copy(tripId = created.trip.id)) }
                        }
                    }
                    publish(TripSyncEvent(waiting.id, TripSync.Created(created)))
                }
                TripOutcome.Deferred -> {
                    storedTrips = trips.all()
                    publishLocalTrips()
                    return
                }
                is TripOutcome.Rejected -> {
                    trips.remove(waiting.id)
                    val message = "Ton voyage « ${waiting.draft.title} » n’a pas pu être créé. ${outcome.reason}"
                    mutableRejection.value = message
                    publish(TripSyncEvent(waiting.id, TripSync.Rejected(message)))
                }
            }
        }

        storedTrips = trips.all()
        publishLocalTrips()
    }

    private suspend fun deliver(draft: TripDraft): TripOutcome =
        try {
            TripOutcome.Created(createTrip(draft))
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            when (val outcome = outcome(error)) {
                // Une création de voyage ne consomme aucun crédit : un refus de
                // crédit ici ne peut venir que d'un serveur confus — on retentera.
                Outcome.Deferred, is Outcome.WaitingForCredit, is Outcome.WaitingForUnlimited -> TripOutcome.Deferred
                is Outcome.Rejected -> TripOutcome.Rejected(outcome.reason)
                // L'appel a abouti, la réponse ne s'est pas lue : le voyage
                // existe, mais sans code à montrer. Il se rejoue sans risque —
                // la création reconnaît son identifiant — donc on retentera.
                is Outcome.Sent -> TripOutcome.Deferred
            }
        }

    private sealed interface TripOutcome {
        data class Created(val created: CreatedTrip) : TripOutcome
        data object Deferred : TripOutcome
        data class Rejected(val reason: String) : TripOutcome
    }

    private fun publish(event: TripSyncEvent) {
        for (listener in tripListeners.values) listener.trySend(event)
    }

    // MARK: - Bac à sable
    //
    // De quoi jouer le hors-ligne sans couper le wifi du Mac. Le panneau qui
    // les appelle n'existe qu'en Debug — voir `HomeDebugPanel`.
    //
    // Elles sont dans ce fichier et pas ailleurs parce que l'état de la file
    // est privé : le bac à sable peut donc poser un état, une vue ne le peut pas.

    /**
     * Coupe (ou rétablit) le réseau pour l'app entière.
     *
     * Ce n'est **pas** un faux affichage : hors ligne, un vocal enregistré part
     * vraiment sur le disque, et le rétablissement le fait vraiment repartir.
     * C'est le même chemin que sous un tunnel.
     *
     * Le double d'API se coupe avec (`SandboxNetwork.isOffline`) : sans quoi
     * le bac à sable répondrait pendant que la file se croit hors ligne.
     */
    fun debugSetOffline(offline: Boolean) {
        SandboxNetwork.isOffline = offline
        forcedOffline = offline
        refreshOnline()
        if (isOnline.value) scope.launch { flush() }
    }

    /** Met un vocal en file sans passer par le micro. */
    suspend fun debugQueue(audio: RecordedAudio, tripId: String) {
        withContext(confined) { queue(OutgoingTurn.voice(audio, levels = emptyList()), tripId) }
    }

    /** Montre l'envoi en cours, sans rien envoyer. */
    fun debugShowSending(count: Int) {
        mutableSending.value += count
        scope.launch {
            delay(3_000)
            mutableSending.value = maxOf(0, mutableSending.value - count)
        }
    }

    /** Montre la confirmation d'arrivée, sans rien avoir livré. */
    fun debugShowDelivered(count: Int) {
        noteDelivery(count)
    }

    /** Repart d'une file vide, en ligne, sans message. */
    suspend fun debugReset(): Unit = withContext(confined) {
        forcedOffline = false
        refreshOnline()
        confirmation?.cancel()
        mutableJustDelivered.value = null
        mutableRejection.value = null
        mutableSending.value = 0
        creditWake?.cancel()
        creditWake = null
        store.removeAll()
        mutablePending.value = 0
        mutableWaitingForCredit.value = 0
        mutableWaitingForUnlimited.value = 0
        trips.removeAll()
        storedTrips = emptyList()
        publishLocalTrips()
    }

    private sealed interface Outcome {
        data class Sent(val receipt: ChatTurnReceipt?) : Outcome
        data object Deferred : Outcome

        /** Refusé faute de crédit du jour : on retentera à [until]. */
        data class WaitingForCredit(val until: Instant, val credit: DailyCredit?) : Outcome

        /** Plus long qu'une journée de crédit : on attendra l'illimité. */
        data class WaitingForUnlimited(val credit: DailyCredit?) : Outcome
        data class Rejected(val reason: String) : Outcome
    }

    companion object {
        /**
         * Combien de temps la confirmation d'arrivée reste à l'écran. Assez pour
         * être lue, assez peu pour ne pas devenir un meuble.
         */
        private const val CONFIRMATION_DELAY_MS = 4_000L

        /** La marge du réveil, après l'heure de recharge annoncée par le serveur. */
        private const val CREDIT_WAKE_MARGIN_MS = 5_000L

        /**
         * Un voyage que le serveur n'a jamais vu, avec **son crédit du jour**
         * (03/10/2026) : plein — rien de ce qu'on y a dit n'est encore arrivé,
         * et ce qui attend dans la file se décompte à part —, rechargé au
         * minuit local suivant, illimité si le compte l'est. Un voyage qui
         * porte déjà un crédit le garde.
         *
         * Sans lui, le carnet créé à l'aéroport s'ouvrait sans rien compter :
         * ni bandeau à 4:30, ni arrêt à 5:00, et un vocal de 6 minutes ne se
         * savait trop long qu'au retour du réseau. L'objection « un abonné
         * verrait le bandeau » ne tient pas : l'accueil gardé dit s'il l'est.
         */
        fun withFreshCredit(trip: Trip, isUnlimited: Boolean, now: Instant = Instant.now()): Trip {
            if (trip.dailyCredit != null) return trip
            return trip.copy(dailyCredit = DailyCredit(isUnlimited = isUnlimited, resetsAt = creditReturns(null, now)))
        }

        /**
         * Un refus faute de crédit pour ce tour se répétera-t-il **chaque
         * jour** ? Oui quand il coûte plus qu'une journée entière
         * ([OutgoingTurn.exceedsAWholeDay]), ou quand le serveur l'a refusé pot
         * plein — sa mesure du vocal fait foi, pas la nôtre. Sans solde rendu,
         * le barème du catalogue.
         */
        fun neverFitsADay(turn: OutgoingTurn, refusal: DailyCredit?): Boolean {
            if (refusal != null && !refusal.isUnlimited && refusal.limitMs > 0 && refusal.remainingMs >= refusal.limitMs) {
                return turn.creditCost(refusal) > 0
            }
            return turn.exceedsAWholeDay(refusal ?: DailyCredit())
        }

        /**
         * Ce tour tient-il dans le reste d'un voyage qui vient d'être refusé ?
         * Ce qui ne coûte rien — une puce, des photos — part toujours ; le
         * reste seulement s'il tient dans le solde rendu, le serveur tranchant
         * de nouveau. Sans solde, rien ne passe qui coûte.
         */
        fun fits(turn: OutgoingTurn, credit: DailyCredit?): Boolean {
            val cost = turn.creditCost(credit ?: DailyCredit())
            if (cost <= 0) return true
            if (credit == null) return false
            return cost <= credit.remainingMs
        }

        /**
         * L'heure à laquelle le crédit revient : celle du serveur quand elle est
         * à venir, sinon le minuit local qui suit — un `resetsAt` absent ou
         * déjà passé (horloge du téléphone en avance, serveur d'avant) ne doit
         * ni bloquer le tour pour toujours, ni le renvoyer en boucle.
         *
         * Le `Calendar` de Swift est ici son fuseau, [zone].
         */
        fun creditReturns(resetsAt: Instant?, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Instant {
            if (resetsAt != null && resetsAt > now) return resetsAt
            return now.atZone(zone).toLocalDate().plusDays(1).atStartOfDay(zone).toInstant()
        }

        /**
         * **La** décision de la file : retenter, ou renoncer.
         *
         * Elle tient en une question — est-ce que réessayer a une chance ? Une
         * panne de transport, oui, c'est même exactement ce pour quoi la file
         * existe. Un 4xx, non : le carnet n'existe plus, le fichier est trop
         * gros. Garder un tour que le serveur refusera à chaque fois, c'est
         * promettre une arrivée qui n'aura jamais lieu.
         *
         * **Sauf le crédit du jour** (03/10/2026) : réessayer a une chance —
         * demain. Le tour attend l'heure que le serveur donne (`resetsAt`), et
         * à défaut le minuit local suivant. Et un tour plus long qu'une
         * journée (`daily_credit_too_long`) a une chance aussi : l'illimité. Il
         * reste sur le disque — le jeter, ce serait perdre ce qu'on a raconté.
         *
         * Le cas tordu est le décodage : l'appel **a abouti**, c'est la réponse
         * qu'on n'a pas su lire. Le tour est donc bien arrivé, et le renvoyer
         * le mettrait deux fois dans le carnet. On le compte comme parti — sans
         * reçu.
         */
        private fun outcome(error: Exception, now: Instant = Instant.now()): Outcome = when (error) {
            is ApiError -> when (error) {
                is ApiError.Transport, ApiError.NotAuthenticated -> Outcome.Deferred
                is ApiError.DailyCreditExhausted ->
                    Outcome.WaitingForCredit(creditReturns(error.credit?.resetsAt, now), error.credit)
                is ApiError.Server -> when {
                    error.code == ApiError.DAILY_CREDIT_TOO_LONG_CODE -> Outcome.WaitingForUnlimited(null)
                    // Une session révoquée n'est pas un refus du tour : il attend
                    // la reconnexion, comme `NotAuthenticated` — l'effacer perdait
                    // le vocal.
                    error.statusCode == 401 -> Outcome.Deferred
                    // Le plafond anti-abus du fil (150 tours par jour et par
                    // voyage) : « reviens demain », dit le message — le tour
                    // attend donc demain.
                    error.statusCode == 429 && error.code == "chat_daily_cap" ->
                        Outcome.WaitingForCredit(creditReturns(null, now), null)
                    error.statusCode >= 500 -> Outcome.Deferred
                    else -> Outcome.Rejected(error.message)
                }
                is ApiError.Decoding -> Outcome.Sent(null)
            }
            // Le `URLError` d'iOS : le transport, hors du client d'API.
            is IOException -> Outcome.Deferred
            else -> Outcome.Rejected(error.localizedMessage ?: error.toString())
        }

        // MARK: - Entre la file et le disque

        /** La fiche d'un tour, telle qu'elle attend sur le disque. */
        private fun record(turn: OutgoingTurn, tripId: String): PendingTurn = when (val body = turn.body) {
            is OutgoingTurn.Body.Text -> PendingTurn(
                id = turn.id,
                tripId = tripId,
                kind = PendingTurn.Kind.Text,
                text = body.text,
                suggestionId = body.suggestionId,
                entryId = body.entryId,
                stepId = turn.stepId,
                recordedAt = Instant.now(),
            )
            is OutgoingTurn.Body.Voice -> PendingTurn(
                id = turn.id,
                tripId = tripId,
                kind = PendingTurn.Kind.Voice,
                stepId = turn.stepId,
                filenames = listOf(body.audio.filename),
                mimeTypes = listOf(body.audio.mimeType),
                duration = body.audio.durationSeconds,
                levels = body.audio.levels,
                placeLabel = body.audio.placeLabel,
                recordedAt = body.audio.capturedAt,
            )
            is OutgoingTurn.Body.Photos -> PendingTurn(
                id = turn.id,
                tripId = tripId,
                kind = PendingTurn.Kind.Photos,
                stepId = turn.stepId,
                filenames = body.photos.map { it.filename },
                mimeTypes = body.photos.map { it.mimeType },
                recordedAt = body.capturedAt,
            )
        }

        private fun files(turn: OutgoingTurn): List<ByteArray> = when (val body = turn.body) {
            is OutgoingTurn.Body.Text -> emptyList()
            is OutgoingTurn.Body.Voice -> listOf(body.audio.data)
            is OutgoingTurn.Body.Photos -> body.photos.map { it.data }
        }

        /**
         * Le tour relu du disque. `null` quand la fiche ne dit plus ce qu'elle
         * promettait — une version d'avant sans fichier, par exemple.
         *
         * Une attente du crédit **échue** ne se recopie pas : la fiche garde sa
         * date jusqu'au prochain envoi, mais le tour, lui, n'attend plus rien —
         * la conversation le rouvre « en cours d'envoi » et le décompte du jour
         * où il partira, au lieu de « Partira demain » (03/10/2026).
         */
        private fun turn(record: PendingTurn, files: List<ByteArray>, now: Instant = Instant.now()): OutgoingTurn? {
            val waitingForCreditUntil = if (record.isWaitingForCredit(now)) record.waitingForCreditUntil else null
            val body: OutgoingTurn.Body = when (record.kind) {
                PendingTurn.Kind.Text -> OutgoingTurn.Body.Text(
                    text = record.text ?: return null,
                    suggestionId = record.suggestionId,
                    entryId = record.entryId,
                )
                PendingTurn.Kind.Voice -> {
                    val data = files.firstOrNull() ?: return null
                    val filename = record.filenames.firstOrNull() ?: return null
                    val mimeType = record.mimeTypes.firstOrNull() ?: return null
                    OutgoingTurn.Body.Voice(
                        RecordedTurnAudio(
                            data = data,
                            filename = filename,
                            mimeType = mimeType,
                            capturedAt = record.recordedAt,
                            durationSeconds = record.duration ?: 0.0,
                            levels = record.levels,
                            placeLabel = record.placeLabel,
                        ),
                    )
                }
                PendingTurn.Kind.Photos -> {
                    if (files.size != record.filenames.size || files.size != record.mimeTypes.size || files.isEmpty()) return null
                    OutgoingTurn.Body.Photos(
                        photos = files.indices.map { ChatPhotoUpload(files[it], record.filenames[it], record.mimeTypes[it]) },
                        capturedAt = record.recordedAt,
                    )
                }
            }
            return OutgoingTurn(
                id = record.id,
                stepId = record.stepId,
                body = body,
                waitingForCreditUntil = waitingForCreditUntil,
                waitingForUnlimited = record.waitingForUnlimited,
            )
        }

        /**
         * Ce qu'on écrit quand le serveur a refusé. Le libellé du serveur est
         * déjà destiné à l'utilisateur — on le reprend plutôt que d'en inventer un.
         */
        private fun message(turn: OutgoingTurn, reason: String): String = "${subject(turn)} n’a pas pu être envoyé. $reason"

        private fun subject(turn: OutgoingTurn): String = when (turn.body) {
            is OutgoingTurn.Body.Text -> "Ton message"
            is OutgoingTurn.Body.Voice -> "Ton vocal"
            is OutgoingTurn.Body.Photos -> "Tes photos"
        }

        /** Le `try?` de Swift : la valeur, ou `null` sur un échec — jamais sur une annulation. */
        private suspend fun <T> attempt(block: suspend () -> T): T? =
            try {
                block()
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                null
            }
    }
}

/** Ce que le serveur a fait d'un voyage créé sur le téléphone. */
sealed interface TripSync {
    /** Il existe, et voici son code d'accès. */
    data class Created(val created: CreatedTrip) : TripSync

    /**
     * Il a été refusé, et le redire ne changerait rien. Le libellé est écrit
     * pour l'utilisateur.
     */
    data class Rejected(val message: String) : TripSync
}

internal data class TripSyncEvent(val tripId: String, val sync: TripSync)

/**
 * Un tour vocal depuis un enregistrement du micro — l'accueil et la
 * conversation en font le même.
 */
fun OutgoingTurn.Companion.voice(
    audio: RecordedAudio,
    levels: List<Double>,
    id: String = UUID.randomUUID().toString().lowercase(),
    stepId: String? = null,
    placeLabel: String? = null,
): OutgoingTurn = OutgoingTurn(
    id = id,
    stepId = stepId,
    body = OutgoingTurn.Body.Voice(
        RecordedTurnAudio(
            data = audio.data,
            filename = audio.filename,
            mimeType = audio.mimeType,
            capturedAt = audio.recordedAt,
            durationSeconds = audio.duration,
            levels = levels,
            placeLabel = placeLabel,
        ),
    ),
)
