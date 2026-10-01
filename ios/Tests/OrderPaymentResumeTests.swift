import MemoBookCore
@testable import MemoBookFeature
import MemoBookPayments
import XCTest

/// **« Payer » reprend la commande déjà passée** (01/10/2026). Il en créait une
/// seconde à chaque tapotis — une nouvelle intention, et un second débit de
/// cagnotte. Sans simulateur : le modèle reçoit ses fonctions, comme l'app les
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
        paidFromWallet: false,
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
