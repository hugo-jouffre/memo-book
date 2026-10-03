import MemoBookPayments
import SwiftUI

/// Ce que l'offre et la feuille d'abonnement savent faire de l'App Store, pour
/// le compte connecté — voir ``AppDependencies/subscriptionPurchase(accountId:)``.
///
/// Des fonctions et non le magasin lui-même : l'écran n'a pas à savoir à qui
/// la transaction est remise, ni sous quel compte. Il demande un achat, et
/// reçoit ce qui s'est passé.
struct SubscriptionPurchase: Sendable {
    /// Le prix d'Apple, dans le pays du compte. `nil` tant qu'il n'est pas revenu.
    var displayPrice: @MainActor @Sendable () async -> String?
    /// La période que ce prix paie — « mois » —, lue sur le produit. `nil`
    /// tant qu'elle n'est pas revenue : l'écran écrit alors celle de l'offre.
    var displayPeriod: @MainActor @Sendable () async -> String?
    /// Achète l'abonnement, rattaché au voyage qu'il finance quand on le sait.
    var purchase: @MainActor @Sendable (_ memoId: String?) async -> PurchaseOutcome
    /// « Restaurer mes achats ».
    var restore: @MainActor @Sendable () async throws -> RestoreOutcome
    /// Le renouvellement est-il encore armé chez Apple — lu sur l'appareil.
    var willAutoRenew: @MainActor @Sendable () async -> Bool?
    /// Remet au serveur ce que StoreKit garde encore — un achat qu'Apple a
    /// encaissé et que le serveur n'a pas reçu (`awaitingServer`). Le profil
    /// s'en sert à l'ouverture tant que l'abonnement acheté n'y apparaît pas
    /// (03/10/2026).
    var deliverUnfinished: @MainActor @Sendable () async -> Void = {}
}

extension EnvironmentValues {
    /// L'achat de l'abonnement, pour le compte connecté. `nil` dans un aperçu
    /// isolé : l'offre s'y comporte comme si l'achat avait réussi.
    @Entry var subscriptionPurchase: SubscriptionPurchase?
}
