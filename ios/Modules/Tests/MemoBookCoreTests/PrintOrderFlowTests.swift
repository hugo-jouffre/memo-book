import XCTest

@testable import MemoBookCore

/// Ce que le tunnel de commande décide **hors d'une vue** : le rang des
/// étapes, la propagation des options d'un exemplaire à l'autre, et les
/// phrases accordées de la confirmation.
///
/// Ces règles vivent dans ``PrintOrderDraft`` et non dans l'écran précisément
/// pour être vérifiables ici, sans simulateur.
final class PrintOrderFlowTests: XCTestCase {

    private func draft(copies: Int) -> PrintOrderDraft {
        var draft = PrintOrderDraft(
            copies: copies,
            shipping: ShippingAddress(
                name: "Clara Perrin",
                line1: "7 rue Simon Fryd",
                postalCode: "69007",
                city: "Lyon",
                country: "FR"
            )
        )
        draft.alignCopyOptions(defaults: PrintedCopyOptions(position: 1))
        return draft
    }

    // MARK: - Les étapes

    func testStepsAnnounceTheirRankOutOfSeven() {
        XCTAssertEqual(OrderStep.start.progressLabel, "Étape 1/7 - Démarrage")
        XCTAssertEqual(OrderStep.copies.progressLabel, "Étape 3/7 - Exemplaires")
        XCTAssertEqual(OrderStep.confirmation.progressLabel, "Étape 7/7 - Confirmation")
    }

    /// La confirmation ne recule pas : la commande est passée, revenir sur le
    /// paiement n'a plus de sens. La première non plus — derrière elle, il n'y
    /// a plus le tunnel.
    func testFirstAndLastStepsDoNotGoBack() {
        XCTAssertFalse(OrderStep.start.allowsGoingBack)
        XCTAssertFalse(OrderStep.confirmation.allowsGoingBack)
        XCTAssertTrue(OrderStep.payment.allowsGoingBack)
    }

    // MARK: - Les exemplaires

    func testAddingACopyCopiesTheFirstOne() {
        var draft = self.draft(copies: 1)
        draft.setOption(.quiz, to: false, forCopyAt: 1)

        draft.copies = 3
        draft.alignCopyOptions(defaults: PrintedCopyOptions(position: 1))

        XCTAssertEqual(draft.copyOptions.count, 3)
        XCTAssertEqual(draft.copyOptions.map(\.position), [1, 2, 3])
        // Les nouveaux reprennent la version du premier, quiz coupés compris.
        XCTAssertTrue(draft.copyOptions.allSatisfy { $0.quizEnabled == false })
    }

    func testRemovingACopyDropsTheLastRanks() {
        var draft = self.draft(copies: 4)
        draft.copies = 2
        draft.alignCopyOptions(defaults: PrintedCopyOptions(position: 1))

        XCTAssertEqual(draft.copyOptions.map(\.position), [1, 2])
    }

    /// Toucher au premier carnet emmène ceux qui portaient encore sa version.
    func testChangingTheFirstCopyCarriesAlongTheOnesThatFollowedIt() {
        var draft = self.draft(copies: 3)
        draft.setOption(.crossword, to: false, forCopyAt: 1)

        XCTAssertTrue(draft.copyOptions.allSatisfy { $0.crosswordEnabled == false })
    }

    /// …mais pas ceux qu'on a détachés. Une version choisie ne se fait pas
    /// écraser par un réglage du premier carnet.
    func testChangingTheFirstCopyLeavesADetachedCopyAlone() {
        var draft = self.draft(copies: 2)
        draft.setFollowsFirstCopy(false, forCopyAt: 2)
        let detached = draft.copyOptions[1]

        draft.setOption(.decorations, to: false, forCopyAt: 1)

        XCTAssertFalse(draft.copyOptions[0].decorationsEnabled)
        XCTAssertEqual(draft.copyOptions[1], detached)
    }

    /// Détacher sans rien changer laisserait deux carnets identiques et un
    /// écran qui prétend le contraire.
    func testDetachingACopyMakesItActuallyDifferent() {
        var draft = self.draft(copies: 2)
        XCTAssertTrue(draft.followsFirstCopy(2))

        draft.setFollowsFirstCopy(false, forCopyAt: 2)

        XCTAssertFalse(draft.followsFirstCopy(2))
    }

    func testReattachingACopyRestoresTheFirstVersion() {
        var draft = self.draft(copies: 2)
        draft.setOption(.freeZones, to: false, forCopyAt: 1)
        draft.setFollowsFirstCopy(false, forCopyAt: 2)
        draft.setFollowsFirstCopy(true, forCopyAt: 2)

        XCTAssertTrue(draft.followsFirstCopy(2))
        XCTAssertFalse(draft.copyOptions[1].freeZonesEnabled)
        // Le rang ne se perd pas dans la recopie.
        XCTAssertEqual(draft.copyOptions[1].position, 2)
    }

