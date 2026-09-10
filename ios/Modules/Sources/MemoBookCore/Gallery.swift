import Foundation

// La galerie des carnets de la communauté — l'écran « Exemples de carnets ».
//
// Même principe que ``HomeFeed`` et ``TripDetail`` : l'écran ne sait rien du
// contenu, il ne sait que le dessiner. Titres, sous-titres, catégories,
// pictogrammes et jusqu'au libellé du bouton du bas viennent d'ici.

/// Une catégorie de la galerie : « Tour du monde », « Randonnée », « Vélo ».
///
/// Elle vient de la base (`gallery_categories`) et non d'une énumération Swift :
/// ajouter une catégorie, la renommer ou la retirer de la barre est une
/// écriture en base, pas une livraison d'app.
public struct GalleryCategory: Codable, Sendable, Hashable, Identifiable {
    public let id: String

    /// L'identifiant stable, celui qu'on écrit dans un script. `name` peut
    /// changer, `slug` non.
    public let slug: String

    /// Le libellé de la pastille, tel qu'il s'affiche.
    public let name: String

    /// La clé du pictogramme, résolue par `MemoBookDesign`. Une clé que l'app
    /// ne connaît pas encore ne casse rien : elle retombe sur une boussole.
    public let iconKey: String

    public init(id: String, slug: String, name: String, iconKey: String) {
        self.id = id
        self.slug = slug
        self.name = name
        self.iconKey = iconKey
    }
}

/// Un carnet de la galerie, tel que sa carte le montre.
///
/// Volontairement plus maigre qu'un ``Trip`` : la galerie n'affiche ni
/// compteurs, ni progression, ni co-voyageurs — ce sont les carnets d'autres
/// gens, et une carte qui ne s'ouvre pas encore n'a rien à porter de plus.
public struct GalleryTrip: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String

    /// La phrase sous le titre : « 2 semaines de trek », « Un couple autour du
    /// monde ». Elle sera **déduite du contenu du voyage** par un agent ; `nil`
    /// tant qu'il ne l'a pas écrite, et la carte n'affiche alors que son titre.
    public let subtitle: String?

    /// Les pays traversés, sans doublon, celui du carnet d'abord. C'est leur
    /// **nombre** qui décide du pictogramme de la carte — voir ``flag``.
    public let destinations: [Destination]

    public let coverPhotoUrl: URL?

    /// Les catégories auxquelles le carnet est rattaché. Plusieurs, parce qu'un
    /// tour du monde à pied est aussi une randonnée.
    public let categoryIds: [String]

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        destinations: [Destination] = [],
        coverPhotoUrl: URL? = nil,
        categoryIds: [String] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.destinations = destinations
        self.coverPhotoUrl = coverPhotoUrl
        self.categoryIds = categoryIds
    }

    /// Le drapeau à poser dans le coin de la carte — et `nil` dès qu'il y a
    /// plus d'un pays.
    ///
    /// Un voyage à travers dix pays n'a pas de drapeau : en choisir un
    /// désignerait le premier comme *le* pays du carnet, ce qu'il n'est pas.
    /// L'écran met alors un globe, et c'est aussi ce qu'il fait quand le pays
    /// n'a pas de code ISO exploitable.
    public var flag: String? {
        guard destinations.count == 1 else { return nil }
        return destinations.first?.flag
    }

    /// `true` quand la carte appartient à une catégorie donnée. `nil` veut dire
    /// « Tout » : la barre ouverte, aucun filtre posé.
    public func belongs(to categoryId: String?) -> Bool {
        guard let categoryId else { return true }
        return categoryIds.contains(categoryId)
    }
}

/// Tout ce qu'il faut pour dessiner la galerie, en une seule réponse.
public struct Gallery: Codable, Sendable, Hashable {
    /// Les catégories actives, déjà rangées par le serveur.
    public let categories: [GalleryCategory]

    /// Les carnets publics, du plus récent au plus ancien. Le filtrage se fait
    /// dans l'app : la barre bascule d'une catégorie à l'autre sans
    /// aller-retour réseau, et la liste ne peut pas se retrouver en avance sur
    /// ses filtres.
    public let trips: [GalleryTrip]

    /// Le voyage que celui qui regarde a déjà ouvert : celui en cours, sinon le
    /// prochain prévu. C'est lui qui décide du bouton du bas — « Continuer mon
    /// voyage » plutôt que « Créer mon voyage ». `nil` quand il n'y en a aucun.
    public let resumableTripId: String?

    public init(
        categories: [GalleryCategory] = [],
        trips: [GalleryTrip] = [],
        resumableTripId: String? = nil
    ) {
        self.categories = categories
        self.trips = trips
        self.resumableTripId = resumableTripId
    }
}
