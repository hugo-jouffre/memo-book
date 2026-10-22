package com.memobook.feature.trip

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.memobook.core.Trip
import com.memobook.core.TripDetail
import com.memobook.core.TripStep
import com.memobook.core.TripTransport
import com.memobook.feature.CachedValue
import com.memobook.feature.ContentFreshness
import com.memobook.feature.contentFreshness
import com.memobook.networking.ApiError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlin.time.Duration.Companion.seconds

/**
 * Ce que l'accueil d'un voyage sait faire : charger son contenu, et filtrer
 * ses étapes. Jumeau de `Trip/TripHomeModel.swift`.
 *
 * Même construction que `HomeModel` et `ProfileModel` : le modèle ne connaît
 * pas l'API, il reçoit **une source**. L'app y branche `api.tripDetail(id)`
 * (voir [com.memobook.feature.trip.tripModel]), les aperçus n'en fournissent
 * aucune et montrent les quatre états sur le jeu d'essai.
 *
 * L'intention de l'écran, `TripIntent`, vit dans `Navigation.kt` avec les
 * autres : c'est le contrat avec `RootView`.
 *
 * @param source le voyage, par son identifiant.
 * @param cached ce qu'on avait sur le disque — voir `ContentCache`. `null` en aperçu.
 * @param homeCard ce que la carte de l'accueil sait du voyage — titre, dates,
 *   photo —, pour l'ouvrir hors ligne quand il n'a **jamais** été ouvert ici
 *   (D11, Hugo, 19/10/2026). `null` en aperçu.
 * @param validateStep « Valider cette étape ». `null` en aperçu, où le geste
 *   reste possible mais ne parle à aucun serveur.
 * @param deleteEntry efface un souvenir — `DELETE /v1/entries/:id` (T235).
 *   `null` en aperçu : la croix ne paraît pas.
 */
