import Foundation
import MemoBookCore
import Observation
import SwiftUI

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
/// L'app leur branche `POST /v1/memos/:id/renders` et `GET /v1/renders/:id` ;
/// les aperçus n'en fournissent aucune et travaillent en mémoire.
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

    /// Le PDF et ses pages rendues.
    ///
    /// `internal` : le rendu est un détail de ces écrans-là, pas une API du
    /// module. Ce qui sort d'ici, ce sont des états et des images, pas un
    /// document PDF.
    let renderer = BookPageRenderer()

    /// La feuille regardée, à partir de 0.
    public private(set) var sheetIndex = 0

    public private(set) var isFullScreen = false

    /// Le lien de prévisualisation, une fois demandé.
    public private(set) var shareLink: URL?
    public private(set) var isPreparingLink = false

    private let memoId: String
    private let source: (String) async throws -> BookPreview
    private let requestLink: ((String) async throws -> URL)?

    /// Combien de temps la cascade dure.
    ///
    /// **C'est aussi le plancher de l'attente** : même si le serveur répond en
    /// 300 ms, l'écran tient ces secondes-là. Ce n'est pas une lenteur ajoutée
    /// pour faire joli — une page qui se monte et disparaît avant d'être finie
    /// donne l'impression d'un bogue, et l'aperçu qui suit arrive alors sans
    /// qu'on ait compris ce qui venait de se passer.
    private static let compositionDuration: Duration = .seconds(2.6)

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

    public init(
        memoId: String,
        source: @escaping (String) async throws -> BookPreview = { _ in .fixture },
        requestLink: ((String) async throws -> URL)? = nil
    ) {
        self.memoId = memoId
        self.source = source
        self.requestLink = requestLink
    }

    // MARK: - Composer, puis montrer

    /// Le parcours entier : monter la page, suivre la composition, ouvrir le
    /// PDF, et passer à l'aperçu quand les deux sont prêts.
    ///
    /// Les deux attentes sont menées **en parallèle** et non l'une après
    /// l'autre : la cascade et la composition du serveur n'ont aucune raison de
    /// s'attendre, et c'est la plus longue des deux qui décide.
    public func run() async {
        guard stage == .composing else { return }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in await self?.playComposition() }
            group.addTask { [weak self] in await self?.followComposition() }
        }

        // Un échec de composition laisse l'écran où il est : le message dit ce
        // qui s'est passé, et le bouton de reprise est dans la vue. Passer à un
        // aperçu vide serait pire que d'attendre.
        guard errorMessage == nil else { return }
        stage = .preview
    }

    /// Fait monter la page, et n'en sort qu'une fois la cascade finie.
    private func playComposition() async {
        compositionProgress = 0

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
    private func followComposition() async {
        while !Task.isCancelled {
            do {
                let loaded = try await source(memoId)
                preview = loaded
                errorMessage = nil

                switch loaded.status {
                case .ready:
                    if let url = loaded.pdfUrl {
                        await renderer.load(from: url)
                    }
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

    /// Relance le parcours après un échec — la composition **et** la cascade.
    public func retry() async {
        errorMessage = nil
        stage = .composing
        compositionProgress = 0
        await run()
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

    /// La feuille regardée se configure : c'est la première ou la dernière, les
    /// couvertures n'ont pas encore été choisies, **et il y a une page dessous**.
    ///
    /// La dernière condition n'est pas un détail : sans elle, l'invitation se
    /// posait sur un aplat vide tant que le PDF n'était pas descendu, et
    /// proposait de configurer une couverture qu'on ne voyait pas.
    public var isOnConfigurableCover: Bool {
        guard renderer.sheetCount > 0 else { return false }
        return preview?.isConfigurableCover(page: sheetIndex, in: sheetCount) ?? false
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
        guard let data = renderer.documentData else { return nil }

        let title = preview?.title ?? "Carnet MemoBook"
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
