import Foundation

// La cagnotte : ce qu'il y a dessus, d'où ça vient, et ce que le carnet coûtera.
//
// **Elle appartient au compte, pas au voyage.** Deux co-voyageurs ont chacun la
// leur (voir ``Companion``), et c'est la même somme qu'on lit dans le profil et
// dans les paramètres d'un voyage — d'où le fait qu'il n'y ait qu'un seul modèle
// ici. Ce qui change d'un écran à l'autre, c'est le **voyage qu'on finance**, et
// c'est ``Wallet/tripTitle`` qui le porte.
//
// Le côté serveur est un **registre en ajout seul** (`wallet_entries`) en
// centimes entiers, dont le solde du compte n'est qu'un cache. Cette structure
// en est la lecture : des euros en `Decimal`, jamais en `Double`.

/// La nature d'une écriture de cagnotte.
///
/// La liste est fermée côté app mais **tolérante au décodage**, comme
/// ``TripStage`` : une nature ajoutée côté serveur ne fait pas disparaître la
/// ligne de l'historique, elle la laisse simplement sans pastille.
public enum WalletEntryKind: Sendable, Hashable {
    /// Ce qu'un proche a offert. C'est **la** raison d'être de la cagnotte, et
    /// la seule écriture qui porte un nom de personne.
    case gift
    /// Un rechargement encaissé — la part de l'abonnement qui tombe dans la
    /// cagnotte chaque semaine, ou une recharge faite à la main.
    case topup
    /// Le remboursement d'une commande annulée.
    case refund
    /// Ce qu'une impression a prélevé. Négatif, donc.
    case orderPayment
    /// Une correction du support. Toujours motivée par un libellé.
    case adjustment
    case unknown(String)

    /// La pastille qui qualifie la ligne — « DON », « ABONNEMENT ».
    ///
    /// `nil` pour les écritures qui se lisent d'elles-mêmes : un remboursement
    /// ou un paiement portent déjà leur motif dans leur libellé, et une nature
    /// inconnue du serveur n'a rien à annoncer.
    public var badge: String? {
        switch self {
        case .gift: "Don"
        case .topup: "Abonnement"
        case .refund: "Remboursement"
        case .orderPayment: nil
        case .adjustment: nil
        case .unknown: nil
        }
    }

    /// L'écriture vient de quelqu'un d'autre.
    ///
    /// C'est elle qui décide de deux choses à l'écran : la pastille bleue et
    /// l'initiale du prénom plutôt qu'un pictogramme. Et c'est elle aussi qui
    /// alimente le total « offert par tes proches ».
    public var isFromSomeoneElse: Bool {
        if case .gift = self { return true }
        return false
    }
}

extension WalletEntryKind: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self =
            switch raw {
            case "gift": .gift
            case "topup": .topup
            case "refund": .refund
            case "order_payment": .orderPayment
            case "adjustment": .adjustment
            default: .unknown(raw)
            }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .gift: "gift"
        case .topup: "topup"
        case .refund: "refund"
        case .orderPayment: "order_payment"
        case .adjustment: "adjustment"
        case .unknown(let raw): raw
        }
    }
}

/// Une ligne de l'historique de la cagnotte.
public struct WalletEntry: Codable, Sendable, Hashable, Identifiable {
    public let id: String

    /// Le montant, **signé** et en euros : positif au crédit, négatif au débit.
    /// `Decimal` et non `Double` — c'est de l'argent.
    public let amount: Decimal

    public let kind: WalletEntryKind

    /// Qui, ou quoi — « Marie D. », « Abonnement MB ». `nil` quand le serveur
    /// n'a pas de motif à donner ; la ligne se lit alors sur sa seule nature.
    public let label: String?

    public let date: Date

    public init(
        id: String,
        amount: Decimal,
        kind: WalletEntryKind,
        label: String? = nil,
        date: Date
    ) {
        self.id = id
        self.amount = amount
        self.kind = kind
        self.label = label
        self.date = date
    }

