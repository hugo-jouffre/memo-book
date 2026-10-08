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

    /// Une composition est suivie en ce moment. Garde ``run()`` d'un second
    /// départ — la tâche de l'écran et celle d'un retour sur l'écran.
    private var isRunning = false

    /// Combien de temps la cascade dure.
    ///
    /// **C'est aussi le plancher de l'attente** : même si le serveur répond en
    /// 300 ms, l'écran tient ces secondes-là. Ce n'est pas une lenteur ajoutée
    /// pour faire joli — une page qui se monte et disparaît avant d'être finie
    /// donne l'impression d'un bogue, et l'aperçu qui suit arrive alors sans
    /// qu'on ait compris ce qui venait de se passer.
    ///
    /// **4,2 s et non plus 2,6** (Hugo, 08/10/2026) : la cascade était courte
    /// pour l'attente qui suit, et le rythme est désormais celui de chaque
    /// page de la boucle — voir ``BookCompositionLoop``.
    private static let compositionDuration: Duration = .seconds(BookCompositionLoop.assembly)

    /// Le pas entre deux relevés de l'avancement. 1/60 s : la cascade se joue
    /// dans une animation SwiftUI, ce rythme ne sert qu'à savoir **quand elle
    /// est finie**.
    private static let progressTick: Duration = .milliseconds(100)

    /// L'intervalle entre deux questions au serveur pendant la composition.
    ///
    /// Deux secondes : une composition dure des dizaines de secondes, et
    /// demander plus souvent ne ferait que payer des allers-retours pour la
    /// même réponse.
    private static let pollInterval: Duration = .seconds(2)

    /// L'intervalle entre deux sondages pendant une régénération en fond.
    ///
    /// Plus large que ``pollInterval`` : une régénération refait tout le
    /// travail (LLM puis rendu), elle prend donc plus que quelques dizaines de
    /// secondes — sonder aussi souvent que la première composition ne ferait
    /// que payer des allers-retours pour la même réponse.
    private static let recompositionPollInterval: Duration = .seconds(4)

    /// Combien de sondages **sans changement** avant de laisser tomber —
    /// quatre minutes, à quatre secondes l'un. Même raisonnement que
    /// `StatisticsModel.maxUnchangedPolls` : un rendu peut rester bloqué pour
    /// de mauvaises raisons, et l'écran ne doit pas sonder indéfiniment un
    /// aperçu resté ouvert. Revenir sur l'écran relance un sondage.
    ///
    /// Quatre et non deux : la mise en page attend jusqu'à trois minutes les
    /// souvenirs encore en rédaction, sans que rien ne bouge entre-temps.
    private static let maxUnchangedRecompositionPolls = 60

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
            errorMessage = launchFailure ?? error.localizedDescription
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
            return
        }

        if case .failed(let message) = first.status {
            await apply(first)
            errorMessage = message
            return
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in await self?.playComposition() }
            group.addTask { [weak self] in await self?.followComposition(firstLoad: first) }
        }

        // Un écran quitté pendant la composition ne passe pas à l'aperçu : son
        // retour reprendra le suivi, sans rejouer la cascade.
        guard !Task.isCancelled else { return }

        // Un échec de composition laisse l'écran où il est : le message dit ce
        // qui s'est passé, et le bouton de reprise est dans la vue. Passer à un
        // aperçu vide serait pire que d'attendre.
        guard errorMessage == nil else { return }
        stage = .preview
    }

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
        withAnimationCompat(duration: Self.compositionDuration) { self.compositionProgress = 1 }

        let started = ContinuousClock.now
        while ContinuousClock.now - started < Self.compositionDuration {
            if Task.isCancelled { return }
            try? await Task.sleep(for: Self.progressTick)
        }
    }

    /// Interroge le serveur jusqu'à ce que le carnet soit composé, puis ouvre
    /// son PDF.
    ///
    /// - Parameter firstLoad: la réponse déjà en main, pour ne pas la
    ///   redemander — ``run()`` l'a lue pour décider s'il y avait une
    ///   composition à suivre.
    private func followComposition(firstLoad: BookPreview? = nil) async {
        var next = firstLoad

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
                    return
                case .failed(let message):
                    errorMessage = message
                    return
                case .composing:
                    try? await Task.sleep(for: Self.pollInterval)
                }
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
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

        switch loaded.status {
        case .ready, .failed:
            isRecomposing = false
        case .composing:
            isRecomposing = true
        }

        // Le PDF se recharge quand **un autre** rendu a abouti, ou qu'aucun
        // document n'est ouvert. Un sondage qui confirme le même rendu ne
        // retélécharge rien.
        if let url = loaded.pdfUrl,
            renderer.sheetCount == 0 || ShownBook(loaded).document != previous.map(ShownBook.init)?.document
        {
            await renderer.load(from: url)
        }
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
        while !Task.isCancelled, isRecomposing, unchanged < Self.maxUnchangedRecompositionPolls {
            try? await Task.sleep(for: Self.recompositionPollInterval)
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
        renderer.sheetCount > 0 ? renderer.sheetCount : (preview?.pageCount ?? 0)
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
    public func exportPdf() -> URL? {
        let title = preview?.title ?? "Carnet MemoBook"

        // **Il y a toujours un fichier à partager** (Hugo, 19/09/2026). Quand
        // le PDF du serveur n'est pas chargé — aperçu du jeu d'essai, réseau
        // absent, carnet pas encore composé —, `documentData` est nul et le
        // bouton ne faisait rien du tout : on touchait « Partager le fichier
        // PDF » et la feuille du système n'arrivait jamais. On en compose donc
        // un, d'une page, qui dit ce qu'il est.
        let data = renderer.documentData ?? Self.placeholderPdf(title: title)
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

    /// Un PDF d'une page, composé par l'app, à la place du carnet.
    ///
    /// Il **dit qu'il n'est pas le carnet** : partager un fichier vide ou une
    /// page blanche laisserait croire à un carnet raté. Une page A5 au format
    /// du carnet, le titre, et la phrase qui explique.
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

    #if DEBUG
        /// Rejoue la composition depuis le début. Absent de l'app livrée.
        func debugReplayComposition() {
            stage = .composing
            compositionProgress = 0
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

    // `easeOut` et non un ressort : les morceaux doivent **se poser**, et un
    // ressort les ferait rebondir tous ensemble à la fin de la cascade.
    withAnimation(.easeOut(duration: seconds), changes)
}

/// Le chemin vers les couvertures, posé sur une page de l'aperçu.
public enum CoverCallToAction: Sendable, Hashable {
    /// « Définis maintenant ta 1ère et 4ème de couverture », sur le voile.
    case invitation
    /// La pastille « Configurer » seule : les couvertures sont choisies, on
    /// peut y revenir.
    case edit
}
