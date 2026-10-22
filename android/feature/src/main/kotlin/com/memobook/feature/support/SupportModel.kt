package com.memobook.feature.support

import android.content.Context
import android.os.Build
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.core.content.pm.PackageInfoCompat
import androidx.lifecycle.ViewModel
import com.memobook.core.Faq
import com.memobook.core.FaqCategory
import com.memobook.core.FaqEntry
import com.memobook.core.FaqQuery
import com.memobook.core.FaqVariables
import com.memobook.core.FaqVote
import com.memobook.core.SupportCopy
import com.memobook.core.SupportDiagnostics
import com.memobook.core.SupportMessage
import com.memobook.networking.ApiError
import com.memobook.networking.MemoBookApi
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.io.IOException
import java.util.Locale
import kotlin.time.Duration.Companion.milliseconds

/**
 * Ce que l'écran de support sait faire : servir la foire aux questions, retenir
 * si une réponse a aidé, et porter un message jusqu'à l'équipe. Jumeau de
 * `Support/SupportModel.swift`.
 *
 * Même construction que `BookCustomisationModel` : le modèle ne connaît pas
 * l'API, il reçoit des fonctions ([SupportBackend]). Les aperçus n'en
 * fournissent aucune et travaillent en mémoire.
 *
 * **La foire aux questions arrive elle aussi par un paramètre**, alors qu'elle
 * est statique aujourd'hui. C'est voulu : la page Notion demande que le contenu
 * soit « servi depuis une source distante, pas figé dans le binaire, pour
 * corriger une réponse sans passer par une mise à jour ». Le jour où la route
 * existe, c'est ce seul branchement qui change — ni l'écran, ni la feuille.
 *
 * **Un seul modèle pour la session** : les votes « Est-ce utile ? » déjà donnés
 * ne doivent pas se redemander parce qu'on a refermé l'écran entre-temps. La
 * porte le range dans [com.memobook.feature.LocalSessionViewModelStoreOwner]
 * (voir [rememberSessionSupportModel]), vidé à chaque changement de compte.
 *
 * @param topics les neuf paquets de « sujets courants ».
 * @param contact le paquet « Nous contacter », qui a sa propre section sur l'écran.
 * @param variables les valeurs qui bougent — seuils, prix, délais —, résolues
 *   à l'affichage. Voir [FaqVariables].
 * @param backend les trois routes du support. `null` pour les aperçus : la
 *   feuille fait alors comme si, ce qui permet de dérouler les trois étapes
 *   sans réseau. Sur iOS, `RootView` le branche à chaque compte
 *   ([connect]) ; ici le modèle naît avec celui de la session, puisque le
 *   magasin de la session est vidé quand le compte change.
 * @param appVersion « 0.1.0 (21) », joint à chaque message — voir [SupportDevice].
 * @param diagnostics ce que le message dit de l'appareil — voir [SupportDevice].
 */
