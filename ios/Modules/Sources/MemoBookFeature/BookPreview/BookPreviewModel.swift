import PDFKit
import Foundation
import MemoBookCore
import Observation
import SwiftUI
import UIKit

/// Ce que le parcours de l'aperçu sait faire : suivre la composition du carnet,
/// ouvrir son PDF, et fabriquer de quoi le partager.
///
/// Un seul modèle pour deux écrans — la composition et l'aperçu — parce que
/// **c'en est un seul** : la composition finit et l'aperçu apparaît, sans que
/// personne appuie sur quoi que ce soit. Les couper en deux modèles aurait
/// demandé de passer un état de l'un à l'autre, ce qui est exactement ce que
/// ``Stage`` fait ici, en interne.
///
/// Comme ``ProfileModel``, il ne connaît pas l'API : il reçoit des fonctions.
/// L'app leur branche `POST /v1/memos/:id/renders` pour lancer la composition,
/// `GET /v1/memos/:id/preview` pour la suivre et `GET /v1/trips/:id/covers`
/// pour les deux plats ; les aperçus n'en fournissent aucune et travaillent en
/// mémoire.
@MainActor
@Observable
public final class BookPreviewModel {
    /// Où en est le parcours.
    public enum Stage: Equatable {
        /// La page se monte à l'écran pendant que le serveur compose.
        case composing
        /// Le carnet se feuillette.
        case preview
    }

    public private(set) var stage: Stage = .composing
    public private(set) var preview: BookPreview?
    public private(set) var errorMessage: String?

    /// L'avancement de la cascade de la page en composition, de 0 à 1.
    ///
    /// Il vit dans le modèle et non dans la vue parce que c'est **lui** qui
    /// décide du passage à l'aperçu : la page doit être finie avant que l'écran
    /// change, sinon un morceau resterait en vol.
    public private(set) var compositionProgress: Double = 0

    /// Une régénération (étape validée) tourne en fond **derrière** l'aperçu
    /// déjà affiché — jamais pendant la toute première composition, qui reste
    /// sur ``Stage/composing``. C'est ce qui distingue « le carnet n'existe pas
    /// encore » de « le carnet existe, une version plus à jour arrive ».
    public private(set) var isRecomposing = false

    /// Ce que le dernier sondage a appris. Ne s'anime que sur un vrai
    /// changement — voir ``ContentFreshness`` — pour que le flash de
    /// rafraîchissement ne se joue jamais sur une confirmation « toujours
    /// pareil ».
    public private(set) var freshness: ContentFreshness = .unknown

    /// Le PDF et ses pages rendues.
    ///
    /// `internal` : le rendu est un détail de ces écrans-là, pas une API du
    /// module. Ce qui sort d'ici, ce sont des états et des images, pas un
    /// document PDF.
    let renderer = BookPageRenderer()

    /// La feuille regardée, à partir de 0.
    public private(set) var sheetIndex = 0

    public private(set) var isFullScreen = false

    /// Le carnet est composé côté serveur, donc imprimable.
    ///
    /// C'est ce qui allume « Commander ce carnet ». Volontairement indépendant
    /// de ``BookPageRenderer`` : le rendu des pages est un confort d'écran, et
    /// son échec ne doit pas interdire une commande.
    ///
    /// **Composé une fois suffit** : un carnet qu'une remise à jour recompose se
    /// commande encore — c'est le rendu prêt d'avant qui partira, celui qu'on
    /// feuillette.
    public var isComposed: Bool { preview?.hasReadyRender ?? false }

    /// **Le carnet se partage** : une composition a abouti, il y a donc un
    /// carnet derrière la page (T302).
    ///
    /// Ce n'est pas ``isComposed``, qui croit un statut « prêt » sur parole —
    /// voir ``BookPreview/hasComposedDocument``. Un carnet que le serveur
    /// annonce prêt sans PDF n'a ni fichier ni lien à envoyer, et c'est
    /// exactement l'état dans lequel « Partager » envoyait un faux carnet.
    ///
    /// **Ou bien le PDF est là**, gardé sur l'appareil (T299) : un carnet
    /// ouvert sans réseau se partage, puisque les octets sont en main — c'est
    /// même le seul cas où le partage ne dépend pas du tout du serveur. Les
    /// pages blanches du debug n'en sont pas : on regarde le document, pas
    /// ``sheetCount``.
    public var canShare: Bool {
        (preview?.hasComposedDocument ?? false) || renderer.sheetCount > 0
    }

    /// **Le sous-titre de l'en-tête** : « Rome et la Dolce Vita - 10 pages
    /// composées », ou le **titre seul** tant que rien n'est composé (T302).
    ///
    /// Le compte de pages vient du serveur, et il survit à un rendu qui n'a
    /// pas abouti : annoncer « 10 pages composées » au-dessus d'une page vide
    /// est la première chose qui fait prendre ce carnet pour un carnet prêt.
    public var headerSubtitle: String {
        let titre = preview?.title ?? ""
        guard canShare else { return titre }
        return BookCopy.Preview.subtitle(title: titre, pages: sheetCount)
    }

    /// Quelqu'un a touché « Partager » alors qu'il était fermé. Retombe dès
    /// que le carnet est composé — voir ``apply(_:)``.
    public private(set) var hasAskedToShare = false

    /// Ce que l'aperçu dit de lui-même, sous son en-tête.
    public struct Notice: Equatable {
        public let message: String
        /// Vrai quand la phrase **répond à un geste** — un appui sur
        /// « Partager » fermé : c'est le ton `.information` de la marque. Faux
        /// pour l'état des choses, qui reste au beige.
        public let answersAGesture: Bool
    }

