import Foundation
import MemoBookDesign
import Observation
import PDFKit
import SwiftUI

/// Le PDF du carnet, et ses pages rendues à la demande.
///
/// **L'app ne redessine pas le carnet, elle affiche le PDF.** C'est le seul
/// moyen d'être sûr que l'aperçu montre ce qui sortira de l'imprimante, et
/// c'est aussi le plus rapide : rendre une page A5 à 250 pt de large coûte
/// quelques millisecondes à PDFKit, là où rejouer la mise en page en SwiftUI
/// demanderait de réimplémenter le template — et de le maintenir en double.
///
/// Trois choses tiennent la fluidité de l'écran :
///
/// 1. **Une page n'est rendue qu'une fois.** Les images vivent dans un
///    ``NSCache``, qui les rend au système quand la mémoire manque plutôt que
///    de faire tuer l'app.
/// 2. **La page voisine est préparée d'avance.** Tourner la page ne déclenche
///    donc aucun rendu : il a eu lieu pendant qu'on lisait la précédente.
/// 3. **Le document n'est pas mis en cache sur le disque.** Le lien est signé
///    et de courte durée ; le garder ne servirait qu'à afficher un carnet
///    périmé.
@MainActor
@Observable
final class BookPageRenderer {
    /// Le document ouvert. `nil` avant le premier chargement, et après un échec.
    private var document: PDFDocument?

    /// Ce qui a été rendu. La clé porte la largeur : la même page en vignette et
    /// en plein écran sont deux images, et la seconde ne doit pas remplacer la
    /// première dans la bande de miniatures.
    ///
    /// `NSCache` et non un dictionnaire : c'est lui qui sait vider quand la
    /// mémoire se tend. Un carnet de soixante pages en plein écran sur un
    /// iPhone SE, sinon, finit par se faire tuer.
    private let cache = NSCache<NSString, UIImage>()

    /// Combien de feuilles le PDF contient.
    ///
    /// Distinct de ``BookPreview/pageCount``, qui vient du serveur : celui-ci
    /// est la vérité du document, et c'est lui que le compteur du plein écran
    /// affiche (« 1 sur 24 »).
    private(set) var sheetCount = 0

    /// Le chargement a échoué. Le carnet existe, c'est le téléchargement qui
    /// n'a pas abouti — d'où un message qui propose de réessayer, pas de
    /// recomposer.
    private(set) var didFail = false

    private(set) var isLoading = false

    /// Le rapport largeur / hauteur de la première feuille.
    ///
    /// Il vient du **document** et non d'une constante : le template est en A5
    /// aujourd'hui, il peut changer, et une page rendue dans le mauvais rapport
    /// se voit immédiatement. 1/√2 tant que rien n'est chargé — c'est l'A5, le
    /// format actuel du carnet.
    private(set) var aspectRatio: CGFloat = 1 / 1.414

    init() {
        // Les images de pages sont grosses et peu nombreuses : une limite en
        // nombre suffit, et elle évite de garder tout un carnet en mémoire.
        cache.countLimit = 24
    }

    /// Ouvre le PDF. Rejouable : réessayer après un échec passe par ici.
    func load(from url: URL) async {
        guard !isLoading else { return }
        isLoading = true
        didFail = false
        defer { isLoading = false }

        do {
            // Le document est téléchargé en entier avant d'être ouvert.
            // `PDFDocument(url:)` sait lire un lien distant, mais il le fait de
            // façon synchrone et bloquerait l'écran le temps du transfert.
            let (data, response) = try await URLSession.shared.data(from: url)

            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                didFail = true
                return
            }

            guard let opened = PDFDocument(data: data) else {
                didFail = true
                return
            }

            document = opened
            sheetCount = opened.pageCount
            cache.removeAllObjects()

            if let first = opened.page(at: 0) {
                let box = first.bounds(for: .cropBox)
                if box.height > 0 { aspectRatio = box.width / box.height }
            }
        } catch {
            didFail = true
        }
    }

    /// L'image d'une feuille, rendue si besoin.
    ///
    /// Synchrone, et c'est voulu : appelée depuis le corps d'une vue, elle doit
    /// rendre quelque chose tout de suite. Le coût réel est celui du cache dans
    /// la quasi-totalité des cas — voir ``prepare(around:width:)``, qui a
    /// déjà fait le travail.
    func image(sheet index: Int, width: CGFloat) -> UIImage? {
        guard let document, index >= 0, index < document.pageCount, width > 0 else { return nil }

        // La largeur est arrondie au point : sans ça, deux rendus de la même
        // page à 251,7 et 251,9 pt seraient deux entrées de cache, et le second
        // recalculerait pour rien.
        let key = "\(index)@\(Int(width.rounded()))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard let page = document.page(at: index) else { return nil }

        let box = page.bounds(for: .cropBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let size = CGSize(width: width, height: width * box.height / box.width)

        // `thumbnail(of:for:)` et non un rendu à la main : c'est le chemin
        // optimisé de PDFKit, et il respecte la boîte de rognage du document.
        let rendered = page.thumbnail(of: size, for: .cropBox)
        cache.setObject(rendered, forKey: key)
        return rendered
    }

    /// Prépare la feuille demandée et ses voisines immédiates.
    ///
    /// C'est ce qui fait que tourner la page ne coûte rien : le rendu a eu lieu
    /// pendant qu'on lisait la page d'avant. Trois feuilles et pas plus — au
    /// delà, on rendrait un carnet entier pour un lecteur qui va s'arrêter à la
    /// troisième page.
    func prepare(around index: Int, width: CGFloat) {
        for offset in [0, 1, -1] {
            _ = image(sheet: index + offset, width: width)
        }
    }

    /// Le PDF, tel quel, pour le partager.
    ///
    /// Les données et non l'URL : le lien du serveur est signé et expire, alors
    /// qu'un fichier écrit sur le disque de l'app se partage à n'importe quelle
    /// autre app. `nil` quand rien n'est chargé.
    var documentData: Data? { document?.dataRepresentation() }
}

/// Une feuille du carnet, rendue depuis le PDF.
///
/// Elle mesure d'abord, rend ensuite : la largeur de rendu est celle que la vue
/// occupe vraiment, à l'échelle de l'écran. Une page rendue à 252 pt puis
/// étirée à 390 serait floue, et une page rendue à 1170 px pour une vignette de
/// 42 pt serait du gâchis.
struct BookSheetImage: View {
    let renderer: BookPageRenderer
    let index: Int

    /// Le repli affiché tant que le document n'est pas là : le papier du
    /// carnet, vide. **Pas un gris système** — ce serait un champ désactivé.
    var showsPlaceholder = true

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * displayScale

            if let image = renderer.image(sheet: index, width: width) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if showsPlaceholder {
                MemoBookColor.paper
            }
        }
        .accessibilityHidden(true)
    }
}
