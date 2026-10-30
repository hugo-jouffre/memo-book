import SwiftUI
import UIKit

/// **Une photo du réseau qui ne se redessine pas à chaque apparition.**
///
/// `AsyncImage` repart de zéro chaque fois que la vue est reconstruite : il
/// pose son remplacement, relance sa requête, puis remplace l'image. Le
/// fichier, lui, est bien en cache (`URLCache`, 256 Mo, posé au lancement par
/// `MemoBookApp.init()`) — mais l'écran clignote quand même : la couverture
/// d'un voyage repassait par son motif à chaque défilement de l'accueil et à
/// chaque retour sur l'écran (Hugo, 28/10/2026 — « la photo du voyage se
/// recharge à chaque fois alors que ça devrait garder la dernière en
/// locale »).
///
/// Ce composant garde donc les images **décodées** en mémoire, par URL
/// (``RemoteImageCache``) : une photo déjà vue est là au premier dessin, sans
/// remplacement ni fondu. Une inconnue se charge comme avant, et son arrivée
/// se fond.
///
/// Elle est décodée **réduite et hors de l'acteur principal**
/// (``ChatImage/decode(_:maximumPixelSize:)``, le même chemin que les photos
/// du fil) : une photo d'iPhone pèse des dizaines de mégaoctets une fois
/// dépliée, et une couverture s'affiche sur 400 pt.
///
/// Ce qu'il ne fait **pas** : garder les images d'un lancement à l'autre.
/// C'est le travail d'`URLCache`, qui le fait déjà sur le disque ; en
/// redoubler un ici reviendrait à tenir deux caches d'accord.
///
/// ⚠️ **Pas pour les photos du fil** : celles-ci passent par la session
/// (`/v1/entries/:id/media` la refuse sans en-tête) et par
/// ``ChatModel/loadImage(_:)``. Ce composant-ci sert les photos **publiques** :
/// la couverture d'un voyage, l'en-tête de la conversation.
struct RemoteImage<Placeholder: View>: View {
    private let url: URL?
    private let placeholder: () -> Placeholder

    /// L'image déjà décodée, s'il y en a une. Posée **avant le premier
    /// dessin** quand le cache la connaît : c'est ce qui supprime le
    /// clignotement.
    @State private var image: UIImage?

    init(url: URL?, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder
        // `State(initialValue:)` et non `.task` : une photo connue doit être
        // là à la première image, pas à la seconde.
        _image = State(initialValue: url.flatMap { RemoteImageCache.shared.image(for: $0) })
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        // Le fondu ne joue que pour une photo qui arrive vraiment : celle qui
        // vient du cache est déjà là quand la vue se dessine.
        .animation(.easeOut(duration: 0.2), value: image == nil)
        .task(id: url) { await load(url) }
    }

    /// Charge une fois. Un échec n'est pas retenu : la vue garde son
    /// remplacement et redemandera en réapparaissant — même règle que les
    /// vignettes du fil.
    private func load(_ url: URL?) async {
        guard let url, image == nil else { return }
        if let cached = RemoteImageCache.shared.image(for: url) {
            image = cached
            return
        }

        // `URLSession.shared` et non le client d'API : c'est lui qui porte
        // `URLCache`, et ces photos-là se servent sans session.
        let data = try? await URLSession.shared.data(from: url).0
        guard let decoded = await ChatImage.decode(data) else { return }

        RemoteImageCache.shared.store(decoded, for: url)
        image = decoded
    }
}

extension RemoteImage where Placeholder == Color {
    /// Sans remplacement dessiné : un aplat transparent le temps du chargement.
    init(url: URL?) {
        self.init(url: url) { Color.clear }
    }
}

/// Les photos publiques déjà décodées, par URL — voir ``RemoteImage``.
///
/// `NSCache` et non un dictionnaire : il se vide tout seul sous pression
/// mémoire, ce qu'une couverture doit accepter sans faire tomber l'app, et il
/// est sûr entre fils d'exécution — d'où le `@unchecked Sendable`, qui ne
/// promet rien de plus que ce que `NSCache` garantit déjà. Il se lit donc
/// depuis l'initialiseur d'une vue, avant tout dessin.
///
/// La limite est en **nombre d'images** plutôt qu'en octets : réduites à
/// 1 024 px, vingt suffisent à couvrir un accueil entier et le fil qu'on en
/// ouvre.
final class RemoteImageCache: @unchecked Sendable {
    static let shared = RemoteImageCache()

    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.countLimit = 20
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }

    /// À appeler quand le compte change : les photos d'un voyage ne restent
    /// pas en mémoire devant la personne suivante — voir
    /// ``AppDependencies/forgetAccountContent()``.
    func clear() {
        cache.removeAllObjects()
    }
}
