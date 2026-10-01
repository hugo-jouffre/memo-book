import Foundation
import StoreKit
import UIKit

/// Les produits App Store de MemoBook.
///
/// L'identifiant est posé dans *App Store Connect ▸ Abonnements* et ne se change
/// plus jamais : Apple ne le laisse ni modifier ni réutiliser. Le serveur porte
/// la même valeur (`APP_STORE_PRODUCT_IDS`, `subscriptionCatalog.ts`), et
/// `MemoBook.storekit` aussi ; les trois doivent rester identiques.
public enum StoreKitCatalog {
    public static let weeklySubscription = "com.memobook.app.subscription.weekly"
}

/// Une transaction signée par l'App Store — un JWS que le serveur vérifie
/// jusqu'au certificat racine d'Apple. L'app ne l'ouvre pas : elle le transmet.
public struct SignedTransaction: Sendable, Hashable {
    public let jws: String

    public init(jws: String) {
        self.jws = jws
    }
}

/// Ce qu'on fait d'une transaction : la remettre au serveur.
///
/// **Lève si le serveur ne l'a pas prise.** La transaction reste alors ouverte,
/// et StoreKit la rendra au prochain lancement (`Transaction.unfinished`) :
/// c'est ce qui rend un achat fait dans un tunnel impossible à perdre.
public typealias TransactionDelivery = @Sendable (SignedTransaction) async throws -> Void

/// Le serveur a vu la transaction, et la refuse **pour de bon** : faite depuis
/// un autre compte MemoBook, déjà rattachée ailleurs, ou qu'il ne sait pas
/// vérifier — un achat Xcode envoyé à la production, typiquement.
///
/// La transaction est alors **finie** : la rejouer à chaque lancement ne la
/// ferait pas accepter. Mais l'achat ne compte pas comme réussi, et l'écran dit
/// pourquoi — c'est le message du serveur.
public struct TransactionRefused: LocalizedError, Sendable {
    public let message: String

    public var errorDescription: String? { message }

    public init(message: String) {
        self.message = message
    }
}

/// Ce qu'un achat rend.
public enum PurchaseOutcome: Sendable, Hashable {
    /// Payé, et le serveur l'a appris : l'abonnement est ouvert.
    case subscribed
    /// Payé chez Apple, mais le serveur n'a pas répondu. **Ce n'est pas un
    /// échec** : la transaction repartira seule, et Apple notifiera le serveur
    /// de son côté. L'écran se comporte comme pour ``subscribed``.
    case awaitingServer
    /// Il faut une validation de plus — « Demander l'autorisation » d'un
    /// parent, ou la banque. L'abonnement s'ouvrira quand elle arrivera, par
    /// `Transaction.updates`.
    case pending
    /// La personne a fermé la feuille d'Apple. Un choix, pas une erreur.
    case cancelled
    case failed(String)
}

public enum RestoreOutcome: Sendable, Hashable {
    case restored
    case nothingToRestore
}

public enum SubscriptionStoreError: LocalizedError {
    /// Le produit n'est pas revenu de l'App Store : pas de réseau, ou App Store
    /// Connect pas prêt — contrat *Paid Apps* non signé, abonnement sans
    /// métadonnées. C'est la panne de configuration la plus courante.
    case unavailable
    /// L'App Store n'a pas pu garantir que la transaction vient de lui.
    case unverified
    /// Le serveur n'a pas pris l'achat restauré. Il repartira seul.
    case serverUnreachable

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "L’abonnement n’est pas disponible pour le moment. Vérifie ta connexion et réessaie."
        case .unverified:
            "L’App Store n’a pas pu confirmer cet achat. Aucun abonnement n’a été ouvert."
        case .serverUnreachable:
            "Ton abonnement est bien chez Apple, mais notre serveur ne répond pas. Il sera rétabli automatiquement."
        }
    }
}

