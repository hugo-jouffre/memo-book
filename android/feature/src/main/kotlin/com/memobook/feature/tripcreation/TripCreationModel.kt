package com.memobook.feature.tripcreation

import androidx.annotation.DrawableRes
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.memobook.core.CreatedTrip
import com.memobook.core.Trip
import com.memobook.core.TripDraft
import com.memobook.core.TripStage
import com.memobook.core.TripTheme
import com.memobook.core.local
import com.memobook.design.R
import com.memobook.feature.TripSync
import com.memobook.networking.ApiError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.UUID
import com.memobook.feature.chat.NotificationsNudge

/**
 * Les six étapes de « Créer un voyage », dans l'ordre où on les traverse.
 * Jumeau de `TripCreationStep` (`TripCreation/TripCreationModel.swift`).
 *
 * Elles sont **numérotées par la frise** du haut de l'écran : une barre par
 * étape, la verte étant celle qu'on remplit. C'est aussi pour ça qu'elles
 * forment une énumération et non une liste de vues — le compte des barres se
 * dérive du nombre de cas, et ajouter une étape ne demande pas de penser à la
 * frise.
 */
enum class TripCreationStep {
    Theme,
    Name,
    Dates,
    Notifications,
    Ratio,
    Companions,
    ;

    /** Le titre vert, tel qu'il s'écrit dans la maquette. */
    val title: String
        get() = when (this) {
            Theme -> "Contexte de ton voyage"
            Name -> "Nom de ton aventure"
            Dates -> "Dates"
            Notifications -> "Notifications"
            Ratio -> "Ratio image/texte"
            Companions -> "Co-voyageur(s)"
        }

    /**
     * L'illustration posée au-dessus du titre. Elles viennent toutes du même
     * jeu — voir `ios/Tools/import-brand-illustrations.py`.
     */
    @get:DrawableRes
    val illustration: Int
        get() = when (this) {
            Theme -> R.drawable.illustration_carnet
            Name -> R.drawable.illustration_tag
            Dates -> R.drawable.illustration_valise
            Notifications -> R.drawable.illustration_horloge
            Ratio -> R.drawable.illustration_appareil_photo
            Companions -> R.drawable.illustration_duo
        }

    /** Le libellé du bouton du bas. La dernière étape ne valide plus rien : elle ouvre le voyage. */
    val callToAction: String get() = if (this == Companions) "Commencer !" else "Valider"

    /**
     * L'étape a un « Passer ». Toutes, sauf trois : la dernière — le voyage
     * existe déjà, et il n'y a rien à éviter sur un écran qui ne fait que
     * montrer son code d'accès (Hugo, 14/09/2026) —, **le nom**, que la base
     * exige et qu'on ne remplace pas par « Mon voyage » en douce (Hugo,
     * 29/09/2026), et **les dates**, comme le nom (01/10/2026) : le bouton du
     * bas reste éteint tant que le départ n'est pas posé.
     */
    val canBeSkipped: Boolean get() = this != Companions && this != Name && this != Dates

    /** L'étape qui suit celle-ci dans le parcours, `null` sur la dernière. */
    val next: TripCreationStep?
        get() {
            val index = active.indexOf(this)
            return if (index < 0) null else active.getOrNull(index + 1)
        }

    /** L'étape qui précède celle-ci dans le parcours, `null` sur la première. */
    val previous: TripCreationStep?
        get() {
            val index = active.indexOf(this)
            return if (index <= 0) null else active[index - 1]
        }

    /** Le rang de l'étape dans le parcours, pour la frise. */
    val position: Int get() = active.indexOf(this).coerceAtLeast(0)

