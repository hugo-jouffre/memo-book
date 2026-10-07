import Foundation
import MemoBookCore
import MemoBookNetworking
import MemoBookPayments

/// « Finaliser ma commande », depuis Profil › Suivi des commandes (T232).
///
/// Une commande au paiement abandonné se **reprend**, elle ne se repasse pas :
/// `POST /v1/orders/:id/payment` la rouvre avec une nouvelle intention Stripe,
/// au prix figé à la commande — même quand le ménage des 24 h l'avait fermée.
/// Rouvrir le tunnel aurait fait ressaisir l'adresse et les exemplaires d'une
/// commande qui les a déjà, et en aurait passé une seconde.
///
/// Comme ``OrderModel``, il ne connaît ni l'API ni le SDK : trois fonctions,
/// que ``AppDependencies/finishAbandonedOrder(orderId:)`` branche.
public struct AbandonedOrderPayment: Sendable {
    /// Ce que la feuille du suivi doit en faire.
    public enum Outcome: Sendable, Hashable {
        /// Payée — ou plus rien à régler. Le suivi relit le profil : la carte
        /// passe en livraison.
        case paid
        /// La feuille de Stripe a été fermée. Ni message ni relecture : la
        /// commande attend toujours, le bouton aussi.
        case cancelled
        /// Ce que la personne doit lire.
        case failed(String)
    }

    let resume: @Sendable (String) async throws -> ResumedOrderPayment
    let present: @Sendable (PaymentIntentTicket) async -> PaymentOutcome
    let reload: (@Sendable (String) async throws -> PrintOrder)?

    /// Une seconde entre deux relectures, six fois au plus — le même budget
    /// que la confirmation du tunnel (``OrderModel``).
    var settlementAttempts = 6
    var settlementInterval: Duration = .seconds(1)

    public init(
        resume: @escaping @Sendable (String) async throws -> ResumedOrderPayment,
        present: @escaping @Sendable (PaymentIntentTicket) async -> PaymentOutcome,
        reload: (@Sendable (String) async throws -> PrintOrder)? = nil
    ) {
        self.resume = resume
        self.present = present
        self.reload = reload
    }

    public func finish(orderId: String) async -> Outcome {
        let resumed: ResumedOrderPayment
        do {
            resumed = try await resume(orderId)
        } catch {
            // `409 order_refunded` arrive avec sa phrase : la commande a été
            // payée puis remboursée, il faut en passer une autre. Le serveur
            // la dit mieux que nous.
            return .failed(error.localizedDescription)
        }

        // `payment: null` : payée entre-temps, ou un paiement déjà en cours.
        // Rien à ouvrir — le profil relu dira où elle en est.
        guard let payment = resumed.payment else { return .paid }

        switch payment.settlement {
        case .unavailable:
            return .failed(BookCopy.Order.Payment.unavailable)

        case .card(let ticket):
            switch await present(ticket) {
            case .cancelled:
                return .cancelled
            case .failed(let message):
                return .failed(message)
            case .succeeded:
                // La feuille dit que Stripe a accepté, pas que le serveur l'a
                // appris : on attend le webhook avant de relire le profil,
                // sans quoi la carte resterait « abandonnée » sur un paiement
                // réussi.
                await waitUntilSettled(orderId)
                return .paid
            }
        }
    }

    private func waitUntilSettled(_ orderId: String) async {
        guard let reload else { return }
        for _ in 0..<settlementAttempts {
            try? await Task.sleep(for: settlementInterval)
            guard let fresh = try? await reload(orderId) else { continue }
            if fresh.status != .draft { return }
        }
    }
}