/// La seule porte par laquelle l'app achète l'abonnement.
///
/// Un protocole et non StoreKit directement, pour la même raison que
/// ``PaymentPresenter`` : les aperçus Xcode ont besoin d'un achat qui n'appelle
/// personne, et le paywall ne doit pas savoir comment on paie.
@MainActor
public protocol SubscriptionStore: AnyObject, Sendable {
    /// Le prix tel qu'Apple l'affiche dans le pays du compte — « 1,99 € » en
    /// France. `nil` tant que le produit n'est pas revenu de l'App Store.
    func displayPrice() async -> String?

    /// Achète l'abonnement. `appAccountToken` est l'identifiant du compte
    /// MemoBook : Apple le recopie dans chaque transaction, et c'est ce qui
    /// permet au serveur de rattacher un renouvellement sans que l'app parle.
    func purchase(appAccountToken: UUID?, deliver: @escaping TransactionDelivery) async
        -> PurchaseOutcome

    /// « Restaurer mes achats » — exigé par App Review. Resynchronise avec
    /// l'App Store, puis remet au serveur ce qui est en cours.
    func restore(deliver: @escaping TransactionDelivery) async throws -> RestoreOutcome

    /// Écoute ce qui arrive hors de l'écran d'achat : un renouvellement, une
    /// validation parentale, un achat fait sur un autre appareil, un
    /// remboursement. À démarrer **au lancement**, sinon StoreKit les garde.
    func startListening(deliver: @escaping TransactionDelivery)

    /// Remet au serveur ce qui n'a pas pu partir — à la connexion, typiquement.
    func deliverUnfinished(deliver: @escaping TransactionDelivery) async

    /// Le renouvellement est-il encore armé chez Apple ? Lu sur l'appareil,
    /// donc juste après que la personne a quitté la feuille de gestion des
    /// abonnements — sans attendre la notification du serveur. `nil` quand on
    /// ne sait pas.
    func willAutoRenew() async -> Bool?
}

/// Le vrai StoreKit 2.
@MainActor
public final class StoreKitSubscriptionStore: SubscriptionStore {
    private let productId: String
    private var product: Product?
    private var listener: Task<Void, Never>?

    public init(productId: String = StoreKitCatalog.weeklySubscription) {
        self.productId = productId
    }

    public func displayPrice() async -> String? {
        try? await loadProduct()?.displayPrice
    }