class SupportModel(
    val topics: List<FaqCategory> = Faq.topics,
    val contact: FaqCategory = Faq.contact,
    val variables: FaqVariables = FaqVariables.current,
    backend: SupportBackend? = null,
    private val appVersion: String? = null,
    private val diagnostics: () -> SupportDiagnostics = SupportDevice::diagnostics,
) : ViewModel() {

    /** Où en est l'envoi d'un message. */
    sealed interface SendState {
        data object Idle : SendState
        data object Sending : SendState
        data object Sent : SendState
        data class Failed(val message: String) : SendState
    }

    /** Le vote qui n'a pas pu partir, et pourquoi. */
    data class VoteFailure(val questionId: String, val message: String)

    /**
     * Ce que l'écran et la feuille lisent.
     *
     * @property votes ce que le lecteur a répondu à « Est-ce utile ? », par
     *   identifiant de question. **Relu du serveur** à chaque compte
     *   (`GET /v1/support/faq-votes`, T226) : une question déjà votée garde son
     *   « Merci ! » d'une session à l'autre. Ceci ne sert qu'à remplacer les deux
     *   pouces par un merci une fois qu'on a voté : les laisser actifs invite à
     *   voter deux fois, et fausserait justement la mesure. **Le merci attend
     *   le serveur** : un vote n'entre ici qu'une fois reçu.
     * @property pendingVotes les votes partis, pas encore reçus : les pouces se
     *   figent le temps de la réponse.
     * @property voteFailure le vote qui n'a pas pu partir, et pourquoi — sous ses
     *   pouces, rendus actifs pour réessayer.
     * @property search ce qu'on cherche. Vide, l'écran montre les dix paquets tels quels.
     * @property visibleTopics les paquets qui répondent à ce qu'on cherche, déjà
     *   réduits à leurs questions retenues.
     * @property visibleContact le paquet « Nous contacter », filtré lui aussi.
     *   `null` quand rien n'y répond : sa section disparaît alors, sauf la ligne
     *   « Écris à notre équipe », qui reste — c'est la sortie de secours d'une
     *   recherche qui ne trouve rien.
     */
    data class State(
        val sendState: SendState = SendState.Idle,
        val votes: Map<String, Boolean> = emptyMap(),
        val pendingVotes: Set<String> = emptySet(),
        val voteFailure: VoteFailure? = null,
        val search: String = "",
        val visibleTopics: List<FaqCategory> = emptyList(),
        val visibleContact: FaqCategory? = null,
    ) {
        /** On cherche quelque chose. */
        val isSearching: Boolean get() = !FaqQuery(search).isEmpty

        /** On cherche, et rien ne répond. L'écran le dit et propose d'écrire. */
        val hasNoResults: Boolean get() = isSearching && visibleTopics.isEmpty() && visibleContact == null

        /** Combien de questions la recherche a retenues, pour l'annoncer. */
        val resultCount: Int get() = visibleTopics.sumOf { it.entries.size } + (visibleContact?.entries?.size ?: 0)
    }

    private val _state = MutableStateFlow(State(visibleTopics = topics, visibleContact = contact))
    val state: StateFlow<State> = _state.asStateFlow()

    private var backend: SupportBackend? = backend

    val sendState: SendState get() = _state.value.sendState
    val votes: Map<String, Boolean> get() = _state.value.votes
    val pendingVotes: Set<String> get() = _state.value.pendingVotes
    val voteFailure: VoteFailure? get() = _state.value.voteFailure

    /**
     * Ce qu'on cherche.
     *
     * **La recherche vit dans le modèle et non dans la vue**, comme les trois
     * listes triées de l'accueil : filtrer quarante-cinq questions et leurs
     * réponses à chaque recomposition, c'est le refaire à chaque image
     * d'animation. Ici c'est refait à chaque frappe, et pas plus.
     */
    var search: String
        get() = _state.value.search
        set(value) {
            if (value == _state.value.search) return
            val query = FaqQuery(value)
            _state.update {
                it.copy(
                    search = value,
                    visibleTopics = topics.mapNotNull { category -> category.filtered(query, variables) },
                    visibleContact = contact.filtered(query, variables),
                )
            }
        }

    /**
     * Branche le support sur le compte qui vient d'entrer, et relit ses votes.
     * **Les votes du compte d'avant s'effacent** : ce ne sont pas les siens.
     */
    suspend fun connect(backend: SupportBackend?) {
        this.backend = backend
        _state.update {
            it.copy(votes = emptyMap(), pendingVotes = emptySet(), voteFailure = null, sendState = SendState.Idle)
        }
        loadVotes()
    }

    /**
     * Relit les votes déjà donnés. Un échec ne dit rien : les pouces restent,
     * et un vote de plus remplacera l'ancien côté serveur.
     */
    suspend fun loadVotes() {
        val backend = backend ?: return
        val served = try {
            backend.loadVotes()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            return
        }
        _state.update { current ->
            val kept = served.filter { it.questionId !in current.pendingVotes }
            current.copy(votes = current.votes + kept.associate { it.questionId to it.isHelpful })
        }
    }

    /** Efface la recherche — la croix du champ, et la fermeture de l'écran. */
    fun clearSearch() {
        search = ""
    }

    /** La réponse d'une question, variables résolues. */
    fun answer(entry: FaqEntry): List<String> = entry.answer(variables)

    /**
     * Vote « Est-ce utile ? » — et ne dit « Merci ! » qu'une fois le vote reçu
     * (T226). Hors ligne, les pouces reviennent avec une ligne qui le dit : un
     * merci pour un vote perdu fausserait la mesure qu'il sert.
     */
    suspend fun vote(isHelpful: Boolean, entry: FaqEntry) {
        val current = _state.value
        if (current.votes[entry.id] != null || entry.id in current.pendingVotes) return
        val backend = backend
        if (backend == null) {
            _state.update { it.copy(votes = it.votes + (entry.id to isHelpful)) }
            return
        }

        _state.update {
            it.copy(
                pendingVotes = it.pendingVotes + entry.id,
                voteFailure = it.voteFailure?.takeUnless { failure -> failure.questionId == entry.id },
            )
        }
        try {
            backend.vote(entry.id, isHelpful)
            _state.update { it.copy(votes = it.votes + (entry.id to isHelpful)) }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            val message = if (isOffline(error)) SupportCopy.Answer.voteOffline else SupportCopy.Answer.voteFailed
            _state.update { it.copy(voteFailure = VoteFailure(entry.id, message)) }
        } finally {
            _state.update { it.copy(pendingVotes = it.pendingVotes - entry.id) }
        }
    }

    /**
     * Envoie le message, et dit ce qu'il devient — **« envoyé » seulement une
     * fois que le serveur l'a reçu** (Hugo, 06/10/2026, T226).
     *
     * Sans serveur — les aperçus —, la feuille marque une pause avant de
     * confirmer plutôt que de sauter à l'étape suivante : une confirmation
     * instantanée se lit comme un bouton qui n'a rien fait.
     *
     * @param source le formulaire du support, ou « Partager mes retours ».
     * @param topicId la question de « Nous contacter » qui a ouvert le formulaire.
     * @param tripId le voyage d'où l'on écrit.
     */
    suspend fun send(
        message: String,
        source: SupportMessage.Source = SupportMessage.Source.Support,
        topicId: String? = null,
        tripId: String? = null,
    ) {
        val trimmed = message.trim()
        if (trimmed.isEmpty() || _state.value.sendState == SendState.Sending) return

        _state.update { it.copy(sendState = SendState.Sending) }
        try {
            val backend = backend
            if (backend != null) {
                backend.send(
                    SupportMessage(
                        source = source,
                        topicId = topicId,
                        message = trimmed,
                        tripId = tripId,
                        appVersion = appVersion,
                        diagnostics = diagnostics(),
                    ),
                )
            } else {
                delay(600.milliseconds)
            }
            _state.update { it.copy(sendState = SendState.Sent) }
        } catch (error: CancellationException) {
            // Un envoi interrompu ne bloque pas le formulaire sur « envoi en cours ».
            _state.update { it.copy(sendState = SendState.Idle) }
            throw error
        } catch (error: Exception) {
            _state.update { it.copy(sendState = SendState.Failed(sendFailure(error))) }
        }
    }

    /**
     * Remet le formulaire à zéro — à la fermeture de la feuille, pour que la
     * suivante ne s'ouvre pas sur la confirmation de la précédente.
     */
    fun resetSending() {
        _state.update { it.copy(sendState = SendState.Idle) }
    }

    companion object {
        /**
         * Ce que le formulaire dit quand le message n'est pas parti : pas de
         * réseau, trop de messages aujourd'hui, ou le reste.
         */
        fun sendFailure(error: Throwable): String = when {
            isOffline(error) -> SupportCopy.Contact.sendOffline
            (error as? ApiError)?.code == "support_rate_limited" -> SupportCopy.Contact.sendRateLimited
            else -> SupportCopy.Contact.sendFailed
        }

        private fun isOffline(error: Throwable): Boolean =
            (error as? ApiError)?.isTransport ?: (error is IOException)
    }
}

