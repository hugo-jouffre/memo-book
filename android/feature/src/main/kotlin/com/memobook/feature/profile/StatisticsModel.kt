package com.memobook.feature.profile

import androidx.lifecycle.ViewModel
import com.memobook.core.TravelStatistics
import com.memobook.feature.CachedValue
import com.memobook.feature.ContentFreshness
import com.memobook.feature.RecordingOutbox
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/**
 * Ce que la feuille « Statistiques » sait faire : lire les chiffres, et les
 * **relire tant que l'agent en relève de nouveaux**. Jumeau de
 * `Profile/StatisticsModel.swift`.
 *
 * Même construction que [ProfileModel] — une fonction qui lit, une case de
 * cache — avec une chose en plus : la veille. Le serveur dit combien de
 * souvenirs attendent encore leur relevé (`pendingDetections`) ; tant qu'il y
 * en a, le modèle relit la feuille toutes les quelques secondes, et un
 * chiffre qui vient d'être relevé apparaît sous les yeux. Dès que la file est
 * vide, la veille s'arrête : pas de requête à vide sur un voyage immobile.
 *
 * **Aucune connexion ouverte, et c'est un choix.** Un flux serveur aurait
 * été plus « instantané » d'une seconde, et aurait demandé une seconde forme
 * de client d'API pour une feuille qu'on regarde trente secondes. La relance
 * s'arrête toute seule, elle ne coûte rien le reste du temps.
 *
 * @param source d'où viennent les chiffres. Par défaut, le jeu d'essai.
 * @param cached ce qu'on avait sur le disque — voir `ContentCache`. `null` en aperçu.
 * @param outbox la file des vocaux de l'app, dont le compteur de livraisons
 *   relance la veille. `null` en aperçu, où rien ne part.
 * @param pollInterval le temps entre deux relectures — [POLL_INTERVAL] ; un
 *   test le raccourcit.
 */
class StatisticsModel(
    private val source: suspend () -> TravelStatistics = { TravelStatistics.fixture },
    private val cached: CachedValue<TravelStatistics>? = null,
    outbox: RecordingOutbox? = null,
    private val pollInterval: Duration = POLL_INTERVAL,
) : ViewModel() {

    /**
     * Ce que la feuille lit.
     *
     * @property freshness ce que le dernier chargement a appris. **Comparé sur
     *   les chiffres, pas sur l'horodatage** : deux lectures à trois secondes
     *   d'écart sur un voyage immobile ne doivent pas faire clignoter la feuille.
     */
    data class State(
        val statistics: TravelStatistics? = null,
        val errorMessage: String? = null,
        val freshness: ContentFreshness = ContentFreshness.Unknown,
    ) {
        /**
         * `true` tant qu'on n'a rien à montrer. La feuille se dessine quand
         * même, avec des barres d'attente à la place des chiffres.
         */
        val isLoading: Boolean get() = statistics == null && errorMessage == null

        /**
         * `true` tant que le serveur relit des souvenirs. La feuille le dit
         * d'une ligne, et c'est ce qui tient la veille éveillée.
         */
        val isDetecting: Boolean get() = statistics?.isDetecting ?: false
    }

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    /**
     * Combien de vocaux sont arrivés depuis le lancement. La feuille s'en sert
     * comme **clé de sa veille** : à chaque changement, l'effet repart et relit
     * tout de suite, sans attendre la prochaine relance. Toujours zéro en
     * aperçu.
     */
    val deliveries: StateFlow<Int> = outbox?.deliveries ?: MutableStateFlow(0).asStateFlow()

    /** Une lecture, du disque puis du serveur. */
    suspend fun load() {
        if (_state.value.statistics == null) {
            cached?.invoke()?.let { stored ->
                _state.update { it.copy(statistics = stored, freshness = ContentFreshness.Restored) }
            }
        }

        try {
            val loaded = source()
            _state.update { it.copy(freshness = freshness(loaded, it.statistics), statistics = loaded, errorMessage = null) }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            _state.update { it.copy(errorMessage = error.localizedDescription) }
        }
    }

    /**
     * Lit, puis **veille** : relit à intervalle court tant que le serveur
     * annonce des relevés en attente, et s'arrête dès qu'il n'y en a plus.
     *
     * À lancer depuis un `LaunchedEffect` de la feuille : c'est lui qui
     * l'annule quand la feuille se referme, et qui le relance quand un vocal
     * vient de partir (sa clé est le compteur de livraisons de la file). Une
     * panne réseau au milieu ne tue pas la veille tant qu'un relevé était
     * attendu : la relance suivante réessaie, et le bandeau d'erreur dit
     * pourquoi en attendant. Sans rien à attendre, on s'arrête — le bandeau a
     * son bouton.
     */
    suspend fun watch() {
        load()

        var unchanged = 0
        while (currentCoroutineContext().isActive && _state.value.isDetecting && unchanged < MAX_UNCHANGED_POLLS) {
            delay(pollInterval)
            load()
            unchanged = if (_state.value.freshness.isUpdated) 0 else unchanged + 1
        }
    }

    private fun freshness(incoming: TravelStatistics, shown: TravelStatistics?): ContentFreshness {
        shown ?: return ContentFreshness.Unchanged
        return if (shown.hasSameFigures(incoming)) ContentFreshness.Unchanged else ContentFreshness.Updated
    }

    companion object {
        /**
         * Le temps entre deux relectures pendant qu'un relevé est en cours.
         *
         * Trois secondes : la rédaction d'un souvenir prend dix à trente
         * secondes, et l'œil ne fait pas la différence entre un chiffre arrivé
         * une seconde ou trois secondes après. En dessous, on frapperait le
         * serveur pour rien.
         */
        val POLL_INTERVAL: Duration = 3.seconds

        /**
         * Combien de relectures **sans changement** avant de lâcher la veille —
         * deux minutes, à trois secondes l'une.
         *
         * Un souvenir peut rester « en attente » pour de mauvaises raisons : un
         * worker tombé, un job perdu, un jeu d'essai qui n'a jamais enfilé sa
         * rédaction. Sans borne, la feuille frapperait le serveur toutes les
         * trois secondes tant qu'elle est ouverte. Passé ce cap, elle
         * s'arrête ; un vocal livré ou une réouverture la relancent.
         */
        const val MAX_UNCHANGED_POLLS = 40
    }
}
