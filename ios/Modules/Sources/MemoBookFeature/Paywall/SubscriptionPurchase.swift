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
    /// Achète l'abonnement, rattaché au voyage qu'il finance quand on le sait.
    var purchase: @MainActor @Sendable (_ memoId: String?) async -> PurchaseOutcome
    /// « Restaurer mes achats ».
    var restore: @MainActor @Sendable () async throws -> RestoreOutcome
    /// Le renouvellement est-il encore armé chez Apple — lu sur l'appareil.
    var willAutoRenew: @MainActor @Sendable () async -> Bool?
}

extension EnvironmentValues {
    /// L'achat de l'abonnement, pour le compte connecté. `nil` dans un aperçu
    /// isolé : l'offre s'y comporte comme si l'achat avait réussi.
    @Entry var subscriptionPurchase: SubscriptionPurchase?
}