/**
 * Les trois routes du support (contrat du 06/10/2026, point 4), en fonctions —
 * le modèle ne connaît pas l'API.
 *
 * @property send `POST /v1/support/messages`.
 * @property vote `PUT /v1/support/faq-votes/:questionId`.
 * @property loadVotes `GET /v1/support/faq-votes`.
 */
class SupportBackend(
    val send: suspend (SupportMessage) -> Unit,
    val vote: suspend (questionId: String, isHelpful: Boolean) -> Unit,
    val loadVotes: suspend () -> List<FaqVote>,
) {
    /** Les trois routes, sur l'API du compte. */
    constructor(api: MemoBookApi, appVersion: String?) : this(
        send = { api.sendSupportMessage(it) },
        vote = { questionId, isHelpful -> api.voteOnFaq(questionId, isHelpful, appVersion) },
        loadVotes = { api.faqVotes() },
    )
}

/** Ce que le diagnostic dit de l'appareil — et rien d'autre. */
object SupportDevice {
    /**
     * « 0.1.0 (21) » : le nom de version et son numéro. Lu sur le paquet
     * installé — `:feature` ne voit pas le `BuildConfig` de l'app.
     */
    fun appVersion(context: Context): String? = runCatching {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        val name = info.versionName ?: return@runCatching null
        "$name (${PackageInfoCompat.getLongVersionCode(info)})"
    }.getOrNull()

    /** « 0.1.0 », pour le pied de page du support. */
    fun shortVersion(context: Context): String? = runCatching {
        context.packageManager.getPackageInfo(context.packageName, 0).versionName
    }.getOrNull()

    /** « Android 16 », « Google Pixel 9 », « fr_FR ». */
    fun diagnostics(): SupportDiagnostics = SupportDiagnostics(
        osVersion = "Android ${Build.VERSION.RELEASE ?: ""}".trim(),
        deviceModel = listOfNotNull(Build.MANUFACTURER, Build.MODEL).joinToString(" ").ifEmpty { "Android" },
        locale = Locale.getDefault().toString(),
    )
}

/**
 * Le support de la session, pour un écran qui doit l'ouvrir **par-dessus lui**
 * au lieu de le faire pousser par `RootView` — le `supportModel` de
 * l'environnement d'iOS.
 *
 * Un seul écran est dans ce cas, et c'est le paywall (Hugo, 16/09/2026) :
 * « Besoin d'aide ? » y refermait l'offre avant de pousser le support, et la
 * flèche de retour ramenait donc au profil — l'écran qui avait présenté le
 * paywall — au lieu de l'étape qu'on regardait. Le support se pose désormais
 * **sur** le paywall, qui reste monté derrière avec sa page.
 *
 * Le modèle est celui de la session et non un neuf : les votes et le message en
 * cours d'écriture ne doivent pas repartir de zéro parce qu'on est entré par une
 * porte plutôt qu'une autre. `null` en aperçu, où le paywall en fabrique un à la
 * volée. `RootView` le pose (`rememberSessionSupportModel`) ; la porte du
 * paywall le pose aussi pour elle-même.
 */
val LocalSupportModel = staticCompositionLocalOf<SupportModel?> { null }
