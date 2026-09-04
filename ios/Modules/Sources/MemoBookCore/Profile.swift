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

/// L'abonnement hebdomadaire, tel que la feuille le présente.
public struct Subscription: Codable, Sendable, Hashable {
    public let weeklyPrice: Decimal
    public var isActive: Bool

    public init(weeklyPrice: Decimal, isActive: Bool = false) {
        self.weeklyPrice = weeklyPrice
        self.isActive = isActive
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

/// Tout ce que l'écran de profil montre, d'un seul tenant.
public struct TravellerProfile: Codable, Sendable, Hashable {
    public var fullName: String
    public var email: String?
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

    public init(
        fullName: String,
        email: String? = nil,
        phoneNumber: String? = nil,
        avatarUrl: URL? = nil,
        address: PostalAddress = PostalAddress(),
        wantsNewsletter: Bool = false,
        walletBalance: Decimal = 0,
        cards: [PaymentCard] = [],
        selectedCardId: String? = nil,
        connectors: [Connector] = [],
        subscription: Subscription = Subscription(weeklyPrice: 0),
        orders: [OrderTracking] = []
    ) {
        self.fullName = fullName
        self.email = email
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
    }

    /// La carte affichée sur la ligne « Carte bancaire enregistrée ». Celle qui
    /// est sélectionnée, ou la première à défaut : la ligne ne reste pas vide
    /// parce qu'aucun choix n'a encore été fait.
    public var selectedCard: PaymentCard? {
        cards.first { $0.id == selectedCardId } ?? cards.first
    }

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
