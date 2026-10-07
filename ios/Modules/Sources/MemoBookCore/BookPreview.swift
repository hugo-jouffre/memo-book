import Foundation

// L'aperçu du carnet : le PDF que la conversation a produit, page par page.
//
// **L'app ne redessine pas le carnet.** Les pages viennent du PDF composé par
// le back-end (OpenAI structure le récit, APITemplate le met en page) et
// s'affichent telles quelles. C'est la seule façon d'être sûr que l'aperçu
// montre ce qui sortira de l'imprimante — et c'est aussi la plus rapide : une
// page de PDF se rend en quelques millisecondes, là où rejouer la mise en page
// en SwiftUI demanderait de réimplémenter le template et de le maintenir en
// double.
//
// Voir `docs/apitemplate.md` pour la composition, et `MemoBook Generator/templates/travel-journal/`
// pour le template lui-même.

/// Où en est la composition du carnet.
public enum BookPreviewStatus: Sendable, Hashable {
    /// Le back-end compose. C'est l'écran « On compose ton Carnet » qui occupe
    /// l'attente, et il n'attend pas passivement : il montre une page en train
    /// de se monter.
    case composing
    /// Le PDF est là, on peut le feuilleter.
    case ready
    /// La composition a échoué. Le message vient du serveur : lui seul sait si
    /// c'est un souvenir illisible ou une panne de son côté.
    case failed(String)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

extension BookPreviewStatus: Codable {
    private enum Keys: String, CodingKey { case status, message }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let raw = try container.decode(String.self, forKey: .status)
        self =
            switch raw {
            case "ready": .ready
            case "failed": .failed(
                try container.decodeIfPresent(String.self, forKey: .message)
                    ?? "La composition n’a pas abouti."
            )
            // Tout le reste — « queued », « running », un état ajouté demain —
            // est une attente. C'est le repli sûr : montrer la composition en
            // cours coûte quelques secondes, annoncer un échec à tort fait
            // fermer l'écran.
            default: .composing
            }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .composing: try container.encode("composing", forKey: .status)
        case .ready: try container.encode("ready", forKey: .status)
        case .failed(let message):
            try container.encode("failed", forKey: .status)
            try container.encode(message, forKey: .message)
        }
    }
}

/// Où en est **une** composition, telle que le serveur la mène
/// (`render.phase`, 06/10/2026).
///
/// Plus fin que ``BookPreviewStatus``, qui ne dit que « ça compose » : une
/// composition attend son tour, met les souvenirs en pages — en attendant ceux
/// qui sont encore en rédaction —, puis fabrique le PDF. C'est ce que l'écran
/// de composition dit sous sa page, pour qu'une attente de plusieurs minutes
/// ne se lise pas comme un écran figé.
public enum BookRenderPhase: Sendable, Hashable {
    /// En file, pas encore commencée.
    case queued
    /// Les textes se mettent en page — et la composition attend, jusqu'à trois
    /// minutes, les souvenirs encore en rédaction.
    case writing
    /// Le PDF se fabrique chez APITemplate.
    case composing
    case ready
    case failed
    /// Une phase ajoutée côté serveur après cette version : une attente, comme
    /// tout ce qui n'est ni prêt ni en échec.
    case unknown(String)
}

extension BookRenderPhase: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self =
            switch raw {
            case "queued": .queued
            case "writing": .writing
            case "composing": .composing
            case "ready": .ready
            case "failed": .failed
            default: .unknown(raw)
            }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        let raw =
            switch self {
            case .queued: "queued"
            case .writing: "writing"
            case .composing: "composing"
            case .ready: "ready"
            case .failed: "failed"
            case .unknown(let raw): raw
            }
        try container.encode(raw)
    }
}

