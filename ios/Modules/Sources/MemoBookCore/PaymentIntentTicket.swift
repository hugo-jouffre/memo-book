import Foundation

/// Ce que le serveur donne à l'app pour ouvrir une feuille de paiement.
///
/// **Rien de secret ici, et c'est le point.** Le `clientSecret` n'ouvre qu'une
/// intention, celle-là et pas une autre ; la clé publique est faite pour partir
/// dans un binaire. La clé secrète, elle, ne quitte jamais le serveur — c'est
/// lui qui a décidé du montant, et l'app ne peut pas le contredire.
///
/// C'est pour ça que le montant voyage aussi : il ne sert **qu'à l'affichage**.
/// Le débit, lui, est celui que le serveur a posé sur l'intention.
public struct PaymentIntentTicket: Codable, Sendable, Hashable {
    public let clientSecret: String
    public let publishableKey: String
    public let amountCents: Int
    public let currency: String

    /// **Le client Stripe du compte, et la clé qui ouvre ses cartes** — pour un
    /// court moment, et pour ce client seulement. Avec eux, la feuille montre
    /// les cartes déjà enregistrées, propose d'enregistrer la nouvelle, et
    /// laisse en retirer une. Absents d'un serveur plus ancien : la feuille
    /// s'ouvre alors sans cartes enregistrées, et on paie quand même.
    public let customerId: String?
    public let ephemeralKeySecret: String?

    public init(
        clientSecret: String,
        publishableKey: String,
        amountCents: Int,
        currency: String,
        customerId: String? = nil,
        ephemeralKeySecret: String? = nil
    ) {
        self.clientSecret = clientSecret
        self.publishableKey = publishableKey
        self.amountCents = amountCents
        self.currency = currency
        self.customerId = customerId
        self.ephemeralKeySecret = ephemeralKeySecret
    }

    /// Le montant tel qu'on l'écrit à l'écran — « 107,88 € ».
    public var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.uppercased()
        formatter.locale = Locale(identifier: "fr_FR")
        let euros = NSDecimalNumber(value: amountCents).dividing(by: 100)
        return formatter.string(from: euros) ?? "\(euros) \(currency.uppercased())"
    }
}

/// Ce qui ouvre la feuille « Moyens de paiement » de Stripe, depuis le profil :
/// le client du compte et une clé éphémère dans la version d'API du SDK.
public struct CustomerPaymentKey: Decodable, Sendable, Hashable {
    public let customerId: String
    public let ephemeralKeySecret: String
    public let publishableKey: String

    public init(customerId: String, ephemeralKeySecret: String, publishableKey: String) {
        self.customerId = customerId
        self.ephemeralKeySecret = ephemeralKeySecret
        self.publishableKey = publishableKey
    }
}