class TripHomeModel(
    private val tripId: String,
    private val source: suspend (String) -> TripDetail = { TripDetail.fixture(it) },
    private val cached: CachedValue<TripDetail>? = null,
    private val homeCard: CachedValue<Trip>? = null,
    private val validateStep: (suspend (String, String) -> TripDetail)? = null,
    private val deleteEntry: (suspend (String) -> Unit)? = null,
) : ViewModel() {

    /**
     * Ce que l'écran lit.
     *
     * @property country,transport les deux filtres. `null` veut dire « tous » :
     *   c'est l'état d'ouverture de l'écran, et celui vers lequel « Tout
     *   afficher » ramène. Il y en a eu un troisième, sur une étape — retiré,
     *   voir `TripStepsSection` (T30).
     * @property freshness ce que le dernier chargement a appris. C'est lui que
     *   la vue anime — voir `BrandRefreshFlash`.
     * @property confirmation un mot qui s'efface tout seul, après une
     *   validation réussie — même motif que `TripSettingsModel.confirm`.
     * @property deletingStepId l'étape dont on efface les souvenirs, le temps
     *   des requêtes.
     * @property stepDeletionError ce que le serveur a répondu si l'effacement a
     *   échoué — lu dans la feuille de confirmation.
     */
    data class State(
        val detail: TripDetail? = null,
        val errorMessage: String? = null,
        val country: String? = null,
        val transport: TripTransport? = null,
        val freshness: ContentFreshness = ContentFreshness.Unknown,
        val confirmation: String? = null,
        val deletingStepId: String? = null,
        val stepDeletionError: String? = null,
    ) {
        /**
         * `true` tant qu'on n'a rien à montrer. L'écran ne dessine alors rien
         * plutôt qu'un demi-voyage.
         */
        val isLoading: Boolean get() = detail == null && errorMessage == null

        /**
         * Les étapes qui restent une fois les filtres posés.
         *
         * Les deux se combinent : choisir un pays **et** un transport ne garde
         * que ce qui satisfait les deux. C'est ce qu'on attend d'une barre de
         * filtres, et ça évite d'avoir à expliquer une règle de priorité.
         */
        val visibleSteps: List<TripStep>
            get() {
                val steps = detail?.steps ?: return emptyList()
                return steps.filter { step ->
                    (country == null || step.destination?.name == country) &&
                        (transport == null || step.transport == transport)
                }
            }

        val hasActiveFilter: Boolean get() = country != null || transport != null
    }

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    val detail: TripDetail? get() = _state.value.detail
    val errorMessage: String? get() = _state.value.errorMessage
    val isLoading: Boolean get() = _state.value.isLoading
    val freshness: ContentFreshness get() = _state.value.freshness
    val confirmation: String? get() = _state.value.confirmation
    val deletingStepId: String? get() = _state.value.deletingStepId
    val stepDeletionError: String? get() = _state.value.stepDeletionError
    val visibleSteps: List<TripStep> get() = _state.value.visibleSteps
    val hasActiveFilter: Boolean get() = _state.value.hasActiveFilter

    var country: String?
        get() = _state.value.country
        set(value) = _state.update { it.copy(country = value) }

    var transport: TripTransport?
        get() = _state.value.transport
        set(value) = _state.update { it.copy(transport = value) }

    private var pendingValidation: Job? = null

    suspend fun load() {
        // Ce qu'on avait, tout de suite, et seulement au premier chargement :
        // un « tirer pour rafraîchir » ne doit pas repasser par une copie.
        if (_state.value.detail == null) {
            cached?.invoke()?.let { stored ->
                _state.update { it.copy(detail = stored, freshness = ContentFreshness.Restored) }
            }
        }

        try {
            val loaded = source(tripId)
            _state.update {
                it.copy(
                    freshness = contentFreshness(loaded, it.detail),
                    detail = loaded,
                    errorMessage = null,
                )
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            // Un échec **ne vide pas** ce qui vient du disque : on garde la
            // page et on pose le bandeau. C'est la même règle que l'accueil
            // hors ligne.
            _state.update { it.copy(errorMessage = describe(error)) }

            // Rien sur le disque, et pas de réseau : un voyage rejoint
            // ailleurs, ou une installation neuve. L'écran s'ouvrait sur un
            // squelette et son bandeau, sans chemin vers la conversation — qui,
            // elle, s'ouvre hors ligne. On le dessine d'après la carte de
            // l'accueil, sans étapes, **sous** le bandeau : la page ne prétend
            // pas être à jour (D11). Une réponse du serveur — un 404, un 500 —
            // n'est pas une panne : elle garde son écran d'erreur.
            if (_state.value.detail == null && (error as? ApiError)?.isTransport == true) {
                homeCard?.invoke()?.let { card ->
                    _state.update { it.copy(detail = TripDetail(trip = card), freshness = ContentFreshness.Restored) }
                }
            }
        }
    }

    // MARK: - Filtres

    fun clearFilters() {
        _state.update { it.copy(country = null, transport = null) }
    }

    // MARK: - Valider une étape

    /**
     * « Valider cette étape » : confirme l'étape et déclenche en fond une
     * nouvelle génération du carnet — l'écran n'a rien d'autre à faire que le
     * dire.
     *
     * **L'écran a déjà bougé** quand la requête part : une coche qui attend un
     * aller-retour réseau pour apparaître se lit comme cassée. Un échec revient
     * à l'état du serveur (`load()`), pas seulement à celui d'avant — une
     * deuxième validation pourrait avoir eu lieu entre-temps.
     */
    fun validateStep(step: TripStep) {
        val validateStepRemotely = validateStep ?: return
        val current = _state.value.detail ?: return
        if (step.validatedAt != null || current.steps.none { it.id == step.id }) return

        _state.update {
            it.copy(detail = current.copy(steps = current.steps.map { candidate -> if (candidate.id == step.id) candidate.validated() else candidate }))
        }

        pendingValidation?.cancel()
        pendingValidation = viewModelScope.launch {
            try {
                val updated = validateStepRemotely(tripId, step.id)
                _state.update { it.copy(detail = updated, errorMessage = null) }
                confirm("Étape validée. Ton carnet va se mettre à jour.")
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                _state.update { it.copy(errorMessage = describe(error)) }
                load()
            }
        }
    }

    // MARK: - Supprimer les souvenirs d'une étape

    /**
     * La croix s'offre sur cette étape : l'app sait l'effacer, et le serveur
     * a dit quels souvenirs elle porte ([TripStep.entryIds]).
     */
    fun canDeleteMemories(step: TripStep): Boolean = deleteEntry != null && step.hasDeletableMemories

    /**
     * Efface **tous** les souvenirs d'une étape — une étape est un lieu, elle
     * en porte souvent plusieurs : un vocal, un texte, des photos (T235).
     *
     * Un à un, parce que c'est la route qui existe ; un souvenir déjà parti
     * (un co-voyageur l'a effacé entre-temps) n'est pas un échec — la
     * fonction branchée par l'app avale ce 404. Au premier vrai refus, on
     * s'arrête et on relit le voyage : ce qui est parti est parti, la feuille
     * dit le reste.
     *
     * @return `true` quand tout est effacé — la feuille se referme.
     */
    suspend fun deleteMemories(step: TripStep): Boolean {
        val deleteEntry = deleteEntry ?: return false
        val ids = step.entryIds
        if (ids.isNullOrEmpty() || _state.value.deletingStepId != null) return false
        _state.update { it.copy(deletingStepId = step.id, stepDeletionError = null) }

        try {
            try {
                for (id in ids) deleteEntry(id)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                _state.update { it.copy(stepDeletionError = describe(error)) }
                load()
                return false
            }

            // L'étape quitte l'écran tout de suite ; la relecture dit ce que le
            // serveur en a fait — une étape sans souvenir disparaît du voyage.
            _state.update { current ->
                current.copy(detail = current.detail?.let { it.copy(steps = it.steps.filter { candidate -> candidate.id != step.id }) })
            }
            confirm(DeleteStepCopy.done(ids.size))
            load()
            return true
        } finally {
            _state.update { it.copy(deletingStepId = null) }
        }
    }

    /** Oublie l'erreur d'un effacement, quand la feuille se referme. */
    fun dismissStepDeletionError() {
        _state.update { it.copy(stepDeletionError = null) }
    }

    /**
     * Un mot qui s'efface tout seul, quatre secondes après une validation —
     * même motif que `TripSettingsModel.confirm`.
     */
    private fun confirm(message: String) {
        _state.update { it.copy(confirmation = message) }
        viewModelScope.launch {
            delay(4.seconds)
            _state.update { if (it.confirmation == message) it.copy(confirmation = null) else it }
        }
    }

    /** Le `localizedDescription` d'iOS : la phrase de l'API, déjà en français. */
    private fun describe(error: Throwable): String =
        (error as? ApiError)?.errorDescription ?: error.localizedMessage ?: error.toString()
}
