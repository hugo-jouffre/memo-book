package com.memobook.feature.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.memobook.core.CreatedTrip
import com.memobook.core.DailyCredit
import com.memobook.core.HomeFeed
import com.memobook.core.Traveller
import com.memobook.core.Trip
import com.memobook.core.TripStage
import com.memobook.feature.CachedValue
import com.memobook.feature.ContentFreshness
import com.memobook.feature.RecordingOutbox
import com.memobook.feature.SandboxCredit
import com.memobook.feature.SandboxPersona
import com.memobook.feature.chat.OutgoingTurn
import com.memobook.feature.contentFreshness
import com.memobook.feature.voice
import com.memobook.networking.ApiError
import com.memobook.recording.RecordedAudio
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.UUID
import kotlin.math.roundToInt

/**
 * Ce que l'accueil sait faire : charger son contenu, et dire dans quel état
 * il est. Jumeau de `Home/HomeModel.swift`.
 *
 * Le modèle ne connaît pas l'API. Il reçoit **une source**, une fonction qui
 * rend un [HomeFeed] : l'app y branche `api.homeFeed()` (voir
 * `AppDependencies.homeModel()`), les aperçus n'en fournissent aucune et
 * tombent sur le jeu d'essai. C'est ce qui permet de montrer les quatre états
 * de l'écran sans serveur ni protocole simulé.
 *
 * Il reçoit aussi la [RecordingOutbox], et celle-là est un **objet** et non
 * une fonction : elle ne rend pas un contenu, elle tient un état — le réseau,
 * la file des vocaux — qui survit à l'écran et que le profil, demain, lira
 * aussi. C'est la même raison qui fait descendre `AppDependencies` jusqu'à la
 * porte de l'écran plutôt que jusqu'à sa vue.
 *
 * **Deux lectures du même état.** La vue lit [state], un `StateFlow` qui réunit
 * ce que le modèle sait et ce que la file dit — le réseau, ce qui part, ce qui
 * attend. Les propriétés du modèle ([notice], [errorMessage], [isOffline]…) le
 * relisent **tout de suite**, sur les valeurs de la file : c'est ce que font
 * les propriétés calculées d'iOS, et ce que les tests vérifient.
 *
 * @param source d'où vient le contenu. Par défaut, le jeu d'essai — voir
 *   `HomeFeed.fixture`.
 * @param cached ce que l'appareil a gardé du dernier passage. Sert à **ouvrir
 *   tout de suite** plutôt qu'à attendre le réseau ; la lecture continue
 *   derrière, et remplace. `null` en aperçu.
 * @param outbox où partent les vocaux. Par défaut, une file qui n'envoie nulle
 *   part et se croit toujours en ligne : les aperçus n'ont pas de serveur, et un
 *   enregistrement y est un geste sans conséquence. Elle vit alors avec le
 *   modèle.
 * @param remove supprime un voyage, depuis le tiroir d'une carte. `null` en
 *   aperçu, où la carte disparaît comme si c'était fait.
 * @param join rejoint un voyage par son code d'accès. `null` en aperçu.
 * @param subscriptionIsManagedByAppStore **sans jumeau sur iOS** : qui tient
 *   l'abonnement, pour le rappel de fin de voyage — `true` l'App Store, `false`
 *   Google Play, `null` on ne sait pas. Voir [tripEndReminderCanOpenHere].
 *   `null` (la fonction) en aperçu, où l'abonnement se joue tenu par Google Play.
 */
