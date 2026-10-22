package com.memobook.feature.tripsettings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.memobook.core.BookCopy
import com.memobook.core.DailyCredit
import com.memobook.core.NarrationPace
import com.memobook.core.TripNotificationPreferences
import com.memobook.core.TripSettings
import com.memobook.core.TripSettingsEdit
import com.memobook.core.TripTheme
import com.memobook.feature.CachedValue
import com.memobook.feature.ContentFreshness
import com.memobook.feature.chat.OutgoingTurn
import com.memobook.feature.contentFreshness
import com.memobook.networking.ApiError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Instant
import kotlin.time.Duration.Companion.seconds

/**
 * Ce que l'écran des paramètres d'un voyage sait faire : les charger, et
 * enregistrer ce qu'on y change. Jumeau de `TripSettings/TripSettingsModel.swift`.
 *
 * Même construction que `ProfileModel` : le modèle ne connaît pas l'API, il
 * reçoit **des fonctions** — une qui lit, une qui écrit. L'app leur branche
 * `GET` et `PATCH /v1/trips/:id/settings` ; les aperçus n'en fournissent aucune
 * et travaillent alors en mémoire, sans serveur.
 *
 * **Un réglage modifié part au serveur dès qu'il est touché**, un par un. Pas
 * de bouton « Enregistrer » : c'est le contrat des lignes des Réglages, ici
 * comme dans le profil. Et un seul réglage à la fois dans la requête
 * ([TripSettingsEdit]), pour ne pas écraser ce qu'un co-voyageur aurait
 * changé entre-temps.
 *
 * @param source la lecture des réglages. Par défaut, le jeu d'essai.
 * @param persist l'écriture d'un réglage. `null` en aperçu : l'écran bouge, rien ne part.
 * @param removeCompanion retirer un co-voyageur — un geste que le `PATCH` des
 *   réglages ne sait pas porter : il touche `memo_members`, pas `memos`.
 * @param resendInvitation renvoyer son lien d'invitation, même raison.
 * @param delete supprimer le voyage — **le propriétaire seul**, et le serveur le
 *   vérifie. `null` en aperçu : on ne supprime pas un voyage depuis une maquette.
 * @param clearConversation supprimer la conversation — le propriétaire seul,
 *   comme le voyage : le serveur refuse un co-voyageur (`docs/conversation.md`
 *   § 7), et l'écran pâlit le lien pour le dire avant. `null` en aperçu, où la
 *   feuille se joue quand même.
 * @param cached ce qu'on avait sur le disque — voir `ContentCache`. `null` en aperçu.
 * @param themes les thèmes de voyage, **la même source qu'à la création du
 *   voyage** — voir [State.themes].
 * @param waitingTurns les tours **envoyés** à ce voyage que le serveur n'a pas
 *   encore reçus — ce que la file garde, hors ligne surtout. `null` en aperçu.
 */
