import Foundation

// Ce que l'écran de profil affiche, modélisé comme le back-end le renverra.
//
// Même principe que ``HomeFeed`` : la vue ne sait rien du contenu, elle ne sait
// que le dessiner. Aucune route n'existe encore — l'écran lit un
// ``TravellerProfile`` fourni par une closure, aujourd'hui le jeu d'essai.

/// L'adresse où le carnet imprimé sera livré.
public struct PostalAddress: Codable, Sendable, Hashable {
    public var street: String
    public var postalCode: String
    public var city: String
    /// Nom du pays tel que l'utilisateur l'a saisi. Pas un code ISO : la
    /// maquette montre un champ libre, et l'imprimeur lit une étiquette.
    public var country: String

    public init(street: String = "", postalCode: String = "", city: String = "", country: String = "") {
        self.street = street
        self.postalCode = postalCode
        self.city = city
        self.country = country
    }

    /// Une adresse ne vaut que complète : un colis part avec les quatre lignes
    /// ou ne part pas.
    public var isComplete: Bool {
        [street, postalCode, city, country].allSatisfy { !$0.trimmed.isEmpty }
    }

    /// L'adresse sur une ligne, pour la ligne du profil : « 7 Rue Simon Fryd,
    /// Lyon, France ». Les champs vides sont sautés plutôt que de laisser des
    /// virgules orphelines.
    public var singleLine: String {
        [street, city, country].map(\.trimmed).filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// Une carte enregistrée. **Le numéro complet n'entre jamais dans ce modèle** :
/// l'app n'en garde que les quatre derniers chiffres, le reste appartient au
/// prestataire de paiement.
public struct PaymentCard: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    /// Le nom que l'utilisateur donne à sa carte : « Carte perso ».
    public var label: String
    public let last4: String

    public init(id: String, label: String, last4: String) {
        self.id = id
        self.label = label
        self.last4 = last4
    }

    /// Le numéro masqué de la maquette. Les X sont ceux du dessin, pas des
    /// puces : c'est un gabarit de carte, pas un mot de passe.
    public var maskedNumber: String { "XXXX XXXX XXXX \(last4)" }

    /// « MM/AA », composé au fil de la frappe.
    ///
    /// Le champ ne garde que des chiffres et pose la barre lui-même : on tape
    /// quatre chiffres, on obtient une date. C'est ce qui permet un pavé
    /// **numérique** — un clavier qui porterait la barre oblique porte aussi
    /// tout le reste de la ponctuation, et laisse écrire « 1-2/3 ».
    ///
    /// **La barre s'efface avec le chiffre qui la précède** : elle n'est pas
    /// saisie, elle est déduite des deux premiers chiffres. Effacer le
    /// troisième chiffre la fait donc disparaître toute seule, plutôt que
    /// d'obliger à un second retour arrière sur un caractère qu'on n'a jamais
    /// tapé.
    ///
    /// Elle vit ici, et non dans la feuille qui l'affiche : c'est une règle,
    /// elle se teste sans simulateur.
    public static func formattedExpiry(_ raw: String) -> String {
        let digits = String(raw.filter(\.isNumber).prefix(4))
        guard digits.count > 2 else { return digits }
        return "\(digits.prefix(2))/\(digits.dropFirst(2))"
    }
}

/// Une application tierce que MemoBook peut interroger pour enrichir un carnet.
public struct Connector: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    /// Ce que MemoBook fera de l'accès, en une phrase. C'est le consentement
    /// qui se lit, pas une description marketing.
    public let promise: String
    public var isEnabled: Bool

    /// Nom de l'asset embarqué qui porte le logo de la marque.
    ///
    /// Provisoire : le jour où l'API sert les connecteurs, elle enverra une URL
    /// et ce champ disparaîtra. En attendant, les six logos vivent dans
    /// `MemoBookAssets.xcassets` — ce sont des marques tierces, elles ne se
    /// teintent pas et ne se remplacent pas par une icône MemoBook.
    public let logoAssetName: String?

