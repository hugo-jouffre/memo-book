import Foundation

/// **Une demande d'avis, poussée par le serveur** (T273, Hugo, 05/11/2026 —
/// « commencer à recueillir leur avis dans l'app »).
///
/// L'app ne connaît que les **formes** de question et sait les dessiner ; le
/// texte, l'ordre, le nombre et le moment viennent de la base
/// (`feedback_campaigns`). Ajouter une campagne est une insertion, pas une
/// livraison : c'est la réponse à « peut-on envoyer des popups sans faire
/// retélécharger l'app ».
///
/// ⚠️ **Jamais de note sur l'App Store** : on demande un avis, pas une étoile
/// (écarté par Hugo pour le moment).
public struct FeedbackCampaign: Codable, Sendable, Hashable, Identifiable {
    public let id: String

    /// L'identifiant lisible qu'on cite dans une analyse : `avis-v1`.
    public let key: String

    public let title: String
    public let subtitle: String?

    /// Le libellé du bouton d'envoi — il vient du serveur, parce qu'une
    /// campagne peut demander autre chose qu'« Envoyer ».
    public let submitLabel: String

    public let questions: [FeedbackQuestion]

    public init(
        id: String,
        key: String,
        title: String,
        subtitle: String? = nil,
        submitLabel: String = "Envoyer",
        questions: [FeedbackQuestion] = []
    ) {
        self.id = id
        self.key = key
        self.title = title
        self.subtitle = subtitle
        self.submitLabel = submitLabel
        self.questions = questions
    }

    /// **Cette version sait-elle dessiner toute la campagne ?**
    ///
    /// Une modale à trous ne se montre pas : une question qu'on saute peut
    /// être celle qui comptait, et l'avis rendu dirait le contraire de ce
    /// qu'on a demandé. Une campagne qui emploie une forme que cette version
    /// ne dessine pas attend donc la suivante — et paraîtra toute seule le
    /// jour où elle sortira, sans qu'on touche à la base.
    public var isDrawable: Bool {
        !questions.isEmpty && questions.allSatisfy(\.kind.isDrawable)
    }
}

/// Une question d'une campagne.
public struct FeedbackQuestion: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let kind: Kind

    /// L'intitulé au-dessus du champ. Nul pour une zone de commentaire qui se
    /// contente de son texte d'invite.
    public let prompt: String?

    /// Le texte grisé d'un champ libre.
    public let placeholder: String?

    public let isRequired: Bool

    /// Les options d'un `choice`, lues dans `config`. Vide pour les autres
    /// formes — et pour un `choice` mal rempli, que l'app ne dessinera donc
    /// pas (``FeedbackCampaign/isDrawable``).
    public let options: [Option]

    public init(
        id: String,
        kind: Kind,
        prompt: String? = nil,
        placeholder: String? = nil,
        isRequired: Bool = false,
        options: [Option] = []
    ) {
        self.id = id
        self.kind = kind
        self.prompt = prompt
        self.placeholder = placeholder
        self.isRequired = isRequired
        self.options = options
    }

    /// Les quatre formes du serveur, plus celles qu'on ne connaît pas encore.
    ///
    /// `unknown` est là pour la même raison que celui d'``EntryStatus`` : une
    /// forme ajoutée côté serveur ne doit pas faire échouer tout le décodage
    /// de l'accueil.
    public enum Kind: Sendable, Hashable {
        /// Zone de texte libre.
        case text
        /// Liste d'options, une seule réponse.
        case choice
        /// Curseur gradué. **Pas encore dessiné** : la marque n'a pas de
        /// curseur, et `BrandGauge` se lit sans se régler.
        case slider
        /// Note en étoiles. **Pas encore dessinée.**
        case rating
        case unknown(String)

        /// Ce que cette version sait mettre à l'écran.
        public var isDrawable: Bool {
            switch self {
            case .text, .choice: true
            case .slider, .rating, .unknown: false
            }
        }
    }

    /// Une option d'un `choice` : la clé part au serveur, le libellé se lit.
    public struct Option: Codable, Sendable, Hashable, Identifiable {
        public let key: String
        public let label: String
        public let hint: String?

        public var id: String { key }

        public init(key: String, label: String, hint: String? = nil) {
            self.key = key
            self.label = label
            self.hint = hint
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, prompt, placeholder, isRequired, config
    }

    private struct Config: Codable {
        var options: [Option]?
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `config` porte les réglages propres à chaque forme ; illisible, il
        // ne fait pas échouer la question — elle sera simplement jugée
        // indessinable si elle en avait besoin.
        let config = try? container.decodeIfPresent(Config.self, forKey: .config)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            kind: try container.decode(Kind.self, forKey: .kind),
            prompt: try container.decodeIfPresent(String.self, forKey: .prompt),
            placeholder: try container.decodeIfPresent(String.self, forKey: .placeholder),
            isRequired: try container.decodeIfPresent(Bool.self, forKey: .isRequired) ?? false,
            options: config?.options ?? []
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(prompt, forKey: .prompt)
        try container.encodeIfPresent(placeholder, forKey: .placeholder)
        try container.encode(isRequired, forKey: .isRequired)
        if !options.isEmpty { try container.encode(Config(options: options), forKey: .config) }
    }
}

extension FeedbackQuestion.Kind: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self =
            switch raw {
            case "text": .text
            case "choice": .choice
            case "slider": .slider
            case "rating": .rating
            default: .unknown(raw)
            }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }

    public var raw: String {
        switch self {
        case .text: "text"
        case .choice: "choice"
        case .slider: "slider"
        case .rating: "rating"
        case .unknown(let value): value
        }
    }
}

/// Ce que l'app renvoie d'une question.
public struct FeedbackAnswer: Codable, Sendable, Hashable {
    public let questionId: String
    public let text: String?
    public let number: Double?
    public let choiceKey: String?

    public init(questionId: String, text: String? = nil, number: Double? = nil, choiceKey: String? = nil) {
        self.questionId = questionId
        self.text = text
        self.number = number
        self.choiceKey = choiceKey
    }
}

/// Ce qu'on a fait de la modale : répondu, ou fermé. **Les deux se disent au
/// serveur** — savoir qu'on écarte une question est un résultat.
public struct FeedbackResponse: Codable, Sendable, Hashable {
    public let dismissed: Bool
    public let appVersion: String?
    public let answers: [FeedbackAnswer]

    public init(dismissed: Bool = false, appVersion: String? = nil, answers: [FeedbackAnswer] = []) {
        self.dismissed = dismissed
        self.appVersion = appVersion
        self.answers = answers
    }
}
