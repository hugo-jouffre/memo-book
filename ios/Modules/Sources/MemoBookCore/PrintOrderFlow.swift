import Foundation

// Le tunnel de commande du carnet : ses sept étapes, ce qu'elles lisent, et ce
// qu'elles envoient.
//
// **Aucun montant ne se calcule ici.** Le récapitulatif arrive tout fait de
// `POST /v1/memos/:id/orders/quote` : un prix qui s'additionne des deux côtés
// finit par diverger, et c'est le client qui a tort au pire moment — devant la
// personne qui paie. Les `Decimal` de ce fichier ne servent qu'à mettre en
// page ce que le serveur a compté.

// MARK: - Les étapes

/// Les sept étapes, dans l'ordre où on les traverse.
///
/// L'ordre est celui du `rawValue` : c'est lui qui écrit « Étape 3/7 », et
/// c'est lui qui décide du sens de l'animation quand on avance ou qu'on revient.
public enum OrderStep: Int, CaseIterable, Sendable, Hashable, Comparable {
    case start
    case shipping
    case copies
    case speed
    case summary
    case payment
    case confirmation

    public static func < (lhs: OrderStep, rhs: OrderStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Le mot qui suit « Étape 3/7 — ». Celui de la maquette, au mot près.
    public var label: String {
        switch self {
        case .start: "Démarrage"
        case .shipping: "Livraison"
        case .copies: "Exemplaires"
        case .speed: "Rapidité"
        case .summary: "Récapitulatif"
        case .payment: "Paiement"
        case .confirmation: "Confirmation"
        }
    }

    /// « Étape 3/7 - Exemplaires ».
    public var progressLabel: String {
        "Étape \(rawValue + 1)/\(OrderStep.allCases.count) - \(label)"
    }

    /// La dernière étape ne se quitte pas par la flèche de retour : la commande
    /// est passée, revenir sur le paiement n'a plus de sens.
    public var allowsGoingBack: Bool { self != .confirmation && self != .start }
}

// MARK: - L'acheminement

/// Le palier d'acheminement. Deux, parce que c'est ce que l'imprimeur vend.
public enum ShippingSpeed: String, Codable, Sendable, Hashable, CaseIterable {
    case standard
    case express

    public var title: String {
        switch self {
        case .standard: "Standard"
        case .express: "Express"
        }
    }
}

/// Un pays où l'imprimeur livre. **Servi par le serveur**, jamais codé en dur :
/// la liste suit l'imprimeur, elle ne doit pas attendre une version de l'app.
public struct ShippingCountry: Codable, Sendable, Hashable, Identifiable {
    /// ISO 3166-1 alpha-2. C'est la seule forme que la base garde.
    public let code: String
    public let name: String

    public var id: String { code }

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

// MARK: - Les options d'un exemplaire

/// Les quatre options d'**un** exemplaire — « 1er Carnet », « 2e Carnet ».
///
/// Elles pendent de l'exemplaire et non de la commande parce que l'écran laisse
/// offrir le deuxième carnet dans une autre version que le premier.
public struct PrintedCopyOptions: Codable, Sendable, Hashable, Identifiable {
    /// Le rang, à partir de 1.
    public let position: Int

    public var decorationsEnabled: Bool
    public var quizEnabled: Bool
    public var freeZonesEnabled: Bool
    public var crosswordEnabled: Bool

    public var id: Int { position }

    public init(
        position: Int,
        decorationsEnabled: Bool = true,
        quizEnabled: Bool = true,
        freeZonesEnabled: Bool = true,
        crosswordEnabled: Bool = true
    ) {
        self.position = position
        self.decorationsEnabled = decorationsEnabled
        self.quizEnabled = quizEnabled
        self.freeZonesEnabled = freeZonesEnabled
        self.crosswordEnabled = crosswordEnabled
    }

    /// Le même jeu d'options, porté par un autre rang. C'est ce que fait
    /// « appliquer la même version que ton 1er carnet ».
    public func moved(to position: Int) -> PrintedCopyOptions {
        PrintedCopyOptions(
            position: position,
            decorationsEnabled: decorationsEnabled,
            quizEnabled: quizEnabled,
            freeZonesEnabled: freeZonesEnabled,
            crosswordEnabled: crosswordEnabled
        )
    }

    /// Les deux exemplaires portent-ils la même version ? C'est ce qui décide
    /// si le deuxième carnet s'annonce « par défaut » ou comme un choix à part.
    public func matches(_ other: PrintedCopyOptions) -> Bool {
        decorationsEnabled == other.decorationsEnabled
            && quizEnabled == other.quizEnabled
            && freeZonesEnabled == other.freeZonesEnabled
            && crosswordEnabled == other.crosswordEnabled
    }

