import MemoBookDesign
import MemoBookNetworking
import SwiftUI

/// Point d'entrée de l'interface.
///
/// Deux mondes, et un seul aiguillage entre eux : le flow d'entrée dans l'app
/// (splash, welcome, comptes) tant qu'aucune session n'est ouverte, la liste
/// des carnets dès qu'il y en a une.
public struct RootView: View {
    @Environment(AppDependencies.self) private var dependencies

    public init() {}

    public var body: some View {
        Group {
            if dependencies.onboarding.step == .home {
                NavigationStack {
                    MemoListView()
                }
            } else {
                OnboardingFlowView(
                    model: dependencies.onboarding,
                    dependencies: dependencies
                )
            }
        }
        .tint(MemoBookColor.action)
        // Le lien reçu par email — `memobook://reset-password?token=…`. C'est
        // le seul chemin vers *Mdp oublié - config*, y compris quand l'app
        // était déjà ouverte sur un autre écran.
        .onOpenURL { url in
            _ = dependencies.onboarding.open(deepLink: url)
        }
    }
}

// MARK: - Aperçus

// Ces deux aperçus montent **tout le flow**, branché sur `PreviewAPI` : on
// parcourt les écrans au clic, on crée un compte, on se trompe de mot de passe.
// Rien ne sort de la machine, aucun back-end n'a besoin de tourner.

#Preview("Le flow, au premier lancement") {
    RootView()
        .environment(
            AppDependencies(
                api: PreviewAPI(seeded: false),
                sessions: InMemorySessionStore(),
                social: PreviewSocialSignInBroker()
            )
        )
}

#Preview("Le flow, onboarding déjà vu") {
    RootView()
        .environment(
            AppDependencies(
                api: PreviewAPI(seeded: false),
                sessions: InMemorySessionStore(hasSeenOnboarding: true),
                social: PreviewSocialSignInBroker()
            )
        )
}
