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

    /// Le plat d'en face.
    public var opposite: CoverFace { self == .front ? .back : .front }

    /// « 1ère de couverture » et « 4e de couverture », les deux onglets.
    ///
    /// « 1ère » et non « 1re » : c'est l'abréviation que la maquette emploie
    /// partout, et l'app la suit (Hugo, 17/09/2026, T91).
    public var title: String {
        switch self {
        case .front: "1ère de couverture"
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

    /// Cette composition **porte-t-elle une photo** ?
    ///
    /// Deux des quatre n'en portent pas : un aplat et un kraft sont des fonds,
    /// pas des cadres. Choisir une photo dessus ne changerait rien au plat —
    /// et c'est exactement ce que faisait le carrousel des photos avant qu'on
    /// le dise (Hugo, 16/09/2026).
    public var carriesPhoto: Bool {
        switch self {
        case .photo, .framed: true
        case .plain, .kraft: false
        }
    }

    /// Cette composition **porte-t-elle un texte**, sur ce plat-là ?
    ///
    /// La question ne se pose qu'au dos. Un devant a toujours son titre, quelle
    /// que soit la composition — posé sur la photo, sur l'aplat ou à la main.
    /// Au dos, en revanche, la photo pleine page **occupe tout le plat** : il
    /// n'y a pas de place pour le texte de quatrième, et l'écran des textes n'a
    /// donc rien à y écrire.
    public func carriesText(on face: CoverFace) -> Bool {
        switch face {
        case .front: true
        case .back: self != .photo
        }
    }
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

/// **Les sept gabarits de couverture** de `assets/covers` (Hugo, 08/10/2026 :
/// « intégrer les visuels de cover en associant correctement la front cover et
/// la back cover »).
///
/// Chaque famille a **sa** 1ère et **sa** 4e de couverture : les fichiers de
/// Hugo vont par paires, nommés pareil à la fin — « front cover_style dessin »
/// et « back cover_style dessin ». C'est la famille qui fait la paire, et donc
/// la pastille « Assortie à ta 1ère de couverture » (``CoverStyle/matches(_:)``).
///
/// L'app **redessine** chaque gabarit avec la photo et les mots du voyageur
/// (`CoverTemplates.swift`) : ni le titre « PHILIPPINES » ni la photo de la
/// maquette n'y restent. Une famille inconnue — un serveur plus récent — se
/// décode en `nil`, et le plat retombe sur sa composition (``CoverTreatment``).
public enum CoverFamily: String, Codable, Sendable, Hashable, CaseIterable {
    /// La photo pleine page, le titre en capitales à empattements dessus ; au
    /// dos, le trajet et les chiffres.
    case `default`
    /// Un bandeau crème et son titre noir, la photo comme une aquarelle ; au
    /// dos, le récit en trois temps, chacun avec son image.
    case watercolor
    /// Le bleu de la marque, le titre vert, une palme ; au dos, le récit et
    /// les chiffres sur le même bleu.
    case assouline
    /// Le papier crème, l'écriture à la main et des dessins au trait.
    case drawing
    /// La photo pleine page, des courbes de niveau tracées à la main par-dessus
    /// et le titre manuscrit ; au dos, un aplat d'eau claire et un mot.
    case photoDrawing = "photo-drawing"
    /// Le carnet de bord : des timbres, un tampon, le vert de la marque ; au
    /// dos, une photo dans un cadre déchiré.
    case travelBook = "travel-book"
    /// Le titre fin à empattements, la photo comme un tirage ; au dos, un
    /// paysage en bandeau et quelques lignes.
    case elegant

    /// Ce plat de cette famille **porte-t-il une photo** — celle qu'on choisit
    /// dans le carrousel des photos ?
    public func carriesPhoto(on face: CoverFace) -> Bool {
        switch (self, face) {
        case (.default, .front), (.watercolor, _), (.photoDrawing, .front), (.travelBook, _), (.elegant, _):
            true
        case (.default, .back), (.assouline, _), (.drawing, _), (.photoDrawing, .back):
            false
        }
    }

    /// Ce plat porte-t-il **un texte qu'on écrit** — le titre et la signature
    /// devant, le texte de quatrième au dos ?
    public func carriesText(on face: CoverFace) -> Bool {
        switch (self, face) {
        case (_, .front): true
        case (.default, .back), (.travelBook, .back): false
        case (.watercolor, .back), (.assouline, .back), (.drawing, .back), (.photoDrawing, .back),
            (.elegant, .back):
            true
        }
    }

    /// Ce plat imprime-t-il **les chiffres du voyage** ? Au dos seulement, et
    /// pas sur tous : deux maquettes les posent.
    public func carriesStats(on face: CoverFace) -> Bool {
        face == .back && (self == .default || self == .assouline)
    }
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
    /// Le gabarit — voir ``CoverFamily``. `nil` pour un style d'avant le
    /// 08/10/2026, ou d'une famille que cette app ne connaît pas encore : le
    /// plat se dessine alors d'après ``treatment`` et ``tint``, que le serveur
    /// sert toujours pour les apps installées.
    public let family: CoverFamily?

    public init(
        id: String,
        name: String,
        treatment: CoverTreatment,
        tint: CoverTint,
        family: CoverFamily? = nil
    ) {
        self.id = id
        self.name = name
        self.treatment = treatment
        self.tint = tint
        self.family = family
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, treatment, tint, family
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            treatment: try container.decode(CoverTreatment.self, forKey: .treatment),
            tint: try container.decode(CoverTint.self, forKey: .tint),
            // Une famille inconnue ne fait pas tomber le catalogue : le plat
            // retombe sur sa composition.
            family: (try? container.decodeIfPresent(CoverFamily.self, forKey: .family)) ?? nil
        )
    }

    /// Ce style **s'accorde** à un autre. C'est ce que la pastille « Assortie
    /// à ta 1ère de couverture » veut dire, et elle se calcule sur le plat
    /// d'en face **tel qu'il est choisi** — un drapeau figé dans le catalogue
    /// ne suivait pas le devant quand on le changeait (Clara, 17/09/2026).
    ///
    /// **La même famille** depuis le 08/10/2026 : la 4e « dessin » va avec la
    /// 1ère « dessin », comme les fichiers de Hugo. Sans famille des deux
    /// côtés, même composition et même aplat, comme avant.
    public func matches(_ other: CoverStyle) -> Bool {
        if let family, let otherFamily = other.family { return family == otherFamily }
        return treatment == other.treatment && tint == other.tint
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

    // MARK: Ce qu'un plat accepte, vu du style qu'il porte

    /// La composition que ce plat porte en ce moment. `nil` si le style n'est
    /// pas dans le catalogue — un plat servi par un serveur plus récent.
    public func treatment(of face: CoverFace) -> CoverTreatment? {
        style(id: self[face].styleId)?.treatment
    }

    /// Le gabarit que ce plat porte en ce moment, s'il en a un.
    public func family(of face: CoverFace) -> CoverFamily? {
        style(id: self[face].styleId)?.family
    }

    /// Ce plat accepte-t-il une photo ? **Oui par défaut** quand le style est
    /// inconnu : on n'interdit pas un geste parce qu'on n'a pas su lire.
    public func acceptsPhoto(on face: CoverFace) -> Bool {
        if let family = family(of: face) { return family.carriesPhoto(on: face) }
        return treatment(of: face)?.carriesPhoto ?? true
    }

    /// Ce plat accepte-t-il un texte ? Même règle de prudence.
    public func acceptsText(on face: CoverFace) -> Bool {
        if let family = family(of: face) { return family.carriesText(on: face) }
        return treatment(of: face)?.carriesText(on: face) ?? true
    }

    /// Ce plat imprime-t-il les chiffres du voyage ? Le dos seulement ; tous
    /// les dos d'avant les gabarits les portaient.
    public func acceptsStats(on face: CoverFace) -> Bool {
        guard face == .back else { return false }
        return family(of: face)?.carriesStats(on: face) ?? true
    }

    /// Les chiffres retenus pour le dos, dans l'ordre du catalogue.
    public var statSelection: [CoverStat] {
        back.statIds.compactMap { id in stats.first { $0.id == id } }
    }

    /// Ce style, proposé pour `face`, reprend-il le style **choisi** sur
    /// l'autre plat ? C'est lui que le carrousel coiffe de la pastille
    /// « Assortie à ta 1ère de couverture ».
    public func isMatched(_ style: CoverStyle, on face: CoverFace) -> Bool {
        let other: CoverFace = face == .front ? .back : .front
        guard let chosen = self.style(id: self[other].styleId) else { return false }
        return style.matches(chosen)
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