    /// Le nom affiché de la ligne. Le libellé du serveur d'abord ; à défaut, ce
    /// que la nature de l'écriture permet d'en dire.
    ///
    /// Jamais vide : une ligne de l'historique sans nom serait un montant
    /// tombé de nulle part, ce qui est exactement ce qu'un registre doit
    /// empêcher.
    public var displayName: String {
        if let label, !label.trimmingCharacters(in: .whitespaces).isEmpty { return label }
        return switch kind {
        case .gift: "Un proche"
        case .topup: "Rechargement"
        case .refund: "Remboursement"
        case .orderPayment: "Commande d’impression"
        case .adjustment, .unknown: "Ajustement"
        }
    }

    /// L'initiale posée dans la pastille, pour un don. Une seule lettre : la
    /// pastille fait 36 pt et « Julie et Tom » y tiendrait mal à deux.
    public var initial: String {
        displayName.first.map { String($0).uppercased() } ?? "?"
    }
}

/// La cagnotte d'un compte, lue depuis l'écran d'un voyage.
public struct Wallet: Codable, Sendable, Hashable {
    /// Le solde disponible, en euros. Il peut valoir zéro — c'est l'état que
    /// l'écran « Cagnotte vide » raconte, et il n'a rien d'anormal.
    public let balance: Decimal

    /// L'historique, **du plus récent au plus ancien**. C'est le serveur qui
    /// ordonne : l'app ne retrie pas, sinon deux écritures du même jour
    /// changeraient de place d'un affichage à l'autre.
    public let entries: [WalletEntry]

    /// Le voyage que cette cagnotte finance — « Rome ». Il ne change pas la
    /// somme, il nomme seulement ce qu'on est en train de payer.
    public let tripTitle: String?

    /// Ce que le carnet fera, au rythme actuel, et ce que ça coûtera.
    ///
    /// Une estimation et non un prix : le carnet n'est pas fini, et son nombre
    /// de pages bouge à chaque souvenir raconté. `nil` quand il n'y a pas encore
    /// assez de matière pour estimer quoi que ce soit — la barre et sa phrase
    /// disparaissent alors plutôt que d'annoncer un chiffre inventé.
    public let estimate: WalletEstimate?

    public init(
        balance: Decimal,
        entries: [WalletEntry] = [],
        tripTitle: String? = nil,
        estimate: WalletEstimate? = nil
    ) {
        self.balance = balance
        self.entries = entries
        self.tripTitle = tripTitle
        self.estimate = estimate
    }

    /// La cagnotte n'a **jamais rien reçu**.
    ///
    /// Le solde ne suffit pas à le dire : une cagnotte qui a servi à payer une
    /// impression retombe à zéro sans être vide pour autant, et son historique
    /// mérite d'être montré. C'est donc l'absence d'écritures qui décide.
    public var isEmpty: Bool { entries.isEmpty }

    /// Ce que les proches ont offert, et ce que l'abonnement a versé. Les deux
    /// pastilles de synthèse, sous l'historique.
    ///
    /// Seuls les **crédits** comptent : un paiement d'impression ne retire pas
    /// rétroactivement un cadeau reçu.
    public var giftedTotal: Decimal {
        entries.filter { $0.kind.isFromSomeoneElse && $0.amount > 0 }.reduce(0) { $0 + $1.amount }
    }

    public var subscriptionTotal: Decimal {
        entries.filter { $0.kind == .topup && $0.amount > 0 }.reduce(0) { $0 + $1.amount }
    }
}

/// Ce que le carnet pèsera et ce qu'il coûtera, au rythme actuel.
public struct WalletEstimate: Codable, Sendable, Hashable {
    public let pageCount: Int

    /// Le coût estimé de l'impression, en euros.
    public let cost: Decimal

    public init(pageCount: Int, cost: Decimal) {
        self.pageCount = pageCount
        self.cost = cost
    }

    /// De 0 à 1 : la part du coût que la cagnotte couvre déjà.
    ///
    /// Bornée des deux côtés, comme ``TripProgress/fraction`` : une cagnotte
    /// plus garnie que le carnet ne coûte ne fait pas déborder sa barre. Et un
    /// coût nul rendrait la fraction indéfinie — on la lit alors comme
    /// « entièrement couvert », qui est la vérité.
    public func coverage(of balance: Decimal) -> Double {
        guard cost > 0 else { return 1 }
        let ratio = (balance / cost) as NSDecimalNumber
        return min(max(ratio.doubleValue, 0), 1)
    }
}
