import MemoBookDesign
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