    companion object {
        /**
         * Les étapes **qu'on traverse**, dans l'ordre. Le contexte (les thèmes)
         * et le ratio image / texte sont **retirés du parcours pour le moment**
         * (Hugo, 17/09/2026) : leur code reste — écran, modèle, brouillon —, et
         * le brouillon part avec leurs valeurs par défaut. Les remettre, c'est
         * une ligne ici.
         *
         * Un `get()` et non un champ : la liste cite les cas de l'énumération,
         * et le compagnon peut se charger avant eux (voir `android/CLAUDE.md`).
         */
        val active: List<TripCreationStep> get() = listOf(Name, Dates, Notifications, Companions)

        /**
         * L'étape après laquelle le voyage **existe**.
         *
         * La création ne se fait pas au « Commencer ! » de la fin : la dernière
         * étape montre le code d'accès, et un code d'accès désigne un voyage. Le
         * carnet est donc enregistré à la validation de l'avant-dernière — de
         * celles qu'on traverse — **sur le téléphone d'abord** : le serveur
         * l'apprend quand il peut (Hugo, 01/10/2026).
         */
        val lastBeforeSave: TripCreationStep
            get() {
                val index = active.indexOf(Companions).takeIf { it >= 0 } ?: active.size
                return active[maxOf(0, index - 1)]
            }
    }
}

/**
 * Ce que sait faire la création d'un voyage : garder le brouillon des six
 * étapes, aller d'une étape à l'autre, et l'enregistrer. Jumeau de
 * `TripCreation/TripCreationModel.swift`.
 *
 * **Rien n'y attend le réseau, sauf le code d'accès** (Hugo, 01/10/2026). On
 * crée un voyage dans l'avion de bout en bout : la validation garde le
 * brouillon sur le téléphone et passe à l'étape suivante ; « Commencer ! »
 * ouvre le voyage ; le serveur le reçoit au retour du réseau, et c'est lui qui
 * tire le code — la seule chose de l'écran qu'il faut lui demander.
 *
 * Même construction que `HomeModel` et `TripHomeModel` : le modèle ne connaît
 * ni l'API ni la file, il reçoit **deux fonctions** — une qui enregistre, une
 * qui attend le code. Les aperçus n'en fournissent aucune et traversent le
 * formulaire sans serveur.
 *
 * @param save garde le brouillon — l'app y branche la file de départ
 *   (`RecordingOutbox.saveTrip`), qui l'envoie quand elle peut. Le brouillon
 *   porte déjà son identifiant ; la même fonction sert la création et la
 *   correction qui suit un retour en arrière.
 * @param sync attend ce que le serveur a fait du voyage — son code d'accès, ou
 *   son refus (`RecordingOutbox.tripSync`).
 * @param themes d'où viennent les thèmes de la première étape. Par défaut la
 *   liste du jeu d'essai, pour les aperçus ; l'app y branche
 *   `GET /v1/trip-themes`.
 * @param isOffline le téléphone est-il sans réseau ? L'app y branche
 *   `RecordingOutbox.isOnline`. Sur iOS une fonction lue pendant le dessin, qui
 *   redessine l'étape au retour du réseau ; ici un flux, que le modèle suit.
 *   Par défaut, toujours en ligne.
 * @param notificationsStepPassed l'étape « Notifications » vient d'être
 *   traversée — choisie ou passée. L'app le retient sur l'appareil : la
 *   conversation proposera d'activer les notifications à qui l'a passée sans
 *   les autoriser (`NotificationsNudge`, T246).
 */