    /// « 1er Carnet », « 2e Carnet », « 3e Carnet ».
    public var title: String {
        position == 1 ? "1er Carnet" : "\(position)e Carnet"
    }
}

// MARK: - Ce que le tunnel reçoit pour s'ouvrir

/// Tout ce dont les sept étapes ont besoin, en **une** réponse.
///
/// Une seule et non une par étape : le parcours est une seule destination, et
/// le découper ferait apparaître une attente à chaque « Continuer ». Seul le
/// récapitulatif a sa propre route, parce que lui seul dépend de choix qui ne
/// sont pas encore faits.
public struct OrderContext: Codable, Sendable, Hashable {
    public let memoId: String

    /// Le rendu qui partira à l'impression. `nil` quand le carnet n'a jamais
    /// été composé — il n'y a alors rien à commander, et l'écran le dit.
    public let renderId: String?

    /// Le titre du **récit** — « Rome et la Dolce Vita ».
    public let bookTitle: String
    public let pageCount: Int

    /// La carte du voyage, celle de l'accueil. Même modèle, même composant.
    public let trip: Trip
    public let wallet: Wallet

    /// Ce que coûte un exemplaire, et le supplément de l'express. Les deux
    /// arrivent d'emblée pour que les étapes 3 et 4 s'affichent sans attendre.
    public let unitPrice: Decimal
    public let expressPrice: Decimal
    public let standardDays: DayRange
    public let expressDays: DayRange

    /// L'adresse proposée, tirée du profil. Une **amorce**, pas l'adresse de la
    /// commande : celle-ci se fige au moment de commander.
    public let shipping: ShippingAddress
    public let countries: [ShippingCountry]

    public let cards: [PaymentCard]
    public let selectedCardId: String?

    /// Le style du carnet, que chaque exemplaire reprend par défaut.
    public let options: PrintedCopyOptions

    public init(
        memoId: String,
        renderId: String?,
        bookTitle: String,
        pageCount: Int,
        trip: Trip,
        wallet: Wallet,
        unitPrice: Decimal,
        expressPrice: Decimal,
        standardDays: DayRange,
        expressDays: DayRange,
        shipping: ShippingAddress,
        countries: [ShippingCountry],
        cards: [PaymentCard],
        selectedCardId: String?,
        options: PrintedCopyOptions
    ) {
        self.memoId = memoId
        self.renderId = renderId
        self.bookTitle = bookTitle
        self.pageCount = pageCount
        self.trip = trip
        self.wallet = wallet
        self.unitPrice = unitPrice
        self.expressPrice = expressPrice
        self.standardDays = standardDays
        self.expressDays = expressDays
        self.shipping = shipping
        self.countries = countries
        self.cards = cards
        self.selectedCardId = selectedCardId
        self.options = options
    }

    /// Le délai annoncé pour un palier : « 5 à 7 jours ouvrés ».
    public func days(for speed: ShippingSpeed) -> DayRange {
        switch speed {
        case .standard: standardDays
        case .express: expressDays
        }
    }
}

/// Deux bornes plutôt qu'une date : un imprimeur annonce un délai, pas un
/// rendez-vous.
public struct DayRange: Codable, Sendable, Hashable {
    public let min: Int
    public let max: Int

    public init(min: Int, max: Int) {
        self.min = min
        self.max = max
    }

    /// « 5 à 7 jours ouvrés », ou « 3 jours ouvrés » quand les bornes se
    /// rejoignent — « 3 à 3 jours » ne se dit pas.
    public var label: String {
        min == max ? "\(max) jours ouvrés" : "\(min) à \(max) jours ouvrés"
    }

    /// « Dans 5 à 7 jours », pour l'écran de confirmation.
    public var deliveryLabel: String {
        min == max ? "Dans \(max) jours" : "Dans \(min) à \(max) jours"
    }
}

// MARK: - Le récapitulatif

/// Une ligne du récapitulatif : un libellé, parfois un détail, un montant.
public struct OrderQuoteLine: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let label: String
    /// « x2 », posé entre le libellé et le montant. `nil` la plupart du temps.
    public let detail: String?
    public let amount: Decimal

    public init(id: String, label: String, detail: String? = nil, amount: Decimal) {
        self.id = id
        self.label = label
        self.detail = detail
        self.amount = amount
    }
}

/// Un groupe de lignes et son sous-total. La maquette en pose deux.
public struct OrderQuoteGroup: Codable, Sendable, Hashable {
    public let lines: [OrderQuoteLine]
    public let subtotal: Decimal

    public init(lines: [OrderQuoteLine], subtotal: Decimal) {
        self.lines = lines
        self.subtotal = subtotal
    }
}

/// Ce que la cagnotte retire du montant dû.
///
/// Le montant est **positif** : c'est l'écran qui pose le signe moins, comme il
/// pose l'euro.
public struct OrderDeduction: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let label: String
    public let amount: Decimal

