package com.memobook.feature.bookpreview

import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.os.Build
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.memobook.core.BookCopy
import com.memobook.core.BookCovers
import com.memobook.core.BookPreview
import com.memobook.core.BookPreviewStatus
import com.memobook.core.BookRenderPhase
import com.memobook.core.CoverFace
import com.memobook.feature.ContentFreshness
import com.memobook.feature.contentFreshness
import com.memobook.feature.tripsettings.fixture
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimeSource

/**
 * Ce que le parcours de l'aperçu sait faire : suivre la composition du carnet,
 * ouvrir son PDF, et fabriquer de quoi le partager. Jumeau de
 * `BookPreview/BookPreviewModel.swift`.
 *
 * Un seul modèle pour deux écrans — la composition et l'aperçu — parce que
 * **c'en est un seul** : la composition finit et l'aperçu apparaît, sans que
 * personne appuie sur quoi que ce soit. Les couper en deux modèles aurait
 * demandé de passer un état de l'un à l'autre, ce qui est exactement ce que
 * [Stage] fait ici, en interne.
 *
 * Comme `ProfileModel`, il ne connaît pas l'API : il reçoit des fonctions.
 * L'app leur branche `POST /v1/memos/:id/renders` pour lancer la composition,
 * `GET /v1/memos/:id/preview` pour la suivre et `GET /v1/trips/:id/covers`
 * pour les deux plats ; les aperçus n'en fournissent aucune et travaillent en
 * mémoire.
 *
 * Ses parcours longs — [run], [refreshIfNeeded], [retry] — sont des fonctions
 * suspendues, lancées par l'écran (`LaunchedEffect`) comme le `.task` d'iOS :
 * un écran qui s'en va les annule, et son retour les reprend.
 *
 * @param covers `GET /v1/trips/:id/covers`. `null` — la feuille du paywall, les
 *   aperçus — ne lit pas les plats.
 * @param requestLink `POST /v1/memos/:id/share-link`.
 * @param workDirectory où le PDF de travail et son export s'écrivent : le cache
 *   de l'app. **Ce n'est pas le magasin** des carnets gardés
 *   ([BookDocumentStore], posé après la construction) : ces fichiers-ci meurent
 *   avec l'écran, ceux-là lui survivent. Le paramètre s'appelait `documents`,
 *   nom que porte désormais le magasin, comme sur iOS.
 *   Par défaut le dossier temporaire de Java, qu'Android pose sur ce même cache
 *   au lancement de l'app — le `URL.temporaryDirectory` d'iOS.
 * @param opensBlankPages le repli en pages blanches est permis — le `#if DEBUG`
 *   d'iOS, voir [State.showsBlankPages]. La porte le pose pour un build
 *   débogable ; l'app livrée garde l'écran de composition et son « Réessayer ».
 */
