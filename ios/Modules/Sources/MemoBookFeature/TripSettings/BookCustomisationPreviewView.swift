import MemoBookCore
import MemoBookDesign
import Observation
import SwiftUI
import UIKit

/// L'aperçu de personnalisation, en tête de l'écran « Personnalisations » : la
/// page que donneraient les réglages qu'on est en train de toucher.
///
/// **Toujours lui, même quand un carnet a déjà été composé** (Hugo,
/// 02/10/2026) : c'est lui qui répond aux réglages, les vraies pages ne
/// changeraient qu'à la prochaine composition. Elles restent dans l'aperçu du
/// carnet.
///
/// Trois règles tiennent la tête immobile :
///
/// - **La place est réservée.** Le bloc a la taille des deux pages d'avant
///   (``BookPagesPeek/headerSize``), qu'il y ait une image ou non : rien ne
///   saute sous lui, ni au chargement, ni à l'échec.
/// - **Le papier nu tant que rien n'est arrivé**, puis un fondu. À l'échec, le
///   papier reste, sans message : l'image est redemandée au réglage suivant,
///   ou à la prochaine ouverture (Hugo, 02/10/2026). Le repli, lui, n'est pas
///   un échec : c'est une image comme les autres.
/// - **L'image d'avant reste tant que la suivante n'est pas prête**, et un
///   curseur qu'on fait glisser ne la change qu'une fois posé — voir
///   ``BookCustomisationPreviewLoader``.
///
/// Ce que l'image montre ne déclenche rien : les douze « composition trop
/// chargée » sont des aperçus comme les autres, le message vit dans l'image.
struct BookCustomisationPreviewView: View {
    /// L'image à montrer, ou `nil` tant que les réglages ne sont pas lus.
    let url: URL?

    @State private var loader = BookCustomisationPreviewLoader()

    /// Le bloc des deux pages d'avant, pour que la tête garde sa hauteur.
    private let size = BookPagesPeek.headerSize

    var body: some View {
        ZStack {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    // Une identité par image : l'ancienne s'efface pendant que
                    // la nouvelle paraît, sans passer par le vide.
                    .id(loader.shownURL)
                    .transition(.opacity)
            } else {
                BookPagesPeek(pdfUrl: nil, size: size)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(.easeInOut(duration: 0.25), value: loader.shownURL)
        // Décor, comme les deux pages qu'il remplace : l'écran dessous dit ce
        // qu'il règle, et VoiceOver n'a pas à s'arrêter sur une image.
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        // L'adresse ne dépend que des cinq réglages qui pilotent l'image : le
        // nombre de pages, le quiz, les zones libres et le mot fléché ne la
        // changent pas, et la tâche ne repart pas.
        .task(id: url) { await loader.show(url) }
    }
}

/// Ce que la tête montre, et quand elle en change.
///
/// À part de la vue pour se tester sans écran : la vue ne fait que dessiner
/// ``image``.
@MainActor
@Observable
final class BookCustomisationPreviewLoader {
    /// L'image à l'écran. `nil` tant qu'aucune n'est arrivée : le papier nu.
    private(set) var image: UIImage?
    /// L'adresse de ``image``.
    private(set) var shownURL: URL?

    private let fetch: (URL) async throws -> UIImage
    private let settle: Duration

    /// Une première adresse a été demandée. Seule celle-là part sans attendre :
    /// la regarder plutôt que ``image`` évite qu'un glissé sur le papier nu —
    /// une ouverture lente, ou ratée — ne charge chaque cran.
    private var hasRequested = false

    /// Les dernières images décodées, pour qu'un aller-retour entre deux
    /// réglages ne retélécharge rien. Huit, pas deux cents : une image décodée
    /// pèse trois mégaoctets.
    private let decoded: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 8
        return cache
    }()

    /// - Parameters:
    ///   - settle: combien de temps un réglage doit tenir avant que l'image le
    ///     suive. Un curseur qu'on fait glisser change de valeur à chaque cran ;
    ///     sans cette attente, la tête changerait d'image à chacun.
    ///   - fetch: télécharge et décode une image. Celle de l'app passe par le
    ///     cache HTTP du système : les images publiées sont immuables, gardées
    ///     un an.
    init(
        settle: Duration = .milliseconds(300),
        fetch: @escaping (URL) async throws -> UIImage = BookCustomisationPreviewLoader.download
    ) {
        self.settle = settle
        self.fetch = fetch
    }

    /// Montre l'image de cette adresse.
    ///
    /// Appelée par `.task(id:)` : une nouvelle adresse **annule** l'appel en
    /// cours, et c'est ce qui fait l'attente du curseur — tant qu'il bouge,
    /// chaque appel est annulé avant la fin de son attente, et seul le dernier
    /// arrive au bout.
    func show(_ url: URL?) async {
        guard let url, url != shownURL else { return }

        // La première image arrive tout de suite : à l'ouverture, il n'y a pas
        // de geste à attendre. Les suivantes attendent qu'il se pose.
        let isFirst = !hasRequested
        hasRequested = true
        if !isFirst {
            do { try await Task.sleep(for: settle) } catch { return }
        }
        // L'attente a pu finir à l'instant où un autre réglage l'annulait :
        // l'image en cache serait alors celle d'un réglage déjà quitté.
        guard !Task.isCancelled else { return }

        if let cached = decoded.object(forKey: url as NSURL) {
            present(cached, from: url)
            return
        }
        // L'échec ne change rien à l'écran : l'image d'avant, ou le papier nu.
        guard let loaded = try? await fetch(url) else { return }
        decoded.setObject(loaded, forKey: url as NSURL)
        // Arrivée trop tard, pendant qu'un autre réglage était déjà demandé :
        // gardée pour plus tard, pas montrée.
        guard !Task.isCancelled else { return }
        present(loaded, from: url)
    }

    private func present(_ image: UIImage, from url: URL) {
        self.image = image
        shownURL = url
    }

    /// Le téléchargement de l'app : une réponse 200, des octets qui sont une
    /// image, décodés hors de l'acteur principal.
    nonisolated static func download(_ url: URL) async throws -> UIImage {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let image = UIImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }
        return await image.byPreparingForDisplay() ?? image
    }
}