    public func purchase(
        appAccountToken: UUID?,
        deliver: @escaping TransactionDelivery
    ) async -> PurchaseOutcome {
        let product: Product
        do {
            guard let loaded = try await loadProduct() else {
                return .failed(SubscriptionStoreError.unavailable.localizedDescription)
            }
            product = loaded
        } catch {
            return .failed(SubscriptionStoreError.unavailable.localizedDescription)
        }

        var options: Set<Product.PurchaseOption> = []
        if let appAccountToken {
            options.insert(.appAccountToken(appAccountToken))
        }

        let result: Product.PurchaseResult
        do {
            // La feuille d'Apple se pose sur la scène active : sans elle, iOS ne
            // sait pas où demander Face ID.
            if let scene = Self.activeScene() {
                result = try await product.purchase(confirmIn: scene, options: options)
            } else {
                return .failed(PaymentError.noPresenter.localizedDescription)
            }
        } catch {
            return .failed(error.localizedDescription)
        }

        switch result {
        case .success(let verification):
            switch await settle(verification, deliver: deliver) {
            case .delivered: return .subscribed
            case .undelivered: return .awaitingServer
            case .refused(let message): return .failed(message)
            case .unverified, .ignored:
                return .failed(SubscriptionStoreError.unverified.localizedDescription)
            }
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    public func restore(deliver: @escaping TransactionDelivery) async throws -> RestoreOutcome {
        // Demande l'identifiant Apple si besoin : c'est le geste que la personne
        // vient de faire, elle s'y attend.
        try await AppStore.sync()

        var restored = false
        var undelivered = false
        for await verification in StoreKit.Transaction.currentEntitlements {
            switch await settle(verification, deliver: deliver) {
            case .delivered: restored = true
            case .undelivered: undelivered = true
            case .refused(let message): throw TransactionRefused(message: message)
            case .unverified, .ignored: break
            }
        }

        if restored { return .restored }
        if undelivered { throw SubscriptionStoreError.serverUnreachable }
        return .nothingToRestore
    }

    public func startListening(deliver: @escaping TransactionDelivery) {
        guard listener == nil else { return }
        listener = Task { [weak self] in
            for await verification in StoreKit.Transaction.updates {
                _ = await self?.settle(verification, deliver: deliver)
            }
        }
    }

    public func deliverUnfinished(deliver: @escaping TransactionDelivery) async {
        for await verification in StoreKit.Transaction.unfinished {
            _ = await settle(verification, deliver: deliver)
        }
    }

    public func willAutoRenew() async -> Bool? {
        guard let statuses = try? await loadProduct()?.subscription?.status else { return nil }

        for status in statuses where status.state != .expired && status.state != .revoked {
            if case .verified(let renewal) = status.renewalInfo {
                return renewal.willAutoRenew
            }
        }
        return nil
    }

    // MARK: -

    private enum Settlement {
        case delivered, undelivered, unverified, ignored
        case refused(String)
    }

    /// Remet une transaction au serveur, et **ne la finit qu'une fois qu'il l'a
    /// prise**. Finir avant, c'est dire à StoreKit qu'on n'en a plus besoin — et
    /// un serveur qui n'a rien reçu ne la reverrait jamais.
    private func settle(
        _ verification: VerificationResult<StoreKit.Transaction>,
        deliver: TransactionDelivery
    ) async -> Settlement {
        guard case .verified(let transaction) = verification else { return .unverified }
        // Un autre produit — l'extension des limites, un jour — aura son propre
        // chemin. Il reste ouvert d'ici là.
        guard transaction.productID == productId else { return .ignored }

        do {
            try await deliver(SignedTransaction(jws: verification.jwsRepresentation))
        } catch let refusal as TransactionRefused {
            await transaction.finish()
            return .refused(refusal.message)
        } catch {
            return .undelivered
        }
        await transaction.finish()
        return .delivered
    }

    private func loadProduct() async throws -> Product? {
        if let product { return product }
        let loaded = try await Product.products(for: [productId]).first
        product = loaded
        return loaded
    }

    private static func activeScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
}

/// Un achat qui n'appelle personne — aperçus Xcode et bac à sable.
///
/// Le résultat est fixé à la construction, comme ``StubPaymentPresenter`` : un
/// aperçu qui échoue une fois sur deux est un aperçu qu'on ne peut pas relire.
@MainActor
public final class StubSubscriptionStore: SubscriptionStore {
    private let outcome: PurchaseOutcome
    private let renewsAfterManagement: Bool?

    /// - Parameter renewsAfterManagement: ce que rend ``willAutoRenew()``. Dans
    ///   le bac à sable, la feuille d'Apple ne s'ouvre pas : `false` fait comme
    ///   si la personne y avait coupé le renouvellement, pour voir la suite.
    public init(outcome: PurchaseOutcome = .subscribed, renewsAfterManagement: Bool? = false) {
        self.outcome = outcome
        self.renewsAfterManagement = renewsAfterManagement
    }

    /// `nil` : l'écran garde le prix du catalogue, celui des maquettes.
    public func displayPrice() async -> String? { nil }

    public func purchase(appAccountToken: UUID?, deliver: @escaping TransactionDelivery) async
        -> PurchaseOutcome
    {
        outcome
    }

    public func restore(deliver: @escaping TransactionDelivery) async throws -> RestoreOutcome {
        .nothingToRestore
    }

    public func startListening(deliver: @escaping TransactionDelivery) {}

    public func deliverUnfinished(deliver: @escaping TransactionDelivery) async {}

    public func willAutoRenew() async -> Bool? { renewsAfterManagement }
}
