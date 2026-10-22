package com.memobook.feature.tripsettings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.memobook.core.BookCustomisation
import com.memobook.core.BookCustomisationEdit
import com.memobook.core.BookCustomisationPreview
import com.memobook.core.BookFontCombo
import com.memobook.core.BookFontRole
import com.memobook.core.BookPageTarget
import com.memobook.core.BookRulesLock
import com.memobook.core.PageTargetAllowance
import com.memobook.core.PageTargetReach
import com.memobook.core.PageTargetTripStage
import com.memobook.core.TripSettings
import com.memobook.networking.ApiError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.net.URI
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.UUID

/**
 * Ce que l'écran des personnalisations sait faire : les lire, et enregistrer
 * ce qu'on y change. Jumeau de `TripSettings/BookCustomisationModel.swift`.
 *
 * Même construction que [TripSettingsModel], et pour la même raison : le
 * modèle ne connaît pas l'API, il reçoit des fonctions. L'app leur branche
 * `GET /v1/trips/:id/settings` et son `PATCH` ; les aperçus n'en fournissent
 * aucune et travaillent en mémoire.
 *
 * **Il lit les réglages entiers, pas seulement les personnalisations**, et
 * c'est la route qui le veut : elles voyagent ensemble parce qu'il y en a un
 * jeu par voyage. Ça tombe bien — la feuille « Nombre de page » a besoin des
 * **dates** pour projeter ses trois paliers, et un second appel pour deux
 * dates déjà servies aurait été un aller-retour pour rien.
 *
 * **Un réglage part seul, dès qu'il est touché.** Pas de bouton
 * « Enregistrer » : c'est le contrat des lignes des Réglages partout dans
 * l'app. Les feuilles qui portent quand même un « Valider » ne l'ont pas pour
 * enregistrer — c'est déjà fait — mais pour se refermer, comme la maquette le
 * dessine.
 *
 * Tout ce que le modèle touche vit sur le fil principal, comme le `@MainActor`
 * d'iOS : la file, ses drapeaux et le compteur de révisions ne se partagent
 * pas entre deux fils.
 *
 * @param source la lecture des réglages. Par défaut, le jeu d'essai.
 * @param persist l'écriture d'un réglage. `null` en aperçu : l'écran bouge, rien ne part.
 * @param rewrite la réécriture des étapes déjà écrites à la nouvelle cible.
 * @param today l'horloge du stade du voyage, pour les tests.
 * @param rulesMemory les pointillés d'avant le verrou — voir [BookRulesMemory].
 */