    /// Le mot posé sous l'en-tête des trois écrans de l'aperçu, ou `nil` quand
    /// la page qu'on regarde est bien celle du carnet.
    ///
    /// Un seul à la fois, et dans cet ordre : la réponse à un geste d'abord —
    /// on vient de la demander —, la remise à jour ensuite, et enfin l'état des
    /// choses.
    public var notice: Notice? {
        if hasAskedToShare {
            return Notice(message: BookCopy.Share.notComposedYet, answersAGesture: true)
        }
        // L'écran de composition dit déjà tout sous sa page, et mieux que ce
        // bandeau : la phase en cours, et les souvenirs qu'elle attend. Le
        // doubler ferait dire deux fois la même chose au même écran — et
        // « On remet à jour ton carnet… » y serait faux : rien n'est à
        // remettre à jour, c'est la première composition.
        if hasAskedToRegenerate {
            return Notice(message: BookCopy.Preview.nothingToRegenerate, answersAGesture: true)
        }
        if isAlreadyUpToDate {
            return Notice(message: BookCopy.Preview.alreadyUpToDate, answersAGesture: true)
        }
        guard stage == .preview else { return nil }
        if isRecomposing {
            return Notice(message: BookCopy.Preview.recomposing, answersAGesture: false)
        }
        // **Avant** l'état des choses : un carnet gardé est bien un carnet, et
        // le serveur n'a simplement rien dit. Sans cette branche, l'ouverture
        // sans réseau annonçait « pas encore composé » au-dessus du carnet
        // qu'on feuillette.
        if let keptAt {
            return Notice(message: BookCopy.Preview.keptVersion(keptAt), answersAGesture: false)
        }
        guard !canShare else { return nil }
        return Notice(message: BookCopy.Preview.notComposed, answersAGesture: false)
    }

    /// Une régénération demandée à la main tourne en ce moment — le temps de
    /// l'appel et du premier sondage. ``isRecomposing`` prend la suite quand le
    /// serveur en a lancé une.
    public private(set) var isRegenerating = false

    /// La dernière régénération demandée n'avait rien à régénérer. Retombe au
    /// geste suivant, et dès qu'une composition part.
    public private(set) var isAlreadyUpToDate = false

    /// La flèche tourne-t-elle. Vrai de l'appui jusqu'à la fin de la
    /// composition, qu'elle vienne de ce geste ou d'une étape validée
    /// ailleurs : ce qui tourne dit « ça travaille », pas « j'ai appuyé ».
    public var isRefreshing: Bool { isRegenerating || isRecomposing }

    /// Dit pourquoi « Partager » ne mène nulle part. Appelé par le bouton
    /// pâli, qui reste tapable : « ce qu'on ne peut pas faire pâlit, ça ne se
    /// désactive pas » (`ios/CLAUDE.md`).
    public func explainShareIsClosed() {
        hasAskedToShare = true
        hasAskedToRegenerate = false
    }

    /// Quelqu'un a touché la flèche de mise à jour alors qu'elle était pâlie
    /// (T299). Retombe dès que le carnet est composé — voir ``apply(_:)``.
    public private(set) var hasAskedToRegenerate = false

    /// Dit pourquoi la flèche ne mène nulle part. Même contrat que
    /// ``explainShareIsClosed()`` : le bouton pâli reste tapable, et l'appui va
    /// chercher son explication.
    public func explainRegenerateIsClosed() {
        hasAskedToRegenerate = true
        hasAskedToShare = false
    }

    /// Le fichier n'a pas pu être fabriqué : le carnet est composé — sinon
    /// « Partager » serait resté fermé —, mais son PDF n'est pas descendu.
    ///
    /// Ce n'est donc pas une composition qui manque, et le message le dit :
    /// ``BookCopy/Preview/loadFailed`` propose de reprendre le téléchargement.
    /// Sans lui, l'appui sur « Partager le fichier pdf » ne faisait plus rien
    /// du tout — c'est le défaut que le PDF d'attente était venu couvrir en
    /// septembre, et il n'est pas question de le laisser revenir.
    public func reportMissingDocument() { errorMessage = BookCopy.Preview.loadFailed }

    /// Où en est la composition qui tourne — ce que l'écran de composition dit
    /// sous sa page. `nil` avant le premier sondage, et sur un serveur qui ne
    /// le dit pas.
    public var compositionPhase: BookRenderPhase? { preview?.render?.phase }

    /// Les souvenirs que la composition attend avant de mettre en page.
    public var pendingMemoryCount: Int { preview?.pendingMemoryCount ?? 0 }

    /// Les deux plats du carnet, lus quand le carnet dit qu'ils sont choisis —
    /// voir ``coverFace(at:)``.
    public private(set) var covers: BookCovers?

    /// Le lien de prévisualisation, une fois demandé.
    public private(set) var shareLink: URL?
    public private(set) var isPreparingLink = false

    private let memoId: String
    private let source: (String) async throws -> BookPreview
    /// `POST /v1/memos/:id/renders`. `nil` — la feuille du paywall, les
    /// aperçus Xcode — ne lance rien et se contente de lire.
    private let startComposition: ((String) async throws -> Void)?
    private let coversSource: ((String) async throws -> BookCovers)?
    private let requestLink: ((String) async throws -> URL)?

    /// Où le dernier carnet composé est gardé (T299). `nil` — les aperçus
    /// Xcode, la plupart des tests — ne garde rien : l'aperçu retéléchargera,
    /// comme avant le ticket.
    ///
    /// Posé après la construction, comme ``pacing`` et pour la même raison :
    /// c'est un rouage interne du module, et l'`init` du modèle est publique.
    var documents: BookDocumentStore?

    /// Le rendu derrière le PDF **ouvert à l'écran** — celui qu'on a gardé,
    /// ou celui qu'on vient de télécharger.
    ///
    /// C'est ce qui évite le transfert : le serveur annonce le même rendu, il
    /// n'y a rien à aller chercher. Distinct de `preview?.readyRenderId`, qui
    /// est ce que le serveur a de plus récent.
    private var openRenderId: String?

    /// Quand le carnet affiché est arrivé sur l'appareil, quand c'est **lui
    /// seul** qu'on peut montrer — le serveur n'a pas répondu. `nil` dès qu'une
    /// réponse confirme le carnet.
    public private(set) var keptAt: Date?

    /// Une composition est suivie en ce moment. Garde ``run()`` d'un second
    /// départ — la tâche de l'écran et celle d'un retour sur l'écran.
    private var isRunning = false

