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
        !questions.isEmpty && questions.allSatisfy(\.isDrawable)
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
    /// pas (``FeedbackQuestion/isDrawable``).
    public let options: [Option]

    /// L'échelle d'un `slider` ou d'un `rating`, lue dans `config`. `nil`
    /// pour les autres formes — et pour une échelle impossible, qui rend la
    /// question indessinable plutôt que dessinée de travers.
    public let scale: Scale?

    public init(
        id: String,
        kind: Kind,
        prompt: String? = nil,
        placeholder: String? = nil,
        isRequired: Bool = false,
        options: [Option] = [],
        scale: Scale? = nil
    ) {
        self.id = id
        self.kind = kind
        self.prompt = prompt
        self.placeholder = placeholder
        self.isRequired = isRequired
        self.options = options
        self.scale = scale
    }

    /// **Cette question se dessine-t-elle ?**
    ///
    /// La forme ne suffit pas : une liste sans option et un curseur dont la
    /// borne haute est sous la basse sont des campagnes mal posées, et une
    /// question vide vaut une question sautée. C'est la campagne entière qui
    /// attend alors (``FeedbackCampaign/isDrawable``) — le temps d'un
    /// `UPDATE`, pas d'une livraison.
    public var isDrawable: Bool {
        switch kind {
        case .text: true
        case .choice: !options.isEmpty
        case .slider, .rating: scale?.isUsable == true
        case .unknown: false
        }
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
        /// Curseur gradué, de la borne basse à la haute — ``Scale``.
        case slider
        /// Note en étoiles, de 1 à ``Scale/max``.
        case rating
        case unknown(String)

    }

    /// **L'échelle d'un curseur ou d'une note**, lue dans `config`.
    ///
    /// Un `slider` s'en sert en entier : il va de ``min`` à ``max`` par pas de
    /// ``step``, et écrit ``ticks`` sous ses crans quand la campagne les
    /// donne. Un `rating` n'en lit que ``max`` : une note part toujours de 1
    /// étoile, et zéro étoile serait une absence de réponse, pas une note.
    public struct Scale: Codable, Sendable, Hashable {
        public let min: Int
        public let max: Int
        public let step: Int

        /// Ce qui s'écrit sous les crans, de la borne basse à la haute. Vide
        /// quand la campagne n'en donne pas : le curseur écrit alors les
        /// nombres.
        ///
        /// ⚠️ **Court** : le cran du moment s'écrit en **gras**, donc plus
        /// large, et ``BrandSlider`` le tronque au-delà d'environ six
        /// caractères — « Souvent » devient « Souv… ». C'est une contrainte
        /// d'écriture de la campagne, pas du dessin : le même curseur sert le
        /// ratio photo/texte, dont les crans sont des pourcentages.
        public let ticks: [String]

        /// Ce que disent les deux bouts — « Jamais », « Tous les jours ».
        public let minLabel: String?
        public let maxLabel: String?

        public init(
            min: Int = 0,
            max: Int = 5,
            step: Int = 1,
            ticks: [String] = [],
            minLabel: String? = nil,
            maxLabel: String? = nil
        ) {
            self.min = min
            self.max = max
            self.step = step
            self.ticks = ticks
            self.minLabel = minLabel
            self.maxLabel = maxLabel
        }

        /// **Une échelle qu'on peut vraiment dessiner.**
        ///
        /// Bornes dans l'ordre, pas positif qui tombe juste sur la borne
        /// haute — un curseur qui s'arrête entre deux étiquettes ferait
        /// douter de ce qu'on vient de choisir (``BrandSlider``) —, et pas
        /// plus de crans qu'un pouce n'en distingue. S'il y a des étiquettes,
        /// il en faut une par cran.
        public var isUsable: Bool {
            guard min < max, step > 0, (max - min) % step == 0 else { return false }
            let crans = (max - min) / step + 1
            guard crans >= 2, crans <= 11 else { return false }
            return ticks.isEmpty || ticks.count == crans
        }

        /// Les crans, de la borne basse à la haute.
        public var steps: [Int] { Swift.stride(from: min, through: max, by: step).map { $0 } }
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

    /// `config` tel que le serveur l'écrit : chaque forme y lit ce qui la
    /// regarde, et ignore le reste.
    private struct Config: Codable {
        var options: [Option]?
        var min: Int?
        var max: Int?
        var step: Int?
        var ticks: [String]?
        var minLabel: String?
        var maxLabel: String?
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `config` porte les réglages propres à chaque forme ; illisible, il
        // ne fait pas échouer la question — elle sera simplement jugée
        // indessinable si elle en avait besoin.
        let config = try? container.decodeIfPresent(Config.self, forKey: .config)
        let kind = try container.decode(Kind.self, forKey: .kind)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            kind: kind,
            prompt: try container.decodeIfPresent(String.self, forKey: .prompt),
            placeholder: try container.decodeIfPresent(String.self, forKey: .placeholder),
            isRequired: try container.decodeIfPresent(Bool.self, forKey: .isRequired) ?? false,
            options: config?.options ?? [],
            scale: Self.scale(of: kind, in: config)
        )
    }

    /// L'échelle que cette forme lit dans `config`.
    ///
    /// **Un `rating` se contente de `max`** : ses bornes sont 1 étoile et
    /// `max`, et une campagne n'a pas à écrire le reste pour cinq étoiles.
    /// Un `slider`, lui, dit tout — et des bornes qui manquent rendent la
    /// question indessinable plutôt que devinée.
    private static func scale(of kind: Kind, in config: Config?) -> Scale? {
        switch kind {
        case .rating:
            guard let max = config?.max else { return nil }
            return Scale(min: 1, max: max, step: 1)
        case .slider:
            guard let config, let min = config.min, let max = config.max else { return nil }
            return Scale(
                min: min,
                max: max,
                step: config.step ?? 1,
                ticks: config.ticks ?? [],
                minLabel: config.minLabel,
                maxLabel: config.maxLabel
            )
        case .text, .choice, .unknown:
            return nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(prompt, forKey: .prompt)
        try container.encodeIfPresent(placeholder, forKey: .placeholder)
        try container.encode(isRequired, forKey: .isRequired)
        if !options.isEmpty || scale != nil {
            try container.encode(
                Config(
                    options: options.isEmpty ? nil : options,
                    min: scale?.min,
                    max: scale?.max,
                    step: scale?.step,
                    ticks: (scale?.ticks.isEmpty ?? true) ? nil : scale?.ticks,
                    minLabel: scale?.minLabel,
                    maxLabel: scale?.maxLabel
                ),
                forKey: .config
            )
        }
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