class TripCreationModel(
    private val save: suspend (TripDraft) -> Trip = { draft ->
        Trip.local(draft, id = draft.id ?: UUID.randomUUID().toString().lowercase())
    },
    private val sync: suspend (String) -> TripSync? = { id ->
        TripSync.Created(CreatedTrip(trip = Trip(id = id, title = TripDraft.untitled, stage = TripStage.Ongoing), accessCode = "JHKFDA"))
    },
    private val themes: suspend () -> List<TripTheme> = { TripTheme.fixtures },
    isOffline: Flow<Boolean> = flowOf(false),
    private val notificationsStepPassed: () -> Unit = {},
) : ViewModel() {

    /**
     * Ce que l'écran lit.
     *
     * @property draft le brouillon, rempli étape par étape. Il ne s'enregistre
     *   **qu'une fois**, à la fin de l'avant-dernière : six requêtes pour un
     *   formulaire qu'on peut remonter donneraient six façons de le laisser à
     *   moitié écrit. ⚠️ Ses champs sont des `var` (le contrat de `:core`) :
     *   on le remplace par une copie, on ne l'écrit jamais en place.
     * @property themes les thèmes de la rangée, **tels que le serveur les
     *   sert** — « Autre » en dernier. Vides le temps de la lecture ; la rangée
     *   montre alors une barre d'attente et non sept émojis inventés. Voir
     *   [loadThemes].
     * @property themesFailure la lecture des thèmes a échoué. L'étape reste
     *   traversable : « Passer » et « Autre » n'ont besoin d'aucune liste.
     * @property selectedTheme le thème choisi dans la rangée d'émojis. `null`
     *   tant qu'on n'a rien touché, ce qui n'est pas la même chose
     *   qu'« Autre » : passer l'étape laisse `theme` vide, choisir « Autre »
     *   ouvre un champ.
     * @property freeTheme le texte de « Autre ». Gardé à part de [draft] pour
     *   qu'un aller-retour sur l'étape ne l'efface pas quand on repasse par un
     *   émoji.
     * @property trip le voyage, une fois enregistré sur le téléphone. C'est ce
     *   que « Commencer ! » ouvre, que le serveur l'ait reçu ou non.
     * @property accessCode le code d'accès, quand le serveur a créé le voyage.
     *   `null` jusque-là : la ligne du code porte une barre d'attente et
     *   « Partager » reste gris — c'est la seule chose de l'écran qui attend le
     *   réseau.
     * @property isSaving l'enregistrement local est en cours — l'affaire d'un instant.
     * @property wasRejected le serveur a refusé le voyage : il n'y a plus rien à ouvrir.
     */
    data class State(
        val step: TripCreationStep = TripCreationStep.active[0],
        val draft: TripDraft = TripDraft(),
        val themes: List<TripTheme> = emptyList(),
        val themesFailure: String? = null,
        val selectedTheme: TripTheme? = null,
        val freeTheme: String = "",
        val trip: Trip? = null,
        val accessCode: String? = null,
        val isSaving: Boolean = false,
        val errorMessage: String? = null,
        val wasRejected: Boolean = false,
        val isOffline: Boolean = false,
    ) {
        /** « Autre » est choisi : le champ libre est ouvert et c'est lui qui compte. */
        val isFreeThemeChosen: Boolean get() = selectedTheme?.isOther == true

        /**
         * Le code attend **le retour du réseau**, pas seulement le serveur : le
         * voyage est gardé, rien n'est revenu, et le téléphone est hors ligne.
         * L'étape le dit sous la barre d'attente — « Ton code arrivera dès ta
         * reconnexion » (T240, Hugo, 06/10/2026). En ligne, le code arrive en
         * une fraction de seconde : la phrase n'y aurait que le temps de
         * clignoter.
         */
        val awaitsReconnection: Boolean get() = trip != null && accessCode == null && !wasRejected && isOffline

        /**
         * Le bouton du bas est-il allumé ?
         *
         * Deux étapes l'éteignent, celles qui n'ont pas de « Passer » : le nom,
         * que la base exige, et les dates, **tant que le départ n'est pas
         * posé** (01/10/2026) — le retour, lui, reste facultatif. Partout
         * ailleurs « Valider » vaut « Passer », et un bouton grisé
         * n'apprendrait rien.
         */
        val canValidate: Boolean
            get() = when (step) {
                TripCreationStep.Name -> draft.title.trim().isNotEmpty()
                TripCreationStep.Dates -> draft.startDate != null
                TripCreationStep.Theme -> !isFreeThemeChosen || freeTheme.trim().isNotEmpty()
                else -> true
            }

        /** La frise : une barre par étape traversée, la verte étant celle-ci. */
        val progress: Int get() = step.position

        /** Combien d'étapes le parcours compte — pour la frise et TalkBack. */
        val stepCount: Int get() = TripCreationStep.active.size

        /** Le glissé vers l'avant vaut « Valider » : il n'avance que si l'étape le permet, comme le bouton. */
        val canAdvance: Boolean get() = canValidate && step != TripCreationStep.Companions

        /** Le glissé vers l'arrière n'a d'effet que s'il y a une étape avant. */
        val canGoBack: Boolean get() = step.previous != null
    }

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    init {
        viewModelScope.launch { isOffline.collect { offline -> _state.update { it.copy(isOffline = offline) } } }
    }

    val step: TripCreationStep get() = _state.value.step
    val trip: Trip? get() = _state.value.trip
    val accessCode: String? get() = _state.value.accessCode
    val errorMessage: String? get() = _state.value.errorMessage
    val wasRejected: Boolean get() = _state.value.wasRejected
    val isSaving: Boolean get() = _state.value.isSaving
    val canValidate: Boolean get() = _state.value.canValidate
    val awaitsReconnection: Boolean get() = _state.value.awaitsReconnection

    /** Le brouillon. Le remplacer par une copie : `model.draft = model.draft.copy(title = …)`. */
    var draft: TripDraft
        get() = _state.value.draft
        set(value) = _state.update { it.copy(draft = value) }

    var selectedTheme: TripTheme?
        get() = _state.value.selectedTheme
        set(value) = _state.update { it.copy(selectedTheme = value) }

    var freeTheme: String
        get() = _state.value.freeTheme
        set(value) = _state.update { it.copy(freeTheme = value) }

    /** Corrige le brouillon d'un geste, sans jamais l'écrire en place. */
    fun editDraft(transform: (TripDraft) -> TripDraft) {
        _state.update { it.copy(draft = transform(it.draft)) }
    }

    /**
     * Lit les thèmes. À appeler à l'ouverture de l'écran ; relire ne fait pas
     * de mal, la rangée garde son choix tant que le thème existe encore.
     */
    suspend fun loadThemes() {
        try {
            val loaded = themes()
            _state.update {
                it.copy(
                    themes = loaded,
                    themesFailure = null,
                    selectedTheme = it.selectedTheme?.takeIf { chosen -> chosen in loaded },
                )
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            _state.update { it.copy(themesFailure = describe(error)) }
        }
    }

    // MARK: - Aller et venir

    /**
     * Valide l'étape courante et passe à la suivante.
     *
     * **Le modèle refuse lui-même une étape incomplète** (T238, Hugo,
     * 06/10/2026 : « c'est impossible de créer un voyage sans dates »). Le
     * bouton gris et le glissé le vérifiaient déjà, chacun de son côté ; le
     * dire ici ferme aussi les chemins à venir — la touche « Terminé » d'un
     * clavier, un raccourci — sans qu'aucun ait à s'en souvenir. Un voyage a
     * toujours un départ : c'est lui qui le range dans « à venir », « en
     * cours » ou « précédents ».
     */
    suspend fun validate() {
        val current = _state.value
        if (!current.canValidate) return
        if (current.step == TripCreationStep.Theme) {
            val theme = if (current.isFreeThemeChosen) current.freeTheme.trim() else current.selectedTheme?.label
            editDraft { it.copy(theme = theme) }
        }
        advance()
    }

    /**
     * Passe l'étape sans rien en retenir — le « Passer » du coin haut droit.
     *
     * Passer, c'est `null`, jamais une valeur inventée. Une étape sans
     * « Passer » ([TripCreationStep.canBeSkipped]) ne se passe pas non plus
     * d'ici : le nom et les dates s'obtiennent par « Valider », une fois
     * remplis.
     */
    suspend fun skip() {
        val step = _state.value.step
        if (!step.canBeSkipped) return
        when (step) {
            TripCreationStep.Theme -> _state.update { it.copy(selectedTheme = null, freeTheme = "", draft = it.draft.copy(theme = null)) }
            TripCreationStep.Notifications -> editDraft { it.copy(narrationPace = null) }
            TripCreationStep.Ratio -> editDraft { it.copy(photoTextRatio = 50) }
            TripCreationStep.Name, TripCreationStep.Dates, TripCreationStep.Companions -> Unit
        }
        advance()
    }

    /**
     * Revient à l'étape précédente. `false` quand il n'y en a pas : c'est
     * alors à l'écran de se refermer, pas au modèle.
     */
    fun goBack(): Boolean {
        val previous = _state.value.step.previous ?: return false
        _state.update { it.copy(errorMessage = null, step = previous) }
        return true
    }

    // MARK: - L'enregistrement

    /**
     * Enregistre le brouillon puis avance, ou avance seulement.
     *
     * Le voyage s'enregistre **une fois** — à la fin de l'avant-dernière
     * étape. Y revenir et revalider ne crée pas un second voyage : le
     * brouillon garde son identifiant, on corrige celui qui existe, et son
     * code d'accès ne bouge pas, parce qu'il a peut-être déjà été envoyé à
     * quelqu'un.
     */
    private suspend fun advance() {
        _state.update { it.copy(errorMessage = null) }
        val step = _state.value.step

        if (step == TripCreationStep.Name) {
            editDraft { draft -> draft.copy(title = draft.title.trim().ifEmpty { TripDraft.untitled }) }
        }

        if (step == TripCreationStep.Notifications) notificationsStepPassed()

        if (step == TripCreationStep.lastBeforeSave && !persist()) return

        val next = step.next ?: return
        _state.update { it.copy(step = next) }
    }

    private suspend fun persist(): Boolean {
        _state.update { it.copy(isSaving = true) }
        try {
            // L'identifiant est tiré **ici**, une fois : c'est celui que le
            // serveur reprendra, et celui sous lequel ce qu'on racontera
            // attendra le réseau.
            if (_state.value.draft.id == null) editDraft { it.copy(id = UUID.randomUUID().toString().lowercase()) }

            val saved = save(_state.value.draft)
            _state.update { it.copy(trip = saved, wasRejected = false) }
            return true
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            _state.update { it.copy(errorMessage = describe(error)) }
            return false
        } finally {
            _state.update { it.copy(isSaving = false) }
        }
    }

    /**
     * Attend ce que le serveur fait du voyage. À lancer **par l'écran**, sur
     * l'identifiant du voyage (`LaunchedEffect(trip?.id)`) : quitter l'écran
     * annule l'attente, pas l'envoi — le voyage reste dans la file.
     *
     * Le code arrive tout de suite en ligne, au retour du réseau sinon. Un
     * refus se dit sur l'étape, et « Commencer ! » n'ouvre plus rien.
     */
    suspend fun awaitAccessCode() {
        val current = _state.value
        val id = current.trip?.id ?: return
        if (current.accessCode != null) return

        when (val result = sync(id)) {
            is TripSync.Created -> _state.update { it.copy(accessCode = result.created.accessCode) }
            is TripSync.Rejected -> _state.update { it.copy(errorMessage = result.message, wasRejected = true) }
            null -> Unit
        }
    }

    /** Le `localizedDescription` d'iOS : la phrase de l'API, déjà en français. */
    private fun describe(error: Throwable): String =
        (error as? ApiError)?.errorDescription ?: error.localizedMessage ?: error.toString()
}

/**
 * Le jeu d'essai de la création.
 *
 * Il rend un voyage qui ressemble au brouillon, sans serveur — c'est ce qui
 * permet de traverser les six étapes dans un aperçu et dans le bac à sable
 * (`PreviewApi.createTrip`). Le code d'accès est celui de la maquette. Même
 * rôle que `TripDetail.fixture(id)` et `HomeFeed.fixture`, et pour la même
 * raison : un écran doit pouvoir se regarder sans back-end.
 *
 * @param id l'identifiant à garder, quand le brouillon corrige un voyage déjà
 *   créé. `null` en tire un nouveau.
 */
fun CreatedTrip.Companion.fixture(draft: TripDraft, id: String? = null): CreatedTrip {
    val start = draft.startDate
    return CreatedTrip(
        trip = Trip(
            id = id ?: UUID.randomUUID().toString().uppercase(),
            title = draft.title.ifEmpty { TripDraft.untitled },
            stage = if (start != null && start > Instant.now()) TripStage.Upcoming else TripStage.Ongoing,
            startDate = draft.startDate,
            endDate = draft.endDate,
        ),
        accessCode = "JHKFDA",
    )
}
