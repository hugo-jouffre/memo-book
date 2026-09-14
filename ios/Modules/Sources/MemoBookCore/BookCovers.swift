import Foundation

// Les deux plats du carnet : la première et la quatrième de couverture.
//
// **C'est la seule chose qu'on voit du Carnet avant de l'ouvrir**, et la seule
// qu'un autre verra sur une étagère. D'où un parcours à part plutôt qu'une ligne
// de réglage de plus : on choisit un style, une photo, puis on écrit les textes
// — trois gestes, dans cet ordre, sur les deux plats.
//
// ⚠️ **L'app dessine les plats, elle ne les importe pas.** La maquette pose des
// rendus de couvertures finies ; on en garde la composition — le cadrage, la
// place du titre, le rapport A5 — avec les moyens de l'app. Un rendu importé
// serait une image figée qui mentirait dès que le voyageur change sa photo ou
// son titre, alors que ces plats-là montrent **les siens**. Même parti pris que
// `CoverStack` sur l'écran des personnalisations (T83).

/// Lequel des deux plats.
public enum CoverFace: String, Codable, Sendable, Hashable, Identifiable, CaseIterable {
    /// Le devant : photo, titre, année.
    case front
    /// Le dos : le texte de quatrième, la carte du trajet et les chiffres du
    /// voyage.
    case back

    public var id: String { rawValue }

    /// « 1re de couverture » et « 4e de couverture », les deux onglets.
    ///
    /// Ordinaux abrégés à la française — `1re`, `4e` — et non `1ère`/`4ème`,
    /// qui sont les fautes courantes. C'est aussi ce qu'écrit la maquette.
    public var title: String {
        switch self {
        case .front: "1re de couverture"
        case .back: "4e de couverture"
        }
    }
}

/// Comment un plat se dessine.
///
/// Quatre familles, et non les sept styles de la maquette : ce sont les quatre
/// **compositions** que l'app sait rendre honnêtement avec la photo et les
/// textes du voyageur. Le jour où le gabarit rendra les couvertures pour de
/// vrai, c'est cette énumération qui disparaîtra, pas l'écran.
public enum CoverTreatment: String, Codable, Sendable, Hashable {
    /// La photo occupe tout le plat, le titre se pose dessus.
    case photo
    /// La photo est encadrée haut, sur un fond papier ; le texte respire
    /// dessous. C'est la composition des quatrièmes de couverture.
    case framed
    /// Pas de photo : un aplat, et le titre seul.
    case plain
    /// Le papier kraft et l'écriture à la main.
    case kraft
}

/// L'aplat d'un style. Un nom et non une couleur : `MemoBookCore` ne connaît pas
/// SwiftUI, et c'est au design system de dire à quoi ressemble « forêt ».
public enum CoverTint: String, Codable, Sendable, Hashable {
    case paper
    case sand
    case forest
    case slate
    case ink
}

/// Un style graphique de couverture.
public struct CoverStyle: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    /// Le nom du style, pour VoiceOver. Il n'est écrit nulle part sur l'écran :
    /// la maquette ne montre que les vignettes, et on choisit une couverture en
    /// la regardant, pas en lisant son nom.
    public let name: String
    public let treatment: CoverTreatment
    public let tint: CoverTint
    /// Le style s'accorde à celui de l'autre plat. La maquette pose la pastille
    /// « Assortie à votre 1e de couverture » sur la quatrième correspondante.
    public let isMatched: Bool

    public init(
        id: String,
        name: String,
        treatment: CoverTreatment,
        tint: CoverTint,
        isMatched: Bool = false
    ) {
        self.id = id
        self.name = name
        self.treatment = treatment
        self.tint = tint
        self.isMatched = isMatched
    }
}

/// Une photo candidate à la couverture.
public struct CoverPhoto: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let url: URL?

    public init(id: String, url: URL? = nil) {
        self.id = id
        self.url = url
    }
}