    public init(
        id: String,
        name: String,
        promise: String,
        isEnabled: Bool = false,
        logoAssetName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.promise = promise
        self.isEnabled = isEnabled
        self.logoAssetName = logoAssetName
    }
}

/// L'abonnement hebdomadaire, tel que les feuilles le présentent.
///
/// **Il ne se résilie pas d'un coup : il s'éteint tout seul.** C'est la promesse
/// que trois des cinq feuilles répètent, et c'est pour ça que ce modèle porte le
/// voyage autant que le prix — sans le voyage, « résiliation automatique à la
/// fin de ton voyage à Rome » n'a rien à écrire.
public struct Subscription: Codable, Sendable, Hashable {
    public let weeklyPrice: Decimal
    public var isActive: Bool

    /// Le voyage qui porte l'abonnement, sous ses deux noms — les feuilles
    /// emploient les deux et ce ne sont pas les mêmes mots.
    ///
    /// La destination se glisse dans une phrase (« à la fin de ton voyage à
    /// **Rome** »), le titre se cite entre guillemets (« ton voyage “**Rome
    /// entre amis**” »). Écrire l'un à la place de l'autre donnerait « à la fin
    /// de ton voyage à Rome entre amis ».
    public var tripDestination: String?
    public var tripTitle: String?

    /// Le jour où l'abonnement s'arrête de lui-même : la fin du voyage.
    ///
    /// C'est de lui que sort le « dans 3 semaines » de la feuille — jamais d'un
    /// nombre écrit à la main quelque part dans une vue.
    public var endsOn: Date?

    /// Le jour où il a été résilié à la main, s'il l'a été.
    public var cancelledAt: Date?

    public init(
        weeklyPrice: Decimal,
        isActive: Bool = false,
        tripDestination: String? = nil,
        tripTitle: String? = nil,
        endsOn: Date? = nil,
        cancelledAt: Date? = nil
    ) {
        self.weeklyPrice = weeklyPrice
        self.isActive = isActive
        self.tripDestination = tripDestination
        self.tripTitle = tripTitle
        self.endsOn = endsOn
        self.cancelledAt = cancelledAt
    }
}

/// Pourquoi on s'en va. Les quatre raisons de la maquette, dans son ordre.
///
/// Une énumération et non une chaîne libre : la réponse part vers un compteur
/// côté serveur, et un compteur ne sait rien faire de quatre orthographes de la
/// même raison.
public enum SubscriptionCancellationReason: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case unused
    case tooExpensive
    case storiesFinished
    case wasTesting

    public var id: String { rawValue }

    /// Figma les saisit avec l'apostrophe droite, alors que le reste de l'app
    /// emploie la typographique ; elles sont corrigées ici comme le reste de la
    /// copie de l'abonnement (D12, T66).
    public var label: String {
        switch self {
        case .unused: "Je ne l’utilise plus"
        case .tooExpensive: "C’est un peu cher"
        case .storiesFinished: "J’ai fini mes récits"
        case .wasTesting: "C’était pour tester"
        }
    }
}

/// Une commande d'impression en cours d'acheminement.
public struct OrderTracking: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    /// Fourchette de livraison, en jours. Deux bornes plutôt qu'une date : un
    /// imprimeur annonce un délai, pas un rendez-vous.
    public let minimumDays: Int
    public let maximumDays: Int
    public let copies: Int
    public let pageCount: Int
    public let coverImageUrl: URL?

    public init(
        id: String,
        minimumDays: Int,
        maximumDays: Int,
        copies: Int,
        pageCount: Int,
        coverImageUrl: URL? = nil
    ) {
        self.id = id
        self.minimumDays = minimumDays
        self.maximumDays = maximumDays
        self.copies = copies
        self.pageCount = pageCount
        self.coverImageUrl = coverImageUrl
    }
}

