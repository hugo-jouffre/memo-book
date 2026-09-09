import Foundation
import MemoBookCore
import Observation

/// Ce que la galerie des carnets sait faire : charger son contenu, le filtrer
/// par catégorie, et le ranger en colonnes.
///
/// Même construction que ``HomeModel`` et ``TripHomeModel`` : le modèle ne
/// connaît pas l'API, il reçoit **une source**. L'app y branche `api.gallery()`
/// (voir ``AppDependencies/galleryModel()``), les aperçus n'en fournissent
/// aucune et tombent sur le jeu d'essai.
///
/// **Les colonnes sont calculées ici, pas dans la vue.** Une mosaïque se répartit
/// en mesurant ce qui est déjà posé ; le faire dans un `body`, c'est le refaire
/// à chaque image d'animation — et la grille se réorganiserait sous les doigts
/// pendant qu'on fait défiler.
@MainActor
@Observable
public final class GalleryModel {
    public private(set) var gallery: Gallery?
    public private(set) var errorMessage: String?

    /// La catégorie cochée. `nil` veut dire « Tout » : c'est l'état d'ouverture
    /// de l'écran.
    public private(set) var selectedCategoryId: String?

    /// Les carnets déjà répartis en colonnes, prêts à être empilés tels quels.
    public private(set) var columns: [[GalleryTrip]] = []

    /// Le nombre de colonnes de la mosaïque.
    ///
    /// Il **vient de la vue** et non des données : il dépend de la taille de
    /// texte de l'utilisateur, que seul l'environnement SwiftUI connaît. C'est
    /// la seule chose que l'écran dise à son modèle, et il la dit une fois, à
    /// l'ouverture et quand le réglage change — pas à chaque passage dans
    /// `body`, où le rangement se referait à chaque image d'animation.
    private var columnCount = GalleryMetrics.columnCount

    private let source: () async throws -> Gallery

    public init(source: @escaping () async throws -> Gallery = { .fixture }) {
        self.source = source
    }

    /// `true` tant qu'on n'a rien à montrer. L'écran pose alors des vignettes
    /// vides plutôt qu'un trou : la grille garde sa forme, seules les images et
    /// les mots arrivent après.
    public var isLoading: Bool { gallery == nil && errorMessage == nil }

    public var categories: [GalleryCategory] { gallery?.categories ?? [] }

    /// Le voyage qu'on propose de reprendre. C'est lui qui décide du bouton du
    /// bas : « Continuer mon voyage » s'il existe, « Créer mon voyage » sinon.
    public var resumableTripId: String? { gallery?.resumableTripId }

    /// La galerie est vide — soit qu'aucun carnet public n'existe encore, soit
    /// que la catégorie cochée n'en range aucun. Les deux ne disent pas la même
    /// chose, et l'écran ne les raconte pas pareil.
    public var isEmpty: Bool { columns.allSatisfy(\.isEmpty) }

    public func load() async {
        do {
            let loaded = try await source()
            gallery = loaded
            errorMessage = nil

            // Une catégorie qui a disparu du serveur ne doit pas laisser la
            // grille filtrée sur rien après un rechargement.
            if let selectedCategoryId,
                !loaded.categories.contains(where: { $0.id == selectedCategoryId })
            {
                self.selectedCategoryId = nil
            }

            layOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Coche une catégorie, ou revient à « Tout » avec `nil`.
    public func select(_ categoryId: String?) {
        guard categoryId != selectedCategoryId else { return }
        selectedCategoryId = categoryId
        layOut()
    }

    /// Dit au modèle sur combien de colonnes la vue peut ranger la mosaïque.
    public func use(columnCount: Int) {
        guard columnCount != self.columnCount else { return }
        self.columnCount = columnCount
        layOut()
    }

    /// Répartit les carnets visibles en deux colonnes.
    ///
    /// Le rangement se fait **une fois par filtre**, pas à chaque passage dans
    /// `body`.
    private func layOut() {
        let visible = (gallery?.trips ?? []).filter { $0.belongs(to: selectedCategoryId) }
        columns = Self.balanced(visible, columns: columnCount)
    }

    /// La mosaïque : chaque carnet va dans la colonne **la plus courte**.
    ///
    /// On ne compare pas des hauteurs en points mais des hauteurs *relatives* :
    /// les colonnes ont la même largeur, donc une vignette de rapport 0,8 est
    /// exactement 1/0,8 fois plus haute que large, quelle que soit la largeur
    /// finale. Le rangement ne dépend donc pas de l'écran, et ne se refait pas
    /// quand on tourne l'appareil.
    ///
    /// En alternant simplement gauche-droite, deux vignettes hautes de suite
    /// dans la même colonne creusaient un vide de cent points en bas de
    /// l'autre.
    static func balanced(_ trips: [GalleryTrip], columns count: Int) -> [[GalleryTrip]] {
        guard count > 0 else { return [] }

        var buckets = Array(repeating: [GalleryTrip](), count: count)
        var heights = Array(repeating: 0.0, count: count)

        for trip in trips {
            // À égalité, la colonne la plus à gauche — c'est là que se pose la
            // première vignette d'une grille.
            var shortest = 0
            for index in heights.indices where heights[index] < heights[shortest] {
                shortest = index
            }

            buckets[shortest].append(trip)
            heights[shortest] += 1 / GalleryMetrics.aspectRatio(for: trip.id)
        }

        return buckets
    }
}