    /// Le rythme du parcours : la cascade, les sondages, et quand cesser
    /// d'attendre. Les valeurs de l'app sont ``Pacing/standard`` ; les tests
    /// les resserrent pour ne pas attendre quatre minutes.
    struct Pacing {
        /// Combien de temps la cascade dure.
        ///
        /// **C'est aussi le plancher de l'attente** : même si le serveur répond
        /// en 300 ms, l'écran tient ces secondes-là. Ce n'est pas une lenteur
        /// ajoutée pour faire joli — une page qui se monte et disparaît avant
        /// d'être finie donne l'impression d'un bogue, et l'aperçu qui suit
        /// arrive alors sans qu'on ait compris ce qui venait de se passer.
        ///
        /// **4,2 s et non plus 2,6** (Hugo, 08/10/2026) : la cascade était
        /// courte pour l'attente qui suit, et le rythme est désormais celui de
        /// chaque page de la boucle — voir ``BookCompositionLoop``.
        ///
        /// **Puis une dizaine de secondes** (Hugo, 10/11/2026 : « plus longue,
        /// plus lente, plus logique — ligne par ligne »). La valeur n'est plus
        /// écrite : c'est la longueur de la chorégraphie elle-même, et le
        /// plancher suit tout seul quand on la règle.
        var compositionDuration: Duration

        /// Le pas entre deux relevés de l'avancement. La cascade se joue dans
        /// une animation SwiftUI, ce rythme ne sert qu'à savoir **quand elle
        /// est finie**.
        var progressTick: Duration

        /// L'intervalle entre deux questions au serveur pendant la composition.
        ///
        /// Deux secondes : une composition dure des dizaines de secondes, et
        /// demander plus souvent ne ferait que payer des allers-retours pour la
        /// même réponse.
        var pollInterval: Duration

        /// Combien de sondages **sans changement** avant que la toute première
        /// composition cesse d'être attendue — quatre minutes, à deux secondes
        /// l'un (19/10/2026). Il n'y avait pas de borne : un rendu que personne
        /// ne finit (worker tombé, job perdu) laissait la page se remonter
        /// indéfiniment. La mise en page attend jusqu'à trois minutes les
        /// souvenirs en rédaction, sans que rien ne bouge : quatre minutes la
        /// laissent faire. Au-delà, l'écran dit que c'est long et propose de
        /// réessayer — le serveur relance de lui-même une composition restée
        /// en plan (`STALE_RENDER_MS`).
        var maxUnchangedCompositionPolls: Int

        /// L'intervalle entre deux sondages pendant une régénération en fond.
        ///
        /// Plus large que ``pollInterval`` : une régénération refait tout le
        /// travail (LLM puis rendu), elle prend donc plus que quelques dizaines
        /// de secondes — sonder aussi souvent que la première composition ne
        /// ferait que payer des allers-retours pour la même réponse.
        var recompositionPollInterval: Duration

        /// Combien de sondages **sans changement** avant de laisser tomber —
        /// quatre minutes, à quatre secondes l'un. Même raisonnement que
        /// `StatisticsModel.maxUnchangedPolls` : un rendu peut rester bloqué
        /// pour de mauvaises raisons, et l'écran ne doit pas sonder
        /// indéfiniment un aperçu resté ouvert. Revenir sur l'écran relance un
        /// sondage.
        ///
        /// Quatre et non deux : la mise en page attend jusqu'à trois minutes
        /// les souvenirs encore en rédaction, sans que rien ne bouge
        /// entre-temps.
        var maxUnchangedRecompositionPolls: Int

        #if DEBUG
            /// En debug, combien de temps la première composition est attendue
            /// avant d'ouvrir l'aperçu **en pages blanches** — la composition
            /// continue derrière, et ses pages remplacent les blanches à
            /// l'arrivée. Plus que les dix secondes de `-composeBook`, pour que
            /// le bac à sable joue toujours sa composition entière.
            var debugBlankPagesAfter: Duration
        #endif

        @MainActor static var standard: Pacing {
            Pacing(
                compositionDuration: .seconds(BookCompositionLoop.assembly),
                progressTick: .milliseconds(100),
                pollInterval: .seconds(2),
                maxUnchangedCompositionPolls: 120,
                recompositionPollInterval: .seconds(4),
                maxUnchangedRecompositionPolls: 60
            )
        }

        init(
            compositionDuration: Duration,
            progressTick: Duration,
            pollInterval: Duration,
            maxUnchangedCompositionPolls: Int,
            recompositionPollInterval: Duration,
            maxUnchangedRecompositionPolls: Int
        ) {
            self.compositionDuration = compositionDuration
            self.progressTick = progressTick
            self.pollInterval = pollInterval
            self.maxUnchangedCompositionPolls = maxUnchangedCompositionPolls
            self.recompositionPollInterval = recompositionPollInterval
            self.maxUnchangedRecompositionPolls = maxUnchangedRecompositionPolls
            #if DEBUG
                debugBlankPagesAfter = .seconds(30)
            #endif
        }
    }

    /// `internal` et modifiable : les tests y posent un rythme serré.
    var pacing = Pacing.standard

    #if DEBUG
        /// L'aperçu montre des pages **blanches** : rien n'a été composé — un
        /// carnet sans souvenir, une composition qui n'aboutit pas ou qui
        /// tarde. Debug seulement (Hugo, 19/10/2026) : « dans la version debug
        /// il faut qu'on puisse prévisualiser sans qu'on ait du vrai contenu ».
        /// L'app livrée garde l'écran de composition et son « Réessayer ».
        public private(set) var showsBlankPages = false

        /// Le repli en pages blanches est permis. Les tests de l'app livrée
        /// l'éteignent : ils tournent en debug, et doivent voir l'écran de
        /// composition et son « Réessayer ».
        var opensBlankPages = true

        /// Combien de pages blanches, quand le serveur n'en compte aucune.
        static let blankPageCount = 8
    #endif

    public init(
        memoId: String,
        source: @escaping (String) async throws -> BookPreview = { _ in .fixture },
        startComposition: ((String) async throws -> Void)? = nil,
        covers: ((String) async throws -> BookCovers)? = nil,
        requestLink: ((String) async throws -> URL)? = nil
    ) {
        self.memoId = memoId
        self.source = source
        self.startComposition = startComposition
        self.coversSource = covers
        self.requestLink = requestLink
    }

    // MARK: - Composer, puis montrer