/// Le voyage en cours, tel que la carte de chiffres du profil le montre : un
/// identifiant pour y aller, et ses bornes pour l'annoncer.
///
/// **Il n'est pas stocké.** Le serveur le déduit des voyages du compte — voir
/// `serializeProfileStats`. C'est un résumé, pas une seconde vérité à tenir à
/// jour à côté de ``Trip``.
public struct CurrentTrip: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let startDate: Date?
    public let endDate: Date?

    public init(id: String, startDate: Date? = nil, endDate: Date? = nil) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
    }
}

/// Tout ce que l'écran de profil montre, d'un seul tenant.
public struct TravellerProfile: Codable, Sendable, Hashable {
    public var fullName: String
    public var email: String?

    /// Par quel fournisseur la session a été ouverte, quand ce n'est pas par
    /// mot de passe.
    ///
    /// Il décide d'une chose et d'une seule : **l'adresse ne se corrige pas**.
    /// Elle appartient au compte Apple ou Google, et la changer ici ne ferait
    /// que la désaccorder de celle avec laquelle on se reconnecte.
    public var signInProvider: AuthProvider?
    public var phoneNumber: String?
    public var avatarUrl: URL?
    public var address: PostalAddress
    public var wantsNewsletter: Bool
    /// La cagnotte, en euros. `Decimal` et non `Double` : c'est de l'argent.
    public var walletBalance: Decimal
    public var cards: [PaymentCard]
    public var selectedCardId: String?
    public var connectors: [Connector]
    public var subscription: Subscription
    public var orders: [OrderTracking]

    /// Les étapes offertes à l'ouverture du compte, et celles qui restent.
    ///
    /// Le même couple que ``Traveller``, et la même règle : `nil` quand le
    /// compte n'a pas de quota — un abonné. C'est lui qui porte la pastille du
    /// haut de l'écran, comme il porte celle de l'accueil.
    public var offeredSteps: Int?
    public var remainingSteps: Int?

    /// Combien de voyages en tout. La carte de chiffres l'affiche, et c'est
    /// tout ce qu'elle en fait.
    public var tripCount: Int

    /// Le voyage du moment, s'il y en a un.
    public var currentTrip: CurrentTrip?

    public init(
        fullName: String,
        email: String? = nil,
        signInProvider: AuthProvider? = nil,
        phoneNumber: String? = nil,
        avatarUrl: URL? = nil,
        address: PostalAddress = PostalAddress(),
        wantsNewsletter: Bool = false,
        walletBalance: Decimal = 0,
        cards: [PaymentCard] = [],
        selectedCardId: String? = nil,
        connectors: [Connector] = [],
        subscription: Subscription = Subscription(weeklyPrice: 0),
        orders: [OrderTracking] = [],
        offeredSteps: Int? = nil,
        remainingSteps: Int? = nil,
        tripCount: Int = 0,
        currentTrip: CurrentTrip? = nil
    ) {
        self.fullName = fullName
        self.email = email
        self.signInProvider = signInProvider
        self.phoneNumber = phoneNumber
        self.avatarUrl = avatarUrl
        self.address = address
        self.wantsNewsletter = wantsNewsletter
        self.walletBalance = walletBalance
        self.cards = cards
        self.selectedCardId = selectedCardId
        self.connectors = connectors
        self.subscription = subscription
        self.orders = orders
        self.offeredSteps = offeredSteps
        self.remainingSteps = remainingSteps
        self.tripCount = tripCount
        self.currentTrip = currentTrip
    }

