import MemoBookDesign
import SwiftUI

/// Point d'entrée de l'interface, et le seul endroit qui décide de l'étape où
/// se trouve l'utilisateur : accueil au tout premier lancement, puis entrée
/// dans le compte, puis l'app.
///
/// Rien n'est mis derrière un écran d'attente réseau : les erreurs
/// appartiennent à l'écran qui fait l'appel — voir ``AppDependencies``.
public struct RootView: View {
    /// L'écran d'accueil ne se montre qu'au premier lancement.
    @AppStorage(OnboardingStorage.hasSeenWelcome) private var hasSeenWelcome = false

    /// Provisoire : il n'y a pas encore d'authentification côté serveur, donc
    /// pas de session à restaurer. Ce drapeau tient lieu de session locale et
    /// devra céder la place à un vrai jeton. Voir ``AuthModel``.
    @AppStorage(OnboardingStorage.isSignedIn) private var isSignedIn = false

    public init() {}

    public var body: some View {
        Group {
            if !hasSeenWelcome {
                WelcomeView { hasSeenWelcome = true }
            } else if !isSignedIn {
                AuthView { isSignedIn = true }
            } else {
                NavigationStack {
                    MemoListView()
                }
                .tint(MemoBookColor.action)
            }
        }
        .animation(.snappy, value: hasSeenWelcome)
        .animation(.snappy, value: isSignedIn)
    }
}
