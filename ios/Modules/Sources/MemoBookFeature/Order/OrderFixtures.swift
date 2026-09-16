import Foundation
import MemoBookCore

// Jeu d'essai du tunnel de commande.
//
// Il porte les chiffres de la maquette — 80 pages estimées — pour que les
// aperçus SwiftUI soient comparables à Figma sans serveur. La cagnotte, elle,
// part **vide** : c'est l'état d'un compte neuf, et un jeu d'essai qui
// annoncerait une déduction que le registre n'a pas donnerait un total faux dès
// qu'on le compare au serveur. Les montants du récapitulatif, eux, se recomposent à partir du
// même barème que le serveur : un jeu d'essai qui annoncerait d'autres totaux
// ne montrerait pas l'écran qu'on livre.

extension OrderContext {
    public static var fixture: OrderContext { fixture(pageCount: 80) }

    public static func fixture(pageCount: Int) -> OrderContext {
        OrderContext(
            memoId: "trip-rome",
            renderId: "render-rome",
            bookTitle: "Rome et la Dolce Vita",
            pageCount: pageCount,
            trip: Trip(
                id: "trip-rome",
                title: "Rome entre frère et sœur",
                destination: Destination(name: "Italie", countryCode: "IT", city: "Rome"),
                stage: .past,
                startDate: .fixture(26, 8, 2026),
                endDate: .fixture(15, 9, 2026),
                stats: TripStats(dayCount: 10, distanceKilometres: 37, photoCount: 24),
                companions: [Companion(id: "c-1", name: "Léa Marchand")],
                progress: TripProgress(memoryCount: 24, pageCount: pageCount, targetPageCount: pageCount),
                isPrintable: true
            ),
            wallet: .fixture,
            unitPrice: OrderPricing.unitPrice(pages: pageCount),
            expressPrice: OrderPricing.express,
            standardDays: DayRange(min: 5, max: 7),
            expressDays: DayRange(min: 2, max: 3),
            shipping: ShippingAddress(
                name: "Clara Perrin",
                line1: "7 rue Simon Fryd",
                postalCode: "69007",
                city: "Lyon",
                country: "FR"
            ),
            countries: ShippingCountry.fixtures,
            cards: [
                PaymentCard(id: "card-business", label: "Carte business", last4: "3246"),
                PaymentCard(id: "card-perso", label: "Carte perso", last4: "1820"),
            ],
            selectedCardId: "card-perso",
            options: PrintedCopyOptions(position: 1)
        )
    }

    /// Le carnet n'a jamais été composé : l'étape 1 n'a rien à commander.
    public static var notComposedFixture: OrderContext {
        let base = OrderContext.fixture
        return OrderContext(
            memoId: base.memoId,
            renderId: nil,
            bookTitle: base.bookTitle,
            pageCount: base.pageCount,
            trip: base.trip,
            wallet: base.wallet,
            unitPrice: base.unitPrice,
            expressPrice: base.expressPrice,
            standardDays: base.standardDays,
            expressDays: base.expressDays,
            shipping: base.shipping,
            countries: base.countries,
            cards: base.cards,
            selectedCardId: base.selectedCardId,
            options: base.options
        )
    }
}

extension ShippingCountry {
    static let fixtures: [ShippingCountry] = [
        ShippingCountry(code: "FR", name: "France"),
        ShippingCountry(code: "BE", name: "Belgique"),
        ShippingCountry(code: "CH", name: "Suisse"),
        ShippingCountry(code: "LU", name: "Luxembourg"),
        ShippingCountry(code: "DE", name: "Allemagne"),
        ShippingCountry(code: "ES", name: "Espagne"),
        ShippingCountry(code: "IT", name: "Italie"),
        ShippingCountry(code: "PT", name: "Portugal"),
        ShippingCountry(code: "NL", name: "Pays-Bas"),
        ShippingCountry(code: "IE", name: "Irlande"),
        ShippingCountry(code: "AT", name: "Autriche"),
        ShippingCountry(code: "GB", name: "Royaume-Uni"),
        ShippingCountry(code: "CA", name: "Canada"),
        ShippingCountry(code: "US", name: "États-Unis"),
    ]
}

/// Le barème, recopié du serveur pour les seuls aperçus.
///
/// ⚠️ **Ce n'est pas la source de vérité** — `services/printPricing.ts` l'est,
/// et c'est lui que l'app interroge en vrai. Ces constantes n'existent que pour
/// que les aperçus SwiftUI montrent des totaux cohérents entre eux.
enum OrderPricing {
    static let paperPerPage = Decimal(132) / 100
    static let cover = Decimal(1490) / 100
    static let binding = Decimal(900) / 100
    static let express = Decimal(990) / 100

    static func unitPrice(pages: Int) -> Decimal {
        Decimal(max(pages, 1)) * paperPerPage + cover + binding
    }
}