    /// Décodage tolérant sur les quatre champs de l'abonnement freemium.
    ///
    /// Même raison que ``Entry`` : une app déjà installée ne doit pas cesser
    /// d'afficher un profil parce qu'un serveur plus ancien ne connaît pas
    /// encore `tripCount`. Le reste garde la synthèse.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        fullName = try container.decode(String.self, forKey: .fullName)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        signInProvider = try container.decodeIfPresent(AuthProvider.self, forKey: .signInProvider)
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        avatarUrl = try container.decodeIfPresent(URL.self, forKey: .avatarUrl)
        address = try container.decode(PostalAddress.self, forKey: .address)
        wantsNewsletter = try container.decode(Bool.self, forKey: .wantsNewsletter)
        walletBalance = try container.decode(Decimal.self, forKey: .walletBalance)
        cards = try container.decode([PaymentCard].self, forKey: .cards)
        selectedCardId = try container.decodeIfPresent(String.self, forKey: .selectedCardId)
        connectors = try container.decode([Connector].self, forKey: .connectors)
        subscription = try container.decode(Subscription.self, forKey: .subscription)
        orders = try container.decode([OrderTracking].self, forKey: .orders)

        offeredSteps = try container.decodeIfPresent(Int.self, forKey: .offeredSteps)
        remainingSteps = try container.decodeIfPresent(Int.self, forKey: .remainingSteps)
        tripCount = try container.decodeIfPresent(Int.self, forKey: .tripCount) ?? 0
        currentTrip = try container.decodeIfPresent(CurrentTrip.self, forKey: .currentTrip)
    }

    /// La carte affichée sur la ligne « Carte bancaire enregistrée ». Celle qui
    /// est sélectionnée, ou la première à défaut : la ligne ne reste pas vide
    /// parce qu'aucun choix n'a encore été fait.
    public var selectedCard: PaymentCard? {
        cards.first { $0.id == selectedCardId } ?? cards.first
    }

    /// `true` quand l'adresse vient d'un fournisseur tiers et ne peut donc pas
    /// être corrigée depuis l'app.
    public var isEmailManagedByProvider: Bool { signInProvider != nil }

    /// **La** question qui départage les deux profils de la maquette : celui
    /// qui paie, et celui qui use ses étapes offertes.
    ///
    /// Elle se lit sur l'abonnement et non sur le quota d'étapes : un compte
    /// peut très bien n'avoir ni l'un ni l'autre — un ancien abonné qui a
    /// résilié — et il faut alors lui reproposer l'abonnement, pas lui
    /// inventer des étapes.
    public var isSubscriber: Bool { subscription.isActive }

    /// Une ou deux initiales, quand la photo manque. Même règle que
    /// ``Companion``.
    public var initials: String {
        let words = fullName.split(separator: " ").prefix(2)
        return words.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Ce qu'on corrige depuis l'écran de profil, envoyé en `PATCH`.
///
/// Même construction que ``EntryEdit``, et pour la même raison : le double
/// optionnel distingue trois cas que le serveur traite différemment. Une
/// valeur remplace, `.some(nil)` efface, et l'absence de clé ne touche à rien.
/// « Pas de téléphone » et « un téléphone vide » ne sont pas la même chose.
public struct ProfileEdit: Encodable, Sendable, Hashable {
    public var firstName: String??
    public var lastName: String??
    public var phoneNumber: String??
    public var wantsNewsletter: Bool?
    public var address: PostalAddress?

    public init(
        firstName: String?? = nil,
        lastName: String?? = nil,
        phoneNumber: String?? = nil,
        wantsNewsletter: Bool? = nil,
        address: PostalAddress? = nil
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.phoneNumber = phoneNumber
        self.wantsNewsletter = wantsNewsletter
        self.address = address
    }

    private enum CodingKeys: String, CodingKey {
        case firstName, lastName, phoneNumber, wantsNewsletter, address
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let firstName { try container.encode(firstName, forKey: .firstName) }
        if let lastName { try container.encode(lastName, forKey: .lastName) }
        if let phoneNumber { try container.encode(phoneNumber, forKey: .phoneNumber) }
        if let wantsNewsletter {
            try container.encode(wantsNewsletter, forKey: .wantsNewsletter)
        }
        if let address { try container.encode(address, forKey: .address) }
    }
}