    /// Le premier carnet est la référence : il n'a rien à suivre, et l'écran
    /// ne lui propose donc pas de se détacher de lui-même.
    func testTheFirstCopyIsItsOwnReference() {
        var draft = self.draft(copies: 2)
        XCTAssertTrue(draft.followsFirstCopy(1))

        draft.setFollowsFirstCopy(false, forCopyAt: 1)
        XCTAssertTrue(draft.followsFirstCopy(1))
    }

    // MARK: - Ce qui laisse passer

    func testAnAddressMissingItsCityDoesNotPass() {
        var draft = self.draft(copies: 1)
        XCTAssertTrue(draft.hasCompleteAddress)

        draft.shipping.city = "  "
        XCTAssertFalse(draft.hasCompleteAddress)
    }

    /// La deuxième ligne est facultative : beaucoup d'adresses n'en ont pas, et
    /// en exiger une bloquerait tout le monde.
    func testTheSecondAddressLineIsOptional() {
        var draft = self.draft(copies: 1)
        draft.shipping.line2 = nil
        XCTAssertTrue(draft.hasCompleteAddress)
    }

    func testApplePayCountsAsAPaymentMethod() {
        var draft = self.draft(copies: 1)
        XCTAssertFalse(draft.hasPaymentMethod)

        draft.usesApplePay = true
        XCTAssertTrue(draft.hasPaymentMethod)
    }

    /// Apple Pay n'enregistre aucune carte : la commande ne doit pas en porter
    /// une restée sélectionnée avant qu'on en change.
    func testApplePayDropsThePreviouslySelectedCard() {
        var draft = self.draft(copies: 1)
        draft.paymentCardId = "card-perso"
        draft.usesApplePay = true

        let request = NewPrintOrderRequest(renderId: "render-1", draft: draft)
        XCTAssertNil(request.paymentCardId)
    }

    // MARK: - Ce qui se lit

    func testDelayReadsAsARangeUnlessBothBoundsMeet() {
        XCTAssertEqual(DayRange(min: 5, max: 7).label, "5 à 7 jours ouvrés")
        XCTAssertEqual(DayRange(min: 3, max: 3).label, "3 jours ouvrés")
        XCTAssertEqual(DayRange(min: 2, max: 3).deliveryLabel, "Dans 2 à 3 jours")
    }

    func testCopyTitlesAreOrdinals() {
        XCTAssertEqual(PrintedCopyOptions(position: 1).title, "1er Carnet")
        XCTAssertEqual(PrintedCopyOptions(position: 2).title, "2e Carnet")
    }

    func testConfirmationAgreesInNumberOnBothSides() {
        XCTAssertEqual(
            BookCopy.Order.Confirmation.summary(copies: 1, pages: 1),
            "1 exemplaire - 1 page"
        )
        XCTAssertEqual(
            BookCopy.Order.Confirmation.summary(copies: 2, pages: 50),
            "2 exemplaires - 50 pages"
        )
    }

    /// Un compte entré par Apple peut n'avoir relayé aucune adresse. Promettre
    /// un email sans destinataire serait pire que de ne rien promettre.
    func testConfirmationWithoutAnEmailDoesNotPromiseOne() {
        let detail = BookCopy.Order.Confirmation.detail(book: "Rome", email: nil)
        XCTAssertFalse(detail.contains("sur ton email"))
        XCTAssertTrue(detail.contains("Rome"))

        let withEmail = BookCopy.Order.Confirmation.detail(book: "Rome", email: "a@b.com")
        XCTAssertTrue(withEmail.contains("a@b.com"))
    }

    /// Une cagnotte qui couvre tout laisse un total nul : l'étape 6 ne présente
    /// alors aucune carte, elle fait valider.
    func testAFullyCoveredQuoteAsksForNoPayment() {
        XCTAssertTrue(OrderQuote.fullyCovered.isFullyCovered)
    }
}

extension OrderQuote {
    /// Un devis entièrement couvert par la cagnotte, monté à la main : ce test
    /// vérifie une règle de lecture, pas le barème du serveur.
    fileprivate static var fullyCovered: OrderQuote {
        OrderQuote(
            bookTitle: "Rome",
            pageCount: 10,
            copies: 1,
            shippingSpeed: .standard,
            unitPrice: 30,
            book: OrderQuoteGroup(lines: [], subtotal: 30),
            fulfilment: OrderQuoteGroup(lines: [], subtotal: 30),
            deductions: [OrderDeduction(id: "wallet", label: "Cagnotte", amount: 30)],
            total: 0,
            estimatedMinDays: 5,
            estimatedMaxDays: 7
        )
    }
}