class HomeModel(
    private val source: suspend () -> HomeFeed = { HomeFeed.fixture },
    private val cached: CachedValue<HomeFeed>? = null,
    outbox: RecordingOutbox? = null,
    private val remove: (suspend (String) -> Unit)? = null,
    join: (suspend (String) -> CreatedTrip)? = null,
    private val subscriptionIsManagedByAppStore: (suspend () -> Boolean?)? = null,
) : ViewModel() {
    /**
     * La file de départ des vocaux. C'est elle qui sait s'il y a du réseau, ce
     * qui attend sur le disque et ce qui est en train de partir.
     */
    val outbox: RecordingOutbox = outbox ?: RecordingOutbox(scope = viewModelScope)

    /**
     * Rejoint un voyage par son code — `POST /v1/trips/join`. `null` en
     * aperçu, où le code de la maquette ouvre le premier voyage du jeu
     * d'essai et tout autre se dit introuvable.
     */
    private val joinByCode = join

    /**
     * Tout ce que l'écran dessine, d'un bloc.
     *
     * @property ongoingTrips les trois listes déjà triées. Elles sont calculées
     *   **une fois** à la réception du contenu, pas à chaque recomposition :
     *   trier dans une vue, c'est trier à chaque image d'animation.
     * @property loadFailure ce qui a raté **au chargement**. Les refus d'envoi,
     *   eux, appartiennent à la file — voir [errorMessage].
     * @property deletingTripId le voyage dont la suppression est partie, le
     *   temps qu'elle aboutisse.
     * @property deletionError ce que le serveur a répondu à une suppression
     *   refusée — un co-voyageur qui essaie, par exemple. Se lit dans la
     *   feuille de confirmation.
     * @property freshness ce que le dernier chargement a appris : rien, une
     *   reprise du disque, une confirmation, ou un vrai changement. C'est lui
     *   que la vue anime.
     * @property unreceivedCosts ce que coûtent, par voyage en cours, les tours
     *   que la file garde sur le disque et que le serveur n'a **pas encore
     *   reçus** — relu de la file après chaque lecture de l'accueil, jamais
     *   mêlé au crédit servi. À part, et recalculé en entier plutôt
     *   qu'additionné (03/10/2026) : le décompte d'un vocal en file vivait dans
     *   le crédit du voyage, en mémoire seulement. La relecture suivante — au
     *   retour de la conversation que l'accueil ouvre après chaque vocal —, hors
     *   ligne, rendait le cache et l'effaçait : un second vocal repartait de
     *   5:00, ni prévenu ni coupé, et le serveur le refusait au retour du
     *   réseau. Relire la file, c'est aussi ne jamais compter deux fois le même
     *   vocal.
     * @property isOnline, sending, pending, justDelivered, rejection : ce que
     *   la file dit, recopié ici pour que la vue n'ait qu'un état à lire.
     */
    data class State(
        val feed: HomeFeed? = null,
        val ongoingTrips: List<Trip> = emptyList(),
        val upcomingTrips: List<Trip> = emptyList(),
        val pastTrips: List<Trip> = emptyList(),
        val isLoading: Boolean = false,
        val loadFailure: String? = null,
        val deletingTripId: String? = null,
        val deletionError: String? = null,
        val freshness: ContentFreshness = ContentFreshness.Unknown,
        val unreceivedCosts: Map<String, Int> = emptyMap(),
        val isOnline: Boolean = true,
        val sending: Int = 0,
        val pending: Int = 0,
        val justDelivered: Int? = null,
        val rejection: String? = null,
    ) {
        /**
         * Le seul message d'erreur de l'écran, d'où qu'il vienne : le
         * chargement ou un refus définitif du serveur sur un vocal. Un seul
         * bandeau, parce qu'il n'y a qu'un endroit où on le lit.
         */
        val errorMessage: String? get() = loadFailure ?: rejection

        /**
         * `true` tant qu'on n'a rien à montrer : le premier chargement, celui
         * que l'écran de lancement couvre. Un rechargement, lui, garde le
         * contenu affiché plutôt que de vider l'écran.
         */
        val isShowingFirstLoad: Boolean get() = feed == null && errorMessage == null

        /** Aucun voyage du tout : l'utilisateur vient d'arriver. */
        val isEmpty: Boolean get() = feed?.trips?.isEmpty() == true

        /**
         * Pas de réseau. L'accueil continue de fonctionner — il montre le
         * dernier contenu reçu et le micro reste ouvert —, il le dit simplement.
         */
        val isOffline: Boolean get() = !isOnline

        /**
         * Ce que la boîte d'information annonce, ou `null` quand il n'y a rien
         * à dire. **Un seul message à la fois**, dans cet ordre :
         *
         * 1. ce qui part **maintenant** — c'est ce qui va changer l'écran ;
         * 2. ce qui **attend** le réseau — la promesse qu'il faut tenir ;
         * 3. ce qui vient d'**arriver** — le temps de le lire ;
         * 4. l'absence de réseau, quand il n'y a rien d'autre à raconter.
         *
         * L'ordre n'est pas une hiérarchie de gravité : c'est celui de
         * l'utilité. Quelqu'un qui a trois vocaux en attente sait déjà qu'il est
         * hors ligne — ce qu'il veut savoir, c'est qu'ils ne sont pas perdus.
         */
        val notice: HomeNotice?
            get() = when {
                sending > 0 -> HomeNotice.Sending(sending)
                pending > 0 -> HomeNotice.WaitingForConnection(pending)
                justDelivered != null -> HomeNotice.Delivered(justDelivered)
                isOffline -> HomeNotice.Offline
                else -> null
            }

        /**
         * Le carnet que la feuille « Nouveau carnet » propose de retrouver
         * plutôt que d'en ouvrir un de plus : celui qui est en cours, sinon le
         * prochain voyage prévu. `null` quand il n'y a ni l'un ni l'autre.
         *
         * Les deux listes sont déjà triées — le voyage le plus récemment
         * commencé d'un côté, le départ le plus proche de l'autre : il n'y a
         * qu'à prendre le premier.
         */
        val resumableTrip: Trip? get() = ongoingTrips.firstOrNull() ?: upcomingTrips.firstOrNull()

        /**
         * **Le crédit du jour du voyage que vise le vocal de l'accueil** — le
         * premier voyage en cours, celui où [upload] envoie (Hugo, 03/10/2026).
         * La feuille d'enregistrement s'en sert pour prévenir à 4:30 et couper
         * à 5:00, comme la barre de la conversation. `null` sans voyage en
         * cours, ou d'un serveur qui ne le sert pas encore.
         *
         * **Passé minuit, le crédit d'hier se recharge** (03/10/2026) —
         * `DailyCredit.refreshed(now)`, la règle de la conversation. Le flux
         * gardé sur le disque, ou laissé en mémoire la nuit, portait le crédit
         * épuisé de la veille : le micro de l'accueil refusait de s'ouvrir le
         * lendemain, toute la journée hors ligne, alors que la file aurait
         * gardé le vocal.
         *
         * **Moins ce qui attend encore dans la file** ([unreceivedCosts]) : le
         * crédit servi — le serveur, ou hors ligne le cache que la lecture rend
         * — ne compte pas un vocal que le serveur n'a pas reçu. C'est la règle
         * de la conversation (`ChatModel.dailyCredit`).
         */
        fun ongoingTripCredit(at: Instant = Instant.now()): DailyCredit? {
            val trip = ongoingTrips.firstOrNull() ?: return null
            return trip.dailyCredit?.refreshed(at)?.consuming(unreceivedCosts[trip.id] ?: 0)
        }
    }

    /** Ce que le modèle tient lui-même ; la file s'y ajoute dans [state]. */
    private val content = MutableStateFlow(State())

    /** Ce que la file dit, d'un bloc. */
    private val connection = combine(
        this.outbox.isOnline,
        this.outbox.sending,
        this.outbox.pending,
        this.outbox.justDelivered,
        this.outbox.rejection,
    ) { isOnline, sending, pending, justDelivered, rejection ->
        Connection(isOnline, sending, pending, justDelivered, rejection)
    }

    /** L'état que la vue dessine : celui du modèle, et ce que la file en dit. */
    val state: StateFlow<State> = combine(content, connection) { state, connection -> state.with(connection) }
        .stateIn(viewModelScope, SharingStarted.Eagerly, current)

    /** L'état **maintenant**, la file relue sur place — les propriétés calculées d'iOS. */
    private val current: State
        get() = content.value.with(
            Connection(
                isOnline = outbox.isOnline.value,
                sending = outbox.sending.value,
                pending = outbox.pending.value,
                justDelivered = outbox.justDelivered.value,
                rejection = outbox.rejection.value,
            ),
        )

    private data class Connection(
        val isOnline: Boolean,
        val sending: Int,
        val pending: Int,
        val justDelivered: Int?,
        val rejection: String?,
    )

    private fun State.with(connection: Connection): State = copy(
        isOnline = connection.isOnline,
        sending = connection.sending,
        pending = connection.pending,
        justDelivered = connection.justDelivered,
        rejection = connection.rejection,
    )

    // MARK: - Ce que l'écran lit

    val feed: HomeFeed? get() = content.value.feed
    val isLoading: Boolean get() = content.value.isLoading
    val ongoingTrips: List<Trip> get() = content.value.ongoingTrips
    val upcomingTrips: List<Trip> get() = content.value.upcomingTrips
    val pastTrips: List<Trip> get() = content.value.pastTrips
    val deletingTripId: String? get() = content.value.deletingTripId
    val deletionError: String? get() = content.value.deletionError
    val freshness: ContentFreshness get() = content.value.freshness

    /** Voir [State.errorMessage]. */
    val errorMessage: String? get() = current.errorMessage

    /** Voir [State.isShowingFirstLoad]. */
    val isShowingFirstLoad: Boolean get() = current.isShowingFirstLoad

    /** Voir [State.isEmpty]. */
    val isEmpty: Boolean get() = current.isEmpty

    /** Voir [State.isOffline]. */
    val isOffline: Boolean get() = !outbox.isOnline.value

    /** Voir [State.notice]. */
    val notice: HomeNotice? get() = current.notice

    /** Voir [State.resumableTrip]. */
    val resumableTrip: Trip? get() = current.resumableTrip

    /** Voir [State.ongoingTripCredit]. */
    val ongoingTripCredit: DailyCredit? get() = ongoingTripCredit(Instant.now())

    /** Le même, à une heure donnée — pour les tests. */
    internal fun ongoingTripCredit(at: Instant): DailyCredit? = current.ongoingTripCredit(at)

    // MARK: - Ce que l'écran fait

    /**
     * Range le contenu reçu. Les trois listes sont triées **une fois**, ici, et
     * pas à chaque recomposition : trier dans une vue, c'est trier à chaque
     * image d'animation.
     */
    private fun apply(loaded: HomeFeed) {
        content.update {
            it.copy(
                feed = loaded,
                ongoingTrips = loaded.ongoingTrips,
                upcomingTrips = loaded.upcomingTrips,
                pastTrips = loaded.pastTrips,
            )
        }
    }

    /**
     * Envoie le vocal qu'on vient d'enregistrer.
     *
     * **Au carnet en cours** — le premier, celui dont la conversation s'ouvre
     * juste après avec la bulle déjà posée. C'est la promesse écrite sur la
     * feuille d'enregistrement — « MemoBook l'attribuera automatiquement » :
     * on n'a rien choisi avant de parler, donc on ne choisit rien après. Un
     * vocal est un tour de **une** conversation (`docs/conversation.md` § 2) ;
     * il ne se recopie plus dans un second voyage mené de front (22/09/2026).
     *
     * L'envoi lui-même appartient à la [RecordingOutbox] : c'est elle qui
     * décide d'essayer ou de garder, et elle continue sans cet écran. Ce qui
     * reste ici, c'est **la suite** — un souvenir arrivé fait vieillir les
     * compteurs et la jauge du carnet, donc on recharge.
     *
     * Sans aucun carnet en cours, il n'y a rien à faire : la feuille ne
     * s'ouvre pas depuis un accueil sans voyage ouvert.
     *
     * `handoffId` est l'identifiant de la bulle qui va s'afficher dans la
     * conversation — et celui du message côté serveur : la file s'en sert pour
     * dire **où en est cet envoi-là**, et c'est ce qui permet à la bulle de ne
     * pas se déclarer arrivée avant de l'être. Voir `RecordingOutbox.lastDelivery`.
     * `levels` est la forme d'onde relevée pendant l'enregistrement : elle part
     * avec le vocal, pour sa bulle.
     */
    suspend fun upload(audio: RecordedAudio, levels: List<Double> = emptyList(), handoffId: String? = null) {
        val tripId = content.value.ongoingTrips.firstOrNull()?.id ?: return

        val turn = OutgoingTurn.voice(audio, levels = levels, id = handoffId ?: UUID.randomUUID().toString().lowercase())
        when (val outcome = outbox.submit(turn, tripId)) {
            is RecordingOutbox.Delivery.Delivered -> {
                content.update { it.copy(loadFailure = null) }
                // Le reçu porte le crédit **après** ce tour ; sans lui, on le
                // décompte ici. La feuille suivante part du bon reste même si la
                // relecture qui suit échoue.
                settleCredit(tripId, served = outcome.receipt?.dailyCredit, spentMs = audio.creditMs)
                // Le carnet vient de grossir : ses compteurs et sa jauge sont
                // périmés. On recharge plutôt que de les corriger à la main ici
                // — c'est le serveur qui sait ce que le souvenir a produit.
                load()
            }
            RecordingOutbox.Delivery.Queued -> {
                // Rien à dire de plus : la boîte d'information le dit déjà, et
                // mieux qu'un bandeau d'erreur — il ne s'est rien passé de mal.
                content.update { it.copy(loadFailure = null) }
                // **Le vocal en file compte déjà** (03/10/2026) : sans ce
                // décompte, un second vocal de l'accueil, hors ligne, partait
                // d'un reste trop haut — ni prévenu à 4:30, ni coupé à 5:00 — et
                // le serveur le refusait au retour du réseau. Il est sur le
                // disque de la file : on la relit, comme après chaque lecture de
                // l'accueil.
                countWaitingTurns()
            }
            // Le message est déjà posé par la file, [errorMessage] le lit.
            is RecordingOutbox.Delivery.Rejected -> Unit
        }
    }

    /**
     * Le crédit du voyage après un vocal **arrivé** : celui du reçu quand le
     * serveur l'a rendu, sinon le reste d'avant **rechargé** (un vocal du matin
     * ne se retire pas du crédit d'hier) moins ce vocal. Un abonné ne décompte
     * rien — `DailyCredit.consuming` le sait.
     */
    private fun settleCredit(tripId: String, served: DailyCredit?, spentMs: Int) {
        content.update { state ->
            val trips = state.ongoingTrips.map { trip ->
                if (trip.id != tripId) return@map trip
                val credit = served ?: trip.dailyCredit?.refreshed(Instant.now())?.consuming(spentMs) ?: return@map trip
                trip.copy(dailyCredit = credit)
            }
            state.copy(ongoingTrips = trips)
        }
    }

    /**
     * Relit ce que la file garde pour chaque voyage en cours, et ce que ça
     * coûtera au crédit d'aujourd'hui — [State.unreceivedCosts].
     *
     * Après une lecture **seulement** : le crédit qu'elle vient de poser ne
     * connaît pas ces tours. Si la lecture a échoué, l'ancien décompte reste
     * juste — un tour parti entre-temps compterait sinon pour rien.
     *
     * Le total est posé d'un coup, après les lectures du disque : deux
     * relectures qui se croisent ne s'additionnent pas.
     */
    private suspend fun countWaitingTurns(now: Instant = Instant.now()) {
        val costs = mutableMapOf<String, Int>()
        for (trip in content.value.ongoingTrips) {
            val credit = trip.dailyCredit?.refreshed(now) ?: continue
            if (credit.isUnlimited) continue
            // Ce qui attend l'illimité, ou une recharge encore à venir, prendra
            // un autre crédit que celui d'aujourd'hui (`OutgoingTurn.isOnHold`).
            val waiting = outbox.waiting(trip.id).filter { !it.waitingForUnlimited && !it.isWaitingForCredit(now) }
            costs[trip.id] = waiting.sumOf { it.creditCost(credit) }
        }
        content.update { it.copy(unreceivedCosts = costs) }
    }

    /**
     * Supprime un voyage depuis le tiroir de sa carte (Hugo, 17/09/2026).
     *
     * La carte disparaît **sur la réponse du serveur**, pas avant : c'est le
     * récit de tout le monde qui part, et un co-voyageur se voit refuser le
     * geste — la feuille lit alors le refus. Rend `true` quand c'est fait, et
     * recharge l'accueil : les compteurs et la section « en cours » ont changé.
     */
    suspend fun deleteTrip(id: String): Boolean {
        content.update { it.copy(deletingTripId = id, deletionError = null) }
        return try {
            val remove = remove
            val feed = content.value.feed
            if (remove != null) {
                remove(id)
                load()
            } else if (feed != null) {
                apply(HomeFeed(traveller = feed.traveller, trips = feed.trips.filter { it.id != id }, showcase = feed.showcase))
            }
            true
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            content.update { it.copy(deletionError = describe(error)) }
            false
        } finally {
            content.update { it.copy(deletingTripId = null) }
        }
    }

    /** Oublie le refus d'une suppression : à la fermeture de la feuille. */
    fun dismissDeletionError() {
        content.update { it.copy(deletionError = null) }
    }

    /**
     * Rejoint le voyage de quelqu'un par son code d'accès — « Rejoins une
     * aventure ».
     *
     * **Trois issues, et la feuille n'en montre que deux.** Le voyage ouvert,
     * et l'accueil rechargé pour qu'il y soit ; un code qui ne mène nulle
     * part, dit par l'alerte « Oups, voyage introuvable » (Clara, 26/09/2026)
     * — une faute de frappe se corrige dans le champ, sans rien refermer ;
     * tout le reste, un réseau absent ou un retrait par le propriétaire, avec
     * la phrase du serveur.
     */
    suspend fun join(code: String): JoinOutcome {
        val joinByCode = joinByCode
        if (joinByCode == null) {
            // En aperçu, le code de la maquette ouvre le premier voyage du jeu
            // d'essai ; tout autre est introuvable, pour voir l'alerte.
            val trip = content.value.ongoingTrips.firstOrNull() ?: content.value.feed?.trips?.firstOrNull()
            return if (code == "JHKFDA" && trip != null) JoinOutcome.Joined(trip.id) else JoinOutcome.NotFound
        }

        return try {
            val joined = joinByCode(code)
            load()
            JoinOutcome.Joined(joined.trip.id)
        } catch (error: CancellationException) {
            throw error
        } catch (error: ApiError) {
            if (error is ApiError.Server && (error.statusCode == 404 || error.code == "trip_not_found")) {
                JoinOutcome.NotFound
            } else {
                JoinOutcome.Failed(describe(error))
            }
        } catch (error: Exception) {
            JoinOutcome.Failed(describe(error))
        }
    }

    /**
     * Ce que fait « Réessayer » du bandeau d'erreur : oublier le refus, et
     * redemander le contenu. Les deux, parce qu'un seul bouton ne peut pas
     * laisser un message à l'écran après qu'on a appuyé dessus.
     */
    suspend fun retry() {
        outbox.dismissRejection()
        load()
    }

    suspend fun load() {
        content.update { it.copy(isLoading = true) }
        try {
            // **Ce qu'on avait, tout de suite.** Seulement au premier
            // chargement : un « tirer pour rafraîchir » ne doit pas remplacer ce
            // qui est à l'écran par une copie plus ancienne le temps d'un
            // aller-retour.
            if (content.value.feed == null) {
                cached?.invoke()?.let { stored ->
                    apply(stored)
                    content.update { it.copy(freshness = ContentFreshness.Restored) }
                    countWaitingTurns()
                }
            }

            try {
                val loaded = source()
                // **Avant** de poser la valeur : la comparaison porte sur ce qui
                // est encore à l'écran.
                val freshness = contentFreshness(loaded, content.value.feed)

                // Le personnage et le crédit du bac à sable survivent à un
                // rechargement : sans ça, tirer sur la liste pour la rafraîchir
                // remettait l'abonnement du serveur et le profil, lui, gardait
                // le sien. Deux écrans qui ne racontaient plus la même
                // histoire. Sous `#if DEBUG` sur iOS ; ici, sans effet hors du
                // panneau d'essai, seul à poser un personnage ou un crédit.
                apply(debugSandboxed(loaded))
                content.update { it.copy(freshness = freshness, loadFailure = null) }

                // Hors ligne, la lecture rend le cache sans lever : son crédit
                // ne compte pas plus que celui du serveur ce qui attend dans la
                // file.
                countWaitingTurns()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                // Hors ligne **avec** du contenu déjà à l'écran, on se tait : la
                // boîte d'information dit déjà pourquoi rien ne bouge, et un
                // bandeau rouge par-dessus ferait croire à une panne de l'app.
                // Sans rien à montrer, en revanche, l'erreur est la seule chose
                // qui explique l'écran vide.
                val failure = if (isOffline && content.value.feed != null) null else describe(error)
                content.update { it.copy(loadFailure = failure) }
            }
        } finally {
            content.update { it.copy(isLoading = false) }
        }
    }

    /**
     * **Le rappel de fin de voyage peut-il se tenir ici ?** Sans jumeau sur iOS,
     * où « Résilier » ouvre toujours la feuille de gestion des abonnements
     * d'Apple.
     *
     * Sur Android, un abonnement pris sur l'**App Store** ne se gère pas : ni
     * Google Play ni l'app n'y ont la main, et le proposer mènerait à une page
     * qui ne le connaît pas. Le rappel ne s'ouvre donc que pour un abonnement
     * tenu par **Google Play** — « Résilier » mène alors à sa page
     * d'abonnements. Quand on ne sait pas qui le tient (le profil ne se lit
     * pas, hors ligne), le rappel attend la prochaine lecture plutôt que de
     * risquer la mauvaise porte.
     */
    suspend fun tripEndReminderCanOpenHere(): Boolean {
        val managedByAppStore = subscriptionIsManagedByAppStore ?: return true
        return try {
            managedByAppStore() == false
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            false
        }
    }

    /** Le `localizedDescription` d'iOS : la phrase de l'API, déjà en français. */
    private fun describe(error: Throwable): String =
        (error as? ApiError)?.errorDescription ?: error.localizedMessage ?: error.toString()

    // MARK: - Bac à sable
    //
    // De quoi voir les états de l'accueil sans back-end : un voyage en cours, un
    // voyage à venir, des carnets passés, ou rien du tout. Sous `#if DEBUG` sur
    // iOS ; ici compilées dans les deux builds, et seul le panneau d'essai —
    // qui n'existe que dans une app débogable — les appelle.
    //
    // Elles vivent dans cette classe et non à côté du panneau parce que l'état
    // est privé : le bac à sable peut ranger le contenu, une vue ne le peut pas.

    /**
     * Repart du jeu d'essai complet, personnage et crédit compris — et remet
     * le réseau, la file et les messages à zéro.
     */
    internal fun debugReset() {
        SandboxPersona.current = null
        SandboxCredit.reset()
        content.update { it.copy(loadFailure = null, unreceivedCosts = emptyMap()) }
        apply(HomeFeed.fixture)
        viewModelScope.launch { outbox.debugReset() }
    }

    /** Un compte tout neuf : aucun voyage. */
    internal fun debugRemoveAllTrips() {
        content.update { it.copy(loadFailure = null) }
        apply(HomeFeed(traveller = debugTraveller, trips = emptyList(), showcase = content.value.feed?.showcase))
    }

    /**
     * Ajoute un voyage à l'étape voulue. Rejouable : chaque appel en pose un
     * nouveau, tiré dans une petite banque de destinations.
     */
    internal fun debugAddTrip(stage: TripStage) {
        content.update { it.copy(loadFailure = null) }
        val existing = content.value.feed?.trips.orEmpty()
        apply(
            HomeFeed(
                traveller = debugTraveller,
                trips = existing + Trip.debugRandom(stage, index = existing.size),
                showcase = content.value.feed?.showcase,
            ),
        )
    }

    /**
     * Devenir un abonné : il raconte sans limite — plus de crédit compté dans
     * la conversation ni dans les réglages — et, dans le profil, la pastille
     * « Abonné(e) » et la ligne « Mon abonnement ».
     */
    internal fun debugBecomeSubscriber() {
        debugPlay(SandboxPersona.Subscriber)
    }

    /** Sans abonnement : le crédit du jour compte, et le profil propose « Découvrir l'abonnement ». */
    internal fun debugBecomeFree() {
        debugPlay(SandboxPersona.Free)
    }

    /**
     * Quelqu'un qui n'a **jamais** été abonné : le paywall s'ouvre sur la
     * découverte en trois écrans. Le profil du jeu d'essai démarre abonné, et
     * « Sans abonnement » en fait un ancien abonné : sans ce personnage, la
     * découverte était inatteignable dans le bac à sable (recette du
     * 03/10/2026). Le panneau remet aussi la session à zéro.
     */
    internal fun debugBecomeNeverSubscribed() {
        debugPlay(SandboxPersona.NeverSubscribed)
    }

    /**
     * Fait servir ce crédit du jour à chaque voyage — « Crédit neuf », « Plus
     * que 30 s », « Crédit épuisé » —, par le double d'API (fil de la
     * conversation, ses mises à jour, le reçu d'un tour, réglages du voyage) et
     * sur l'accueil tout de suite. Le crédit ne compte que pour qui n'est pas
     * abonné : le personnage passe donc sans abonnement.
     *
     * Avec un vrai serveur, seul l'accueil se retouche : la conversation et les
     * réglages lisent le crédit du serveur.
     */
    internal fun debugPlayCredit(preset: SandboxCredit.Preset) {
        SandboxCredit.play(preset)
        debugPlay(SandboxPersona.Free)
    }

    /**
     * Fait jouer un personnage à l'app entière — l'accueil tout de suite, le
     * profil à la prochaine ouverture. Voir [SandboxPersona].
     */
    private fun debugPlay(persona: SandboxPersona) {
        SandboxPersona.current = persona
        content.update { it.copy(loadFailure = null) }
        apply(
            debugSandboxed(
                HomeFeed(
                    traveller = debugTraveller,
                    trips = content.value.feed?.trips.orEmpty(),
                    showcase = content.value.feed?.showcase,
                ),
            ),
        )
    }

    /**
     * Ce que le bac à sable retouche sur un accueil reçu : le crédit des
     * voyages en cours d'abord — seulement si un réglage est joué, pour ne
     * jamais maquiller celui d'un vrai serveur —, puis le personnage.
     */
    private fun debugSandboxed(loaded: HomeFeed): HomeFeed {
        val credited = if (SandboxCredit.isPlaying) SandboxCredit.applied(loaded) else loaded
        return SandboxPersona.current?.applied(credited) ?: credited
    }

    /** Montre l'état d'erreur, sans toucher au contenu. */
    internal fun debugShowError() {
        // Le `URLError(.notConnectedToInternet).localizedDescription` d'iOS,
        // tel qu'un iPhone réglé en français l'écrit.
        content.update { it.copy(loadFailure = "La connexion Internet semble être désactivée.") }
    }

    // MARK: Hors ligne
    //
    // Le hors-ligne du bac à sable n'est **pas** un faux affichage : il coupe
    // vraiment le réseau pour l'app, et tout ce qui suit — le vocal qui part
    // sur le disque, la file qui se vide au retour — emprunte le même chemin
    // que sous un tunnel. C'est la seule façon de vérifier que la promesse
    // écrite dans la boîte est tenue.

    /**
     * Coupe le réseau, ou le rétablit. Le rétablissement déclenche l'envoi de
     * ce qui attendait, exactement comme une vraie reconnexion.
     */
    internal fun debugToggleOffline() {
        outbox.debugSetOffline(!isOffline)
    }

    /**
     * Met un vocal en file sans passer par le micro : de quoi voir la boîte
     * « tes vocaux sont conservés » sans avoir à parler.
     *
     * Il vise **le carnet en cours**, comme un vrai. Sur un voyage du jeu
     * d'essai, le serveur le refusera à la reconnexion et la file le dira —
     * c'est le comportement attendu, pas un bug du bac à sable.
     */
    internal suspend fun debugQueueRecording() {
        val tripId = content.value.ongoingTrips.firstOrNull()?.id
        if (tripId == null) {
            content.update { it.copy(loadFailure = "Aucun voyage en cours : il n’y a pas de carnet où envoyer un vocal.") }
            return
        }
        outbox.debugQueue(debugSilence(), tripId)
    }

    /** Montre l'envoi en cours, quelques secondes. */
    internal fun debugShowSending() {
        outbox.debugShowSending(1)
    }

    /** Montre la confirmation d'arrivée. */
    internal fun debugShowDelivered() {
        outbox.debugShowDelivered(1)
    }

    private val debugTraveller: Traveller
        get() = content.value.feed?.traveller ?: HomeFeed.fixture.traveller
}