extension OrderQuote {
    public static var fixture: OrderQuote { fixture(copies: 2, speed: .standard) }

    public static func fixture(
        copies: Int,
        speed: ShippingSpeed,
        pageCount: Int = 80,
        // Vide par défaut, comme ``Wallet/fixture`` : un récapitulatif qui
        // annoncerait une déduction que la cagnotte n'a pas serait un total
        // faux dès qu'on le compare au serveur.
        walletBalance: Decimal = 0
    ) -> OrderQuote {
        let unit = OrderPricing.unitPrice(pages: pageCount)
        let items = unit * Decimal(copies)
        let shipping = speed == .express ? OrderPricing.express : 0
        let due = items + shipping

        // La cagnotte ne rend pas la monnaie : elle est plafonnée au montant dû.
        let applied = min(walletBalance, due)
        // La répartition du serveur, rejouée : les dons d'un côté, les
        // versements d'abonnement de l'autre.
        let subscription = min(applied, Decimal(199) / 100 * 4)
        let gifts = applied - subscription

        return OrderQuote(
            bookTitle: "Rome et la Dolce Vita",
            pageCount: pageCount,
            copies: copies,
            shippingSpeed: speed,
            unitPrice: unit,
            book: OrderQuoteGroup(
                lines: [
                    OrderQuoteLine(
                        id: "book",
                        label: BookCopy.Order.Summary.bookLine(pages: pageCount),
                        amount: unit
                    )
                ],
                subtotal: unit
            ),
            specifications: [
                "80g. non couché ivoire",
                "Couverture rigide & matte",
                "Livre broché",
            ],
            fulfilment: OrderQuoteGroup(
                lines: [
                    OrderQuoteLine(
                        id: "copies",
                        label: "Exemplaires",
                        detail: "x\(copies)",
                        amount: items
                    ),
                    OrderQuoteLine(
                        id: "shipping",
                        label: speed == .express ? "Livraison Express" : "Livraison Standard",
                        amount: shipping
                    ),
                ],
                subtotal: due
            ),
            deductions: [
                OrderDeduction(
                    id: "subscription",
                    label: "Déduction abonnements hebdomadaires versés",
                    amount: subscription
                ),
                OrderDeduction(
                    id: "wallet",
                    label: "Déduction de la cagnotte de tes proches",
                    amount: gifts
                ),
            ].filter { $0.amount > 0 },
            total: max(due - applied, 0),
            estimatedMinDays: speed == .express ? 2 : 5,
            estimatedMaxDays: speed == .express ? 3 : 7
        )
    }

    /// Le cas où la cagnotte couvre tout : l'étape 6 ne présente alors aucune
    /// carte, elle fait valider.
    public static var fullyCoveredFixture: OrderQuote {
        fixture(copies: 1, speed: .standard, pageCount: 4, walletBalance: 500)
    }
}

extension NewPrintOrderRequest {
    /// De quoi fabriquer une commande d'aperçu, quand aucune n'a été passée.
    public static var previewRequest: NewPrintOrderRequest {
        NewPrintOrderRequest(
            renderId: "render-rome",
            copies: 1,
            shippingSpeed: .standard,
            shipping: OrderContext.fixture.shipping,
            copyOptions: [PrintedCopyOptions(position: 1)],
            paymentCardId: nil
        )
    }
}

extension PlacedPrintOrder {
    /// Ce que le bac à sable rend : une commande **déjà réglée**.
    ///
    /// `paidFromWallet` plutôt qu'un faux `clientSecret` : c'est le seul cas qui
    /// n'ouvre aucune feuille. Une preview Xcode ne doit pas pouvoir appeler Stripe,
    /// même par accident.
    public static func fixture(
        memoId: String,
        request: NewPrintOrderRequest
    ) -> PlacedPrintOrder {
        PlacedPrintOrder(
            order: .fixture(memoId: memoId, request: request),
            payment: OrderPayment(paidFromWallet: true, amountCents: 0, currency: "eur")
        )
    }
}

extension PrintOrder {
    /// La commande que le double d'aperçu rend, à partir de ce qu'on lui envoie.
    public static func fixture(memoId: String, request: NewPrintOrderRequest) -> PrintOrder {
        let days = request.shippingSpeed == .express
            ? DayRange(min: 2, max: 3)
            : DayRange(min: 5, max: 7)

        return PrintOrder(
            id: UUID().uuidString,
            memoId: memoId,
            renderId: request.renderId,
            status: .draft,
            copies: request.copies,
            shippingSpeed: request.shippingSpeed,
            shipping: request.shipping,
            pageCount: 80,
            coverImageUrl: nil,
            estimatedMinDays: days.min,
            estimatedMaxDays: days.max,
            total: OrderQuote.fixture(copies: request.copies, speed: request.shippingSpeed).total,
            copyOptions: request.copyOptions,
            createdAt: .now,
            updatedAt: .now
        )
    }
}
