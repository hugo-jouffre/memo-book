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
// Voir `docs/apitemplate.md` pour la composition, et `templates/travel-journal/`
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
        hasConfiguredCovers: Bool = false
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
}
