import Foundation
// `PaymentIntentTicket` vit dans `MemoBookCore` et non ici : c'est un modèle
// pur, que le client réseau décode et que ce module consomme. Le mettre à côté
// du SDK obligerait `MemoBookNetworking` à dépendre de Stripe pour décoder une
// réponse JSON.
import MemoBookCore
import StripePaymentSheet
import UIKit

/// La seule porte par laquelle l'app peut déclencher un paiement.
///
/// Un protocole, et non directement le SDK Stripe, pour deux raisons :
/// les aperçus Xcode et les tests ont besoin d'un paiement qui n'appelle
/// personne, et le jour où la feuille change — Apple Pay natif, un autre
/// prestataire — c'est cette façade qui change, pas les écrans.
@MainActor
public protocol PaymentPresenter: Sendable {
    func present(_ ticket: PaymentIntentTicket) async -> PaymentOutcome
}

/// La version d'API Stripe que pin le SDK de l'app — « 2020-08-27 » pour
/// stripe-ios 24. Le serveur en a besoin pour créer une clé éphémère que la
/// feuille sache lire ; ce module est le seul à connaître le SDK, d'où cette
/// constante plutôt qu'une valeur écrite ailleurs.
public enum StripeSDK {
    public static var apiVersion: String { STPAPIClient.apiVersion }

    /// Rend à Stripe un lien qui lui revient — le retour d'un paiement qui
    /// passe par une autre app ou une page web (3-D Secure, Klarna…). Sans
    /// ça, la feuille attendait un retour qui n'arrivait jamais. Rend `true`
    /// quand le lien était pour lui.
    @discardableResult
    public static func handle(_ url: URL) -> Bool {
        StripeAPI.handleURLCallback(with: url)
    }
}

/// La vraie feuille Stripe.
@MainActor
public final class StripePaymentSheetPresenter: PaymentPresenter {
    /// Ce qui s'affiche en tête de la feuille, et sur le relevé bancaire.
    private let merchantName: String

    /// Le pays du **marchand**, pas du client. `FR` parce que c'est là qu'est
    /// le compte Stripe ; le client, lui, peut payer depuis n'importe où.
    private let merchantCountryCode: String

    /// L'identifiant marchand Apple Pay, quand il existe.
    ///
    /// `nil` tant que le certificat Apple Pay n'est pas posé : la feuille
    /// affiche alors les cartes seules, au lieu d'un bouton Apple Pay qui
    /// échouerait. Voir `ios/project.yml` et le tableau de bord Stripe.
    private let applePayMerchantId: String?

    public init(
        merchantName: String = "MemoBook",
        merchantCountryCode: String = "FR",
        applePayMerchantId: String? = nil
    ) {
        self.merchantName = merchantName
        self.merchantCountryCode = merchantCountryCode
        self.applePayMerchantId = applePayMerchantId
    }

    public func present(_ ticket: PaymentIntentTicket) async -> PaymentOutcome {
        // La clé publique est posée **à chaque paiement**, depuis la réponse du
        // serveur, et non figée dans le binaire. Changer de compte Stripe — ou
        // passer de test à production — devient une variable d'environnement
        // côté serveur, pas une livraison sur l'App Store.
        STPAPIClient.shared.publishableKey = ticket.publishableKey

        var configuration = PaymentSheet.Configuration()
        configuration.merchantDisplayName = merchantName
        configuration.returnURL = "memobook://stripe-redirect"

        if let applePayMerchantId {
            configuration.applePay = .init(
                merchantId: applePayMerchantId,
                merchantCountryCode: merchantCountryCode
            )
        }

        // **Les cartes du compte.** Avec le client et sa clé éphémère, la
        // feuille montre les cartes déjà enregistrées, propose « Enregistrer
        // pour la prochaine fois », et laisse en retirer une — tout ce que
        // l'app faisait semblant de faire avec son propre formulaire. Sans
        // eux (un serveur plus ancien), on paie quand même, carte saisie.
        if let customerId = ticket.customerId, let key = ticket.ephemeralKeySecret {
            configuration.customer = .init(id: customerId, ephemeralKeySecret: key)
        }

        guard let presenter = UIApplication.topViewController() else {
            return .failed(PaymentError.noPresenter.localizedDescription)
        }

        let sheet = PaymentSheet(
            paymentIntentClientSecret: ticket.clientSecret,
            configuration: configuration
        )

        return await withCheckedContinuation { continuation in
            sheet.present(from: presenter) { result in
                switch result {
                case .completed:
                    continuation.resume(returning: .succeeded)
                case .canceled:
                    continuation.resume(returning: .cancelled)
                case .failed(let error):
                    continuation.resume(returning: .failed(error.localizedDescription))
                }
            }
        }
    }
}

/// Un paiement qui n'appelle personne — aperçus Xcode et tests.
///
/// Le résultat est **fixé à la construction** plutôt que tiré au hasard : un
/// aperçu qui échoue une fois sur deux est un aperçu qu'on ne peut pas relire.
@MainActor
public struct StubPaymentPresenter: PaymentPresenter {
    private let outcome: PaymentOutcome

    public init(outcome: PaymentOutcome = .succeeded) {
        self.outcome = outcome
    }

    public func present(_ ticket: PaymentIntentTicket) async -> PaymentOutcome {
        outcome
    }
}
