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
