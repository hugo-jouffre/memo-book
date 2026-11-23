import Foundation

// Un carnet de la galerie de la communauté, ouvert — l'écran derrière une carte
// d'« Exemples de carnets » (T236).
//
// Même principe que ``Gallery`` : l'écran ne sait rien du contenu, il ne sait
// que le dessiner. Il se lit **sans compte** — c'est à ça que sert une vitrine,
// montrer à quoi ressemble un MemoBook terminé à quelqu'un qui n'en a pas.
//
// ⚠️ **Ce modèle est le contrat de ce qu'un carnet public montre.** Il ne porte
// ni propriétaire, ni co-voyageurs, ni conversation avec MEMO, ni code d'accès :
// non par oubli, mais parce que la route ne les sert pas, et pour les raisons
// que porte `backend/src/routes/publicBook.ts`. Un champ ajouté ici devrait
// d'abord être ajouté là-bas, et c'est une décision de Hugo.

/// Une étape d'un carnet public : un lieu, et ce qui s'y est raconté.
public struct PublicBookStep: Codable, Sendable, Hashable, Identifiable {
    public let id: String

    /// Son rang dans le voyage, tel que le serveur l'a numéroté.
    public let number: Int

    /// Le lieu précis s'il est connu, sinon le pays. `nil` pour une étape
    /// qu'aucun récit n'a su nommer — l'écran la titre alors par son rang.
    public let place: String?

    public let countryCode: String?

    /// « du 1er au 8 juin 2026 », déjà écrit en français par le serveur : le
    /// même texte que la page publique d'un carnet partagé, pour que les deux
    /// ne datent pas un voyage de deux façons.
    public let dates: String?

    /// La photo de l'étape. `nil` quand elle n'en a pas de **publiée** : la
    /// galerie ne sert jamais une photo de notre seau, qui est privé.
    public let photoUrl: URL?

    /// Le moyen de transport, **tel quel** : `walk`, `bike`, `car`, `bus`,
    /// `train`, `boat`, `plane`.
    ///
    /// Une chaîne et non un ``TripTransport``, et c'est voulu : le décodeur de
    /// cette énumération **échoue** sur une valeur qu'il ne connaît pas, et un
    /// huitième transport ajouté côté serveur ferait alors cesser de décoder
    /// *tout l'écran*, pas seulement la ligne concernée (`ios/CLAUDE.md`, « Un
    /// état inconnu ne casse pas le décodage »). On garde donc le brut, et
    /// ``mode`` le traduit quand il sait.
    public let transport: String?

    /// Le récit de l'étape, un paragraphe par souvenir, dans l'ordre vécu.
    /// Vide pour une étape dont rien n'est encore rédigé.
    public let story: [String]

    /// Les photos des souvenirs de l'étape, celles qui sont publiées.
    public let photoUrls: [URL]

    public init(
        id: String,
        number: Int,
        place: String? = nil,
        countryCode: String? = nil,
        dates: String? = nil,
        photoUrl: URL? = nil,
        transport: String? = nil,
        story: [String] = [],
        photoUrls: [URL] = []
    ) {
        self.id = id
        self.number = number
        self.place = place
        self.countryCode = countryCode
        self.dates = dates
        self.photoUrl = photoUrl
        self.transport = transport
        self.story = story
        self.photoUrls = photoUrls
    }

    /// Le drapeau du pays de l'étape, ou `nil` sans code exploitable.
    public var flag: String? {
        Destination(name: place ?? "", countryCode: countryCode).flag
    }

    /// Le transport traduit, quand l'app connaît la clé — de quoi écrire « À
    /// pied » ou « Bateau ». `nil` pour une étape sans transport **comme** pour
    /// une clé que cette version ne connaît pas : dans les deux cas l'écran n'a
    /// rien à en dire, et c'est exactement ce qu'on veut qu'il fasse.
    public var mode: TripTransport? {
        guard let transport else { return nil }
        return TripTransport.allCases.first { $0.rawValue == transport }
    }

    /// `true` quand l'étape n'a ni récit ni photo : l'écran la pose alors comme
    /// un simple jalon du trajet, sans réserver la place d'un contenu absent.
    public var isBare: Bool { story.isEmpty && photoUrls.isEmpty }
}

/// Un carnet de la galerie, tel que son écran le montre.
public struct PublicBook: Codable, Sendable, Hashable, Identifiable {
    public let id: String

    /// Le titre imprimé en couverture — celui que le récit s'est donné s'il en
    /// a un, celui du voyage sinon. C'est le serveur qui tranche.
    public let title: String

    /// « du 1er au 21 juin 2026 », ou `nil` pour un voyage sans date.
    public let dates: String?

    /// La phrase sous le titre, la même que sur la carte dont on vient : écrite
    /// si quelqu'un l'a écrite, déduite des chiffres du voyage sinon.
    public let summary: String?

    public let coverPhotoUrl: URL?

    /// Les pays traversés, sans doublon, celui du carnet d'abord.
    public let destinations: [Destination]

    /// Le nombre de pages du carnet composé, et le nombre de souvenirs qui le
    /// remplissent. Les deux chiffres qui disent « c'est un vrai carnet fini »,
    /// et toute la promesse de l'écran.
    public let pageCount: Int
    public let memoryCount: Int

    public let steps: [PublicBookStep]

    public init(
        id: String,
        title: String,
        dates: String? = nil,
        summary: String? = nil,
        coverPhotoUrl: URL? = nil,
        destinations: [Destination] = [],
        pageCount: Int = 0,
        memoryCount: Int = 0,
        steps: [PublicBookStep] = []
    ) {
        self.id = id
        self.title = title
        self.dates = dates
        self.summary = summary
        self.coverPhotoUrl = coverPhotoUrl
        self.destinations = destinations
        self.pageCount = pageCount
        self.memoryCount = memoryCount
        self.steps = steps
    }

    /// Le drapeau du coin de l'en-tête, et `nil` dès qu'il y a plus d'un pays —
    /// même règle que ``GalleryTrip/flag``, et pour la même raison : choisir un
    /// drapeau parmi dix désignerait le premier pays comme *le* pays du carnet.
    public var flag: String? {
        guard destinations.count == 1 else { return nil }
        return destinations.first?.flag
    }

    /// Les étapes qui portent quelque chose à lire. C'est sur elles que l'écran
    /// décide s'il a un carnet à montrer ou seulement un trajet.
    public var tellingSteps: [PublicBookStep] { steps.filter { !$0.isBare } }

    /// `true` quand le carnet est partagé mais que rien n'y est encore rédigé :
    /// l'écran le dit, au lieu de dérouler des étapes vides.
    public var hasNothingToRead: Bool { tellingSteps.isEmpty }
}
