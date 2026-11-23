import Foundation
import MemoBookCore
import Observation

/// Ce que l'écran d'un carnet de la galerie sait faire : le charger, et dire
/// pourquoi il n'y arrive pas.
///
/// Même construction que ``GalleryModel`` : le modèle ne connaît pas l'API, il
/// reçoit **une source**. L'app y branche `api.publicBook(id:)` (voir
/// ``AppDependencies/publicBookModel(id:)``), les aperçus n'en fournissent
/// aucune et tombent sur le jeu d'essai.
///
/// **Pas de cache**, contrairement aux six écrans de ``ContentCache``, et c'est
/// délibéré : ceux-là gardent une copie de ce qui appartient au compte, et
/// s'effacent à la déconnexion. Un carnet public n'est à personne qui regarde —
/// le garder sur le disque serait garder le récit de quelqu'un d'autre sans
/// qu'il l'ait demandé, pour un écran qu'on ouvre une fois.
@MainActor
@Observable
public final class PublicBookModel {
    public private(set) var book: PublicBook?
    public private(set) var errorMessage: String?

    /// Ce que la carte montrait déjà : le titre et la photo du carnet.
    ///
    /// L'écran s'ouvre **dessus**, avant que le récit arrive — c'est ce qui lui
    /// évite d'ouvrir sur un vide puis de sauter. Vient de la carte sur
    /// laquelle on a tapé, donc jamais du réseau.
    public let preview: GalleryTrip?

    /// Le voyage que celui qui regarde peut reprendre, descendu de la galerie :
    /// c'est lui qui décide du bouton du bas, comme sur la galerie elle-même.
    public let resumableTripId: String?

    private let source: () async throws -> PublicBook

    public init(
        preview: GalleryTrip? = nil,
        resumableTripId: String? = nil,
        source: @escaping () async throws -> PublicBook = { .fixture }
    ) {
        self.preview = preview
        self.resumableTripId = resumableTripId
        self.source = source
    }

    /// `true` tant qu'on n'a rien à lire. L'écran pose alors des barres
    /// d'attente sous l'en-tête de la carte, qu'il a déjà.
    public var isLoading: Bool { book == nil && errorMessage == nil }

    /// Le titre à afficher **tout de suite** : celui du carnet quand il est
    /// arrivé, celui de la carte en attendant.
    public var title: String { book?.title ?? preview?.title ?? "" }

    /// La phrase sous le titre, même règle que le titre.
    public var summary: String? { book?.summary ?? preview?.subtitle }

    /// La photo de couverture, même règle encore — et c'est elle qui compte le
    /// plus : elle est déjà en cache d'URL, puisque la carte l'affichait.
    public var coverPhotoUrl: URL? { book?.coverPhotoUrl ?? preview?.coverPhotoUrl }

    public func load() async {
        do {
            book = try await source()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
