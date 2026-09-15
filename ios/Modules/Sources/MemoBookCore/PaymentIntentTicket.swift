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

    public init(clientSecret: String, publishableKey: String, amountCents: Int, currency: String) {
        self.clientSecret = clientSecret
        self.publishableKey = publishableKey
        self.amountCents = amountCents
        self.currency = currency
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