    /// Le parcours entier : lancer la composition, monter la page, la suivre,
    /// ouvrir le PDF, et passer à l'aperçu quand les deux sont prêts.
    ///
    /// **La composition part d'ici** (Hugo, 06/10/2026, T224) : ouvrir l'aperçu
    /// — l'imprimante de l'accueil du voyage, « Prévisualisation PDF » des
    /// réglages, l'en-tête des personnalisations, la bannière de la
    /// conversation — appelle `POST /v1/memos/:id/renders`. **Sûr à rappeler** :
    /// le serveur rend la composition en cours, ou le dernier rendu s'il est à
    /// jour, et n'en relance une — payante — que si le récit a changé depuis.
    /// Avant, plus aucun écran ne la lançait, et l'aperçu attendait une
    /// composition qui ne venait jamais.
    ///
    /// Un premier sondage décide ensuite s'il y a vraiment une composition à
    /// suivre : un carnet déjà composé — réouverture d'un aperçu déjà vu —
    /// passe direct à l'aperçu, sans cascade ni plancher de 2,6 s, **même si
    /// une remise à jour tourne** : on feuillette le carnet d'avant, et le
    /// bandeau « On remet à jour ton carnet… » dit que le nouveau arrive. Le
    /// temps de chargement le plus court possible, c'est ne pas en inventer un.
    ///
    /// Sinon — un carnet jamais composé —, les deux attentes sont menées **en
    /// parallèle** et non l'une après l'autre : la cascade et la composition
    /// du serveur n'ont aucune raison de s'attendre, et c'est la plus longue des
    /// deux qui décide.
    public func run() async {
        guard stage == .composing, !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        errorMessage = nil

        // 0. **Le carnet qu'on avait**, avant tout appel (T299) : s'il est sur
        //    l'appareil, il s'ouvre tout de suite, et la suite se passe
        //    derrière des pages qu'on feuillette déjà. C'est tout le ticket —
        //    l'attente d'avant était celle du transfert, pas celle de la
        //    composition, que l'empreinte avait déjà supprimée (T224).
        await openKeptDocument()
        guard !Task.isCancelled else { return }

        // 1. Lancer la composition — ou retrouver celle qui tourne. Un échec ne
        //    s'affiche pas encore : un carnet déjà composé reste feuilletable,
        //    et c'est le sondage qui suit qui le dira.
        let launchFailure = await launchComposition()
        guard !Task.isCancelled else { return }

        // 2. Ce que le serveur en dit.
        let first: BookPreview
        do {
            first = try await source(memoId)
        } catch {
            // Le carnet gardé est à l'écran : il n'y a **pas** d'erreur à
            // montrer, il y a une version à nommer. Sans réseau, c'est
            // exactement ce que le ticket demande — « donc lisible sans
            // réseau » —, et le mot sous l'en-tête dit de quand elle date.
            guard keptAt == nil else { return }
            errorMessage = launchFailure ?? error.localizedDescription
            #if DEBUG
                openBlankPages()
            #endif
            return
        }
        guard !Task.isCancelled else { return }

        loadCovers(for: first)

        // Un carnet déjà composé s'ouvre tout de suite. Une remise à jour qui
        // tourne se suit en fond, derrière les pages qu'on a déjà.
        if first.hasReadyRender {
            await apply(first)
            if case .failed(let message) = first.status { errorMessage = message }
            stage = .preview
            if isRecomposing { await watchRecomposition() }
            return
        }

        // Jamais composé, et la composition n'a pas pu partir — un carnet sans
        // souvenir (`400 empty_memo`), une panne : rien ne viendra. Le message
        // du serveur le dit, et la page reste vierge plutôt que de se monter
        // pour rien.
        if let launchFailure, first.render == nil {
            await apply(first)
            errorMessage = launchFailure
            #if DEBUG
                openBlankPages()
            #endif
            return
        }

        if case .failed(let message) = first.status {
            await apply(first)
            errorMessage = message
            #if DEBUG
                openBlankPages()
            #endif
            return
        }

        let outcome = await withTaskGroup(of: CompositionOutcome?.self) { group in
            group.addTask { [weak self] in
                await self?.playComposition()
                return nil
            }
            group.addTask { [weak self] in await self?.followComposition(firstLoad: first) }

            var outcome = CompositionOutcome.finished
            for await result in group {
                if let result { outcome = result }
            }
            return outcome
        }

        // Un écran quitté pendant la composition ne passe pas à l'aperçu : son
        // retour reprendra le suivi, sans rejouer la cascade.
        guard !Task.isCancelled else { return }

        #if DEBUG
            // Trop longue pour le debug : les pages blanches tout de suite, et
            // la composition suivie derrière, comme une remise à jour.
            if outcome == .debugTimedOut {
                openBlankPages()
                if isRecomposing { await watchRecomposition() }
                return
            }
            if errorMessage != nil {
                openBlankPages()
                return
            }
        #endif

        // Un échec de composition laisse l'écran où il est : le message dit ce
        // qui s'est passé, et le bouton de reprise est dans la vue. Passer à un
        // aperçu vide serait pire que d'attendre.
        guard errorMessage == nil else { return }
        stage = .preview
    }

    /// Comment le suivi de la première composition s'est arrêté.
    private enum CompositionOutcome {
        /// Prête, en échec, ou l'écran quitté : ``errorMessage`` dit lequel.
        case finished
        #if DEBUG
            /// Le debug a cessé d'attendre — voir
            /// ``Pacing/debugBlankPagesAfter``.
            case debugTimedOut
        #endif
    }

    #if DEBUG
        /// Ouvre l'aperçu sur des pages blanches : rien n'a été composé, et le
        /// debug doit pouvoir feuilleter quand même. Le bandeau dit pourquoi,
        /// s'il y a une raison.
        private func openBlankPages() {
            guard opensBlankPages, !Task.isCancelled else { return }
            // Un carnet est ouvert — celui que l'appareil gardait (T299) : on
            // ne le remplace pas par des pages blanches.
            guard renderer.sheetCount == 0 else { return }
            if preview == nil {
                preview = BookPreview(memoId: memoId, title: BookCopy.Preview.blankTitle)
            }
            showsBlankPages = true
            compositionProgress = 1
            stage = .preview
        }
    #endif

