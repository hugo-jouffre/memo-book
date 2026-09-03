import Foundation
import MemoBookNetworking

/// Où l'app note l'étape franchie par l'utilisateur, et comment revenir en
/// arrière pendant le développement.
///
/// Ces réglages survivent à une réinstallation depuis Xcode : un ⌘R pose la
/// nouvelle app **par-dessus** l'ancienne sans toucher à son conteneur. Sans
/// ce qui suit, l'écran d'accueil devient impossible à revoir une fois passé —
/// ce qui est exactement ce qu'on veut pour l'utilisateur, et exactement ce
/// qu'on ne veut pas quand on est en train de le dessiner.
public enum OnboardingStorage {
    /// L'écran d'accueil a été vu au moins une fois.
    public static let hasSeenWelcome = "hasSeenWelcome"

    /// Argument de lancement qui remet l'app à son tout premier démarrage.
    ///
    /// Il se coche dans Xcode — *Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸
    /// Arguments* — ou se passe en ligne de commande :
    ///
    /// ```bash
    /// xcrun simctl launch <device> com.memobook.app -resetOnboarding
    /// ```
    public static let resetArgument = "-resetOnboarding"

    /// À appeler au démarrage, avant toute lecture des réglages.
    ///
    /// Ne fait rien en release : cet interrupteur ne doit pas exister dans
    /// l'app livrée, où effacer la session d'un utilisateur serait une perte
    /// de données.
    public static func resetIfRequested() {
        #if DEBUG
            guard ProcessInfo.processInfo.arguments.contains(resetArgument) else { return }
            UserDefaults.standard.removeObject(forKey: hasSeenWelcome)

            // La session n'est pas dans les réglages mais au trousseau, qui
            // survit à une désinstallation. Sans cette ligne, on reverrait
            // l'accueil puis on atterrirait directement dans l'app, sans jamais
            // repasser par l'écran d'entrée. Le jeton d'appareil, lui, reste :
            // c'est encore lui qui porte les carnets.
            KeychainTokenStore(account: "session-token").clear()
        #endif
    }
}