class TripSettingsModel(
    private val tripId: String,
    private val source: suspend (String) -> TripSettings = { TripSettings.fixture },
    private val persist: (suspend (String, TripSettingsEdit) -> TripSettings)? = null,
    private val removeCompanion: (suspend (String, String) -> TripSettings)? = null,
    private val resendInvitation: (suspend (String, String) -> Unit)? = null,
    delete: (suspend (String) -> Unit)? = null,
    clearConversation: (suspend (String) -> Unit)? = null,
    private val cached: CachedValue<TripSettings>? = null,
    themes: suspend () -> List<TripTheme> = { TripTheme.fixtures },
    private val waitingTurns: (suspend () -> List<OutgoingTurn>)? = null,
) : ViewModel() {

    /**
     * Les lignes qui se corrigent sur place, sans feuille. Une seule pour
     * l'instant ; le type est là pour que la coche ne soit jamais un booléen
     * anonyme.
     */
    enum class SavedField { Name }

    /**
     * Ce que l'écran lit.
     *
     * @property errorAdvice ce qu'on peut **faire** de l'erreur, sous sa phrase —
     *   voir `ApiError.recoveryAdvice`. « Erreur interne du serveur » seul
     *   laissait chercher ce qu'on avait mal fait (Hugo, 15/09/2026).
     * @property freshness ce que le dernier chargement a appris. C'est lui que la
     *   vue anime — voir `BrandRefreshFlash`.
     * @property isDeleting `true` pendant la suppression. L'écran verrouille
     *   alors la feuille : la demande est définitive, elle ne doit pas partir
     *   deux fois.
     * @property isClearingConversation `true` pendant la suppression de la
     *   conversation. Même verrou que pour le voyage : la feuille ne repart pas
     *   deux fois.
     * @property confirmation ce qu'on vient de faire, et qu'il faut dire. Un mot
     *   sous la liste de la feuille — « Invitation renvoyée » —, pas une
     *   alerte : l'action a réussi, il n'y a rien à confirmer.
     * @property justSaved la ligne dont la correction sur place vient d'être
     *   enregistrée — la coche verte du crayon, le temps qu'on la voie.
     * @property themes les thèmes de voyage, dans l'ordre du serveur — « Autre »
     *   en dernier. **La même source qu'à la création du voyage**, et c'est la
     *   note du nœud qui l'exige : « les thèmes doivent venir de la même base
     *   de données que lors de la création ». Un second jeu ici ferait dériver
     *   `memos.theme`, que l'agent de rédaction lit tel quel.
     * @property unreceivedCostMs ce que les tours envoyés et pas encore reçus
     *   coûteront au crédit d'aujourd'hui — relu après chaque lecture des
     *   réglages, jamais mêlé au crédit servi. Voir [dailyCredit].
     */
    data class State(
        val settings: TripSettings? = null,
        val errorMessage: String? = null,
        val errorAdvice: String? = null,
        val freshness: ContentFreshness = ContentFreshness.Unknown,
        val isDeleting: Boolean = false,
        val isClearingConversation: Boolean = false,
        val confirmation: String? = null,
        val justSaved: SavedField? = null,
        val themes: List<TripTheme> = emptyList(),
        val unreceivedCostMs: Int = 0,
    ) {
        /**
         * `true` tant qu'on n'a pas de valeurs. L'écran se dessine quand même :
         * ses intitulés, ses groupes et ses lignes appartiennent à l'app, pas au
         * serveur. Seules les valeurs portent une barre d'attente — voir
         * `BrandSkeleton`.
         */
        val isLoading: Boolean get() = settings == null && errorMessage == null

        /**
         * Où en est le voyage aujourd'hui, et si celui qui lit raconte sans
         * limite. `null` quand le serveur ne le sert pas encore : la ligne
         * disparaît alors, plutôt que d'annoncer un reste inventé.
         *
         * **Il ne se rafraîchit qu'avec les réglages** : une seule source, le
         * `GET`. Après un abonnement, la vue appelle [load] pour relire
         * `isUnlimited` — le serveur seul sait que l'achat est passé.
         *
         * **Passé minuit, le crédit d'hier se recharge** (03/10/2026) —
         * `DailyCredit.refreshed(now)`, la règle de la conversation et de
         * l'accueil. Les réglages s'ouvrent sur le cache : la ligne et la
         * feuille y lisaient « Plus rien pour aujourd’hui » le lendemain d'un
         * crédit épuisé, tant que le serveur n'avait pas répondu.
         *
         * **Seul l'envoyé compte** (Hugo, 06/10/2026 : « il ne faut pas que
         * lorsqu'on va dans paramètres du voyage > crédits du jour ces derniers
         * soient marqués comme consommés »). Le crédit servi ne contient que ce
         * que le serveur a reçu ; on en retire ce qui a été **envoyé** et attend
         * encore dans la file ([unreceivedCostMs]) — la règle de la
         * conversation et de l'accueil, pour que les trois écrans disent le
         * même reste. Un vocal en cours, **ou en pause**, n'est envoyé nulle
         * part : il ne compte ici pour rien, et ne comptera qu'à son « Envoyer ».
         */
        val dailyCredit: DailyCredit?
            get() = settings?.dailyCredit?.refreshed(Instant.now())?.consuming(unreceivedCostMs)
    }

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    /** Le crédit du jour tel que l'écran le dit — voir [State.dailyCredit]. */
    val dailyCredit: DailyCredit? get() = _state.value.dailyCredit

    private val removeTrip = delete
    private val clearTripConversation = clearConversation
    private val readThemes = themes

    /**
     * L'envoi en cours. Le garder permet d'annuler celui d'avant quand deux
     * bascules s'enchaînent : c'est la dernière qui compte, et la réponse
     * d'une requête dépassée réécrirait l'écran avec une valeur périmée.
     */
    private var pendingSave: Job? = null

    // MARK: - Le chargement

    /**
     * Les thèmes, chargés à l'ouverture de leur feuille et pas avant : c'est
     * un appel de plus, et la plupart des visites de cet écran ne changent pas
     * de thème. Un échec laisse la rangée vide et le champ libre ouvert — on
     * peut toujours écrire son thème à la main.
     */
    suspend fun loadThemes() {
        if (_state.value.themes.isNotEmpty()) return
        val loaded = try {
            readThemes()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            emptyList()
        }
        _state.update { it.copy(themes = loaded) }
    }

    suspend fun load() {
        // Trente valeurs pour un écran qu'on ouvre pour en changer une : c'est
        // celui qui gagne le plus à s'ouvrir sur ce qu'on avait.
        if (_state.value.settings == null) {
            cached?.invoke()?.let { stored ->
                _state.update { it.copy(settings = stored, freshness = ContentFreshness.Restored) }
            }
        }

        try {
            val loaded = source(tripId)
            _state.update {
                it.copy(
                    settings = loaded,
                    freshness = contentFreshness(loaded, it.settings),
                    errorMessage = null,
                    errorAdvice = null,
                )
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            report(error)
        }
        countWaitingTurns()
    }

    /**
     * Relit ce que la file garde pour ce voyage, et ce que ça coûtera au
     * crédit d'aujourd'hui. Ce qui attend l'illimité ou la recharge de
     * minuit prendra un autre crédit que celui-ci — même filtre que
     * l'accueil (`OutgoingTurn.isOnHold`).
     */
    private suspend fun countWaitingTurns(now: Instant = Instant.now()) {
        val read = waitingTurns
        val credit = _state.value.settings?.dailyCredit?.refreshed(now)
        if (read == null || credit == null || credit.isUnlimited) {
            _state.update { it.copy(unreceivedCostMs = 0) }
            return
        }
        val waiting = read().filter { !it.waitingForUnlimited && !it.isWaitingForCredit(at = now) }
        val cost = waiting.sumOf { it.creditCost(credit) }
        _state.update { it.copy(unreceivedCostMs = cost) }
    }

    // MARK: - Supprimer le voyage

    /**
     * Supprime le voyage et tout ce qui est à lui. Rend `true` quand c'est
     * fait — c'est le signal qui ramène l'app à l'accueil.
     *
     * L'écran a déjà demandé confirmation : ce n'est pas au modèle de la
     * redemander, et il n'y a rien à annuler après. Un refus du serveur — un
     * co-voyageur qui essaie, le propriétaire seul y a droit — reste à
     * l'écran, dans la feuille.
     */
    suspend fun delete(): Boolean {
        val remove = removeTrip ?: return false

        _state.update { it.copy(isDeleting = true) }
        return try {
            remove(tripId)
            clearError()
            true
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            report(error)
            false
        } finally {
            _state.update { it.copy(isDeleting = false) }
        }
    }

    // MARK: - Supprimer la conversation

    /**
     * Efface le fil de la conversation — les messages, pas le mot d'accueil
     * de MEMO, qui est là pour quiconque n'a rien dit encore. Rend `true`
     * quand c'est fait : la feuille se ferme, et on reste sur les réglages.
     *
     * L'écran a déjà demandé confirmation, comme pour le voyage. Sans
     * fonction — en aperçu —, la feuille se ferme comme si c'était fait.
     */
    suspend fun clearConversation(): Boolean {
        val clear = clearTripConversation ?: return true

        _state.update { it.copy(isClearingConversation = true) }
        return try {
            clear(tripId)
            clearError()
            true
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            report(error)
            false
        } finally {
            _state.update { it.copy(isClearingConversation = false) }
        }
    }

    /**
     * Pose l'erreur **et son conseil** : la phrase dit ce qui s'est passé, le
     * conseil ce qu'on peut faire.
     */
    private fun report(error: Throwable) {
        val message = (error as? ApiError)?.errorDescription ?: error.localizedMessage ?: error.toString()
        _state.update { it.copy(errorMessage = message, errorAdvice = (error as? ApiError)?.recoveryAdvice) }
    }

    private fun clearError() {
        _state.update { it.copy(errorMessage = null, errorAdvice = null) }
    }

    // MARK: - Ce qu'on change depuis l'écran
    //
    // Des fonctions plutôt qu'un `settings` ouvert en écriture : une vue ne
    // doit pas pouvoir poser une valeur sans qu'elle parte au serveur.

    /**
     * Le nom du voyage, corrigé sur place depuis la première ligne de
     * l'écran — comme le téléphone sur le profil : le clavier s'ouvre sur la
     * ligne, et sortir du champ enregistre (Hugo, 18/09/2026).
     *
     * Un nom vide n'est pas un nom : on ne l'envoie pas, et la ligne reprend
     * celui qu'elle avait — elle relit le modèle en sortant du champ.
     */
    fun setName(name: String) {
        val trimmed = name.trim()
        val current = _state.value.settings ?: return
        if (trimmed.isEmpty() || trimmed == current.name) return
        _state.update { it.copy(settings = current.copy(name = trimmed)) }
        save(TripSettingsEdit.Name(trimmed), confirming = SavedField.Name)
    }

    fun setNotifications(isOn: Boolean) {
        val current = _state.value.settings ?: return
        _state.update { it.copy(settings = current.copy(wantsNotifications = isOn)) }
        save(TripSettingsEdit.Notifications(isOn))
    }

    fun setPublicGallery(isOn: Boolean) {
        val current = _state.value.settings ?: return
        _state.update { it.copy(settings = current.copy(isPublicGallery = isOn)) }
        save(TripSettingsEdit.PublicGallery(isOn))
    }

    /**
     * Les deux dates d'un coup : elles se bornent l'une l'autre, et les
     * envoyer séparément ferait refuser l'intermédiaire par le serveur.
     */
    fun setDates(start: Instant?, end: Instant?) {
        val current = _state.value.settings ?: return
        _state.update { it.copy(settings = current.copy(startDate = start, endDate = end)) }
        save(TripSettingsEdit.Dates(start = start, end = end))
    }

    fun setPace(pace: NarrationPace) {
        val current = _state.value.settings ?: return
        _state.update { it.copy(settings = current.copy(narrationPace = pace)) }
        save(TripSettingsEdit.NarrationPace(pace))
    }

    fun setTheme(theme: String) {
        val trimmed = theme.trim()
        val current = _state.value.settings ?: return
        if (trimmed.isEmpty() || trimmed == current.theme) return
        _state.update { it.copy(settings = current.copy(theme = trimmed)) }
        save(TripSettingsEdit.Theme(trimmed))
    }

    fun setNotificationPreferences(preferences: TripNotificationPreferences) {
        val current = _state.value.settings ?: return
        _state.update { it.copy(settings = current.copy(notifications = preferences)) }
        save(TripSettingsEdit.NotificationPreferences(preferences))
    }

    // MARK: - Les co-voyageurs

    /**
     * Retire quelqu'un du voyage.
     *
     * **Le propriétaire ne se retire pas** — c'est la note « Logique » de la
     * maquette, et c'est aussi ce que le serveur refuserait. Le garde-fou est
     * ici pour que l'action ne soit pas *proposée*, pas pour rattraper un
     * appel.
     */
    fun remove(companion: com.memobook.core.Companion) {
        val removeCompanion = removeCompanion ?: return
        if (companion.isOwner) return
        val current = _state.value.settings ?: return

        // L'écran a déjà bougé : une ligne qui reste en place le temps d'un
        // aller-retour donne l'impression que le geste n'a pas pris.
        _state.update { it.copy(settings = current.copy(companions = current.companions.filter { c -> c.id != companion.id })) }

        pendingSave?.cancel()
        pendingSave = viewModelScope.launch {
            try {
                val updated = removeCompanion(tripId, companion.id)
                if (!currentCoroutineContext().isActive) return@launch
                _state.update { it.copy(settings = updated, errorMessage = null) }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                report(error)
                load()
            }
        }
    }

    /** Renvoie le lien d'invitation à quelqu'un qui n'est jamais entré. */
    fun resendInvitation(companion: com.memobook.core.Companion) {
        val resendInvitation = resendInvitation ?: return
        if (!companion.isPending) return

        viewModelScope.launch {
            try {
                resendInvitation(tripId, companion.id)
                confirm(BookCopy.Invite.resent(companion.name))
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                report(error)
            }
        }
    }

    /**
     * La coche d'une ligne qui se corrige sur place — le même accusé de
     * réception que sur le profil, quatre secondes, puis plus rien.
     */
    private fun confirm(field: SavedField) {
        _state.update { it.copy(justSaved = field) }
        viewModelScope.launch {
            delay(4.seconds)
            _state.update { if (it.justSaved == field) it.copy(justSaved = null) else it }
        }
    }

    /**
     * Un mot qui s'efface tout seul. Il ne demande rien, il **accuse
     * réception** — le laisser à l'écran obligerait à le refermer.
     */
    private fun confirm(message: String) {
        _state.update { it.copy(confirmation = message) }
        viewModelScope.launch {
            delay(4.seconds)
            _state.update { if (it.confirmation == message) it.copy(confirmation = null) else it }
        }
    }

    /**
     * Envoie un réglage, et remplace l'écran par ce que le serveur relit.
     *
     * **L'écran a déjà bougé** quand on arrive ici : un interrupteur qui
     * attend un aller-retour réseau pour basculer se lit comme cassé. La
     * réponse ne fait que confirmer — ou, en cas d'échec, remettre les
     * valeurs du serveur, ce qui annule visiblement la bascule.
     */
    private fun save(edit: TripSettingsEdit, confirming: SavedField? = null) {
        val persist = persist ?: return

        pendingSave?.cancel()
        _state.update { it.copy(justSaved = null) }
        pendingSave = viewModelScope.launch {
            try {
                val updated = persist(tripId, edit)
                if (!currentCoroutineContext().isActive) return@launch
                _state.update { it.copy(settings = updated, errorMessage = null, errorAdvice = null) }
                if (confirming != null) confirm(confirming)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                report(error)
                // Remettre ce que le serveur a vraiment : sans ça,
                // l'interrupteur resterait sur une valeur que personne n'a
                // enregistrée.
                load()
            }
        }
    }

    // MARK: - Le bac à sable

    /** Les états du crédit que le panneau de bac à sable rejoue. Debug seulement. */
    enum class DailyCreditDebugState {
        /** Rien raconté aujourd'hui : 5 minutes devant soi. */
        Fresh,

        /** Trente secondes : le seuil où la barre d'enregistrement prévient. */
        LastSeconds,

        /** Plus rien : la ligne passe au rouge, la feuille dit « reviens demain ». */
        Exhausted,

        /** Abonné : « Illimité », sans jauge ni bouton. */
        Unlimited,
    }

    /**
     * Rejoue un état du crédit du jour, **sans rien envoyer**.
     *
     * Le jeu d'essai n'en montre qu'un (un voyage entamé). Les trois autres
     * sont ceux dont le dessin n'existe nulle part ailleurs : la jauge pleine,
     * la jauge rouge, et la ligne d'un abonné. Si le serveur n'a pas servi de
     * crédit, on part du barème du catalogue. Le panneau qui l'appelle n'existe
     * qu'en Debug.
     */
    fun debugPlayDailyCredit(state: DailyCreditDebugState) {
        val current = _state.value.settings ?: return
        val credit = current.dailyCredit ?: DailyCredit()
        val usedMs = when (state) {
            DailyCreditDebugState.Fresh, DailyCreditDebugState.Unlimited -> 0
            DailyCreditDebugState.LastSeconds -> maxOf(0, credit.limitMs - credit.warningRemainingMs)
            DailyCreditDebugState.Exhausted -> credit.limitMs
        }
        val played = credit.copy(isUnlimited = state == DailyCreditDebugState.Unlimited, usedMs = usedMs)
        _state.update { it.copy(settings = current.copy(dailyCredit = played)) }
    }

    /**
     * Ajoute un co-voyageur **à l'écran seulement**, pour voir la feuille se
     * remplir et son tiroir se glisser.
     *
     * Le jeu d'essai en compte deux, et il faut un compte de plus pour en
     * inviter un vrai : sans ça, le retrait et l'invitation relancée ne se
     * vérifient qu'à deux, et jamais sur une invitation en attente. Retirer
     * celui-ci passe par le même chemin que les autres — la réponse du
     * serveur remettra la liste d'aplomb.
     */
    internal fun debugAddCompanion() {
        val current = _state.value.settings ?: return
        val index = current.companions.size
        val added = com.memobook.core.Companion(
            id = "debug-companion-$index-${java.util.UUID.randomUUID().toString().take(4)}",
            name = debugCompanionNames[index % debugCompanionNames.size],
            role = "Co-voyageur",
            // Un sur deux n'a pas encore accepté : c'est l'état qui porte
            // « Relancer l'invitation ».
            isPending = index % 2 == 0,
        )
        _state.update { it.copy(settings = current.copy(companions = current.companions + added)) }
    }

    /** Vide les valeurs pour rejouer l'état de chargement. Debug seulement. */
    internal fun debugShowSkeleton() {
        _state.update { it.copy(settings = null, errorMessage = null, errorAdvice = null) }
    }

    private companion object {
        val debugCompanionNames = listOf("Camille Roux", "Sacha Blin", "Inès Fabre", "Naïm Bacri", "Lou Vidal")
    }
}
