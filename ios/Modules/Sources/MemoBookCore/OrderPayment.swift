import Foundation

/// Ce que le serveur rend quand une commande est enregistrée : la commande, et
/// par quel chemin elle se règle.
///
/// **Deux objets et non un**, parce qu'ils ne vivent pas au même rythme. La
/// commande est un enregistrement durable, qu'on relira demain dans l'historique
/// du carnet. Le paiement est un aller-retour qui ne vaut que pour cette
/// minute-là : son `clientSecret` n'ouvre qu'une intention, et une fois la
/// feuille fermée il ne sert plus à rien. Les séparer ici garantit qu'aucun
/// écran ne pourra ranger l'un à côté de l'autre et garder le second.
public struct PlacedPrintOrder: Decodable, Sendable, Hashable {
    public let order: PrintOrder
    public let payment: OrderPayment

    public init(order: PrintOrder, payment: OrderPayment) {
        self.order = order
        self.payment = payment
    }

    private enum CodingKeys: String, CodingKey {
        case payment
    }

    public init(from decoder: any Decoder) throws {
        // La commande occupe la racine de la réponse et `payment` est une clé à
        // côté d'elle : on lit donc le même décodeur sous ses deux formes.
        // Redéclarer les vingt champs de ``PrintOrder`` pour les aplatir ici
        // ferait deux listes à tenir d'accord, et c'est celle qu'on oublie.
        order = try PrintOrder(from: decoder)
        payment = try decoder
            .container(keyedBy: CodingKeys.self)
            .decode(OrderPayment.self, forKey: .payment)
    }
}

/// La reprise du paiement d'une commande déjà passée —
/// `POST /v1/orders/:id/payment`. La commande à la racine, comme
/// ``PlacedPrintOrder`` ; `payment` est nul quand il n'y a plus rien à régler :
/// payée, en cours, ou plus un brouillon. L'app relit alors la commande.
public struct ResumedOrderPayment: Decodable, Sendable, Hashable {
    public let order: PrintOrder
    public let payment: OrderPayment?

    public init(order: PrintOrder, payment: OrderPayment?) {
        self.order = order
        self.payment = payment
    }

    private enum CodingKeys: String, CodingKey {
        case payment
    }

    public init(from decoder: any Decoder) throws {
        order = try PrintOrder(from: decoder)
        payment = try decoder
            .container(keyedBy: CodingKeys.self)
            .decodeIfPresent(OrderPayment.self, forKey: .payment)
    }
}

/// Comment une commande se règle — la réponse du serveur, telle quelle.
///
/// On ne la lit jamais champ par champ depuis un écran : ``settlement`` en tire
/// la seule question qui se pose, « faut-il ouvrir une feuille de paiement, et
/// avec quoi ». C'est ce qui évite qu'un écran conclue « rien à payer » d'un
/// `clientSecret` absent, alors que son absence peut aussi vouloir dire que le
/// serveur est mal configuré.
public struct OrderPayment: Decodable, Sendable, Hashable {
    // **Plus de `paidFromWallet`** (Hugo, 06/10/2026, T230) : la cagnotte qui
    // pouvait tout couvrir est partie, et avec elle la commande réglée sans
    // feuille. Une commande se paie par Stripe, toujours.

    /// Ce qui est à régler par carte.
    public let amountCents: Int
    public let currency: String

    /// Absents seulement quand le serveur n'a pas ses clés Stripe — voir
    /// ``OrderSettlement/unavailable``.
    public let clientSecret: String?
    public let publishableKey: String?

    /// Les cartes du compte, pour la feuille — voir ``PaymentIntentTicket``.
    public let customerId: String?
    public let ephemeralKeySecret: String?

    /// Apple Pay, quand le serveur le propose — voir ``PaymentIntentTicket``.
    public let applePayMerchantId: String?

    public init(
        amountCents: Int,
        currency: String,
        clientSecret: String? = nil,
        publishableKey: String? = nil,
        customerId: String? = nil,
        ephemeralKeySecret: String? = nil,
        applePayMerchantId: String? = nil
    ) {
        self.amountCents = amountCents
        self.currency = currency
        self.clientSecret = clientSecret
        self.publishableKey = publishableKey
        self.customerId = customerId
        self.ephemeralKeySecret = ephemeralKeySecret
        self.applePayMerchantId = applePayMerchantId
    }

    /// Ce qu'il reste à faire pour que la commande soit payée.
    public var settlement: OrderSettlement {
        // Une chaîne vide, et pas seulement `nil` : côté serveur,
        // `STRIPE_PUBLISHABLE_KEY` vaut `""` quand elle n'est pas configurée, et
        // c'est cette valeur-là qui arrive jusqu'ici. Une feuille montée sur une
        // clé vide échoue au moment de payer, après Face ID.
        guard let clientSecret, !clientSecret.isEmpty,
              let publishableKey, !publishableKey.isEmpty
        else {
            return .unavailable
        }

        return .card(
            PaymentIntentTicket(
                clientSecret: clientSecret,
                publishableKey: publishableKey,
                amountCents: amountCents,
                currency: currency,
                customerId: customerId,
                ephemeralKeySecret: ephemeralKeySecret,
                applePayMerchantId: applePayMerchantId
            )
        )
    }
}

/// Par où passe le règlement d'une commande.
public enum OrderSettlement: Sendable, Hashable {
    /// Il reste à payer, et voici de quoi ouvrir la feuille.
    case card(PaymentIntentTicket)

    /// Il reste à payer, et le serveur n'a pas donné de quoi le faire.
    ///
    /// **Un cas de configuration, pas un cas d'usage.** Il n'arrive que si
    /// `STRIPE_SECRET_KEY` ou `STRIPE_PUBLISHABLE_KEY` manquent à l'API
    /// déployée. La commande existe alors en brouillon et n'est pas payée : il
    /// faut le dire, et surtout ne pas afficher une confirmation.
    case unavailable
}
