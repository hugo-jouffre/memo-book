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

    /// Le mot des fondateurs a été lu au moins une fois.
    ///
    /// Il s'ouvre **tout seul** au premier aperçu d'un carnet, sans qu'on
    /// l'ait demandé — c'est ce qui fait sa valeur, et c'est aussi ce qui le
    /// rendrait insupportable s'il revenait à chaque fois. Une fois lu, il ne
    /// revient plus : la feuille reste ouvrable à la main, elle ne s'invite
    /// plus.
    public static let hasSeenFoundersNote = "hasSeenFoundersNote"

    /// Argument de lancement qui remet l'app à son tout premier démarrage.
    ///
    /// Il se coche dans Xcode — *Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸
    /// Arguments* — ou se passe en ligne de commande :
    ///
    /// ```bash
    /// xcrun simctl launch <device> com.memobook.app -resetOnboarding
    /// ```
    public static let resetArgument = "-resetOnboarding"

    /// Argument de lancement qui **saute l'entrée dans le compte** et ouvre
    /// l'app directement sur l'accueil, avec le jeu d'essai.
    ///
    /// Il existe pour une raison précise : vérifier un écran en simulateur
    /// demande une session, la session vit dans le trousseau, et le trousseau
    /// part avec le conteneur dès qu'on réinstalle l'app. Sans cet interrupteur,
    /// une réinstallation coûte un back-end debout et une connexion à refaire —
    /// pour regarder un coin arrondi.
    ///
    /// ```bash
    /// xcrun simctl launch <device> com.memobook.app -previewSignedIn
    /// ```
    ///
    /// Il n'ouvre **aucun accès** : le compte est un jeu d'essai local, aucun
    /// jeton n'est écrit, et tout appel réseau échouera comme il le doit. Sans
    /// effet en release — voir ``isPreviewingSignedIn``.
    public static let previewSignedInArgument = "-previewSignedIn"

    /// `true` quand l'app a été lancée avec ``previewSignedInArgument``.
    /// Toujours `false` en release.
    public static var isPreviewingSignedIn: Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains(previewSignedInArgument)
        #else
            false
        #endif
    }

    /// À appeler au démarrage, avant toute lecture des réglages.
    ///
    /// Ne fait rien en release : cet interrupteur ne doit pas exister dans
    /// l'app livrée, où effacer la session d'un utilisateur serait une perte
    /// de données.
    public static func resetIfRequested() {
        #if DEBUG
            guard ProcessInfo.processInfo.arguments.contains(resetArgument) else { return }
            UserDefaults.standard.removeObject(forKey: hasSeenWelcome)
            UserDefaults.standard.removeObject(forKey: hasSeenFoundersNote)

            // La session n'est pas dans les réglages mais au trousseau, qui
            // survit à une désinstallation. Sans cette ligne, on reverrait
            // l'accueil puis on atterrirait directement dans l'app, sans jamais
            // repasser par l'écran d'entrée. Le jeton d'appareil, lui, reste :
            // c'est encore lui qui porte les carnets.
            KeychainTokenStore(account: "session-token").clear()
        #endif
    }
}