/// Un chiffre du voyage, tel qu'il s'imprimera au dos.
public struct CoverStat: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    /// « 13 », « 22k », « 3 ». Une chaîne et non un nombre : c'est le serveur
    /// qui décide d'abréger 22 000 en 22k, et lui seul sait à partir de quand.
    public let value: String
    /// « jours de voyage ». S'imprime sur deux lignes dans le carnet, donc le
    /// texte porte son retour à la ligne.
    public let label: String

    public init(id: String, value: String, label: String) {
        self.id = id
        self.value = value
        self.label = label
    }
}

/// Ce qu'on a choisi pour un plat.
public struct BookCover: Codable, Sendable, Hashable {
    public var styleId: String
    /// La photo retenue. `nil` sur un style qui n'en porte pas, et sur un plat
    /// qu'on n'a pas encore réglé.
    public var photoId: String?
    /// Le grand titre — le nom du pays sur la maquette.
    public var title: String
    /// La ligne sous le titre : les prénoms et la date sur la première, le texte
    /// de quatrième sur l'autre.
    public var subtitle: String
    /// Les chiffres choisis pour le dos. Vide sur la première de couverture.
    public var statIds: [String]

    public init(
        styleId: String,
        photoId: String? = nil,
        title: String = "",
        subtitle: String = "",
        statIds: [String] = []
    ) {
        self.styleId = styleId
        self.photoId = photoId
        self.title = title
        self.subtitle = subtitle
        self.statIds = statIds
    }
}

/// Les deux plats et tout ce qui sert à les composer.
public struct BookCovers: Codable, Sendable, Hashable {
    public var front: BookCover
    public var back: BookCover

    /// Les styles proposés, par plat : le catalogue de la première n'est pas
    /// celui de la quatrième.
    public var frontStyles: [CoverStyle]
    public var backStyles: [CoverStyle]

    /// Les photos du voyage, dans l'ordre où le carrousel les propose.
    public var photos: [CoverPhoto]

    /// Tous les chiffres que le voyage sait produire. Le voyageur en retient
    /// trois ou quatre — voir ``statSelection``.
    public var stats: [CoverStat]

    public init(
        front: BookCover,
        back: BookCover,
        frontStyles: [CoverStyle],
        backStyles: [CoverStyle],
        photos: [CoverPhoto],
        stats: [CoverStat]
    ) {
        self.front = front
        self.back = back
        self.frontStyles = frontStyles
        self.backStyles = backStyles
        self.photos = photos
        self.stats = stats
    }

    public subscript(face: CoverFace) -> BookCover {
        get {
            switch face {
            case .front: front
            case .back: back
            }
        }
        set {
            switch face {
            case .front: front = newValue
            case .back: back = newValue
            }
        }
    }

    public func styles(for face: CoverFace) -> [CoverStyle] {
        switch face {
        case .front: frontStyles
        case .back: backStyles
        }
    }

    public func style(id: String) -> CoverStyle? {
        (frontStyles + backStyles).first { $0.id == id }
    }

    public func photo(id: String?) -> CoverPhoto? {
        guard let id else { return nil }
        return photos.first { $0.id == id }
    }

    /// Combien de chiffres le dos accepte. « Choisis-en 3 ou 4 », dit la
    /// feuille, et la contrainte vient du gabarit : sous trois, le bandeau a des
    /// colonnes vides ; au-delà de quatre, les chiffres ne sont plus lisibles à
    /// la taille imprimée.
    public static let statRange = 3...4

    /// Les chiffres retenus pour le dos, dans l'ordre du catalogue.
    public var statSelection: [CoverStat] {
        back.statIds.compactMap { id in stats.first { $0.id == id } }
    }
}

/// Ce qu'un plat modifié envoie au serveur.
///
/// Un geste à la fois, comme ``BookCustomisationEdit`` : l'écran ne renvoie que
/// ce qu'on vient de valider.
public enum BookCoverEdit: Sendable, Hashable {
    case style(CoverFace, String)
    case photo(CoverFace, String?)
    case texts(CoverFace, title: String, subtitle: String)
    case stats([String])
}
