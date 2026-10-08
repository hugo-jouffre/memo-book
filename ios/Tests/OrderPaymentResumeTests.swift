import MemoBookCore
@testable import MemoBookFeature
import MemoBookPayments
import XCTest

/// **« Payer » reprend la commande déjà passée** (01/10/2026). Il en créait une
/// seconde à chaque tapotis — une nouvelle intention, et un second débit. Sans
/// simulateur : le modèle reçoit ses fonctions, comme l'app les
/// lui branche, et on compte ce qu'il appelle.
@MainActor
final class OrderPaymentResumeTests: XCTestCase {
    /// Ce que le modèle a demandé au serveur.
    private final class Calls {
        var submitted: [NewPrintOrderRequest] = []
        var resumed: [String] = []
        var cancelled: [String] = []
    }

    private let ticket = OrderPayment(
        amountCents: 4_990,
        currency: "eur",
        clientSecret: "pi_test_secret_test",
        publishableKey: "pk_test_x"
    )

    private func model(calls: Calls, sheet: [PaymentOutcome]) -> OrderModel {
        var outcomes = sheet
        let ticket = self.ticket
        return OrderModel(
            memoId: "memo-1",
            submit: { memoId, request in
                calls.submitted.append(request)
                return PlacedPrintOrder(order: .fixture(memoId: memoId, request: request), payment: ticket)
            },
            presentPayment: { _ in outcomes.isEmpty ? .succeeded : outcomes.removeFirst() },
            reloadOrder: nil,
            resumePayment: { orderId in
                calls.resumed.append(orderId)
                let order = PrintOrder.fixture(memoId: "memo-1", request: calls.submitted.last!)
                return ResumedOrderPayment(order: order, payment: ticket)
            },
            cancelOrder: { orderId in
                calls.cancelled.append(orderId)
                return .fixture(memoId: "memo-1", request: calls.submitted.last!)
            }
        )
    }

    /// Apple Pay arrive du serveur, avec le paiement : la feuille ne le montre
    /// que s'il est là — un serveur sans certificat Apple Pay n'en envoie pas.
    func testApplePayComesFromTheServerWithThePayment() throws {
        let withApplePay = try JSONDecoder().decode(OrderPayment.self, from: Data("""
        {"amountCents":4990,"currency":"eur","clientSecret":"pi_x_secret_y",\
        "publishableKey":"pk_test_x","applePayMerchantId":"merchant.com.tonapp.memobook"}
        """.utf8))
        guard case .card(let ticket) = withApplePay.settlement else { return XCTFail("carte attendue") }
        XCTAssertEqual(ticket.applePayMerchantId, "merchant.com.tonapp.memobook")

        guard case .card(let cardsOnly) = self.ticket.settlement else { return XCTFail("carte attendue") }
        XCTAssertNil(cardsOnly.applePayMerchantId)
    }

    /// « Payer » sur un carnet qu'aucune composition n'a rendu (T224) : le
    /// serveur répond `409 no_render`, et l'étape le dit au lieu de ne rien
    /// faire. Le jeu d'essai du modèle répond comme le serveur.
    func testPayingWithoutARenderSaysSo() async {
        let model = OrderModel(memoId: "memo-1", context: { _ in .notComposedFixture })
        await model.load()

        await model.pay()

        XCTAssertTrue(model.isMissingRender)
        XCTAssertNil(model.paymentError, "Ce n'est pas une panne : pas de bandeau d'erreur.")
        XCTAssertNotEqual(model.step, .confirmation)
    }

    func testAClosedSheetResumesTheSameOrder() async {
        let calls = Calls()
        let model = model(calls: calls, sheet: [.cancelled, .succeeded])
        await model.load()

        await model.pay()
        XCTAssertEqual(model.step, .start, "La feuille refermée ne passe pas à la confirmation.")
        await model.pay()

        XCTAssertEqual(calls.submitted.count, 1, "Une seule commande, malgré deux « Payer ».")
        XCTAssertEqual(calls.resumed.count, 1)
        XCTAssertTrue(calls.cancelled.isEmpty)
        XCTAssertEqual(model.step, .confirmation)
    }

    func testAChangedDraftAbandonsTheOldOrderFirst() async {
        let calls = Calls()
        let model = model(calls: calls, sheet: [.cancelled, .succeeded])
        await model.load()

        await model.pay()
        let first = model.order?.id
        model.draft.copies = 2
        await model.pay()

        XCTAssertEqual(calls.submitted.count, 2, "Le brouillon a changé : une commande neuve.")
        XCTAssertEqual(calls.cancelled, [first].compactMap { $0 }, "L'ancienne rend sa réservation.")
        XCTAssertTrue(calls.resumed.isEmpty)
    }
}