class BookCustomisationModel(
    private val tripId: String,
    private val source: suspend (String) -> TripSettings = { TripSettings.fixture },
    private val persist: (suspend (String, BookCustomisationEdit) -> TripSettings)? = null,
    private val rewrite: (suspend (String) -> TripSettings)? = null,
    private val today: () -> Instant = { Instant.now() },
    private val rulesMemory: BookRulesMemory = BookRulesMemory.inMemory(),
) : ViewModel() {

    /**
     * Ce que l'écran lit.
     *
     * @property errorAdvice ce qu'on peut **faire** de l'erreur — voir
     *   `ApiError.recoveryAdvice`.
     * @property rulesWithdrawnBy l'assortiment qui vient d'éteindre les
     *   pointillés, le temps que la feuille des typographies le dise. `null` dès
     *   le geste suivant.
     * @property isExplainingRulesLock on vient de toucher l'interrupteur
     *   verrouillé — voir [showsRulesLockNotice].
     * @property pageTargetChange le changement de nombre de pages cible que la
     *   feuille raconte, d'étape en étape — voir [PageTargetChange]. `null` quand
     *   elle est fermée.
     * @property pageTargetReach **une cible personnalisée hors d'atteinte** (Hugo,
     *   18/10/2026) : la feuille qui le dit, avant que rien ne change. Ouverte par
     *   un nombre choisi à la main, ou par un ratio qui rend la cible posée
     *   irréalisable.
     * @property isExplainingPageTargetLimit on vient de toucher un palier alors
     *   que la cible ne bouge plus — voir [showsPageTargetLimitNotice].
     * @property isRewritingWrittenSteps la réécriture des étapes déjà écrites
     *   part — le lien du panneau attend sa réponse.
     * @property hasStartedRewrite la réécriture est lancée : le panneau le dit, à
     *   la place du lien.
     */
    data class State(
        val settings: TripSettings? = null,
        val errorMessage: String? = null,
        val errorAdvice: String? = null,
        val rulesWithdrawnBy: BookFontCombo? = null,
        val isExplainingRulesLock: Boolean = false,
        val pageTargetChange: PageTargetChange? = null,
        val pageTargetReach: PageTargetReach? = null,
        val isExplainingPageTargetLimit: Boolean = false,
        val isRewritingWrittenSteps: Boolean = false,
        val hasStartedRewrite: Boolean = false,
    ) {
        val customisation: BookCustomisation? get() = settings?.customisation

        /**
         * `true` tant qu'on n'a pas de valeurs. L'écran se dessine quand même :
         * ses intitulés et ses groupes appartiennent à l'app.
         */
        val isLoading: Boolean get() = settings == null && errorMessage == null

        /**
         * Combien de jours dure le voyage, bornes comprises. `null` quand une des
         * deux dates manque — les paliers de pages retombent alors sur le défaut
         * de la base (40 / 60 / 80) plutôt que d'annoncer une projection qu'on
         * n'a pas de quoi faire.
         *
         * **Sans date de fin, on ne sait pas** (15/10/2026) : la date de début
         * servait de fin, le voyage durait un jour, et le palier « Par défaut »
         * tombait à 30 pages pour un voyage qui commence à peine.
         *
         * Le `Calendar.current` d'iOS est ici le fuseau du téléphone.
         */
        val tripDays: Int?
            get() {
                val start = settings?.startDate ?: return null
                val end = settings.endDate ?: return null
                val zone = ZoneId.systemDefault()
                val days = ChronoUnit.DAYS.between(start.atZone(zone), end.atZone(zone)).toInt()
                return maxOf(1, days + 1)
            }

        /**
         * L'image de l'aperçu de personnalisation, en tête de l'écran — voir
         * `BookCustomisationPreview.imageURL`. `null` tant que les réglages ne
         * sont pas lus.
         *
         * Elle ne dépend que des cinq réglages qui la pilotent : l'écran peut
         * suivre cette adresse sans jamais recharger pour le nombre de pages, le
         * quiz, les zones libres ou le mot fléché.
         */
        val previewURL: URI? get() = customisation?.let(BookCustomisationPreview::imageURL)

        /** Les pointillés sont-ils verrouillés par l'assortiment du carnet ? */
        val areRulesLocked: Boolean get() = customisation?.let(BookRulesLock::isLocked) ?: false

        /**
         * L'interrupteur doit-il pâlir ? Verrou posé **et** pointillés éteints.
         *
         * Allumés sous un verrou — une remise dans le rang qui a échoué —, ils
         * s'impriment : l'interrupteur reste libre de les éteindre, puisque le
         * verrou n'interdit que de les rallumer, et la note qui dit « ils ne
         * s'impriment qu'avec Carnet de voyage » mentirait.
         */
        val isRulesSwitchLocked: Boolean get() = areRulesLocked && customisation?.rulesEnabled == false

        /**
         * On vient de toucher l'interrupteur verrouillé : Extras dit pourquoi,
         * tant que le verrou tient.
         */
        val showsRulesLockNotice: Boolean get() = isExplainingRulesLock && isRulesSwitchLocked

        /**
         * Ce que le serveur dit des changements de cible — rien de compté tant
         * qu'il ne l'a pas dit.
         */
        val pageTargetAllowance: PageTargetAllowance get() = settings?.pageTargetAllowance ?: PageTargetAllowance.unrestricted

        /** Les paliers doivent-ils pâlir ? Les deux changements sont faits. */
        val isPageTargetLocked: Boolean get() = pageTargetAllowance.isExhausted

        /**
         * On vient de toucher un palier alors que la cible ne bouge plus : le
         * panneau le dit à l'orange, sous les paliers pâlis. Comme la note du
         * verrou des pointillés, elle répond à un appui, pas à un état.
         */
        val showsPageTargetLimitNotice: Boolean get() = isExplainingPageTargetLimit && isPageTargetLocked

        /**
         * Le lien « Mettre les étapes déjà écrites à la nouvelle cible » : la
         * réécriture reste ouverte — on a répondu « Plus tard » — et la feuille
         * est fermée.
         */
        val offersRewrite: Boolean
            get() = pageTargetAllowance.rewriteAvailable && pageTargetChange == null && !hasStartedRewrite

        /** La note du verrou s'en va avec lui. */
        internal fun forgettingLockNoticeIfUnlocked(): State =
            if (!isRulesSwitchLocked) copy(isExplainingRulesLock = false) else this
    }

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    // Ce que l'écran lit, sous les noms d'iOS — les tests s'en servent.
    val settings: TripSettings? get() = _state.value.settings
    val customisation: BookCustomisation? get() = _state.value.customisation
    val errorMessage: String? get() = _state.value.errorMessage
    val rulesWithdrawnBy: BookFontCombo? get() = _state.value.rulesWithdrawnBy
    val showsRulesLockNotice: Boolean get() = _state.value.showsRulesLockNotice
    val pageTargetChange: PageTargetChange? get() = _state.value.pageTargetChange
    val pageTargetReach: PageTargetReach? get() = _state.value.pageTargetReach
    val showsPageTargetLimitNotice: Boolean get() = _state.value.showsPageTargetLimitNotice
    val hasStartedRewrite: Boolean get() = _state.value.hasStartedRewrite
    val tripDays: Int? get() = _state.value.tripDays
    val previewURL: URI? get() = _state.value.previewURL
    val areRulesLocked: Boolean get() = _state.value.areRulesLocked
    val isRulesSwitchLocked: Boolean get() = _state.value.isRulesSwitchLocked
    val pageTargetAllowance: PageTargetAllowance get() = _state.value.pageTargetAllowance
    val isPageTargetLocked: Boolean get() = _state.value.isPageTargetLocked
    val offersRewrite: Boolean get() = _state.value.offersRewrite

    /** Les réglages qui attendent leur tour, envoyés **un par un**, dans l'ordre — voir [save]. */
    private val queue = mutableListOf<BookCustomisationEdit>()
    private var isSending = false

    /** Un envoi est parti, et le serveur n'a pas encore répondu. */
    private var isAwaitingResponse = false

    /**
     * Compte les gestes et les réponses : une relecture partie avant l'un
     * d'eux est périmée — voir [reload].
     */
    private var revision = 0

    /**
     * Lit les réglages, puis remet dans le rang un carnet que le verrou des
     * pointillés n'a pas encore touché — voir `BookRulesLock.normalised`.
     */
    suspend fun load() {
        if (!reload()) return
        settleRules()
    }

    /**
     * Lit les réglages, sans rien renvoyer. C'est la relecture d'après un
     * envoi raté : y remettre les pointillés dans le rang renverrait le même
     * envoi, qui raterait de la même façon, sans fin.
     *
     * **Une lecture que croise un geste n'est pas montrée** : elle a été prise
     * avant lui, et la poser effacerait à l'écran un réglage qui part encore —
     * ou effacerait la mémoire du verrou qu'il vient d'écrire. Pareil tant
     * qu'un envoi attend sa réponse : c'est elle qui remettra l'écran d'accord
     * avec le serveur. Rend `false` dans ces deux cas, comme à l'échec —
     * [load] ne remet alors rien dans le rang.
     */
    private suspend fun reload(): Boolean {
        val before = revision
        return try {
            val fresh = source(tripId)
            if (revision != before || isAwaitingResponse || queue.isNotEmpty()) return false
            // Relu après un envoi raté, le carnet peut être revenu sur Carnet de
            // voyage, pointillés allumés : la note dirait le contraire.
            _state.update {
                it.copy(settings = fresh, errorMessage = null, errorAdvice = null, rulesWithdrawnBy = null)
                    .forgettingLockNoticeIfUnlocked()
            }
            forgetRulesIfUnlocked()
            true
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            report(error)
            false
        }
    }

    /**
     * Pose l'erreur **et son conseil** : la phrase dit ce qui s'est passé, le
     * conseil ce qu'on peut faire (Hugo, 15/09/2026).
     */
    private fun report(error: Throwable) {
        _state.update { it.copy(errorMessage = describe(error), errorAdvice = (error as? ApiError)?.recoveryAdvice) }
    }

    private fun clearError() {
        _state.update { it.copy(errorMessage = null, errorAdvice = null) }
    }

    // MARK: - Ce qu'on change depuis les feuilles

    /**
     * Le ratio photo / texte. **S'applique à tout le carnet dès la prochaine
     * mise en page** (Hugo, 18/10/2026) : le ratio ne touche pas au texte.
     *
     * Une cible posée sur un palier suit le palier — les paliers dépendent du
     * ratio, le serveur fait de même sans compter de changement
     * (`presetTargetForRatio`). Une cible personnalisée ne bouge pas ; si elle
     * devient hors d'atteinte, la feuille [PageTargetReach] s'ouvre.
     */
    fun setPhotoTextRatio(ratio: Int) {
        val current = _state.value
        val before = current.customisation?.photoTextRatio ?: 50
        val target = current.customisation?.targetPageCount
        val days = current.tripDays
        val tier = target?.let { BookPageTarget.matching(pageCount = it, tripDays = days, ratio = before) }
        edit(BookCustomisationEdit.PhotoTextRatio(ratio)) { customisation ->
            val pages = tier?.takeIf { it != BookPageTarget.Custom }?.pageCount(days, ratio)
            customisation.copy(photoTextRatio = ratio, targetPageCount = pages ?: customisation.targetPageCount)
        }
        if (tier == BookPageTarget.Custom) {
            _state.value.pageTargetAllowance.reach(of = target, ratio = ratio)?.let { reach ->
                _state.update { it.copy(pageTargetReach = reach) }
            }
        }
    }

    /**
     * Demande une cible **personnalisée** : hors d'atteinte, la feuille le dit
     * avant que rien ne change ; sinon, le chemin de toujours.
     */
    fun requestCustomTarget(pages: Int) {
        val current = _state.value
        val ratio = current.customisation?.photoTextRatio ?: 50
        if (pages != current.customisation?.targetPageCount) {
            val reach = current.pageTargetAllowance.reach(of = pages, ratio = ratio)
            if (reach != null) {
                _state.update { it.copy(pageTargetReach = reach) }
                return
            }
        }
        setTargetPageCount(pages)
    }

    /** « Choisir N pages » : la cible atteignable la plus proche. */
    fun chooseReachableTarget() {
        val reach = _state.value.pageTargetReach ?: return
        _state.update { it.copy(pageTargetReach = null) }
        setTargetPageCount(reach.closestTarget)
    }

    /** « Passer à 75 % de photos » : le ratio qui ouvre la cible, puis la cible. */
    fun raiseRatioForTarget() {
        val reach = _state.value.pageTargetReach ?: return
        val ratio = reach.ratioThatReaches ?: return
        _state.update { it.copy(pageTargetReach = null) }
        edit(BookCustomisationEdit.PhotoTextRatio(ratio)) { it.copy(photoTextRatio = ratio) }
        setTargetPageCount(reach.target)
    }

    /**
     * « Garder N pages quand même » : la cible part telle quelle. Le carnet
     * s'en approchera autant qu'il pourra, sans rien forcer.
     */
    fun keepUnreachableTarget() {
        val reach = _state.value.pageTargetReach ?: return
        _state.update { it.copy(pageTargetReach = null) }
        setTargetPageCount(reach.target)
    }

    /** La feuille refermée d'un glissé : rien ne change. */
    fun dismissPageTargetReach() {
        _state.update { it.copy(pageTargetReach = null) }
    }

    /**
     * Change le nombre de pages cible — ou ouvre la feuille qui le fait.
     *
     * **Tant qu'aucune étape n'est écrite, le changement est libre** et part
     * au geste, comme tout réglage. Ensuite, il compte (Hugo, 15/10/2026) : la
     * feuille prévient d'abord de ce qui reste, et rien ne change avant qu'on
     * confirme — l'écran garde l'ancien palier coché. Les deux changements
     * faits, rien ne part : le panneau dit pourquoi, à l'orange.
     */
    fun setTargetPageCount(pages: Int) {
        val current = _state.value.customisation?.targetPageCount ?: return
        if (pages == current) return
        val allowance = _state.value.pageTargetAllowance
        if (!allowance.changesCount) {
            edit(BookCustomisationEdit.TargetPageCount(pages)) { it.copy(targetPageCount = pages) }
            return
        }
        if (allowance.changesLeft <= 0) {
            explainPageTargetLimit()
            return
        }
        val change = PageTargetChange(
            from = current,
            to = pages,
            tripDays = _state.value.tripDays,
            step = PageTargetChange.Step.Confirm(changesLeft = allowance.changesLeft),
        )
        _state.update { it.copy(pageTargetChange = change) }
    }

    fun setFunFacts(isOn: Boolean) = edit(BookCustomisationEdit.FunFacts(isOn)) { it.copy(funFactsEnabled = isOn) }

    /**
     * Verrou posé, les pointillés ne se rallument pas : l'interrupteur pâlit
     * et explique ([BookExtrasPanel]), et un appel qui passerait quand même
     * ne part pas.
     */
    fun setRules(isOn: Boolean) {
        if (isOn && _state.value.areRulesLocked) return
        edit(BookCustomisationEdit.Rules(isOn)) { it.copy(rulesEnabled = isOn) }
    }

    /**
     * L'appui sur l'interrupteur verrouillé : poser la note qui dit pourquoi,
     * et comment en sortir. Elle s'en va avec le verrou, et ne revient pas
     * d'elle-même au suivant : elle répond à un appui, pas à un état.
     */
    fun explainRulesLock() {
        _state.update { it.copy(isExplainingRulesLock = true) }
    }

    fun setDecorationQuota(quota: Int) = edit(BookCustomisationEdit.DecorationQuota(quota)) { it.copy(decorationQuota = quota) }

    /**
     * L'assortiment de typographies du carnet : les quatre polices d'un coup.
     *
     * **Il n'y a plus de réglage par rôle** (Hugo, 16/09/2026) — voir
     * [BookFontCombo]. Une seule édition part, et les quatre colonnes bougent
     * ensemble : c'est ce qui garantit qu'aucun carnet ne se retrouve avec deux
     * polices d'un assortiment et deux d'un autre.
     *
     * **Les pointillés partent avec elles** : *Manuscrit* et *Éditorial* les
     * éteignent, le retour au défaut rend ceux d'avant — [BookRulesLock]
     * décide, et la même édition porte les cinq valeurs.
     *
     * Retoucher l'assortiment déjà choisi n'envoie rien : l'édition porterait
     * les pointillés de l'écran, et rallumerait ceux qu'un co-voyageur vient
     * d'éteindre.
     */
    fun setFontCombo(combo: BookFontCombo) {
        val current = _state.value.customisation ?: return
        if (combo.matches(current)) return
        val change = BookRulesLock.choosing(combo, current, remembered = rulesMemory.read(tripId))
        change.remember?.let { rulesMemory.write(tripId, it) }

        edit(BookCustomisationEdit.FontCombo(combo, rulesEnabled = change.rulesEnabled)) { customisation ->
            BookFontRole.entries
                .fold(customisation) { written, role -> role.writing(combo.font(role), into = written) }
                .copy(rulesEnabled = change.rulesEnabled)
        }
        // Après `edit`, qui efface la note du geste précédent.
        if (current.rulesEnabled && !change.rulesEnabled) _state.update { it.copy(rulesWithdrawnBy = combo) }
    }

    fun setQuiz(isOn: Boolean) = edit(BookCustomisationEdit.Quiz(isOn)) { it.copy(quizEnabled = isOn) }

    fun setFreeZones(isOn: Boolean) = edit(BookCustomisationEdit.FreeZones(isOn)) { it.copy(freeZonesEnabled = isOn) }

    fun setCrossword(isOn: Boolean) = edit(BookCustomisationEdit.Crossword(isOn)) { it.copy(crosswordEnabled = isOn) }

    /**
     * Pose la valeur à l'écran, puis l'envoie.
     *
     * Les deux dans cet ordre, toujours : un curseur qui attend un aller-retour
     * réseau pour bouger se lit comme cassé, et les quatre feuilles à curseur
     * seraient inutilisables.
     */
    private fun edit(change: BookCustomisationEdit, apply: (BookCustomisation) -> BookCustomisation) {
        val current = _state.value.settings ?: return
        val customisation = current.customisation ?: return
        revision += 1
        _state.update {
            it.copy(settings = current.copy(customisation = apply(customisation)), rulesWithdrawnBy = null)
                .forgettingLockNoticeIfUnlocked()
        }
        save(change)
    }

    /**
     * Envoie un réglage, et remplace l'écran par ce que le serveur relit.
     *
     * **En file, et non en annulant l'envoi d'avant** (02/10/2026). Annuler
     * valait pour les crans d'un même curseur, mais pas pour deux réglages
     * voisins : éteindre les fun facts puis le quiz annulait l'envoi des fun
     * facts, la réponse du quiz les rendait allumés, et l'aperçu de
     * personnalisation bougeait après un geste qui ne le concerne pas. Donc :
     *
     * - un envoi part quand le précédent a répondu ;
     * - un réglage qui attend encore est remplacé par un plus récent **du même
     *   champ** : un curseur qu'on fait glisser n'envoie que son premier cran et
     *   celui où il s'arrête ;
     * - seule la réponse du dernier envoi remplace l'écran — elle a vu tous les
     *   gestes d'avant, les autres seraient déjà périmées ;
     * - un envoi raté ne retient pas ceux qui attendent derrière : ce sont
     *   d'autres réglages, ils partent quand même, et la réponse du dernier
     *   montre ce que le serveur a vraiment — le réglage raté compris. Quand
     *   c'est le dernier qui rate, l'écran relit le serveur.
     */
    private fun save(change: BookCustomisationEdit) {
        if (persist == null) return
        queue.removeAll { it.field == change.field }
        queue.add(change)
        // Posé ici, sans attendre que la coroutine démarre : deux gestes dans
        // la même image lanceraient sinon deux envois côte à côte.
        if (isSending) return
        isSending = true
        viewModelScope.launch { sendQueue() }
    }

    private suspend fun sendQueue() {
        try {
            val persist = persist ?: return
            while (queue.isNotEmpty()) {
                val change = queue.removeAt(0)
                isAwaitingResponse = true
                try {
                    val updated = persist(tripId, change)
                    isAwaitingResponse = false
                    revision += 1
                    if (queue.isNotEmpty()) continue
                    _state.update {
                        it.copy(settings = updated, errorMessage = null, errorAdvice = null).forgettingLockNoticeIfUnlocked()
                    }
                    forgetRulesIfUnlocked()
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    isAwaitingResponse = false
                    revision += 1
                    // Le troisième changement de cible, refusé : ce n'est pas une
                    // panne. Le panneau le dit à l'orange, et la relecture
                    // ci-dessous fait pâlir les paliers.
                    if ((error as? ApiError)?.code == ApiError.PAGE_TARGET_LIMIT_REACHED_CODE) {
                        explainPageTargetLimit()
                    } else {
                        report(error)
                    }
                    // D'autres réglages attendent : ils partent, et la réponse
                    // du dernier remettra l'écran d'accord avec le serveur.
                    if (queue.isNotEmpty()) continue
                    // Rien derrière : l'écran relit le serveur, et montre ce
                    // qu'il a vraiment. Un geste fait pendant cette relecture
                    // entre dans la file — la boucle l'envoie au lieu de l'y
                    // laisser.
                    reload()
                }
            }
        } finally {
            isSending = false
        }
    }

    // MARK: - Le changement de nombre de pages cible

    /** L'appui sur un palier pâli : poser la note orange. */
    fun explainPageTargetLimit() {
        _state.update { it.copy(isExplainingPageTargetLimit = true) }
    }

    /**
     * « Changer le nombre de pages cible ». Avec une date de fin, les dates
     * disent où en est le voyage ; sans elle, la feuille le demande.
     */
    fun confirmPageTargetChange() {
        val change = _state.value.pageTargetChange ?: return
        if (change.step !is PageTargetChange.Step.Confirm) return
        val settings = _state.value.settings
        val stage = PageTargetTripStage.from(startDate = settings?.startDate, endDate = settings?.endDate, today = today())
        if (stage == null) {
            _state.update { it.copy(pageTargetChange = change.copy(step = PageTargetChange.Step.Stage)) }
            return
        }
        viewModelScope.launch { commitPageTarget(stage) }
    }

    /** La réponse à « À quel stade de ton voyage en es-tu ? ». */
    fun choosePageTargetStage(stage: PageTargetTripStage) {
        if (_state.value.pageTargetChange?.step != PageTargetChange.Step.Stage) return
        viewModelScope.launch { commitPageTarget(stage) }
    }

    /**
     * Ferme la feuille — « Annuler », « Plus tard », « OK », « Compris » ou le
     * glissé. Annulé avant l'envoi, rien n'a changé : l'écran n'avait pas bougé.
     */
    fun dismissPageTargetChange() {
        if (_state.value.pageTargetChange?.isWorking == true) return
        _state.update { it.copy(pageTargetChange = null) }
    }

    /**
     * Envoie la nouvelle cible, et passe la feuille à son étape suivante.
     *
     * **Hors de la file des réglages**, et attendu : la feuille doit savoir si
     * ce changement-ci est passé — un 409 la fait passer à l'orange de la
     * limite (un co-voyageur a pu faire le dernier changement entre-temps), une
     * autre erreur reste sur l'étape avec son message.
     */
    private suspend fun commitPageTarget(stage: PageTargetTripStage) {
        val pending = _state.value.pageTargetChange ?: return
        if (pending.isWorking) return
        val change = pending.copy(isWorking = true, errorMessage = null)
        _state.update { it.copy(pageTargetChange = change) }
        revision += 1
        // Un cran du curseur personnalisé qui attendrait encore ne doit pas
        // repartir derrière celui-ci.
        queue.removeAll { it.field == BookCustomisationEdit.TargetPageCount(0).field }

        val persist = persist
        if (persist == null) {
            // Les aperçus travaillent en mémoire : le changement compte, et la
            // réécriture s'ouvre, comme au serveur.
            _state.update { state ->
                val current = state.settings
                val customisation = current?.customisation
                if (current == null || customisation == null) return@update state
                val allowance = current.pageTargetAllowance
                state.copy(
                    settings = current.copy(
                        customisation = customisation.copy(targetPageCount = change.to),
                        pageTarget = allowance.copy(changesLeft = maxOf(0, allowance.changesLeft - 1), rewriteAvailable = true),
                    ),
                    hasStartedRewrite = false,
                )
            }
            advance(change, PageTargetChange.Step.Done(stage))
            return
        }

        isAwaitingResponse = true
        try {
            val updated = persist(tripId, BookCustomisationEdit.TargetPageCount(change.to))
            isAwaitingResponse = false
            revision += 1
            accept(updated)
            // Un nouveau changement rouvre la réécriture : la phrase « on
            // réécrit » du précédent ne vaut plus.
            _state.update { it.copy(hasStartedRewrite = false) }
            advance(change, PageTargetChange.Step.Done(stage))
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            isAwaitingResponse = false
            revision += 1
            if ((error as? ApiError)?.code == ApiError.PAGE_TARGET_LIMIT_REACHED_CODE) {
                advance(change, PageTargetChange.Step.LimitReached)
                reload()
            } else {
                val failed = change.copy(isWorking = false, errorMessage = describe(error))
                _state.update { if (it.pageTargetChange?.id == change.id) it.copy(pageTargetChange = failed) else it }
            }
        }
    }

    /**
     * Ce que le serveur rend d'un changement de cible. La réponse remplace
     * l'écran quand rien d'autre n'est en route ; sinon, seules la cible et sa
     * règle en sont reprises — la réponse du dernier réglage en file remettra
     * le reste d'accord.
     */
    private fun accept(updated: TripSettings) {
        if (queue.isNotEmpty() || isSending) {
            _state.update { state ->
                val current = state.settings ?: return@update state
                val pages = updated.customisation?.targetPageCount
                val customisation = if (pages != null) current.customisation?.copy(targetPageCount = pages) else current.customisation
                state.copy(settings = current.copy(customisation = customisation, pageTarget = updated.pageTarget))
            }
            return
        }
        _state.update { it.copy(settings = updated, errorMessage = null, errorAdvice = null) }
    }

    /**
     * Passe la feuille à l'étape suivante — si elle est encore ouverte sur ce
     * changement-là : refermée entre-temps, elle ne se rouvre pas.
     */
    private fun advance(change: PageTargetChange, step: PageTargetChange.Step) {
        _state.update {
            if (it.pageTargetChange?.id != change.id) return@update it
            it.copy(pageTargetChange = change.copy(step = step, isWorking = false, errorMessage = null))
        }
    }

    /**
     * « Étoffer / Condenser les étapes déjà écrites », sur la feuille ou par le
     * lien du panneau — `POST /v1/trips/:id/page-target/rewrite`.
     *
     * Un 409 dit que c'est déjà fait (un co-voyageur, un autre téléphone) : le
     * lien s'en va, sans erreur — ce qu'on demandait est en route.
     */
    suspend fun rewriteWrittenSteps() {
        if (_state.value.isRewritingWrittenSteps) return
        val change = _state.value.pageTargetChange
        _state.update {
            it.copy(
                isRewritingWrittenSteps = true,
                pageTargetChange = change?.copy(isWorking = true, errorMessage = null),
            )
        }

        try {
            val rewrite = rewrite
            if (rewrite != null) {
                val updated = rewrite(tripId)
                _state.update { it.copy(settings = it.settings?.copy(pageTarget = updated.pageTarget)) }
            } else {
                closeRewrite()
            }
            _state.update {
                it.copy(
                    hasStartedRewrite = true,
                    pageTargetChange = if (it.pageTargetChange?.id == change?.id) null else it.pageTargetChange,
                )
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            if ((error as? ApiError)?.code == ApiError.PAGE_TARGET_REWRITE_UNAVAILABLE_CODE) {
                closeRewrite()
                _state.update { if (it.pageTargetChange?.id == change?.id) it.copy(pageTargetChange = null) else it }
                return
            }
            if (change != null && _state.value.pageTargetChange?.id == change.id) {
                val failed = change.copy(isWorking = false, errorMessage = describe(error))
                _state.update { it.copy(pageTargetChange = failed) }
            } else {
                report(error)
            }
        } finally {
            _state.update { it.copy(isRewritingWrittenSteps = false) }
        }
    }

    /** La réécriture n'est plus ouverte : le lien s'en va. */
    private fun closeRewrite() {
        _state.update { state ->
            val settings = state.settings ?: return@update state
            val pageTarget = settings.pageTarget ?: return@update state
            state.copy(settings = settings.copy(pageTarget = pageTarget.copy(rewriteAvailable = false)))
        }
    }

    // MARK: - Le verrou des pointillés

    /**
     * Un carnet verrouillé aux pointillés allumés — passé sur *Manuscrit* avant
     * le verrou, ou rallumé par une ancienne version de l'app — est remis dans
     * le rang à l'ouverture : éteints, et « allumés » mémorisé pour le retour
     * au défaut (Hugo, 02/10/2026) — sauf si ce téléphone garde déjà la valeur
     * d'avant le verrou : c'est elle qu'on rendra. C'est une écriture au
     * serveur sans geste du voyageur, et la seule de l'écran.
     */
    private fun settleRules() {
        val customisation = _state.value.customisation ?: return
        val change = BookRulesLock.normalised(customisation, remembered = rulesMemory.read(tripId)) ?: return
        change.remember?.let { rulesMemory.write(tripId, it) }
        edit(BookCustomisationEdit.Rules(change.rulesEnabled)) { it.copy(rulesEnabled = change.rulesEnabled) }
    }

    /**
     * La mémoire ne sert qu'à défaire un verrou : dès que le serveur rend un
     * carnet qui n'en a pas, elle s'efface. **Seulement sur sa parole**, et pas
     * au geste : un retour au défaut dont l'envoi échoue relit un carnet encore
     * verrouillé, et doit encore savoir quoi rendre.
     */
    private fun forgetRulesIfUnlocked() {
        val customisation = _state.value.customisation ?: return
        if (BookRulesLock.isLocked(customisation)) return
        rulesMemory.write(tripId, null)
    }

    private companion object {
        /** La phrase d'une erreur — le `localizedDescription` d'iOS. */
        fun describe(error: Throwable): String =
            (error as? ApiError)?.errorDescription ?: error.localizedMessage ?: error.toString()
    }
}

/**
 * Un changement de nombre de pages cible, tel que sa feuille le raconte.
 *
 * **Une seule feuille, dont le contenu change** (`ios/CLAUDE.md`, « un
 * enchaînement de feuilles ne s'empile pas ») : l'identifiant reste le même
 * d'une étape à l'autre, si bien que la présentation ne se refait pas.
 *
 * ```
 * palier touché ─→ Confirm  (ce qui reste de changements)
 *                     │ Changer le nombre de pages cible
 *                     ▼
 *                  Stage    (sans date de fin seulement)
 *                     │ début · moitié · fin
 *                     ▼
 *                  Done(stage) ─→ fin : étoffer / condenser l'écrit
 *
 * 409 à l'envoi ─→ LimitReached (l'orange)
 * ```
 *
 * @property from la cible d'avant.
 * @property to celle qu'on demande.
 * @property tripDays la durée du voyage au moment du geste : c'est elle qui
 *   nomme les récits (« récit compact »), comme les paliers du panneau.
 * @property isWorking un envoi part — le bouton de l'étape attend.
 * @property errorMessage l'envoi a raté pour une autre raison que la limite : dit
 *   sur la feuille, qui reste à son étape.
 */
data class PageTargetChange(
    val from: Int,
    val to: Int,
    val tripDays: Int?,
    val step: Step,
    val isWorking: Boolean = false,
    val errorMessage: String? = null,
    val id: String = UUID.randomUUID().toString(),
) {
    sealed interface Step {
        /** L'avertissement, avant tout envoi. */
        data class Confirm(val changesLeft: Int) : Step

        /** « À quel stade de ton voyage en es-tu ? » */
        data object Stage : Step

        /** Le serveur a refusé : les deux changements sont faits. */
        data object LimitReached : Step

        /** C'est fait. Vers la fin, la feuille propose de réécrire l'écrit. */
        data class Done(val stage: PageTargetTripStage) : Step
    }

    /** La cible monte : le récit s'étoffe. Sinon il se condense. */
    val isLonger: Boolean get() = to > from
}

/**
 * Le champ que cette édition écrit : deux éditions du même champ en file, seule
 * la dernière part. `FontCombo` et `Rules` restent deux champs — l'un porte les
 * polices, et la file les envoie dans l'ordre.
 */
private val BookCustomisationEdit.field: String
    get() = when (this) {
        is BookCustomisationEdit.PhotoTextRatio -> "photoTextRatio"
        is BookCustomisationEdit.TargetPageCount -> "targetPageCount"
        is BookCustomisationEdit.FunFacts -> "funFacts"
        is BookCustomisationEdit.Rules -> "rules"
        is BookCustomisationEdit.DecorationQuota -> "decorationQuota"
        is BookCustomisationEdit.FontDisplay -> "fontDisplay"
        is BookCustomisationEdit.FontTitle -> "fontTitle"
        is BookCustomisationEdit.FontHand -> "fontHand"
        is BookCustomisationEdit.FontFacts -> "fontFacts"
        is BookCustomisationEdit.FontCombo -> "fontCombo"
        is BookCustomisationEdit.Quiz -> "quiz"
        is BookCustomisationEdit.FreeZones -> "freeZones"
        is BookCustomisationEdit.Crossword -> "crossword"
    }