/// La **dernière** composition du carnet, quel que soit son état — le champ
/// `render` de `GET /v1/memos/:id/preview`.
///
/// Elle distingue ce que ``BookPreviewStatus`` confond : « une composition
/// tourne » et « rien n'a jamais été lancé ». Le serveur répond `composing`
/// dans les deux cas ; seul ce champ, `nil` dans le second, permet à l'écran de
/// ne pas attendre une composition qui ne viendra pas.
public struct BookRenderProgress: Codable, Sendable, Hashable {
    public let id: String
    /// `nil` sur un serveur qui ne la sert pas encore : on lit alors une
    /// attente, comme pour une phase inconnue.
    public let phase: BookRenderPhase?
    public let error: String?

    public init(id: String, phase: BookRenderPhase? = nil, error: String? = nil) {
        self.id = id
        self.phase = phase
        self.error = error
    }
}

/// Les deux lignes que porte la carte de partage : ce que le carnet raconte, en
/// deux phrases prises dedans.
///
/// C'est du **contenu** : les phrases sortent du récit rédigé, pas d'un libellé
/// d'interface. Elles servent aussi de métadonnées Open Graph au lien de
/// prévisualisation, ce qui est la raison pour laquelle elles vivent dans le
/// modèle et non dans la vue.
public struct BookExcerpt: Codable, Sendable, Hashable {
    /// La phrase mise en avant, entre guillemets dans la carte.
    public let quote: String
    /// Ce qui la prolonge, en une phrase.
    public let detail: String?

    public init(quote: String, detail: String? = nil) {
        self.quote = quote
        self.detail = detail
    }
}

/// Tout ce que l'aperçu du carnet a besoin de savoir.
public struct BookPreview: Codable, Sendable, Hashable {
    /// L'identifiant du carnet côté serveur. C'est lui qu'on repasse pour
    /// relancer une composition ou commander l'impression.
    public let memoId: String

    /// Le titre du carnet — « Rome et la Dolce Vita ». Celui du **carnet**, qui
    /// peut différer du nom du voyage : le récit se donne un titre.
    public let title: String

    public let status: BookPreviewStatus

    /// Le PDF composé. `nil` tant que ``status`` n'est pas `ready`.
    ///
    /// C'est un lien signé et de courte durée : il ne se met pas en cache sur
    /// le disque, seul le document déjà chargé reste en mémoire.
    public let pdfUrl: URL?

    /// Combien de pages le carnet fait.
    ///
    /// Il vient du serveur et non du PDF : l'en-tête l'affiche
    /// (« 10 pages composées ») avant que le document soit téléchargé. Une fois
    /// le PDF là, c'est **lui** qui fait foi — voir ``BookPreview/pageCount(from:)``.
    public let pageCount: Int

    /// Le lien de prévisualisation en ligne, à partager. `nil` tant qu'il n'a
    /// pas été demandé — c'est un lien public, il ne se crée pas tout seul.
    ///
    /// **Seul le serveur le fabrique** (`POST /v1/memos/:id/share-link`) : une
    /// page publique `/c/<jeton>` servie par l'API, avec sa vignette Open
    /// Graph pour WhatsApp et iMessage. L'app ne compose jamais d'URL — celle
    /// qu'elle fabriquait, `memo-book.com/c/<identifiant>`, ne menait nulle
    /// part (06/10/2026).
    public let shareUrl: URL?

    /// La couverture, pour la carte de partage.
    public let coverPhotoUrl: URL?

    /// La date du voyage, telle que la carte de partage l'affiche. `nil` quand
    /// le voyage n'en a pas — la pastille disparaît alors plutôt que d'inventer
    /// aujourd'hui.
    public let tripDate: Date?

    public let excerpt: BookExcerpt?

    /// La première et la quatrième de couverture ont-elles été choisies.
    ///
    /// Faux, la page de couverture s'affiche voilée avec son invitation à la
    /// régler — c'est ce que dessine « Prévisualisation PDF - 2 ». Ce n'est pas
    /// un état d'erreur : un carnet est feuilletable sans couverture choisie,
    /// elle se met juste par défaut.
    public let hasConfiguredCovers: Bool