class BookPreviewModel(
    private val memoId: String,
    private val source: suspend (String) -> BookPreview = { BookPreview.fixture },
    /**
     * `POST /v1/memos/:id/renders`. `null` — la feuille du paywall, les
     * aperçus — ne lance rien et se contente de lire.
     */
    private val startComposition: (suspend (String) -> Unit)? = null,
    covers: (suspend (String) -> BookCovers)? = null,
    private val requestLink: (suspend (String) -> String)? = null,
    private val workDirectory: File = File(System.getProperty("java.io.tmpdir") ?: "."),
    opensBlankPages: Boolean = false,
) : ViewModel() {
    /** Où en est le parcours. */
    enum class Stage {
        /** La page se monte à l'écran pendant que le serveur compose. */
        Composing,

        /** Le carnet se feuillette. */
        Preview,
    }

    /**
     * @property compositionProgress l'avancement de la cascade de la page en
     *   composition, de 0 à 1. Il vit dans le modèle et non dans la vue parce
     *   que c'est **lui** qui décide du passage à l'aperçu : la page doit être
     *   finie avant que l'écran change, sinon un morceau resterait en vol. Le
     *   modèle pose la **cible**, la vue l'anime — voir [BookCompositionLoop].
     * @property isRecomposing une régénération (étape validée) tourne en fond
     *   **derrière** l'aperçu déjà affiché — jamais pendant la toute première
     *   composition, qui reste sur [Stage.Composing]. C'est ce qui distingue
     *   « le carnet n'existe pas encore » de « le carnet existe, une version
     *   plus à jour arrive ».
     * @property freshness ce que le dernier sondage a appris. Ne s'anime que sur
     *   un vrai changement — voir [ContentFreshness] — pour que le flash de
     *   rafraîchissement ne se joue jamais sur une confirmation « toujours
     *   pareil ».
     * @property document le PDF et ses pages rendues — voir [BookPageRenderer].
     * @property sheetIndex la feuille regardée, à partir de 0.
     * @property covers les deux plats du carnet, lus quand le carnet dit qu'ils
     *   sont choisis — voir [coverFace].
     * @property shareLink le lien de prévisualisation, une fois demandé.
     * @property showsBlankPages l'aperçu montre des pages **blanches** : rien
     *   n'a été composé — un carnet sans souvenir, une composition qui
     *   n'aboutit pas ou qui tarde. Debug seulement (Hugo, 19/10/2026) : « dans
     *   la version debug il faut qu'on puisse prévisualiser sans qu'on ait du
     *   vrai contenu ». L'app livrée garde l'écran de composition et son
     *   « Réessayer ».
     */
    /**
     * Ce que l'aperçu dit de lui-même, sous son en-tête (T302).
     *
     * @property answersAGesture vrai quand la phrase **répond à un geste** —
     *   un appui sur « Partager » fermé : c'est le ton `Information` de la
     *   marque. Faux pour l'état des choses, qui reste au beige.
     */
    data class Notice(val message: String, val answersAGesture: Boolean)

    data class State(
        val stage: Stage = Stage.Composing,
        val preview: BookPreview? = null,
        val errorMessage: String? = null,
        val compositionProgress: Double = 0.0,
        val isRecomposing: Boolean = false,
        val freshness: ContentFreshness = ContentFreshness.Unknown,
        val document: BookPageRenderer.Document = BookPageRenderer.Document(),
        val sheetIndex: Int = 0,
        val isFullScreen: Boolean = false,
        val covers: BookCovers? = null,
        val shareLink: String? = null,
        val isPreparingLink: Boolean = false,
        val showsBlankPages: Boolean = false,
        /**
         * Quelqu'un a touché « Partager » alors qu'il était fermé (T302).
         * Retombe dès que le carnet est composé — voir `apply`.
         */
        val hasAskedToShare: Boolean = false,
        /**
         * Quelqu'un a touché la flèche de mise à jour alors qu'elle était
         * pâlie (T299). Retombe dès que le carnet est composé.
         */
        val hasAskedToRegenerate: Boolean = false,
        /**
         * Une mise à jour demandée à la main tourne en ce moment — le temps de
         * l'appel et du premier sondage. [isRecomposing] prend la suite quand
         * le serveur en a lancé une.
         */
        val isRegenerating: Boolean = false,
        /**
         * La dernière mise à jour demandée n'avait rien à régénérer. Retombe au
         * geste suivant, et dès qu'une composition part.
         */
        val isAlreadyUpToDate: Boolean = false,
        /**
         * Quand le carnet affiché est arrivé sur l'appareil, quand c'est **lui
         * seul** qu'on peut montrer — le serveur n'a pas répondu. `null` dès
         * qu'une réponse confirme le carnet (T299).
         */
        val keptAt: Long? = null,
    ) {
        /**
         * Le carnet est composé côté serveur, donc imprimable.
         *
         * C'est ce qui allume « Commander ce carnet ». Volontairement
         * indépendant de [BookPageRenderer] : le rendu des pages est un confort
         * d'écran, et son échec ne doit pas interdire une commande.
         *
         * **Composé une fois suffit** : un carnet qu'une remise à jour
         * recompose se commande encore — c'est le rendu prêt d'avant qui
         * partira, celui qu'on feuillette.
         */
        val isComposed: Boolean get() = preview?.hasReadyRender ?: false

        /**
         * **Le carnet se partage** : une composition a abouti, il y a donc un
         * carnet derrière la page (T302).
         *
         * Ce n'est pas [isComposed], qui croit un statut « prêt » sur parole —
         * voir [BookPreview.hasComposedDocument]. Un carnet que le serveur
         * annonce prêt sans PDF n'a ni fichier ni lien à envoyer, et c'est
         * exactement l'état dans lequel « Partager » envoyait un faux carnet.
         */
        /**
         * **Ou bien le PDF est là**, gardé sur l'appareil (T299) : un carnet
         * ouvert sans réseau se partage, puisque le fichier est en main — c'est
         * même le seul cas où le partage ne dépend pas du tout du serveur. Les
         * pages blanches du debug n'en sont pas : on regarde le document, pas
         * [sheetCount].
         */
        val canShare: Boolean
            get() = (preview?.hasComposedDocument ?: false) || document.sheetCount > 0

        /**
         * La flèche tourne-t-elle. Vrai de l'appui jusqu'à la fin de la
         * composition, qu'elle vienne de ce geste ou d'une étape validée
         * ailleurs : ce qui tourne dit « ça travaille », pas « j'ai appuyé ».
         */
        val isRefreshing: Boolean get() = isRegenerating || isRecomposing

        /**
         * Le mot posé sous l'en-tête des trois écrans de l'aperçu, ou `null`
         * quand la page qu'on regarde est bien celle du carnet.
         *
         * Un seul à la fois, et dans cet ordre : la réponse à un geste
         * d'abord — on vient de la demander —, la remise à jour ensuite, et
         * enfin l'état des choses.
         */
        val notice: Notice?
            get() {
                if (hasAskedToShare) return Notice(BookCopy.Share.notComposedYet, answersAGesture = true)
                if (hasAskedToRegenerate) {
                    return Notice(BookCopy.Preview.nothingToRegenerate, answersAGesture = true)
                }
                if (isAlreadyUpToDate) {
                    return Notice(BookCopy.Preview.alreadyUpToDate, answersAGesture = true)
                }
                // L'écran de composition dit déjà tout sous sa page, et mieux
                // que ce bandeau : la phase en cours, et les souvenirs qu'elle
                // attend. Le doubler ferait dire deux fois la même chose au
                // même écran — et « On remet à jour ton carnet… » y serait
                // faux : rien n'est à remettre à jour, c'est la première
                // composition.
                if (stage != Stage.Preview) return null
                if (isRecomposing) return Notice(BookCopy.Preview.recomposing, answersAGesture = false)
                // **Avant** l'état des choses : un carnet gardé est bien un
                // carnet, et le serveur n'a simplement rien dit. Sans cette
                // branche, l'ouverture sans réseau annonçait « pas encore
                // composé » au-dessus du carnet qu'on feuillette.
                if (keptAt != null) {
                    return Notice(BookCopy.Preview.keptVersion(keptAt), answersAGesture = false)
                }
                if (canShare) return null
                return Notice(BookCopy.Preview.notComposed, answersAGesture = false)
            }

        /**
         * **Le sous-titre de l'en-tête** : « Rome et la Dolce Vita - 10 pages
         * composées », ou le **titre seul** tant que rien n'est composé (T302).
         *
         * Le compte de pages vient du serveur, et il survit à un rendu qui n'a
         * pas abouti : annoncer « 10 pages composées » au-dessus d'une page
         * vide est la première chose qui fait prendre ce carnet pour un carnet
         * prêt.
         */
        val headerSubtitle: String
            get() {
                val titre = preview?.title ?: ""
                if (!canShare) return titre
                return BookCopy.Preview.subtitle(title = titre, pages = sheetCount)
            }

        /**
         * Où en est la composition qui tourne — ce que l'écran de composition
         * dit sous sa page. `null` avant le premier sondage, et sur un serveur
         * qui ne le dit pas.
         */
        val compositionPhase: BookRenderPhase? get() = preview?.render?.phase

        /** Les souvenirs que la composition attend avant de mettre en page. */
        val pendingMemoryCount: Int get() = preview?.pendingMemoryCount ?: 0

        /**
         * Combien de feuilles l'aperçu montre.
         *
         * Le document fait foi dès qu'il est là ; avant, c'est le compteur du
         * serveur qui tient la place, pour que l'en-tête et l'indicateur
         * n'affichent pas « Page 1 / 0 » le temps d'un transfert.
         */
        val sheetCount: Int
            get() {
                if (document.sheetCount > 0) return document.sheetCount
                val counted = preview?.pageCount ?: 0
                if (showsBlankPages && counted == 0) return BLANK_PAGE_COUNT
                return counted
            }

        val canGoBack: Boolean get() = sheetIndex > 0
        val canGoForward: Boolean get() = sheetIndex + 1 < sheetCount

        /**
         * Le plat que montre la feuille [index], s'il y en a un à montrer.
         *
         * La première et la dernière, couvertures choisies et lues. Une seule
         * page — le tout premier souvenir — reste la première de couverture.
         */
        fun coverFace(index: Int): CoverFace? {
            if (preview?.hasConfiguredCovers != true || covers == null || sheetCount <= 0) return null
            if (index == 0) return CoverFace.Front
            if (index == sheetCount - 1) return CoverFace.Back
            return null
        }

        /**
         * La feuille regardée se configure : c'est la première ou la dernière,
         * et les couvertures n'ont pas encore été choisies. C'est ce qui pose
         * le voile.
         *
         * **Le compte de feuilles, pas le PDF** (Hugo, 30/09/2026). Jusqu'ici
         * il fallait aussi que le document soit descendu, pour ne pas voiler
         * un aplat vide. Mais l'écran de l'app n'a pas encore de PDF — il vit
         * sur son jeu d'essai tant que T194 n'est pas tranché —, et le
         * garde-fou effaçait donc l'invitation **partout, tout le temps** :
         * Hugo l'a redemandée plusieurs fois sans jamais la voir. Une page
         * papier voilée qui mène aux couvertures vaut mieux qu'une page sans
         * chemin.
         */
        val isOnConfigurableCover: Boolean
            get() = preview?.isConfigurableCover(page = sheetIndex, total = sheetCount) ?: false

        /**
         * La feuille regardée est la première ou la dernière du carnet :
         * celles qu'on règle depuis les couvertures.
         */
        val isOnCover: Boolean get() = sheetCount > 0 && (sheetIndex == 0 || sheetIndex == sheetCount - 1)

        /**
         * Ce que la page regardée porte pour aller aux couvertures.
         *
         * **La première et la dernière page en portent toujours un** (Hugo,
         * 30/09/2026, maquette `3545:21634`) : le voile et son invitation tant
         * que les couvertures ne sont pas choisies, le bouton « Configurer »
         * seul, posé sur la page, ensuite. Le 26/09, seule la première le
         * gardait une fois les couvertures choisies — et la quatrième de
         * couverture n'avait plus de chemin vers son écran.
         */
        val coverCallToAction: CoverCallToAction?
            get() {
                if (!isOnCover) return null
                return if (isOnConfigurableCover) CoverCallToAction.Invitation else CoverCallToAction.Edit
            }
    }

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    private val coversSource = covers

    /**
     * Le PDF et ses pages rendues.
     *
     * `internal` : le rendu est un détail de ces écrans-là, pas une API du
     * module. Ce qui sort d'ici, ce sont des états et des images, pas un
     * document PDF.
     */
    internal val renderer = BookPageRenderer(workDirectory)

    /**
     * Une composition est suivie en ce moment. Garde [run] d'un second départ
     * — l'effet de l'écran et celui d'un retour sur l'écran.
     */
    private var isRunning = false

    /**
     * Où le dernier carnet composé est gardé (T299). `null` — les aperçus, la
     * plupart des tests — ne garde rien : l'aperçu redescendra, comme avant le
     * ticket. Posé après la construction, comme `pacing`.
     */
    var documents: BookDocumentStore? = null

    /**
     * Le rendu derrière le PDF **ouvert à l'écran** — celui qu'on a gardé, ou
     * celui qu'on vient de descendre.
     *
     * C'est ce qui évite le transfert : le serveur annonce le même rendu, il
     * n'y a rien à aller chercher. Distinct du `readyRenderId` de la réponse,
     * qui est ce que le serveur a de plus récent.
     */
    private var openRenderId: String? = null

    /**
     * Le rythme du parcours : la cascade, les sondages, et quand cesser
     * d'attendre. Les valeurs de l'app sont [standard] ; les tests les
     * resserrent pour ne pas attendre quatre minutes.
     *
     * @property compositionDuration combien de temps la cascade dure.
     *   **C'est aussi le plancher de l'attente** : même si le serveur répond en
     *   300 ms, l'écran tient ces secondes-là. Ce n'est pas une lenteur ajoutée
     *   pour faire joli — une page qui se monte et disparaît avant d'être
     *   finie donne l'impression d'un bogue, et l'aperçu qui suit arrive alors
     *   sans qu'on ait compris ce qui venait de se passer. **4,2 s et non plus
     *   2,6** (Hugo, 08/10/2026) : la cascade était courte pour l'attente qui
     *   suit, et le rythme est désormais celui de chaque page de la boucle —
     *   voir [BookCompositionLoop].
     * @property progressTick le pas entre deux relevés de l'avancement. La
     *   cascade se joue dans une animation de la vue, ce rythme ne sert qu'à
     *   savoir **quand elle est finie**.
     * @property pollInterval l'intervalle entre deux questions au serveur
     *   pendant la composition. Deux secondes : une composition dure des
     *   dizaines de secondes, et demander plus souvent ne ferait que payer des
     *   allers-retours pour la même réponse.
     * @property maxUnchangedCompositionPolls combien de sondages **sans
     *   changement** avant que la toute première composition cesse d'être
     *   attendue — quatre minutes, à deux secondes l'un (19/10/2026). Il n'y
     *   avait pas de borne : un rendu que personne ne finit (worker tombé, job
     *   perdu) laissait la page se remonter indéfiniment. La mise en page
     *   attend jusqu'à trois minutes les souvenirs en rédaction, sans que rien
     *   ne bouge : quatre minutes la laissent faire. Au-delà, l'écran dit que
     *   c'est long et propose de réessayer — le serveur relance de lui-même une
     *   composition restée en plan (`STALE_RENDER_MS`).
     * @property recompositionPollInterval l'intervalle entre deux sondages
     *   pendant une régénération en fond. Plus large que [pollInterval] : une
     *   régénération refait tout le travail (LLM puis rendu), elle prend donc
     *   plus que quelques dizaines de secondes — sonder aussi souvent que la
     *   première composition ne ferait que payer des allers-retours pour la
     *   même réponse.
     * @property maxUnchangedRecompositionPolls combien de sondages **sans
     *   changement** avant de laisser tomber — quatre minutes, à quatre
     *   secondes l'un. Même raisonnement que `StatisticsModel.maxUnchangedPolls` :
     *   un rendu peut rester bloqué pour de mauvaises raisons, et l'écran ne
     *   doit pas sonder indéfiniment un aperçu resté ouvert. Revenir sur l'écran
     *   relance un sondage. Quatre et non deux : la mise en page attend jusqu'à
     *   trois minutes les souvenirs encore en rédaction, sans que rien ne
     *   bouge entre-temps.
     * @property debugBlankPagesAfter en debug, combien de temps la première
     *   composition est attendue avant d'ouvrir l'aperçu **en pages blanches**
     *   — la composition continue derrière, et ses pages remplacent les
     *   blanches à l'arrivée. Plus que les dix secondes de `composeBook`, pour
     *   que le bac à sable joue toujours sa composition entière.
     */
    internal data class Pacing(
        val compositionDuration: Duration,
        val progressTick: Duration,
        val pollInterval: Duration,
        val maxUnchangedCompositionPolls: Int,
        val recompositionPollInterval: Duration,
        val maxUnchangedRecompositionPolls: Int,
        val debugBlankPagesAfter: Duration = 30.seconds,
    ) {
        companion object {
            val standard = Pacing(
                compositionDuration = BookCompositionLoop.assembly,
                progressTick = 100.milliseconds,
                pollInterval = 2.seconds,
                maxUnchangedCompositionPolls = 120,
                recompositionPollInterval = 4.seconds,
                maxUnchangedRecompositionPolls = 60,
            )
        }
    }

    /** `internal` et modifiable : les tests y posent un rythme serré. */
    internal var pacing = Pacing.standard

    /**
     * L'horloge des attentes — le `ContinuousClock` d'iOS. Les tests y posent
     * celle de leur ordonnanceur, dont le temps est virtuel.
     */
    internal var timeSource: TimeSource = TimeSource.Monotonic

    /**
     * Le repli en pages blanches est permis. Les tests de l'app livrée
     * l'éteignent : ils doivent voir l'écran de composition et son
     * « Réessayer ».
     */
    internal var opensBlankPages = opensBlankPages

    // Ce que les tests et les vues lisent d'un coup d'œil — l'état courant.
    val stage: Stage get() = state.value.stage
    val preview: BookPreview? get() = state.value.preview
    val errorMessage: String? get() = state.value.errorMessage
    val compositionProgress: Double get() = state.value.compositionProgress
    val isRecomposing: Boolean get() = state.value.isRecomposing
    val freshness: ContentFreshness get() = state.value.freshness
    val covers: BookCovers? get() = state.value.covers
    val sheetCount: Int get() = state.value.sheetCount
    val isComposed: Boolean get() = state.value.isComposed
    val compositionPhase: BookRenderPhase? get() = state.value.compositionPhase
    val showsBlankPages: Boolean get() = state.value.showsBlankPages
    val isOnConfigurableCover: Boolean get() = state.value.isOnConfigurableCover
    val coverCallToAction: CoverCallToAction? get() = state.value.coverCallToAction
    fun coverFace(index: Int): CoverFace? = state.value.coverFace(index)

    // MARK: - Composer, puis montrer

    /**
     * Le parcours entier : lancer la composition, monter la page, la suivre,
     * ouvrir le PDF, et passer à l'aperçu quand les deux sont prêts.
     *
     * **La composition part d'ici** (Hugo, 06/10/2026, T224) : ouvrir l'aperçu
     * — l'imprimante de l'accueil du voyage, « Prévisualisation PDF » des
     * réglages, l'en-tête des personnalisations, la bannière de la
     * conversation — appelle `POST /v1/memos/:id/renders`. **Sûr à rappeler** :
     * le serveur rend la composition en cours, ou le dernier rendu s'il est à
     * jour, et n'en relance une — payante — que si le récit a changé depuis.
     * Avant, plus aucun écran ne la lançait, et l'aperçu attendait une
     * composition qui ne venait jamais.
     *
     * Un premier sondage décide ensuite s'il y a vraiment une composition à
     * suivre : un carnet déjà composé — réouverture d'un aperçu déjà vu —
     * passe direct à l'aperçu, sans cascade ni plancher, **même si une remise
     * à jour tourne** : on feuillette le carnet d'avant, et le bandeau « On
     * remet à jour ton carnet… » dit que le nouveau arrive. Le temps de
     * chargement le plus court possible, c'est ne pas en inventer un.
     *
     * Sinon — un carnet jamais composé —, les deux attentes sont menées **en
     * parallèle** et non l'une après l'autre : la cascade et la composition du
     * serveur n'ont aucune raison de s'attendre, et c'est la plus longue des
     * deux qui décide.
     */
    suspend fun run() {
        if (state.value.stage != Stage.Composing || isRunning) return
        isRunning = true
        try {
            _state.update { it.copy(errorMessage = null) }

            // 0. **Le carnet qu'on avait**, avant tout appel (T299) : s'il est
            //    sur l'appareil, il s'ouvre tout de suite, et la suite se passe
            //    derrière des pages qu'on feuillette déjà. C'est tout le
            //    ticket — l'attente d'avant était celle du transfert, pas celle
            //    de la composition, que l'empreinte avait déjà supprimée
            //    (T224).
            openKeptDocument()
            currentCoroutineContext().ensureActive()

            // 1. Lancer la composition — ou retrouver celle qui tourne. Un échec
            //    ne s'affiche pas encore : un carnet déjà composé reste
            //    feuilletable, et c'est le sondage qui suit qui le dira.
            val launchFailure = launchComposition()
            currentCoroutineContext().ensureActive()

            // 2. Ce que le serveur en dit.
            val first = try {
                source(memoId)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                // Le carnet gardé est à l'écran : il n'y a **pas** d'erreur à
                // montrer, il y a une version à nommer. Sans réseau, c'est
                // exactement ce que le ticket demande — « donc lisible sans
                // réseau » —, et le mot sous l'en-tête dit de quand elle date.
                if (state.value.keptAt != null) return
                setError(launchFailure ?: describe(error))
                openBlankPages()
                return
            }
            currentCoroutineContext().ensureActive()

            loadCovers(first)

            // Un carnet déjà composé s'ouvre tout de suite. Une remise à jour
            // qui tourne se suit en fond, derrière les pages qu'on a déjà.
            if (first.hasReadyRender) {
                apply(first)
                (first.status as? BookPreviewStatus.Failed)?.let { setError(it.message) }
                _state.update { it.copy(stage = Stage.Preview) }
                if (state.value.isRecomposing) watchRecomposition()
                return
            }

            // Jamais composé, et la composition n'a pas pu partir — un carnet
            // sans souvenir (`400 empty_memo`), une panne : rien ne viendra. Le
            // message du serveur le dit, et la page reste vierge plutôt que de
            // se monter pour rien.
            if (launchFailure != null && first.render == null) {
                apply(first)
                setError(launchFailure)
                openBlankPages()
                return
            }

            val failed = first.status as? BookPreviewStatus.Failed
            if (failed != null) {
                apply(first)
                setError(failed.message)
                openBlankPages()
                return
            }

            val outcome = coroutineScope {
                launch { playComposition() }
                async { followComposition(firstLoad = first) }.await()
            }

            // Un écran quitté pendant la composition ne passe pas à l'aperçu :
            // son retour reprendra le suivi, sans rejouer la cascade.
            currentCoroutineContext().ensureActive()

            // Trop longue pour le debug : les pages blanches tout de suite, et
            // la composition suivie derrière, comme une remise à jour.
            if (outcome == CompositionOutcome.DebugTimedOut) {
                openBlankPages()
                if (state.value.isRecomposing) watchRecomposition()
                return
            }

            // Un échec de composition laisse l'écran où il est : le message dit
            // ce qui s'est passé, et le bouton de reprise est dans la vue.
            // Passer à un aperçu vide serait pire que d'attendre — sauf en
            // debug, qui ouvre ses pages blanches.
            if (state.value.errorMessage != null) {
                openBlankPages()
                return
            }
            _state.update { it.copy(stage = Stage.Preview) }
        } finally {
            isRunning = false
        }
    }

    /** Comment le suivi de la première composition s'est arrêté. */
    private enum class CompositionOutcome {
        /** Prête, en échec, ou l'écran quitté : l'erreur posée dit lequel. */
        Finished,

        /** Le debug a cessé d'attendre — voir [Pacing.debugBlankPagesAfter]. */
        DebugTimedOut,
    }

    /**
     * Ouvre l'aperçu sur des pages blanches : rien n'a été composé, et le
     * debug doit pouvoir feuilleter quand même. Le bandeau dit pourquoi, s'il
     * y a une raison. Sans effet dans l'app livrée.
     */
    private suspend fun openBlankPages() {
        if (!opensBlankPages || !currentCoroutineContext().isActive) return
        // Un carnet est ouvert — celui que l'appareil gardait (T299) : on ne le
        // remplace pas par des pages blanches.
        if (state.value.document.sheetCount > 0) return
        _state.update {
            it.copy(
                preview = it.preview ?: BookPreview(memoId = memoId, title = BookCopy.Preview.blankTitle),
                showsBlankPages = true,
                compositionProgress = 1.0,
                stage = Stage.Preview,
            )
        }
    }

    /**
     * Demande la composition au serveur. Rend le message d'un refus, `null`
     * quand elle est partie — ou qu'il n'y a personne à qui la demander : la
     * feuille du paywall et les aperçus, qui n'ont pas de carnet.
     */
    private suspend fun launchComposition(): String? {
        val start = startComposition ?: return null
        return try {
            start(memoId)
            null
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            describe(error)
        }
    }

    /**
     * Fait monter la page, et n'en sort qu'une fois la cascade finie.
     *
     * **Une fois par écran** : revenir sur une composition qu'on avait quittée
     * — le temps d'aller régler son style — retrouve la page déjà montée, au
     * lieu de la voir se défaire et se refaire.
     */
    private suspend fun playComposition() {
        if (state.value.compositionProgress >= 1) return

        // La cible est posée d'un coup : c'est la vue qui interpole, et la
        // boucle qui suit ne fait que mesurer le temps écoulé.
        _state.update { it.copy(compositionProgress = 1.0) }

        val started = timeSource.markNow()
        while (started.elapsedNow() < pacing.compositionDuration) {
            delay(pacing.progressTick)
        }
    }

    /**
     * Interroge le serveur jusqu'à ce que le carnet soit composé, puis ouvre
     * son PDF.
     *
     * @param firstLoad la réponse déjà en main, pour ne pas la redemander —
     *   [run] l'a lue pour décider s'il y avait une composition à suivre.
     *
     * **Bornée** (19/10/2026) : après [Pacing.maxUnchangedCompositionPolls]
     * sondages sans que rien ne bouge — ni la phase, ni les souvenirs
     * attendus —, elle cesse et pose `BookCopy.Composition.tooLong`. Avant, un
     * rendu que personne ne finissait faisait tourner la page sans fin.
     */
    private suspend fun followComposition(firstLoad: BookPreview? = null): CompositionOutcome {
        var next = firstLoad
        var previous: BookPreview? = null
        var unchanged = 0
        val started = timeSource.markNow()

        while (currentCoroutineContext().isActive) {
            try {
                val loaded = next ?: source(memoId)
                next = null

                _state.update { it.copy(errorMessage = null) }
                apply(loaded)

                when (val status = loaded.status) {
                    BookPreviewStatus.Ready -> return CompositionOutcome.Finished
                    is BookPreviewStatus.Failed -> {
                        setError(status.message)
                        return CompositionOutcome.Finished
                    }
                    BookPreviewStatus.Composing -> {
                        unchanged = if (loaded == previous) unchanged + 1 else 0
                        previous = loaded
                        if (unchanged >= pacing.maxUnchangedCompositionPolls) {
                            setError(BookCopy.Composition.tooLong)
                            return CompositionOutcome.Finished
                        }
                        if (opensBlankPages && started.elapsedNow() >= pacing.debugBlankPagesAfter) {
                            return CompositionOutcome.DebugTimedOut
                        }
                        delay(pacing.pollInterval)
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                setError(describe(error))
                return CompositionOutcome.Finished
            }
        }
        return CompositionOutcome.Finished
    }

    /**
     * Le point unique où une réponse du serveur devient de l'état affiché.
     *
     * Une régénération en fond ne doit jamais faire régresser un aperçu déjà
     * affiché : l'erreur n'est posée ni ici ni pour un échec de régénération —
     * c'est aux appelants de la toute première composition de le faire, eux
     * qui savent qu'il n'y a encore rien à montrer à la place.
     */
    private suspend fun apply(loaded: BookPreview) {
        val previous = state.value.preview
        _state.update {
            it.copy(
                // **Ce qui se voit**, et non la réponse entière : la phase d'une
                // composition change à chaque étape du serveur, et le flash de
                // rafraîchissement ne doit se jouer que quand le carnet
                // lui-même a changé — un nouveau PDF, d'autres pages, un autre
                // titre.
                freshness = contentFreshness(ShownBook(loaded), previous?.let(::ShownBook)),
                preview = loaded,
                isRecomposing = loaded.status == BookPreviewStatus.Composing,
                // Le carnet est arrivé : l'explication n'a plus d'objet, et le
                // bouton qu'elle désignait vient de s'ouvrir (T302).
                hasAskedToShare = it.hasAskedToShare && !loaded.hasComposedDocument,
                hasAskedToRegenerate = it.hasAskedToRegenerate && !loaded.hasComposedDocument,
                // Une composition est partie, d'ici ou d'ailleurs : « ton
                // carnet est déjà à jour » vient d'être démenti.
                isAlreadyUpToDate =
                    it.isAlreadyUpToDate && loaded.status != BookPreviewStatus.Composing,
                // Le serveur a répondu : ce qui est à l'écran n'est plus « tout
                // ce qu'on a », c'est le carnet confirmé. Le mot qui nommait sa
                // date n'a plus d'objet.
                keptAt = null,
            )
        }

        // Le PDF se recharge quand le serveur annonce **un autre** rendu que
        // celui qui est ouvert, ou qu'aucun document ne l'est. Un sondage qui
        // confirme le même rendu ne redescend rien — et **le carnet gardé sur
        // l'appareil compte comme ouvert** (T299) : c'est là que rouvrir un
        // carnet inchangé cesse de coûter un transfert de plusieurs
        // mégaoctets.
        //
        // La comparaison se fait sur [openRenderId] et non sur la réponse
        // d'avant : ce qui compte est ce qu'on affiche, pas ce qu'on a lu.
        val url = loaded.pdfUrl ?: return
        val announced = ShownBook(loaded).document
        if (state.value.document.sheetCount > 0 && announced == openRenderId) return

        loadDocument(url)
        if (state.value.document.didFail) return
        openRenderId = announced
        // Gardé **après** l'ouverture : un PDF que `PdfRenderer` refuse n'a
        // rien à faire sur le disque, il ferait échouer les ouvertures
        // suivantes sans réseau pour les réparer.
        val file = renderer.documentFile
        if (announced != null && file != null) {
            documents?.keep(file, renderId = announced, memoId = memoId)
        }
    }

    /**
     * Ouvre le carnet que l'appareil gardait, s'il y en a un (T299).
     *
     * **Avant tout appel réseau**, et sans en faire aucun : c'est ce qui
     * remplace la page crème du premier chargement par le carnet qu'on
     * feuilletait hier. La suite — composition, sondage — se déroule derrière.
     *
     * `keptAt` est posé ici et retiré par [apply] : entre les deux, le carnet
     * affiché est le seul qu'on puisse montrer, et l'écran le dit.
     */
    private suspend fun openKeptDocument() {
        val store = documents ?: return
        if (state.value.document.sheetCount > 0) return
        val kept = store.kept(memoId) ?: return
        val document = renderer.openKept(kept.file)
        if (document.sheetCount == 0) return

        openRenderId = kept.renderId
        _state.update {
            it.copy(document = document, keptAt = kept.keptAt, stage = Stage.Preview)
        }
    }

    /**
     * Ce que l'aperçu montre d'une réponse du serveur — de quoi décider si elle
     * **change l'écran**.
     *
     * @property document le rendu derrière le PDF ; à défaut — un serveur
     *   d'avant le 06/10/2026 —, l'adresse du PDF.
     */
    private data class ShownBook(
        val title: String,
        val pageCount: Int,
        val document: String?,
        val isReady: Boolean,
        val hasConfiguredCovers: Boolean,
    ) {
        constructor(preview: BookPreview) : this(
            title = preview.title,
            pageCount = preview.pageCount,
            document = preview.readyRenderId ?: preview.pdfUrl,
            isReady = preview.status.isReady,
            hasConfiguredCovers = preview.hasConfiguredCovers,
        )
    }

    /**
     * Un sondage léger, pour capter une régénération déclenchée ailleurs
     * (« Valider cette étape » sur l'écran du voyage) pendant que l'aperçu
     * était déjà ouvert ou en arrière-plan — et des couvertures qu'on vient de
     * régler depuis « Configurer ».
     *
     * Sans effet hors de [Stage.Preview] — la toute première composition passe
     * par [run] — et sans effet si une veille tourne déjà.
     */
    suspend fun refreshIfNeeded() {
        if (state.value.stage != Stage.Preview || state.value.isRecomposing) return

        val loaded = try {
            source(memoId)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            // Un sondage silencieux qui échoue ne doit rien afficher sur un
            // aperçu déjà là — même règle que dans `apply`.
            return
        }
        loadCovers(loaded)
        apply(loaded)
        if (state.value.isRecomposing) watchRecomposition()
    }

    /**
     * Sonde à intervalle large tant qu'une régénération tourne, et s'arrête
     * d'elle-même — même motif que `StatisticsModel.watch()`. Jamais de boucle
     * infinie sur un rendu qui ne reviendra pas : au bout du compte, on laisse
     * tomber, et une prochaine ouverture pourra resonder.
     *
     * « Sans changement » se juge sur **la réponse entière**, phase comprise :
     * une composition qui passe de la file à la mise en page avance, même si
     * rien ne change encore à l'écran.
     */
    private suspend fun watchRecomposition() {
        var unchanged = 0
        while (currentCoroutineContext().isActive &&
            state.value.isRecomposing &&
            unchanged < pacing.maxUnchangedRecompositionPolls
        ) {
            delay(pacing.recompositionPollInterval)
            try {
                val previous = state.value.preview
                val loaded = source(memoId)
                apply(loaded)
                unchanged = if (loaded == previous) unchanged + 1 else 0
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                unchanged += 1
            }
        }
        _state.update { it.copy(isRecomposing = false) }
    }

    /**
     * Relance après un échec.
     *
     * Sur un carnet déjà composé, **sans quitter l'aperçu** : on redemande la
     * remise à jour et on la suit en fond, derrière les pages qu'on a. Sur un
     * carnet jamais composé, le parcours entier — la composition **et** la
     * cascade.
     */
    /**
     * **Mettre le carnet à jour**, parce qu'on le demande (T299 — « un bouton à
     * flèche tournante la régénère »).
     *
     * Ouvrir l'aperçu ne remet plus rien en page : le carnet gardé s'affiche,
     * et le serveur ne recompose que si le récit a changé depuis (T224). Ce
     * bouton est donc le geste par lequel on **demande** une version fraîche,
     * au lieu de l'attendre.
     *
     * **Il ne force rien, et c'est voulu.** Une composition coûte de l'IA et un
     * rendu : c'est au serveur de décider s'il y a lieu — il relance quand
     * quelque chose a changé, il rend le dernier rendu sinon. On lit sa réponse
     * pour savoir lequel des deux vient d'arriver, et on le dit : une flèche
     * qui tourne une seconde et rien d'autre se lirait comme une panne.
     */
    suspend fun regenerate() {
        if (state.value.isRefreshing) return
        _state.update {
            it.copy(
                isRegenerating = true,
                errorMessage = null,
                isAlreadyUpToDate = false,
                hasAskedToShare = false,
                hasAskedToRegenerate = false,
            )
        }
        try {
            launchComposition()?.let { failure ->
                setError(failure)
                return
            }
            val loaded = try {
                source(memoId)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                return
            }
            apply(loaded)

            if (state.value.isRecomposing) {
                watchRecomposition()
            } else {
                // **C'est le serveur qui le dit**, et non une déduction : il
                // compare l'empreinte du carnet à celle du dernier rendu
                // (`isUpToDate`, T224) — la même question que celle qui décide
                // de relancer. Un serveur d'avant ce champ ne la répond pas ;
                // rien ne s'est lancé, c'est donc qu'il n'y avait rien à
                // lancer.
                val aJour = loaded.isUpToDate ?: true
                _state.update { it.copy(isAlreadyUpToDate = aJour) }
            }
        } finally {
            _state.update { it.copy(isRegenerating = false) }
        }
    }

    suspend fun retry() {
        _state.update { it.copy(errorMessage = null) }

        val current = state.value
        if (current.stage == Stage.Preview && current.preview?.hasReadyRender == true) {
            launchComposition()?.let { failure ->
                setError(failure)
                return
            }
            val loaded = try {
                source(memoId)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                null
            }
            if (loaded != null) apply(loaded)
            if (state.value.isRecomposing) watchRecomposition()
            return
        }

        _state.update { it.copy(stage = Stage.Composing, compositionProgress = 0.0, showsBlankPages = false) }
        run()
    }

    // MARK: - Les couvertures

    /**
     * Relit les deux plats, quand le carnet dit qu'ils sont choisis : ce sont
     * eux que la première et la dernière page montrent (Hugo, 06/10/2026,
     * T223). Sans effet tant qu'ils ne le sont pas — l'invitation à les
     * choisir se pose alors sur la page du PDF.
     *
     * **Sans attendre** : la page du PDF tient la place le temps de la
     * lecture, et un échec ne coûte que ça — l'aperçu ne bloque pas sur ses
     * couvertures.
     */
    private fun loadCovers(loaded: BookPreview) {
        val read = coversSource ?: return
        if (!loaded.hasConfiguredCovers) return
        viewModelScope.launch {
            val fresh = try {
                read(memoId)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                return@launch
            }
            _state.update { it.copy(covers = fresh) }
        }
    }

    /**
     * Recharge le seul PDF, sans recomposer : le carnet est là, c'est le
     * téléchargement qui a échoué.
     */
    suspend fun reloadDocument() {
        val url = state.value.preview?.pdfUrl ?: return
        loadDocument(url)
    }

    private suspend fun loadDocument(url: String) {
        val document = renderer.load(url)
        _state.update { it.copy(document = document) }
    }

    // MARK: - Feuilleter

    fun goBack() {
        if (!state.value.canGoBack) return
        _state.update { it.copy(sheetIndex = it.sheetIndex - 1) }
    }

    fun goForward() {
        if (!state.value.canGoForward) return
        _state.update { it.copy(sheetIndex = it.sheetIndex + 1) }
    }

    fun show(sheet: Int) {
        if (sheet < 0 || sheet >= state.value.sheetCount) return
        _state.update { it.copy(sheetIndex = sheet) }
    }

    fun setFullScreen(isOn: Boolean) {
        _state.update { it.copy(isFullScreen = isOn) }
    }

    // MARK: - Partager

    /**
     * Demande le lien de prévisualisation, ou rend celui qu'on a déjà.
     *
     * Il n'existe pas tant qu'on ne l'a pas demandé, et c'est volontaire :
     * c'est un lien **public**, il ne se crée pas au chargement d'un écran.
     */
    suspend fun prepareShareLink(): String? {
        state.value.shareLink?.let { return it }
        state.value.preview?.shareUrl?.let { existing ->
            _state.update { it.copy(shareLink = existing) }
            return existing
        }

        val request = requestLink ?: return null

        _state.update { it.copy(isPreparingLink = true) }
        return try {
            val link = request(memoId)
            _state.update { it.copy(shareLink = link) }
            link
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            setError(BookCopy.Share.linkFailed)
            null
        } finally {
            _state.update { it.copy(isPreparingLink = false) }
        }
    }

    /**
     * Le PDF écrit dans un fichier du cache, prêt à partir dans la feuille de
     * partage du système.
     *
     * Un **fichier** et non les données brutes : c'est ce qui donne un nom au
     * document dans WhatsApp ou Gmail, et « Rome et la Dolce Vita.pdf » se
     * reçoit mieux que « Pièce jointe ». Le nom est nettoyé de ce qu'un système
     * de fichiers refuse. Il est écrit dans `books/`, le seul dossier du cache
     * que le `FileProvider` de l'app prête aux autres apps.
     */
    suspend fun exportPdf(): File? = withContext(Dispatchers.IO) {
        val title = state.value.preview?.title ?: "Carnet MemoBook"
        val safe = title
            .split('/', '\\', ':', '?', '%', '*', '|', '"', '<', '>')
            .joinToString(" ")
            .trim()
        val folder = File(workDirectory, SHARED_FOLDER)
        val file = File(folder, "${safe.ifEmpty { "Carnet" }}.pdf")
        val partial = File(folder, "${file.name}.part")

        try {
            folder.mkdirs()
            // **L'app n'invente plus de carnet** (T302, Hugo, 08/11/2026).
            //
            // Elle en composait un, d'une page, qui disait qu'il n'était pas
            // le carnet : c'était la réponse à « il y a toujours un fichier à
            // partager » (Hugo, 19/09/2026), quand toucher « Partager le
            // fichier PDF » sans document n'ouvrait rien du tout. Mais c'est
            // ce fichier-là que Hugo a reçu en croyant partager son carnet, et
            // un faux carnet est pire qu'un bouton qui n'ouvre rien.
            //
            // Le geste est fermé en amont — voir `State.canShare`, qui pâlit
            // le bouton et explique —, donc on n'arrive plus ici sans
            // document. Reste le **bac à sable**, dont le jeu d'essai n'a pas
            // de PDF : sans ce fichier d'attente, ni la feuille de partage ni
            // le choix des étapes (T285) ne se regarderaient hors serveur.
            // `opensBlankPages` est le `#if DEBUG` d'iOS — l'app livrée
            // n'écrit donc jamais ce fichier.
            val document = renderer.documentFile
            when {
                document != null -> document.copyTo(partial, overwrite = true)
                opensBlankPages -> partial.outputStream().use { writePlaceholderPdf(title, it) }
                else -> return@withContext null
            }
            if (!partial.renameTo(file)) {
                partial.copyTo(file, overwrite = true)
                partial.delete()
            }
            file
        } catch (_: IOException) {
            partial.delete()
            null
        }
    }

    /** Rejoue la composition depuis le début. Le `#if DEBUG` d'iOS : sans effet dans l'app livrée. */
    fun debugReplayComposition() {
        if (!opensBlankPages) return
        _state.update { it.copy(stage = Stage.Composing, compositionProgress = 0.0, showsBlankPages = false) }
        viewModelScope.launch { run() }
    }

    override fun onCleared() {
        renderer.close()
    }

    /**
     * Dit pourquoi « Partager » ne mène nulle part. Appelé par le bouton pâli,
     * qui reste tapable : « ce qu'on ne peut pas faire pâlit, ça ne se
     * désactive pas » (`ios/CLAUDE.md`).
     */
    fun explainShareIsClosed() {
        _state.update { it.copy(hasAskedToShare = true, hasAskedToRegenerate = false) }
    }

    /**
     * Dit pourquoi la flèche de mise à jour ne mène nulle part. Même contrat
     * que [explainShareIsClosed] : le bouton pâli reste tapable, et l'appui va
     * chercher son explication (T299).
     */
    fun explainRegenerateIsClosed() {
        _state.update { it.copy(hasAskedToRegenerate = true, hasAskedToShare = false) }
    }

    /**
     * Le fichier n'a pas pu être fabriqué : le carnet est composé — sinon
     * « Partager » serait resté fermé —, mais son PDF n'est pas descendu.
     *
     * Ce n'est donc pas une composition qui manque, et le message le dit :
     * [BookCopy.Preview.loadFailed] propose de reprendre le téléchargement.
     * Sans lui, l'appui sur « Partager le fichier pdf » ne ferait plus rien du
     * tout — c'est le défaut que le PDF d'attente était venu couvrir en
     * septembre, et il n'est pas question de le laisser revenir.
     */
    fun reportMissingDocument() = setError(BookCopy.Preview.loadFailed)

    private fun setError(message: String) {
        _state.update { it.copy(errorMessage = message) }
    }

    companion object {
        /** Combien de pages blanches, quand le serveur n'en compte aucune. */
        const val BLANK_PAGE_COUNT = 8

        /** Le dossier du cache que le `FileProvider` prête — voir `res/xml/photo_paths.xml` de `:app`. */
        const val SHARED_FOLDER = "books"

        /** Le message d'une erreur, prêt pour l'écran — `ApiError` le porte déjà en français. */
        private fun describe(error: Throwable): String = error.localizedMessage ?: error.toString()

        /**
         * Un PDF d'une page, composé par l'app, à la place du carnet.
         *
         * Il **dit qu'il n'est pas le carnet** : partager un fichier vide ou
         * une page blanche laisserait croire à un carnet raté. Une page A5 au
         * format du carnet, le titre, et la phrase qui explique.
         */
        private fun writePlaceholderPdf(title: String, output: java.io.OutputStream) {
            // A5 en points PostScript : le format du carnet.
            val pageWidth = 420
            val pageHeight = 595
            val margin = 48f
            val width = (pageWidth - margin * 2).toInt()
            val ink = android.graphics.Color.rgb(46, 36, 26)

            val document = PdfDocument()
            try {
                val page = document.startPage(PdfDocument.PageInfo.Builder(pageWidth, pageHeight, 1).create())
                val canvas = page.canvas

                val heading = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                    textSize = 24f
                    color = ink
                    typeface = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        Typeface.create(Typeface.DEFAULT, 600, false)
                    } else {
                        Typeface.DEFAULT_BOLD
                    }
                }
                canvas.save()
                canvas.translate(margin, margin)
                canvas.clipRect(0f, 0f, width.toFloat(), 120f)
                StaticLayout.Builder.obtain(title, 0, title.length, heading, width)
                    .setAlignment(Layout.Alignment.ALIGN_NORMAL)
                    .build()
                    .draw(canvas)
                canvas.restore()

                val body = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                    textSize = 13f
                    color = ink
                    alpha = (255 * 0.6f).toInt()
                }
                val text = BookCopy.Preview.placeholderPdfBody
                canvas.save()
                canvas.translate(margin, margin + 120f)
                canvas.clipRect(0f, 0f, width.toFloat(), 200f)
                StaticLayout.Builder.obtain(text, 0, text.length, body, width)
                    .setAlignment(Layout.Alignment.ALIGN_NORMAL)
                    .build()
                    .draw(canvas)
                canvas.restore()

                document.finishPage(page)
                document.writeTo(output)
            } finally {
                document.close()
            }
        }
    }
}

/** Le chemin vers les couvertures, posé sur une page de l'aperçu. */
enum class CoverCallToAction {
    /** « Définis maintenant ta 1ère et 4ème de couverture », sur le voile. */
    Invitation,

    /** La pastille « Configurer » seule : les couvertures sont choisies, on peut y revenir. */
    Edit,
}
