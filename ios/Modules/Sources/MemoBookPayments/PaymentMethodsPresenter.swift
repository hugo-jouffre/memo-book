import Foundation
import MemoBookCore
import StripePaymentSheet
import UIKit

/// La feuille « Moyens de paiement » du profil : les cartes du compte, telles
/// que Stripe les tient — en ajouter une, en retirer une.
///
/// **Elle remplace un formulaire fait main** (01/10/2026) : l'app demandait le
/// numéro, l'échéance et le cryptogramme dans ses propres champs, n'en gardait
/// que les quatre derniers chiffres en mémoire, et ne parlait à personne. Un
/// numéro de carte n'a rien à faire dans l'app : ici, c'est Stripe qui le saisit,
/// le vérifie et le garde.
@MainActor
public protocol PaymentMethodsPresenter: Sendable {
    /// Ouvre la feuille. Rend un message quand elle n'a pas pu s'ouvrir, `nil`
    /// sinon — la refermer n'est pas une erreur.
    func present(
        key: @escaping @Sendable () async throws -> CustomerPaymentKey,
        setupIntent: @escaping @Sendable () async throws -> String
    ) async -> String?
}

/// La vraie, `CustomerSheet` de Stripe, branchée par une clé éphémère — la voie
/// stable de stripe-ios 24 (les sessions client y sont encore en bêta).
@MainActor
public final class StripeCustomerSheetPresenter: PaymentMethodsPresenter {
    private let merchantName: String

    public init(merchantName: String = "MemoBook") {
        self.merchantName = merchantName
    }

    public func present(
        key: @escaping @Sendable () async throws -> CustomerPaymentKey,
        setupIntent: @escaping @Sendable () async throws -> String
    ) async -> String? {
        let customer: CustomerPaymentKey
        do {
            customer = try await key()
        } catch {
            return error.localizedDescription
        }

        // La clé publique, posée à chaque ouverture depuis la réponse du
        // serveur — comme pour un paiement.
        STPAPIClient.shared.publishableKey = customer.publishableKey

        var configuration = CustomerSheet.Configuration()
        configuration.merchantDisplayName = merchantName
        configuration.returnURL = "memobook://stripe-redirect"
        configuration.headerTextForSelectionScreen = "Tes moyens de paiement"

        let adapter = StripeCustomerAdapter(
            customerEphemeralKeyProvider: {
                CustomerEphemeralKey(customerId: customer.customerId, ephemeralKeySecret: customer.ephemeralKeySecret)
            },
            setupIntentClientSecretProvider: { try await setupIntent() }
        )
        let sheet = CustomerSheet(configuration: configuration, customer: adapter)

        guard let presenter = UIApplication.topViewController() else {
            return PaymentError.noPresenter.localizedDescription
        }

        return await withCheckedContinuation { continuation in
            sheet.present(from: presenter) { result in
                switch result {
                case .selected, .canceled:
                    continuation.resume(returning: nil)
                case .error(let error):
                    continuation.resume(returning: error.localizedDescription)
                }
            }
        }
    }
}

/// Une feuille qui n'appelle personne — aperçus Xcode et bac à sable.
@MainActor
public struct StubPaymentMethodsPresenter: PaymentMethodsPresenter {
    public init() {}

    public func present(
        key: @escaping @Sendable () async throws -> CustomerPaymentKey,
        setupIntent: @escaping @Sendable () async throws -> String
    ) async -> String? {
        nil
    }
}

extension UIApplication {
    /// Le contrôleur au-dessus de la pile, celui qui peut présenter.
    ///
    /// L'app est en SwiftUI : il n'y a pas de contrôleur sous la main, et
    /// Stripe en exige un. On remonte donc depuis la fenêtre active, en
    /// traversant les feuilles déjà présentées — sans quoi la feuille de
    /// Stripe s'ouvrirait derrière celle de l'app.
    static func topViewController() -> UIViewController? {
        let scene = shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }

        guard var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return nil
        }

        while let presented = top.presentedViewController {
            top = presented
        }

        return top
    }
}