    /// Demande la composition au serveur. Rend le message d'un refus, `nil`
    /// quand elle est partie — ou qu'il n'y a personne à qui la demander : la
    /// feuille du paywall et les aperçus Xcode, qui n'ont pas de carnet.
    private func launchComposition() async -> String? {
        guard let startComposition else { return nil }
        do {
            try await startComposition(memoId)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Fait monter la page, et n'en sort qu'une fois la cascade finie.
    ///
    /// **Une fois par écran** : revenir sur une composition qu'on avait
    /// quittée — le temps d'aller régler son style — retrouve la page déjà
    /// montée, au lieu de la voir se défaire et se refaire.
    private func playComposition() async {
        guard compositionProgress < 1 else { return }

        // L'animation est posée d'un coup : c'est SwiftUI qui interpole, et la
        // boucle qui suit ne fait que mesurer le temps écoulé.
        withAnimationCompat(duration: pacing.compositionDuration) { self.compositionProgress = 1 }

        let started = ContinuousClock.now
        while ContinuousClock.now - started < pacing.compositionDuration {
            if Task.isCancelled { return }
            try? await Task.sleep(for: pacing.progressTick)
        }
    }

    /// Interroge le serveur jusqu'à ce que le carnet soit composé, puis ouvre
    /// son PDF.
    ///
    /// - Parameter firstLoad: la réponse déjà en main, pour ne pas la
    ///   redemander — ``run()`` l'a lue pour décider s'il y avait une
    ///   composition à suivre.
    ///
    /// **Bornée** (19/10/2026) : après ``Pacing/maxUnchangedCompositionPolls``
    /// sondages sans que rien ne bouge — ni la phase, ni les souvenirs
    /// attendus —, elle cesse et pose ``BookCopy/Composition/tooLong``. Avant,
    /// un rendu que personne ne finissait faisait tourner la page sans fin.
    private func followComposition(firstLoad: BookPreview? = nil) async -> CompositionOutcome {
        var next = firstLoad
        var previous: BookPreview?
        var unchanged = 0
        #if DEBUG
            let started = ContinuousClock.now
        #endif

        while !Task.isCancelled {
            do {
                let loaded: BookPreview
                if let value = next {
                    loaded = value
                    next = nil
                } else {
                    loaded = try await source(memoId)
                }

                errorMessage = nil
                await apply(loaded)

                switch loaded.status {
                case .ready:
                    return .finished
                case .failed(let message):
                    errorMessage = message
                    return .finished
                case .composing:
                    unchanged = loaded == previous ? unchanged + 1 : 0
                    previous = loaded
                    if unchanged >= pacing.maxUnchangedCompositionPolls {
                        errorMessage = BookCopy.Composition.tooLong
                        return .finished
                    }
                    #if DEBUG
                        if opensBlankPages, ContinuousClock.now - started >= pacing.debugBlankPagesAfter {
                            return .debugTimedOut
                        }
                    #endif
                    try? await Task.sleep(for: pacing.pollInterval)
                }
            } catch {
                errorMessage = error.localizedDescription
                return .finished
            }
        }
        return .finished
    }

    /// Le point unique où une réponse du serveur devient de l'état affiché.
    ///
    /// Une régénération en fond ne doit jamais faire régresser un aperçu déjà
    /// affiché : ``errorMessage`` n'est posé ni ici ni pour un échec de
    /// régénération — c'est aux appelants de la toute première composition de
    /// le faire, eux qui savent qu'il n'y a encore rien à montrer à la place.
    private func apply(_ loaded: BookPreview) async {
        let previous = preview
        // **Ce qui se voit**, et non la réponse entière : la phase d'une
        // composition change à chaque étape du serveur, et le flash de
        // rafraîchissement ne doit se jouer que quand le carnet lui-même a
        // changé — un nouveau PDF, d'autres pages, un autre titre.
        freshness = contentFreshness(
            of: ShownBook(loaded),
            replacing: previous.map(ShownBook.init)
        )
        preview = loaded

        // Le carnet est arrivé : l'explication n'a plus d'objet, et le bouton
        // qu'elle désignait vient de s'ouvrir.
        if canShare {
            hasAskedToShare = false
            hasAskedToRegenerate = false
        }

        switch loaded.status {
        case .ready, .failed:
            isRecomposing = false
        case .composing:
            isRecomposing = true
            // Une composition est partie, d'ici ou d'ailleurs : « ton carnet
            // est déjà à jour » vient d'être démenti.
            isAlreadyUpToDate = false
        }

        // Le serveur a répondu : ce qui est à l'écran n'est plus « tout ce
        // qu'on a », c'est le carnet confirmé. Le mot qui nommait sa date n'a
        // plus d'objet.
        keptAt = nil

        // Le PDF se recharge quand le serveur annonce **un autre** rendu que
        // celui qui est ouvert, ou qu'aucun document ne l'est. Un sondage qui
        // confirme le même rendu ne retélécharge rien — et **le carnet gardé
        // sur l'appareil compte comme ouvert** (T299) : c'est là que rouvrir un
        // carnet inchangé cesse de coûter un transfert de plusieurs mégaoctets.
        //
        // La comparaison se fait sur ``openRenderId`` et non sur la réponse
        // d'avant : ce qui compte est ce qu'on affiche, pas ce qu'on a lu.
        guard let url = loaded.pdfUrl else { return }
        let announced = ShownBook(loaded).document
        guard renderer.sheetCount == 0 || announced != openRenderId else { return }

        guard let data = await renderer.load(from: url) else { return }
        openRenderId = announced
        // Gardé **après** l'ouverture : un PDF que PDFKit refuse n'a rien à
        // faire sur le disque, il ferait échouer les ouvertures suivantes sans
        // réseau pour les réparer.
        if let announced {
            await documents?.keep(data, renderId: announced, for: memoId)
        }
    }

    /// Ouvre le carnet que l'appareil gardait, s'il y en a un (T299).
    ///
    /// **Avant tout appel réseau**, et sans en faire aucun : c'est ce qui
    /// remplace la page crème du premier chargement par le carnet qu'on
    /// feuilletait hier. La suite — composition, sondage — se déroule derrière.
    ///
    /// ``keptAt`` est posé ici et retiré par ``apply(_:)`` : entre les deux, le
    /// carnet affiché est le seul qu'on puisse montrer, et l'écran le dit.
    private func openKeptDocument() async {
        guard let documents, renderer.sheetCount == 0 else { return }
        guard let kept = await documents.kept(for: memoId) else { return }
        guard renderer.open(kept.data) else { return }

        openRenderId = kept.renderId
        keptAt = kept.keptAt
        stage = .preview
    }

    /// Ce que l'aperçu montre d'une réponse du serveur — de quoi décider si
    /// elle **change l'écran**.
    private struct ShownBook: Equatable {
        let title: String
        let pageCount: Int
        /// Le rendu derrière le PDF ; à défaut — un serveur d'avant le
        /// 06/10/2026 —, l'adresse du PDF.
        let document: String?
        let isReady: Bool
        let hasConfiguredCovers: Bool

        init(_ preview: BookPreview) {
            title = preview.title
            pageCount = preview.pageCount
            document = preview.readyRenderId ?? preview.pdfUrl?.absoluteString
            isReady = preview.status.isReady
            hasConfiguredCovers = preview.hasConfiguredCovers
        }
    }

    /// Un sondage léger, pour capter une régénération déclenchée ailleurs
    /// (« Valider cette étape » sur l'écran du voyage) pendant que l'aperçu
    /// était déjà ouvert ou en arrière-plan — et des couvertures qu'on vient
    /// de régler depuis « Configurer ».
    ///
    /// Sans effet hors de ``Stage/preview`` — la toute première composition
    /// passe par ``run()`` — et sans effet si une veille tourne déjà.
    public func refreshIfNeeded() async {
        guard stage == .preview, !isRecomposing else { return }

        do {
            let loaded = try await source(memoId)
            loadCovers(for: loaded)
            await apply(loaded)
            if isRecomposing {
                await watchRecomposition()
            }
        } catch {
            // Un sondage silencieux qui échoue ne doit rien afficher sur un
            // aperçu déjà là — même règle que dans `apply(_:)`.
        }
    }

    /// Sonde à intervalle large tant qu'une régénération tourne, et s'arrête
    /// d'elle-même — même motif que `StatisticsModel.watch()`. Jamais de
    /// boucle infinie sur un rendu qui ne reviendra pas : au bout du compte,
    /// on laisse tomber, et une prochaine ouverture pourra resonder.
    ///
    /// « Sans changement » se juge sur **la réponse entière**, phase comprise :
    /// une composition qui passe de la file à la mise en page avance, même si
    /// rien ne change encore à l'écran.
    private func watchRecomposition() async {
        var unchanged = 0
        while !Task.isCancelled, isRecomposing, unchanged < pacing.maxUnchangedRecompositionPolls {
            try? await Task.sleep(for: pacing.recompositionPollInterval)
            guard !Task.isCancelled else { return }
            do {
                let previous = preview
                let loaded = try await source(memoId)
                await apply(loaded)
                unchanged = loaded == previous ? unchanged + 1 : 0
            } catch {
                unchanged += 1
            }
        }
        isRecomposing = false
    }

    /// **Régénérer le carnet**, parce qu'on le demande (T299 — « un bouton à
    /// flèche tournante la régénère »).
    ///
    /// Ouvrir l'aperçu ne remet plus rien en page : le carnet gardé s'affiche,
    /// et le serveur ne recompose que si le récit a changé depuis (T224). Ce
    /// bouton est donc le geste par lequel on **demande** une version fraîche,
    /// au lieu de l'attendre.
    ///
    /// **Il ne force rien, et c'est voulu.** Une composition coûte de l'IA et un
    /// rendu : c'est au serveur de décider s'il y a lieu — il relance quand
    /// quelque chose a changé, il rend le dernier rendu sinon. On lit sa réponse
    /// pour savoir lequel des deux vient d'arriver, et on le dit : une flèche
    /// qui tourne une seconde et rien d'autre se lirait comme une panne.
    public func regenerate() async {
        guard !isRefreshing else { return }
        isRegenerating = true
        defer { isRegenerating = false }
        errorMessage = nil
        isAlreadyUpToDate = false
        hasAskedToShare = false
        hasAskedToRegenerate = false

        if let failure = await launchComposition() {
            errorMessage = failure
            return
        }
        guard let loaded = try? await source(memoId) else { return }
        await apply(loaded)

        if isRecomposing {
            await watchRecomposition()
        } else {
            // **C'est le serveur qui le dit**, et non une déduction : il
            // compare l'empreinte du carnet à celle du dernier rendu
            // (`isUpToDate`, T224) — la même question que celle qui décide de
            // relancer. Un serveur d'avant ce champ ne la répond pas ; rien ne
            // s'est lancé, c'est donc qu'il n'y avait rien à lancer.
            isAlreadyUpToDate = loaded.isUpToDate ?? true
        }
    }

    /// Relance après un échec.
    ///
    /// Sur un carnet déjà composé, **sans quitter l'aperçu** : on redemande la
    /// remise à jour et on la suit en fond, derrière les pages qu'on a. Sur un
    /// carnet jamais composé, le parcours entier — la composition **et** la
    /// cascade.
    public func retry() async {
        errorMessage = nil

        if stage == .preview, preview?.hasReadyRender == true {
            if let failure = await launchComposition() {
                errorMessage = failure
                return
            }
            if let loaded = try? await source(memoId) { await apply(loaded) }
            if isRecomposing { await watchRecomposition() }
            return
        }

        stage = .composing
        compositionProgress = 0
        #if DEBUG
            showsBlankPages = false
        #endif
        await run()
    }

    // MARK: - Les couvertures

    /// Relit les deux plats, quand le carnet dit qu'ils sont choisis : ce sont
    /// eux que la première et la dernière page montrent (Hugo, 06/10/2026,
    /// T223). Sans effet tant qu'ils ne le sont pas — l'invitation à les
    /// choisir se pose alors sur la page du PDF.
    ///
    /// **Sans attendre** : la page du PDF tient la place le temps de la
    /// lecture, et un échec ne coûte que ça — l'aperçu ne bloque pas sur ses
    /// couvertures.
    private func loadCovers(for loaded: BookPreview) {
        guard loaded.hasConfiguredCovers, let coversSource else { return }
        Task { [weak self, memoId] in
            guard let fresh = try? await coversSource(memoId) else { return }
            self?.covers = fresh
        }
    }

    /// Le plat que montre la feuille `index`, s'il y en a un à montrer.
    ///
    /// La première et la dernière, couvertures choisies et lues. Une seule
    /// page — le tout premier souvenir — reste la première de couverture.
    public func coverFace(at index: Int) -> CoverFace? {
        guard preview?.hasConfiguredCovers == true, covers != nil, sheetCount > 0 else { return nil }
        if index == 0 { return .front }
        if index == sheetCount - 1 { return .back }
        return nil
    }

    /// Recharge le seul PDF, sans recomposer : le carnet est là, c'est le
    /// téléchargement qui a échoué.
    public func reloadDocument() async {
        guard let url = preview?.pdfUrl else { return }
        await renderer.load(from: url)
    }

    // MARK: - Feuilleter

    /// Combien de feuilles l'aperçu montre.
    ///
    /// Le document fait foi dès qu'il est là ; avant, c'est le compteur du
    /// serveur qui tient la place, pour que l'en-tête et l'indicateur
    /// n'affichent pas « Page 1 / 0 » le temps d'un transfert.
    public var sheetCount: Int {
        if renderer.sheetCount > 0 { return renderer.sheetCount }
        let counted = preview?.pageCount ?? 0
        #if DEBUG
            if showsBlankPages, counted == 0 { return Self.blankPageCount }
        #endif
        return counted
    }

    public var canGoBack: Bool { sheetIndex > 0 }
    public var canGoForward: Bool { sheetIndex + 1 < sheetCount }

    public func goBack() {
        guard canGoBack else { return }
        sheetIndex -= 1
    }

    public func goForward() {
        guard canGoForward else { return }
        sheetIndex += 1
    }

    public func show(sheet index: Int) {
        guard index >= 0, index < sheetCount else { return }
        sheetIndex = index
    }

    public func setFullScreen(_ isOn: Bool) {
        isFullScreen = isOn
    }

    /// La feuille regardée se configure : c'est la première ou la dernière, et
    /// les couvertures n'ont pas encore été choisies. C'est ce qui pose le
    /// voile.
    ///
    /// **Le compte de feuilles, pas le PDF** (Hugo, 30/09/2026). Jusqu'ici il
    /// fallait aussi que le document soit descendu, pour ne pas voiler un
    /// aplat vide. Mais l'écran de l'app n'a pas encore de PDF — il vit sur son
    /// jeu d'essai tant que T194 n'est pas tranché —, et le garde-fou effaçait
    /// donc l'invitation **partout, tout le temps** : Hugo l'a redemandée
    /// plusieurs fois sans jamais la voir. Une page papier voilée qui mène aux
    /// couvertures vaut mieux qu'une page sans chemin.
    public var isOnConfigurableCover: Bool {
        preview?.isConfigurableCover(page: sheetIndex, in: sheetCount) ?? false
    }

    /// La feuille regardée est la première ou la dernière du carnet : celles
    /// qu'on règle depuis les couvertures.
    public var isOnCover: Bool {
        sheetCount > 0 && (sheetIndex == 0 || sheetIndex == sheetCount - 1)
    }

    /// Ce que la page regardée porte pour aller aux couvertures.
    ///
    /// **La première et la dernière page en portent toujours un** (Hugo,
    /// 30/09/2026, maquette `3545:21634`) : le voile et son invitation tant que
    /// les couvertures ne sont pas choisies, le bouton « Configurer » seul,
    /// posé sur la page, ensuite. Le 26/09, seule la première le gardait une
    /// fois les couvertures choisies — et la quatrième de couverture n'avait
    /// plus de chemin vers son écran.
    public var coverCallToAction: CoverCallToAction? {
        guard isOnCover else { return nil }
        return isOnConfigurableCover ? .invitation : .edit
    }

    // MARK: - Partager

    /// Demande le lien de prévisualisation, ou rend celui qu'on a déjà.
    ///
    /// Il n'existe pas tant qu'on ne l'a pas demandé, et c'est volontaire :
    /// c'est un lien **public**, il ne se crée pas au chargement d'un écran.
    public func prepareShareLink() async -> URL? {
        if let shareLink { return shareLink }
        if let existing = preview?.shareUrl {
            shareLink = existing
            return existing
        }

        guard let requestLink else { return nil }

        isPreparingLink = true
        defer { isPreparingLink = false }

        do {
            let link = try await requestLink(memoId)
            shareLink = link
            return link
        } catch {
            errorMessage = BookCopy.Share.linkFailed
            return nil
        }
    }

    /// Le PDF écrit dans un fichier temporaire, prêt à partir dans la feuille
    /// de partage du système.
    ///
    /// Un **fichier** et non les données brutes : c'est ce qui donne un nom au
    /// document dans WhatsApp ou Mail, et « Rome et la Dolce Vita.pdf » se
    /// reçoit mieux que « Pièce jointe ». Le nom est nettoyé de ce qu'un système
    /// de fichiers refuse.
    public func exportPdf(chapters choisis: Set<Int>? = nil) -> URL? {
        let title = preview?.title ?? "Carnet MemoBook"

        // **L'app n'invente plus de carnet** (T302, Hugo, 08/11/2026).
        //
        // Elle en composait un, d'une page, qui disait qu'il n'était pas le
        // carnet : c'était la réponse à « il y a toujours un fichier à
        // partager » (Hugo, 19/09/2026), quand toucher « Partager le fichier
        // PDF » sans document n'ouvrait rien du tout. Mais c'est ce
        // fichier-là que Hugo a reçu en croyant partager son carnet, et un
        // faux carnet est pire qu'un bouton qui n'ouvre rien.
        //
        // Le geste est fermé en amont — voir ``canShare``, qui pâlit le bouton
        // et explique —, donc on n'arrive plus ici sans document.
        guard let complet = documentToShare(title: title) else { return nil }
        // **Quelques étapes seulement** (T285) : le PDF est déjà là, on le
        // découpe sur place. Rien ne repart au serveur, et ça marche hors
        // ligne. Un découpage qui échoue rend le carnet entier — mieux vaut
        // trop envoyer que rien.
        let data = Self.extrait(complet, chapitres: choisis, preview: preview) ?? complet
        let safe =
            title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let url = URL.temporaryDirectory.appending(path: "\(safe.isEmpty ? "Carnet" : safe).pdf")

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Le document qui part. `nil` quand le PDF du serveur n'est pas chargé.
    ///
    /// ⚠️ **Le bac à sable garde son fichier d'attente.** Le jeu d'essai n'a
    /// pas de PDF — ``BookPreview/fixture`` le dit nommément —, et sans lui la
    /// feuille de partage et le choix des étapes (T285) ne se regarderaient
    /// plus du tout hors serveur. Il n'est compilé qu'en debug : un TestFlight
    /// est un build release, il n'en a pas, et personne ne peut donc recevoir
    /// ce fichier.
    private func documentToShare(title: String) -> Data? {
        if let data = renderer.documentData { return data }
        #if DEBUG
            return Self.placeholderPdf(title: title)
        #else
            return nil
        #endif
    }

    /**
     **Les pages des étapes choisies, découpées dans le PDF déjà chargé**
     (T285, Hugo, 05/11/2026 — « pouvoir choisir ce qu'on envoie »).

     `nil` quand il n'y a rien à découper : aucune sélection, ou toutes les
     étapes cochées — on partage alors le document tel quel, octet pour octet.

     Les couvertures partent **toujours** : un carnet qui commence par
     « Jour 4 » et finit sans sa quatrième n'a plus l'air d'un carnet. Elles
     ne se cochent donc pas, et le serveur ne les compte pas non plus —
     ``BookChapter/pages(inDocumentOf:inner:)`` fait la conversion.
     */
    static func extrait(_ data: Data, chapitres choisis: Set<Int>?, preview: BookPreview?) -> Data? {
        guard let choisis, let chapters = preview?.chapters, !chapters.isEmpty else { return nil }
        // Tout coché : rien à faire, et surtout pas recomposer le document.
        if choisis.count >= chapters.count { return nil }
        guard let document = PDFDocument(data: data), document.pageCount > 0 else { return nil }

        let inner = preview?.pageCount ?? document.pageCount
        var gardees = IndexSet()
        for chapitre in chapters where choisis.contains(chapitre.firstPage) {
            gardees.insert(integersIn: chapitre.pages(inDocumentOf: document.pageCount, inner: inner))
        }
        guard !gardees.isEmpty else { return nil }

        // Les couvertures encadrent toujours : ce qu'on envoie reste un carnet.
        let devant = max(0, (document.pageCount - inner + 1) / 2)
        for page in 0..<devant { gardees.insert(page) }
        for page in (devant + inner)..<document.pageCount { gardees.insert(page) }

        let extrait = PDFDocument()
        var place = 0
        for index in gardees.sorted() {
            guard let page = document.page(at: index) else { continue }
            extrait.insert(page, at: place)
            place += 1
        }
        return place > 0 ? extrait.dataRepresentation() : nil
    }

    #if DEBUG
    /// Un PDF d'une page, composé par l'app, à la place du carnet.
    ///
    /// Il **dit qu'il n'est pas le carnet** : partager un fichier vide ou une
    /// page blanche laisserait croire à un carnet raté. Une page A5 au format
    /// du carnet, le titre, et la phrase qui explique.
    ///
    /// ⚠️ **Debug seulement depuis T302** : il ne sert plus qu'au bac à sable
    /// — voir ``documentToShare(title:)``.
    private static func placeholderPdf(title: String) -> Data {
        // A5 en points PostScript : le format du carnet.
        let page = CGRect(x: 0, y: 0, width: 420, height: 595)
        let renderer = UIGraphicsPDFRenderer(bounds: page)

        return renderer.pdfData { context in
            context.beginPage()

            let margin: CGFloat = 48
            let width = page.width - margin * 2

            let heading = NSAttributedString(
                string: title,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 24, weight: .semibold),
                    .foregroundColor: UIColor(red: 0.18, green: 0.14, blue: 0.10, alpha: 1),
                ]
            )
            heading.draw(in: CGRect(x: margin, y: margin, width: width, height: 120))

            let body = NSAttributedString(
                string: BookCopy.Preview.placeholderPdfBody,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 13),
                    .foregroundColor: UIColor(red: 0.18, green: 0.14, blue: 0.10, alpha: 0.6),
                ]
            )
            body.draw(in: CGRect(x: margin, y: margin + 120, width: width, height: 200))
        }
    }
    #endif

    #if DEBUG
        /// Rejoue la composition depuis le début. Absent de l'app livrée.
        func debugReplayComposition() {
            stage = .composing
            compositionProgress = 0
            showsBlankPages = false
            Task { await run() }
        }
    #endif
}