    /// La dernière composition — voir ``BookRenderProgress``. `nil` quand le
    /// carnet n'a jamais été composé, **et** sur un serveur d'avant le
    /// 06/10/2026 qui ne la sert pas.
    public let render: BookRenderProgress?

    /// Le rendu derrière ``pdfUrl`` : celui qu'on commande. `nil` tant
    /// qu'aucune composition n'a abouti.
    public let readyRenderId: String?

    /// ``pdfUrl`` montre-t-il le contenu actuel ? Faux quand il n'y a pas de
    /// PDF, ou que le récit a changé depuis — une composition va repartir.
    /// `nil` sur un serveur qui ne le dit pas.
    public let isUpToDate: Bool?

    /// Combien de souvenirs sont encore en rédaction : la composition les
    /// attend avant de mettre en page. `nil` sur un serveur qui ne le dit pas.
    public let pendingMemoryCount: Int?

    public init(
        memoId: String,
        title: String,
        status: BookPreviewStatus = .composing,
        pdfUrl: URL? = nil,
        pageCount: Int = 0,
        shareUrl: URL? = nil,
        coverPhotoUrl: URL? = nil,
        tripDate: Date? = nil,
        excerpt: BookExcerpt? = nil,
        hasConfiguredCovers: Bool = false,
        render: BookRenderProgress? = nil,
        readyRenderId: String? = nil,
        isUpToDate: Bool? = nil,
        pendingMemoryCount: Int? = nil
    ) {
        self.memoId = memoId
        self.title = title
        self.status = status
        self.pdfUrl = pdfUrl
        self.pageCount = pageCount
        self.shareUrl = shareUrl
        self.coverPhotoUrl = coverPhotoUrl
        self.tripDate = tripDate
        self.excerpt = excerpt
        self.hasConfiguredCovers = hasConfiguredCovers
        self.render = render
        self.readyRenderId = readyRenderId
        self.isUpToDate = isUpToDate
        self.pendingMemoryCount = pendingMemoryCount
    }

    /// Le lien des jeux d'essai — bac à sable, aperçus Xcode —, à la forme de
    /// celui du serveur (`<hôte de l'API>/c/<jeton>`) mais sur un domaine
    /// réservé aux exemples : il ne mène nulle part, et ne fait pas croire le
    /// contraire. Un vrai jeton ne vient que de `POST /v1/memos/:id/share-link`.
    public static func sampleShareLink(memoId: String) -> URL {
        URL(string: "https://api.memobook.example/c/essai-\(memoId)")!
    }

    /// Les pages qui se **configurent** : la première et la dernière.
    ///
    /// Une seule quand le carnet n'a qu'une page, et aucune quand il n'en a
    /// pas : sans ce garde-fou, un carnet vide aurait proposé de configurer une
    /// page inexistante.
    public func isConfigurableCover(page index: Int, in total: Int) -> Bool {
        guard !hasConfiguredCovers, total > 0 else { return false }
        return index == 0 || index == total - 1
    }

    /// Le PDF est ouvert et feuilletable.
    ///
    /// Distinct de ``status`` : le serveur peut avoir fini de composer alors que
    /// le fichier n'est pas encore descendu. C'est cette question-là que
    /// l'écran doit poser avant de poser quoi que ce soit **sur** une page —
    /// une invitation à choisir sa couverture posée sur un aplat vide promet
    /// une page qui n'existe pas encore.
    public var hasDocument: Bool { status.isReady && pdfUrl != nil }

    /// Une composition a déjà abouti : il y a un carnet à feuilleter et à
    /// commander, **même si une autre tourne** pour le remettre à jour.
    ///
    /// Le PDF est celui du dernier rendu **prêt** (`pdfUrl` ne s'efface pas
    /// pendant une recomposition), d'où le fait qu'il suffise. Le statut prêt
    /// seul compte aussi : c'est le cas du jeu d'essai, qui n'a pas de PDF.
    public var hasReadyRender: Bool {
        readyRenderId != nil || pdfUrl != nil || status.isReady
    }
}