    public init(id: String, label: String, amount: Decimal) {
        self.id = id
        self.label = label
        self.amount = amount
    }

    /// Les versements d'abonnement portent le lime, les dons le bleu — les deux
    /// aplats de la maquette, et les deux natures de ``WalletEntryKind``.
    public var isFromSubscription: Bool { id == "subscription" }
}

/// Le récapitulatif complet, tel que le serveur l'a compté.
public struct OrderQuote: Codable, Sendable, Hashable {
    public let bookTitle: String
    public let pageCount: Int
    public let copies: Int
    public let shippingSpeed: ShippingSpeed
    public let unitPrice: Decimal

    /// Ce que coûte **un** carnet : papier, couverture, reliure.
    public let book: OrderQuoteGroup
    /// Les exemplaires et l'acheminement.
    public let fulfilment: OrderQuoteGroup

    public let deductions: [OrderDeduction]
    public let total: Decimal

    public let estimatedMinDays: Int
    public let estimatedMaxDays: Int

    public init(
        bookTitle: String,
        pageCount: Int,
        copies: Int,
        shippingSpeed: ShippingSpeed,
        unitPrice: Decimal,
        book: OrderQuoteGroup,
        fulfilment: OrderQuoteGroup,
        deductions: [OrderDeduction],
        total: Decimal,
        estimatedMinDays: Int,
        estimatedMaxDays: Int
    ) {
        self.bookTitle = bookTitle
        self.pageCount = pageCount
        self.copies = copies
        self.shippingSpeed = shippingSpeed
        self.unitPrice = unitPrice
        self.book = book
        self.fulfilment = fulfilment
        self.deductions = deductions
        self.total = total
        self.estimatedMinDays = estimatedMinDays
        self.estimatedMaxDays = estimatedMaxDays
    }

    public var estimatedDays: DayRange {
        DayRange(min: estimatedMinDays, max: estimatedMaxDays)
    }

    /// La cagnotte couvre tout : il n'y a plus rien à payer. L'étape 6 le dit
    /// au lieu de présenter une carte pour un débit de zéro.
    public var isFullyCovered: Bool { total <= 0 }
}

// MARK: - Ce qu'on envoie

/// Ce que les six premières étapes remplissent.
///
/// Un brouillon **local** : rien ne part avant « Payer ». C'est ce qui permet
/// de revenir sur ses choix sans écrire six fois dans la base.
public struct PrintOrderDraft: Sendable, Hashable {
    public var copies: Int
    public var shippingSpeed: ShippingSpeed
    public var shipping: ShippingAddress
    /// Un jeu d'options par exemplaire, dans l'ordre des rangs.
    public var copyOptions: [PrintedCopyOptions]
    public var paymentCardId: String?
    /// Apple Pay a été choisi plutôt qu'une carte enregistrée.
    public var usesApplePay: Bool

    public init(
        copies: Int = 1,
        shippingSpeed: ShippingSpeed = .standard,
        shipping: ShippingAddress,
        copyOptions: [PrintedCopyOptions] = [],
        paymentCardId: String? = nil,
        usesApplePay: Bool = false
    ) {
        self.copies = copies
        self.shippingSpeed = shippingSpeed
        self.shipping = shipping
        self.copyOptions = copyOptions
        self.paymentCardId = paymentCardId
        self.usesApplePay = usesApplePay
    }

    /// L'adresse est-elle complète ? C'est ce qui allume « Continuer » à
    /// l'étape 2. La deuxième ligne est facultative — beaucoup d'adresses n'en
    /// ont pas, et en exiger une bloquerait tout le monde.
    public var hasCompleteAddress: Bool {
        !shipping.name.trimmed.isEmpty
            && !shipping.line1.trimmed.isEmpty
            && !shipping.postalCode.trimmed.isEmpty
            && !shipping.city.trimmed.isEmpty
            && !shipping.country.trimmed.isEmpty
    }

    /// Un moyen de paiement a-t-il été choisi ? C'est ce qui allume « Payer ».
    public var hasPaymentMethod: Bool { usesApplePay || paymentCardId != nil }

    /// Ramène la liste d'options à `copies` entrées, en recopiant celles du
    /// premier exemplaire pour tout rang qui vient d'apparaître.
    ///
    /// C'est la promesse de l'écran — « Par défaut, nous appliquons la même
    /// version que ton 1er carnet » — tenue par le modèle plutôt que par la vue.
    public mutating func alignCopyOptions(defaults: PrintedCopyOptions) {
        let first = copyOptions.first ?? defaults
        copyOptions = (1...max(copies, 1)).map { position in
            copyOptions.first { $0.position == position } ?? first.moved(to: position)
        }
    }