/// `withAnimation` depuis un contexte qui n'est pas une vue.
///
/// Le modèle pilote la cascade parce que c'est lui qui décide de la fin de
/// l'attente ; il lui faut donc poser l'animation lui-même. Une fonction à part
/// plutôt qu'un appel en ligne, pour que la durée reste une `Duration` et non un
/// `Double` de secondes qui se promènerait dans le fichier.
@MainActor
private func withAnimationCompat(duration: Duration, _ changes: () -> Void) {
    let seconds = Double(duration.components.seconds)
        + Double(duration.components.attoseconds) / 1e18

    // **Linéaire**, depuis le 10/11/2026 : l'avancement n'est pas un effet, il
    // est l'**horloge** de la chorégraphie — `BookCompositionPiece` y lit la
    // seconde où l'on en est, et chaque morceau porte sa propre courbe
    // d'arrivée. Un `easeOut` global écrasait la fin de la minuterie : le texte
    // s'écrivait vite et les pièces collées tombaient ensemble.
    withAnimation(.linear(duration: seconds), changes)
}

/// Le chemin vers les couvertures, posé sur une page de l'aperçu.
public enum CoverCallToAction: Sendable, Hashable {
    /// « Définis maintenant ta 1ère et 4ème de couverture », sur le voile.
    case invitation
    /// La pastille « Configurer » seule : les couvertures sont choisies, on
    /// peut y revenir.
    case edit
}
