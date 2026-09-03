import MemoBookDesign
import MemoBookFeature
import MemoBookNetworking
import SwiftUI

@main
struct MemoBookApp: App {
    @State private var dependencies = AppDependencies(configuration: .fromBuildConfiguration)

    init() {
        // Sora et General Sans sont des ressources du module design : c'est du
        // code, pas `UIAppFonts`, qui les déclare à iOS. Voir `BrandFonts`.
        BrandFonts.registerIfNeeded()

        // Avant tout, pour que `RootView` lise des réglages déjà remis à zéro
        // si on le lui a demandé. Sans effet en release.
        OnboardingStorage.resetIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
        }
    }
}

extension APIConfiguration {
    /// En debug, l'app parle au back-end lancé en local (`npm run dev`).
    /// L'URL de production sera injectée ici quand l'API sera déployée.
    static var fromBuildConfiguration: APIConfiguration {
        #if DEBUG
            .localDevelopment
        #else
            .localDevelopment
        #endif
    }
}