    /// Change une option d'un exemplaire.
    ///
    /// Toucher au **premier** carnet emmène avec lui tous ceux qui portaient
    /// encore sa version : c'est ce que « par défaut, la même version que ton
    /// 1er carnet » veut dire, et ne pas le faire laisserait le 2e carnet figé
    /// sur un réglage qu'on vient d'abandonner.
    ///
    /// Les exemplaires **déjà détachés** ne bougent pas : quelqu'un qui a
    /// choisi une version différente ne doit pas la voir se faire écraser.
    public mutating func setOption(
        _ option: PrintedCopyOption,
        to isOn: Bool,
        forCopyAt position: Int
    ) {
        guard let index = copyOptions.firstIndex(where: { $0.position == position }) else { return }

        let before = copyOptions[index]
        option.apply(isOn, to: &copyOptions[index])

        guard position == 1 else { return }
        let after = copyOptions[index]
        for other in copyOptions.indices where other != index {
            if copyOptions[other].matches(before) {
                copyOptions[other] = after.moved(to: copyOptions[other].position)
            }
        }
    }

    /// L'exemplaire suit-il encore la version du premier ?
    ///
    /// Le premier se suit lui-même : c'est la référence, la question n'a pas de
    /// sens pour lui et `true` est la réponse qui n'affiche pas de bouton de
    /// détachement sur la référence elle-même.
    public func followsFirstCopy(_ position: Int) -> Bool {
        guard position != 1,
            let first = copyOptions.first,
            let copy = copyOptions.first(where: { $0.position == position })
        else { return true }
        return copy.matches(first)
    }

    /// « Choisir une version différente du 1er carnet », et son retour.
    public mutating func setFollowsFirstCopy(_ follows: Bool, forCopyAt position: Int) {
        guard let first = copyOptions.first,
            let index = copyOptions.firstIndex(where: { $0.position == position }),
            position != 1
        else { return }

        if follows {
            copyOptions[index] = first.moved(to: position)
        } else if copyOptions[index].matches(first) {
            // Détacher sans rien changer laisserait deux carnets identiques et
            // un écran qui prétend le contraire. On ouvre donc sur une
            // différence lisible : le carnet offert se passe des quiz.
            copyOptions[index].quizEnabled.toggle()
        }
    }
}

/// Les quatre options d'un exemplaire, en tant que **champ qu'on désigne**.
///
/// Une énumération plutôt qu'un `WritableKeyPath` exposé : la vue nomme une
/// option, elle n'écrit pas dans la structure.
public enum PrintedCopyOption: String, CaseIterable, Sendable, Hashable, Identifiable {
    case decorations
    case quiz
    case freeZones
    case crossword

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .decorations: BookCopy.Order.Copies.decorations
        case .quiz: BookCopy.Order.Copies.quiz
        case .freeZones: BookCopy.Order.Copies.freeZones
        case .crossword: BookCopy.Order.Copies.crossword
        }
    }

    public func value(in options: PrintedCopyOptions) -> Bool {
        switch self {
        case .decorations: options.decorationsEnabled
        case .quiz: options.quizEnabled
        case .freeZones: options.freeZonesEnabled
        case .crossword: options.crosswordEnabled
        }
    }

    fileprivate func apply(_ isOn: Bool, to options: inout PrintedCopyOptions) {
        switch self {
        case .decorations: options.decorationsEnabled = isOn
        case .quiz: options.quizEnabled = isOn
        case .freeZones: options.freeZonesEnabled = isOn
        case .crossword: options.crosswordEnabled = isOn
        }
    }
}

/// Paramètres d'une commande d'impression, tels qu'ils partent au serveur.
public struct NewPrintOrderRequest: Encodable, Sendable, Hashable {
    public var renderId: String
    public var copies: Int
    public var shippingSpeed: ShippingSpeed
    public var shipping: ShippingAddress
    public var copyOptions: [PrintedCopyOptions]
    public var paymentCardId: String?

    public init(
        renderId: String,
        copies: Int,
        shippingSpeed: ShippingSpeed,
        shipping: ShippingAddress,
        copyOptions: [PrintedCopyOptions],
        paymentCardId: String?
    ) {
        self.renderId = renderId
        self.copies = copies
        self.shippingSpeed = shippingSpeed
        self.shipping = shipping
        self.copyOptions = copyOptions
        self.paymentCardId = paymentCardId
    }

    public init(renderId: String, draft: PrintOrderDraft) {
        self.init(
            renderId: renderId,
            copies: draft.copies,
            shippingSpeed: draft.shippingSpeed,
            shipping: draft.shipping,
            copyOptions: draft.copyOptions,
            // Apple Pay n'enregistre aucune carte : la commande n'en porte
            // alors aucune, et c'est le paiement qui dira par quoi elle est
            // passée.
            paymentCardId: draft.usesApplePay ? nil : draft.paymentCardId
        )
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