/**
 * Ce que ce vocal consomme du crédit du jour, en millisecondes — sa durée,
 * comme le serveur la mesure.
 */
internal val RecordedAudio.creditMs: Int get() = (maxOf(0.0, duration) * 1000).roundToInt()

/**
 * Un vocal de bac à sable : la durée et le nom d'un vrai, et zéro octet de
 * son. Il ne sert qu'à remplir la file. Le `RecordedAudio.debugSilence`
 * d'iOS — `RecordedAudio` n'a pas d'objet compagnon où l'écrire —, et une
 * fonction : chaque appel tire un nouveau nom, comme le `static var` d'iOS.
 */
internal fun debugSilence(): RecordedAudio = RecordedAudio(
    data = ByteArray(0),
    filename = "sandbox-${UUID.randomUUID().toString().uppercase()}.m4a",
    mimeType = "audio/m4a",
    duration = 12.0,
    recordedAt = Instant.now(),
)

/** Ce qu'a donné un code d'accès — voir [HomeModel.join]. */
sealed interface JoinOutcome {
    data class Joined(val tripId: String) : JoinOutcome

    /** Le code ne mène à aucun voyage : l'alerte « Oups, voyage introuvable ». */
    data object NotFound : JoinOutcome

    data class Failed(val message: String) : JoinOutcome
}
