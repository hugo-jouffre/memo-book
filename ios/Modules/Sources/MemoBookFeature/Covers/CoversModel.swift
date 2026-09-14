import Foundation
import MemoBookCore
import Observation

/// Ce que le parcours des couvertures sait faire : lire les deux plats, et
/// enregistrer chaque geste.
///
/// Même construction que ``BookCustomisationModel`` : le modèle ne connaît pas
/// l'API, il reçoit deux fonctions. Les aperçus n'en fournissent aucune et
/// travaillent en mémoire.
///
/// **Un modèle pour les quatre écrans**, et non un par écran : on passe du choix
/// au style puis à la photo puis aux textes sans jamais quitter les mêmes deux
/// plats, et l'onglet « 1re / 4e » suit d'un écran à l'autre. Quatre modèles
/// auraient demandé de recharger à chaque pas, et de se retransmettre l'onglet.
@MainActor
@Observable
public final class CoversModel {
    public private(set) var covers: BookCovers?
    public private(set) var errorMessage: String?

    /// Le plat qu'on regarde. **Partagé par les quatre écrans** : passer de la
    /// quatrième de couverture au choix de sa photo ne doit pas ramener à la
    /// première.
    public var face: CoverFace = .front

    /// Le voyage dont on règle les couvertures. Lisible parce que ``RootView``
    /// tient ce modèle pour les quatre écrans et doit savoir s'il parle encore
    /// du bon voyage.
    public private(set) var tripId: String

    private let source: (String) async throws -> BookCovers
    private let persist: ((String, BookCoverEdit) async throws -> BookCovers)?

    private var pendingSave: Task<Void, Never>?

    public init(
        tripId: String,
        source: @escaping (String) async throws -> BookCovers = { _ in .fixture },
        persist: ((String, BookCoverEdit) async throws -> BookCovers)? = nil
    ) {
        self.tripId = tripId
        self.source = source
        self.persist = persist
    }

    public var isLoading: Bool { covers == nil && errorMessage == nil }

    /// Lit les deux plats, **une fois pour le parcours entier**.
    ///
    /// Les quatre écrans l'appellent à l'apparition, parce qu'aucun ne peut
    /// supposer qu'il vient après un autre. Mais il n'y a qu'un modèle pour les
    /// quatre : relire à chaque pas remplacerait le plat qu'on est en train de
    /// composer par celui du serveur — pousser le carrousel des photos depuis
    /// celui des styles effaçait le style qu'on venait d'y choisir sans
    /// valider.
    public func load() async {
        guard covers == nil else { return }
        await reload()
    }

    /// Relit depuis la source, quoi qu'on ait déjà. C'est ce qu'appelle le
    /// « Réessayer » d'un bandeau d'erreur, et ce que fait un enregistrement
    /// raté pour revenir à ce que le serveur sait.
    public func reload() async {
        do {
            covers = try await source(tripId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Ce qu'on regarde

    /// Le plat courant.
    public var cover: BookCover? { covers?[face] }

    /// Les styles proposés pour le plat courant.
    public var styles: [CoverStyle] { covers?.styles(for: face) ?? [] }

    public func style(of cover: BookCover) -> CoverStyle? { covers?.style(id: cover.styleId) }

    public func photo(of cover: BookCover) -> CoverPhoto? { covers?.photo(id: cover.photoId) }

    // MARK: - Ce qu'on change

    /// Le style se pose **sans partir** : on le regarde d'abord, on valide
    /// ensuite. C'est le bouton « Valider » de la maquette qui envoie, et c'est
    /// la seule différence avec les lignes de réglage de l'app — ici le choix
    /// est visuel, et on veut pouvoir faire défiler sept plats sans écrire sept
    /// fois au serveur.
    public func preview(style: CoverStyle) {
        guard var covers else { return }
        covers[face].styleId = style.id
        self.covers = covers
    }

    public func preview(photo: CoverPhoto?) {
        guard var covers else { return }
        covers[face].photoId = photo?.id
        self.covers = covers
    }

    /// Range une photo importée à côté de celles du voyage.
    ///
    /// **Juste avant la case d'import**, et non en fin de liste : la case est
    /// toujours la dernière du carrousel, et une photo posée après elle serait
    /// hors de portée du geste qui vient de l'ajouter.
    ///
    /// ⚠️ Elle ne part nulle part tant que la route des couvertures n'existe
    /// pas : la photo vit dans les caches de l'appareil, et un
    /// réenregistrement de l'écran la perd. Signalé (T88).
    public func add(_ photo: CoverPhoto) {
        guard var covers else { return }
        guard !covers.photos.contains(where: { $0.id == photo.id }) else { return }
        covers.photos.append(photo)
        self.covers = covers
    }

    public func commitStyle() {
        guard let cover else { return }
        save(.style(face, cover.styleId))
    }

    public func commitPhoto() {
        guard let cover else { return }
        save(.photo(face, cover.photoId))
    }

    public func setTexts(title: String, subtitle: String) {
        guard var covers else { return }
        covers[face].title = title
        covers[face].subtitle = subtitle
        self.covers = covers
        save(.texts(face, title: title, subtitle: subtitle))
    }

    /// Les chiffres du dos. La feuille garde la main sur les bornes — voir
    /// ``BookCovers/statRange`` — et n'appelle ceci qu'à « Valider ».
    public func setStats(_ ids: [String]) {
        guard var covers else { return }
        covers.back.statIds = ids
        self.covers = covers
        save(.stats(ids))
    }

    private func save(_ edit: BookCoverEdit) {
        guard let persist else { return }

        pendingSave?.cancel()
        pendingSave = Task {
            do {
                let updated = try await persist(tripId, edit)
                guard !Task.isCancelled else { return }
                covers = updated
                errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                await reload()
            }
        }
    }
}

/// Ce que le parcours des couvertures demande à l'app d'ouvrir.
public enum CoversIntent: Sendable, Hashable {
    case openStyle
    case openPhoto
    case openTexts
}
