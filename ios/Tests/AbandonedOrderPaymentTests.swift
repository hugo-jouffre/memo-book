import MemoBookCore
@testable import MemoBookFeature
import MemoBookNetworking
import MemoBookPayments
import XCTest

/// **« Finaliser ma commande »** (T232) : la commande abandonnée se reprend
/// par `POST /v1/orders/:id/payment`, sans en passer une seconde. Sans
/// simulateur : on branche les trois fonctions et on regarde ce qui revient.
final class AbandonedOrderPaymentTests: XCTestCase {
    private static let ticket = OrderPayment(
        amountCents: 3_990,
        currency: "eur",
        clientSecret: "pi_test_secret_test",
        publishableKey: "pk_test_x"
    )

    private static func order(_ status: PrintOrderStatus) -> PrintOrder {
        let draft = PrintOrder.fixture(memoId: "memo-1", request: .previewRequest)
        return PrintOrder(
            id: "order-1",
            memoId: draft.memoId,
            renderId: draft.renderId,
            status: status,
            copies: draft.copies,
            shipping: draft.shipping,
            createdAt: draft.createdAt,
            updatedAt: draft.updatedAt
        )
    }

    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var _resumed: [String] = []
        private var _reloads = 0
        var resumed: [String] { lock.withLock { _resumed } }
        var reloads: Int { lock.withLock { _reloads } }
        func resume(_ id: String) { lock.withLock { _resumed.append(id) } }
        func reload() { lock.withLock { _reloads += 1 } }
    }

    private func payment(
        log: Log,
        payment: OrderPayment? = ticket,
        sheet: PaymentOutcome = .succeeded,
        failure: (any Error & Sendable)? = nil
    ) -> AbandonedOrderPayment {
        var flow = AbandonedOrderPayment(
            resume: { id in
                log.resume(id)
                if let failure { throw failure }
                return ResumedOrderPayment(order: Self.order(.draft), payment: payment)
            },
            present: { _ in sheet },
            reload: { _ in
                log.reload()
                return Self.order(log.reloads < 2 ? .draft : .submitted)
            }
        )
        flow.settlementInterval = .zero
        return flow
    }

    func testAPaidSheetWaitsForTheServerBeforeSayingPaid() async {
        let log = Log()
        let outcome = await payment(log: log).finish(orderId: "order-1")

        XCTAssertEqual(outcome, .paid)
        XCTAssertEqual(log.resumed, ["order-1"], "La commande se reprend, elle ne se repasse pas.")
        XCTAssertEqual(log.reloads, 2, "Relue jusqu'à ce que le webhook l'ait sortie du brouillon.")
    }

    func testAClosedSheetLeavesTheOrderWaiting() async {
        let log = Log()
        let outcome = await payment(log: log, sheet: .cancelled).finish(orderId: "order-1")

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(log.reloads, 0)
    }

    func testNothingLeftToPayIsPaid() async {
        let log = Log()
        let outcome = await payment(log: log, payment: nil).finish(orderId: "order-1")

        XCTAssertEqual(outcome, .paid)
    }

    func testARefundedOrderSaysWhatTheServerSays() async {
        let log = Log()
        let refused = APIError.server(
            statusCode: 409,
            code: "order_refunded",
            message: "Cette commande a été remboursée : passes-en une nouvelle."
        )
        let outcome = await payment(log: log, failure: refused).finish(orderId: "order-1")

        guard case .failed(let message) = outcome else {
            return XCTFail("Un refus doit se lire : \(outcome)")
        }
        XCTAssertTrue(message.contains("remboursée"))
    }

    func testAServerWithoutStripeKeysSaysSoInsteadOfOpeningAnEmptySheet() async {
        let log = Log()
        let keyless = OrderPayment(amountCents: 3_990, currency: "eur", clientSecret: nil, publishableKey: nil)
        let outcome = await payment(log: log, payment: keyless).finish(orderId: "order-1")

        XCTAssertEqual(outcome, .failed(BookCopy.Order.Payment.unavailable))
    }
}
